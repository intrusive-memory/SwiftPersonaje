---
type: requirements
state: draft
updated: 2026-10-22
---

# SwiftPersonaje — Requirements

SwiftPersonaje is the engine behind Personaje: a library and a `personaje`
CLI that take one cast member from a name in the screenplay to a finished
dossier, **one step per command, one file per step.** Each command produces
or updates one thing in the bundle, can be re-run on its own, and records
enough to regenerate what it made.

The Personaje app (`~/Projects/apps/Personaje`) links the library later; the
CLI is what agents and the start-to-finish test use now.

**Format.** Every bundle this package touches follows
[dossier-format `docs/DOSSIER-FORMAT.md`](https://github.com/intrusive-memory/dossier-format/blob/development/docs/DOSSIER-FORMAT.md)
(version 2), through SwiftDossier.

**Source.** This replaces Personaje REQUIREMENTS §5 (the CLI sketch) and turns
`docs/RUNBOOK.md` and the Python pilot tools (`tools/*.py`) into commands. The
process rules stay in Personaje `docs/CHARACTER_CREATION.md`; this document
says which command runs each step and what it checks.

## 1. Where it sits

```
personaje (CLI) ─► SwiftPersonaje ─┬─► SwiftDossier (Dossier)   bundle, manifest, face crop, page; CAST.md role/manifest
Personaje (app) ──┘                ├─► SwiftReparto              CAST.md: every other write (parse → mutate → write)
                                   ├─► SwiftCompartido           screenplays: discovery (§7.1), evidence (§7)
                                   └─► PROJECT.md reader         the personaje: block (Q3)
                 runs, as subprocesses, the signed binaries:
                   vinetas (images)   echada (voice design)   diga (speech)
```

| # | Decision |
|---|----------|
| SP-1 | **SwiftPersonaje generates; SwiftDossier and SwiftReparto record.** Every write to a bundle or its manifest goes through SwiftDossier's `Dossier` API. SwiftPersonaje never writes `manifest.json` or `CAST.md` bytes itself. CAST.md `role` and `manifest` are set by SwiftDossier (`create`, `migrate`; SD-12); every other CAST.md change (members from `cast-import` and discovery, `voicePrompt`, `voices.voxalta` on `--adopt`) goes through SwiftReparto: `parse`, mutate the `CastDocument`, `CastMarkdownParser.write`. Field ownership across packages: SwiftReparto `REQUIREMENTS-personaje.md` "Who writes CAST.md". *Restated 2026-10-22;* it said CAST.md writes went only through SwiftDossier, which `cast-import` never did. |
| SP-2 | **Generation is by subprocess,** not by linking SwiftVinetas or SwiftEchada. Only the signed, App-Group-entitled builds see the shared models; an unsigned CLI that linked the engines would build and then find no models. Binaries are found by environment variable, then `personaje.tools` in PROJECT.md, then the defaults in §6. Each run records `provenance.tool` `{name, version, binary}` (DOSSIER-FORMAT §6). |
| SP-3 | **Judgement stays outside the CLI in v1.** Drafting CHARACTER.md, choosing a candidate, writing prompts and answering review questions are done by a person or an agent. The CLI stores what they decide (§4), checks it, and refuses to run a step whose inputs are missing. LLM drafting (Personaje REQUIREMENTS-APP-UI §11) waits on SwiftBruja #48–#50. |
| SP-4 | **Prompts live in the manifest** (decided 2026-10-19): `prompts.portrait`, `prompts.identity`, `prompts.subject` (DOSSIER-FORMAT §5.5). Every view and expression is rebuilt from them, so any single image can be regenerated alone. |
| SP-5 | **One character name everywhere** (DOSSIER-FORMAT §2): commands take the exact CAST.md name, in quotes. The bundle is found through the member's `manifest:` (DOSSIER-FORMAT §3), never by directory scan. |
| SP-6 | **Candidates go to `<charactersDir>/.generations/<CHARACTER>/`** (DOSSIER-FORMAT §4), gitignored. Only selected files enter the bundle. |
| SP-7 | **Every generating command has `--dry-run`,** which prints the exact prompt, references and command line and writes nothing. |
| SP-8 | **Every command accepts `--json`** and `--project <dir>` (default: the nearest directory at or above the working directory holding PROJECT.md). |

Targets: `SwiftPersonaje` (library), `PersonajeCLICore` (command logic, not a
product), `personaje` (executable). macOS 26, Swift 6.2. Builds and tests via
the Makefile and `xcodebuild`; never `swift build` / `swift test`.

## 2. Project commands (once per project)

| Command | Does | Notes |
|---------|------|-------|
| `personaje doctor` | Checks the signed binaries exist and print a version; `vinetas list --json` has Klein 4B; the Qwen3-TTS models are present; `.venv`-free. | Runbook §0. Read-only. |
| `personaje init --art-style "<style>" [--style-notes "…"] [--view-opening "…"] [--expression-opening "…"] [--backdrop "…"]` | Adds the `personaje:` block to PROJECT.md (§5), `characters/`, `.gitignore` → `<charactersDir>/.generations/`, `.gitattributes` → LFS for `<charactersDir>/**/*.png` and `**/*.vox`. Idempotent; never rewrites keys it didn't add. | PROJECT.md written through SwiftProyecto's `coordinatedWrite(ownedFields:)` (Q3). |
| `personaje cast-import` | When CAST.md is missing and PROJECT.md has a legacy `cast:` block: SwiftReparto `ProjectCastImporter` → CAST.md. Reports duplicate members (mr-mr-charles has two `LAWYER`s) and stops on them. | **Never edits PROJECT.md** (Reparto D-13). It prints the `cast:` lines for the user to remove. |
| `personaje status ["NAME"]` | Without a name: every member, tier, completeness and next step. With one: each dossier file, present or missing, stale or not, the gates (§3), and the exact next command. | Read-only. The command an agent runs first and after every step. |
| `personaje cast-discover [--project <dir>] [--dry-run] [--json]` | Builds or extends CAST.md from the screenplays PROJECT.md lists (§7.1). Adds members; never changes or removes one. `--dry-run` prints the members it would add. | **Implemented** (2026-10-22). Replaces `echada generate cast` (SwiftEchada EC-P11). Stops when PROJECT.md still has a legacy `cast:` block and there is no CAST.md (that is `cast-import`'s). |
| `personaje verify` | SwiftDossier `validate(cast:)` for the whole project. | Read-only. |
| `personaje cast-page` | Writes `<charactersDir>/cast.html`: a card per member with a dossier. | Port of `tools/cast_list.py`; honours `charactersDir`. |

## 3. Character commands, in runbook order

Each row is one command. **Gate** is checked before it runs (override:
`--force`, recorded in provenance). **Writes** is the one file it produces.

| # | Command | Gate | Writes | Runbook / CC step |
|---|---------|------|--------|-------------------|
| 1 | `personaje new "NAME" --role <tier>` | Member exists in CAST.md (or `--add`); name valid (DOSSIER-FORMAT §2) | bundle + `manifest.json`; CAST.md `role`, `manifest` | §1 / Step 1 |
| 2 | `personaje evidence "NAME" [--alias REGEX…]` | Bundle exists | `.generations/NAME/evidence/` (`dialogue.txt`, `mentions.txt`, `bible.txt`, `locations.txt`, `stats.json`); prints the tier suggestion (UD19 thresholds) | §2 |
| 3 | `personaje check "NAME"` | CHARACTER.md exists | nothing: front matter, section order, footnotes defined and used, open questions by group, `draft.reviewedAt` (SwiftDossier `check`) | §3–4 / Steps 2, 2b |
| 4 | `personaje reviewed "NAME"` | `check` clean; "Needed before Portrait / Views" empty | CHARACTER.md `draft.reviewedAt` | §4 / Step 2b |
| 5 | `personaje prompt "NAME" portrait\|identity\|subject --set "…" \| --file f \| --show` | Bundle exists | manifest `prompts.*` | §5, §6 |
| 5a | `personaje art-style "NAME" [<style>]` | CHARACTER.md exists | CHARACTER.md `artStyle` (marks this character's images stale) | UD20 |
| 6 | `personaje portrait "NAME" --seeds 7,77,707,7007 [--round N]` | Gate P (below); `prompts.portrait` set | candidates `.generations/NAME/portrait-vN-s<seed>.png` (+ sidecar); `--open` opens Preview | §5 / Step 4 |
| 7 | `personaje refine "NAME" <candidate> --seeds S,…` | as 6 | candidates `portrait-vN-ref-s<seed>.png`, image-to-image from `<candidate>` with the "same person" prefix | §5 (SHANE's v3 round) |
| 8 | `personaje select "NAME" <candidate>` | candidate exists | `images/portrait-<sha8>.png`, selected; marks `face`/`view`/`expression` stale | §5.4 |
| 9 | `personaje face "NAME" [--box x,y,w,h]` | portrait selected | `images/face-<sha8>.png` | §6.1 / Step 5 |
| 10 | `personaje view "NAME" front\|profile\|back\|all [--seed 21]` | Gate V (below) | `images/view-<variant>-<sha8>.png`, selected | §6.2 / Step 5 |
| 11 | `personaje expression "NAME" happy\|sad\|frightened\|mad\|all [--seed 21]` | Gate V | `images/expression-<variant>-<sha8>.png`, selected | §6.3 / Step 6 |
| 12 | `personaje audition "NAME" --label A (--text "…" \| --file f)` | Bundle exists | `.generations/NAME/voice/try-A.vox` and `.wav` (1.7B only); `--open` plays it | §7.2 / Step 8 |
| 13 | `personaje voice "NAME" --from A` | audition A exists | `voice/NAME.vox` (audition + 0.6B pass, both models checked); CAST.md `voicePrompt`, `voices.voxalta` | §7.4–7.5 |
| 13a | `personaje voice "NAME" --adopt [<path>]` | `.vox` has 0.6B and 1.7B | `voice/NAME.vox` copied unchanged (default source `voices/NAME.vox`), `copiedFrom` recorded; CAST.md `voices.voxalta` | fast track |
| 14 | `personaje samples "NAME" [--allow-replace]` | `vox` selected; `voice/samples.yaml` exists | `voice/sample-<variant>.m4a` per entry | §8 / Step 9 |
| 15 | `personaje render "NAME" \| --all` | none (the page lists what's missing) | `<CHARACTER>-dossier.html` | §9 / Step 10 |

`view all` and `expression all` run the set in order (front, profile, back;
happy, sad, frightened, mad), one file at a time, and stop at the first
failure. Re-running one variant replaces only that variant.

### 3.1 Gates

| Gate | Requires | Source |
|------|----------|--------|
| **P** (portrait) | CAST.md `role` set; CHARACTER.md passes `check`; **if `lead`:** `draft.reviewedAt` set and nothing under "Needed before Portrait / Views". **Below lead** (the fast track): review optional. | Runbook §4 gate; fast track decided 2026-10-19 |
| **V** (views, expressions) | portrait selected and not stale for the current `artStyle`; face derived from the *current* portrait (not stale); `prompts.identity` and `prompts.subject` set | CC rule 1 (the portrait is the anchor) |

`status` shows every gate and why it's closed. `--force` runs anyway and
records `"gateOverridden": "<gate>"` in provenance.

### 3.2 Reference-portrait standard

Decided 2026-10-19: **an adult's reference portrait is shirtless, in the
standard pose** (head to mid-chest, three-quarter, arms relaxed at the
sides, plain backdrop). Clothes appear only in other images. Children are
clothed. `portrait` warns (doesn't block) when `prompts.subject` is an adult
and `prompts.portrait` doesn't say "shirtless". Granville's GARETH, KEVIN,
JOANN and RAY are clothed and are flagged by `status` as non-standard.
CHARACTER_CREATION §4.1 ("everyday wardrobe by default", "never a smile")
must be corrected to match (Personaje change, §8).

## 4. Prompts

**Stored** (SP-4): `prompts.portrait` (the full seven-block portrait prompt,
CC §4.2), `prompts.identity` (identity and wardrobe only, ending in an
absences sentence; no expression, gaze or arms), `prompts.subject`.

**Composed** by SwiftPersonaje from templates shipped as a resource
(`Resources/templates.json`), so the wording is data, versioned, and recorded
in provenance (`templateVersion`). The v1 templates are the ones that made
Granville's 42 views and expressions, reconstructed from their sidecars:

```
view:        The same {subject} as in the reference images, with the same face, hair, build and clothes. {viewOpening}, {framing}, centered vertical composition. {identity} No text or lettering anywhere. {backdrop}
expression:  The same {subject} as in the reference images, with the same face, hair and clothes. {expressionOpening}, face centered and filling the frame, three-quarter angle. {identity} Expression: {line} No text or lettering anywhere. {backdrop}
refine:      The same {subject} as in the reference image, with the same face, build and pose. {portrait}
```

References are sent in the order below and recorded with roles
(`portrait`, `face`) in `provenance.references` (DOSSIER-FORMAT §6).

| Variant | Size | `-r` order | Line |
|---------|------|-----------|------|
| front | 864×1536 | portrait, face | facing the camera straight on, symmetrical, head and upper torso to mid-chest, both shoulders square to the camera, looking directly into the lens, neutral relaxed expression |
| profile | 864×1536 | portrait, face | a full side profile facing screen-left: the head and body turned ninety degrees, the nose pointing at the left edge of the frame, only one eye and one ear visible, head and upper torso to mid-chest, neutral relaxed expression |
| back | 864×1536 | portrait only | seen from directly behind: the back of the head, the neck and the shoulders, the face not visible at all, head and upper torso to mid-chest |
| happy | 1024×1024 | face, portrait | a big, genuine, open full smile showing teeth, cheeks lifted, eyes crinkled nearly shut with delight. |
| sad | 1024×1024 | face, portrait | deeply sad: downcast eyes, the corners of the mouth pulled down, the inner ends of the brows raised and pinched together, on the edge of tears. |
| frightened | 1024×1024 | face, portrait | badly frightened: eyes very wide showing the whites, brows raised high and drawn together, lips pulled back and parted, the head drawn slightly back. |
| mad | 1024×1024 | face, portrait | furious: brows drawn down hard into a scowl, jaw clenched and set, nostrils flared, lips pressed thin, glaring straight at the camera. |

All renders: `--model klein4b --steps 8`, default guidance (3.5), `-s` the
character's style (§5), one seed for the whole set (default 21). Each image
records `provenance.style` (the full string) and `provenance.artStyle`
(DOSSIER-FORMAT §6), so changing the character's art style marks its images
stale (§7 there). Portrait
rounds: 864×1536, the seeds given.

`{viewOpening}`, `{expressionOpening}` and `{backdrop}` come from the
project (§5), so a non-photoreal project doesn't get "photograph" and
"85mm lens, f/4" in every prompt. With Granville's values the templates
reproduce all 42 of its view and expression prompts (checked against the
sidecars: every view opens "Photorealistic studio portrait photograph",
every expression "Photorealistic studio head-and-shoulders close-up").

## 5. Project settings (`personaje:` in PROJECT.md)

```yaml
personaje:
  charactersDir: characters
  artStyle: "photorealistic"                       # default for NEW characters only (UD20)
  styleNotes: "editorial portrait photography, natural color grading"   # -s, second part
  viewOpening: "Photorealistic studio portrait photograph"          # default: "<artStyle, capitalized> studio portrait"
  expressionOpening: "Photorealistic studio head-and-shoulders close-up"   # default: "<artStyle, capitalized> studio head-and-shoulders close-up"
  backdrop: "Plain seamless warm-grey studio backdrop, soft diffused key light from the left with gentle fill, 85mm lens, f/4, shallow depth of field, sharp focus."
  bible: [episodes/00-front-matter.fountain]        # extra files evidence reads as the series bible (default: PROJECT.md body)
  evidenceExclude: ["episodes/Mr and Mr Charles-2025JUN.fountain"]      # screenplays evidence must skip (old drafts)
  tools: { vinetas: …, echada: …, diga: … }          # optional binary overrides
```

**Art style is per character** (Personaje APP-UI UD20, decided 2026-10-18):
the character's `artStyle` in CHARACTER.md front matter (DOSSIER-FORMAT §9.1).
`personaje.artStyle` is only what `new` writes into a new character. The `-s`
string is `<character artStyle>, <personaje.styleNotes>`. `personaje
art-style "NAME" [<style>]` shows or sets it (through SwiftDossier's
`CharacterDescription`); `status` flags a character whose style differs from
the project default (APP-UI Q10), never blocking.

## 6. External tools

| Tool | Default | Used by | Notes |
|------|---------|---------|-------|
| `vinetas` | `vinetas-cli` skill launcher → `/Applications/Vinetas.app/Contents/MacOS/VinetasCLI` | portrait, refine, view, expression | Sandboxed: writes only to the App Group. Output goes to `<group>/vinetas-out/<NAME>/` and is moved to `.generations/` as soon as it finishes; reference images are staged there first as `ref-portrait.png` / `ref-face.png`. Each render: 3.5–5 min. |
| `echada` | `~/Projects/package-collection/pkg/SwiftEchada/bin/echada` | audition, voice | `echada voice … --tts-model 1.7b`, stdin closed. `echada voice` writes only its `--output` `.vox` and never touches CAST.md, so `personaje voice` records `voicePrompt` and `voices.voxalta` itself, through SwiftReparto. **`echada cast` and `echada generate vox` are never run:** both rewrite CAST.md (`cast` even with `--dry-run`), and until SwiftEchada ships EC-23 both write `voices/<NAME>.vox` and repoint `voices.voxalta` there, leaving the dossier's `voice/<NAME>.vox` unreferenced (`CastVoiceGenerator.swift:331`, `:537`). *Widened 2026-10-22 from `cast` only.* |
| `diga` | `~/Projects/package-collection/pkg/SwiftVoxAlta/bin/diga` | samples | Refuses to overwrite an existing diga voice of the same name without `--allow-replace`. `--instruct` on a cloned voice is unverified; recorded as such. |

Timeouts are per call (images 15 min, voice 15 min). A failed subprocess
leaves nothing in the bundle; partial output stays in `.generations/`.

## 7. Evidence

v1 ports `tools/evidence.py` (the regex scanner the pilot used), with two
fixes: a `filePattern` given as a comma-separated glob string means "every
`episodesDir/*.fountain` by name", and `personaje.bible` /
`personaje.evidenceExclude` are honoured. When SwiftCompartido's character
query ships (APP-UI §11.6), `evidence` switches to it; the output files keep
their names.

### 7.1 CAST.md from the screenplays (the discovery writer)

*Moved here 2026-10-22* from SwiftReparto `REQUIREMENTS-personaje.md`
Part 2 (decided as Personaje OQ-4); the IDs are kept for traceability.
SwiftReparto can't host it: reading SwiftCompartido would put SwiftData,
SwiftUI and the rest in every CAST.md reader's graph and break Reparto's
leaf rule (RQ-INV-1). This library links both. The writer is a library
API; `personaje cast-discover` (§2) and the Personaje app's review screen
(APP-UI §11.1) both call it.

It calls SwiftCompartido's `DocumentModelActor.extractAllCharacters()`
(CP-P2, shipped in 7.3.0), maps each character to a `CastMember` through
`CastMember.canonicalName(_:)`, merges with `[CastMember].merging(_:)`, and
writes with `CastMarkdownParser.write`.

| ID | Requirement |
|----|-------------|
| RP-P9 | Read SwiftCompartido's character collection (CP-P2) and turn each character into a `CastMember`, with the name passed through `canonicalName` (Reparto RQ-22). CP-P2 names arrive already uppercased and cut at the first `(` (Compartido `cleanCharacterName`); `canonicalName` is idempotent on them. |
| RP-P10 | Merge the discovered members into the current CAST.md with `[CastMember].merging(_:)`: add new members, fill only nil fields, never overwrite or remove what a person wrote. Duplicates are members with the same canonical name. |
| RP-P11 | Works on a store holding one screenplay (a series built by repeated merges) or every episode at once; both give the same CAST.md. CP-P2's `characters` is a dictionary, so the writer sorts discovered members deterministically before merging. |
| RP-P12 | Available from the `personaje` CLI and the Personaje app, both through this library. There is no `reparto` command for it. |
| RP-P13 | Counts (lines, scenes) are **not** written to CAST.md. They are read from SwiftCompartido for tier suggestions (`evidence`, §7; APP-UI UD19). |
| RP-P14 | Two different names for one person are not merged. That's a review step: the app's list (APP-UI §11.1), or by hand after `--dry-run`. |

Depends on SwiftCompartido ≥ 7.3.0 and SwiftReparto 0.2.0 (`canonicalName`,
hard). The writer sets only `character`; `role` and `manifest` come later
from `new` through SwiftDossier.

**Status: implemented 2026-10-22** as `CastDiscovery` in the library
(`Sources/SwiftPersonaje/CastDiscovery.swift`), behind `personaje
cast-discover`:

- `CastDiscovery.discover(screenplays:castFile:dryRun:)` loads the files
  into an in-memory SwiftCompartido store (the "every episode at once"
  path); `discover(from:castFile:dryRun:)` takes a
  `CharacterCollectionResult` from a store the caller already has (the
  app). Both return a `CastDiscovery.Report`.
- `discoveredMembers(from:)` is RP-P9; names `canonicalName` refuses are
  reported in `rejected`, never rewritten.
- `merge(_:into:)` is RP-P10/P11. `merging(_:)` appends new members at
  the end, which makes the result depend on episode order, so each new
  member is moved to just before the first member whose canonical name
  sorts after it. That rule gives the same roster whatever order names
  arrive in; existing members never move. A run that adds nothing writes
  nothing, so an existing CAST.md keeps its bytes.
- **Dependency:** SwiftReparto `.upToNextMajor(from: "0.2.0")`
  (`canonicalName`, released 2026-10-22).

## 8. Changes elsewhere

| Where | Change |
|-------|--------|
| SwiftDossier | Needs: `add --sidecar` provenance folding with references and roles (SD-7), `prompt`, `check`, `candidates`. |
| dossier-format | Nothing outstanding: `prompts`, `provenance.tool`, `copiedFrom`, `references[].role` are in v2 (2026-10-19). |
| Personaje RUNBOOK | Rewritten as `personaje` commands, step for step; the Python snippets go to an appendix until retired. Fix now, before the Swift tools exist: `C=$P/characters/$NAME.dossier`; `CAST=`/`PROJ=` on every `make` call; `$(PY)` → `.venv/bin/python`; document `voice-adopt`, the refine round, `styleNotes`, the fast track. |
| Personaje CHARACTER_CREATION | §4.1 reference-portrait standard (§3.2); Steps 5–6 from the 2026-10-05 pilot (three views, one seed, back view on the portrait only). |
| Personaje `tools/` | Retired when every command here passes acceptance on Granville and the mr-mr-charles run. |

## 9. Acceptance

This repository is public (Swift* packages are public by convention; the
apps are private), and podcast-granville and podcast-mr-mr-charles are
private. Nothing from them is copied in: unit tests use synthetic
characters (SwiftDossier SD-4), and items 1 and 4 run through
`make acceptance PROJECT=<path>` against a local checkout, skipping when it
is absent, never in CI. The parity expectations for item 1 are read from the
checkout's sidecars at run time, not stored here.

1. **Granville parity.** With `prompts.identity` set from each character's
   view sidecar, `personaje view HUNTER front --dry-run` (and every other
   variant, for the six piloted characters) prints a prompt, size, seed and
   reference order identical to the sidecar's.
2. **One file at a time.** Deleting any single image or sample from a
   bundle and re-running its command restores exactly that asset and
   touches no other file except `manifest.json` and the page.
3. **Gates.** On a fresh lead with an unreviewed CHARACTER.md, `portrait`
   refuses with the gate and the missing items; on a `supporting`
   character it runs.
4. **Start to finish on mr-mr-charles** (branch `dossier/start-to-finish`,
   from tag `dossier-baseline`): `doctor`, `init`, `cast-import`, then one
   lead (MITCH) and one supporting character through `render`, with
   `status` naming the correct next command after every step. Then reset to
   the baseline and do it again from the committed tools.
5. No command writes outside the project, `.generations/` and the App Group
   staging folder.

## 10. Open questions

| # | Question | Recommendation |
|---|----------|----------------|
| Q1 | **Reference standard for women.** The shirtless rule (§3.2) is written for men; JOANN is clothed. | Ask. A neutral option is bare shoulders (strapless/tube top), same pose. |
| Q2 | Should views and expressions go through candidates (several seeds, choose) or straight in, as the pilot did? | Straight in, one seed: the pilot's 42 renders were all usable. `--seeds a,b` switches to candidates + `select`. |
| Q3 | **Reading and writing PROJECT.md.** SwiftProyecto owns it but still carries an LLM layer. | *Reading answered 2026-10-22:* SwiftProyecto 5.3.2's library target links no LLM layer (only its `proyecto` executable uses Foundation Models), so the library reads PROJECT.md through `ProjectMarkdownParser`. Writing (`init`) still to check against `coordinatedWrite`. |
| Q4 | Voice placement: SwiftEchada EC-23 (voices written into the bundle) hasn't shipped. | `voice` copies the `.vox` in through SwiftDossier `add`; switch to `refresh` when EC-23 ships. |
| Q5 | Does `personaje` call SwiftDossier as a library (yes) and also expose the `dossier` commands (`select`, `render`)? | Yes, as thin wrappers taking a character name, so an agent needs one CLI. |
| Q6 | Mid-century modern illustration on Klein 4B is untested; illustration styles drift on detail. | Run the mr-mr-charles portrait rounds first and judge before views. |

## 11. Phases

1. **Scaffold + read side:** package, CLI shell, `doctor`, `status`,
   `--project` resolution, PROJECT.md settings, the binary resolver. Needs
   SwiftDossier phase 1.
   *Done 2026-10-22:* package, CLI shell, `--project` resolution, reading
   `episodesDir` / `filePattern`. The rest is open.
2. **Project commands:** `init`, `cast-import`, `verify`. *Done ahead of
   the rest:* `cast-discover` (§7.1).
3. **Character text steps:** `new`, `evidence`, `check`, `reviewed`, `prompt`.
4. **Images:** `portrait`, `refine`, `select`, `face`, `view`, `expression`,
   with `--dry-run` parity tests (acceptance 1).
5. **Voice:** `audition`, `voice`, `voice --adopt`, `samples`.
6. **Render + cast page,** then the start-to-finish run twice.
