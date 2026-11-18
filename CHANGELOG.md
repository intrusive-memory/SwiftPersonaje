---
type: doc
---

# Changelog

All notable changes to SwiftPersonaje are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-11-18

### Added

- **Scene numbering** (`SceneNumbering`, SN-1/SN-2): finds scene headings in a
  screenplay. Only sluglines (`INT.`, `EXT.`, `INT./EXT.`, `EST.` plus
  whitespace) start a scene; forced `.` lines, `[[ ]]` notes and `/* */`
  boneyard never do. Existing `#n#` numbers win; new scenes are numbered 1…n,
  lettered after an existing number (12A, 12B…), or `0A` before the first, skipping
  numbers already used. A position lookup gives any line's scene number without
  writing.
- **Scene-number writer** (`SceneNumberWriter`, SN-3–SN-6): plans the ` #n#`
  suffixes as a byte-level edit (no re-serialisation; encoding, byte-order mark
  and line endings kept) and validates the plan three ways before anything is
  written: stripping the suffixes gives the original bytes, only unnumbered
  sluglines changed, and a SwiftCompartido re-parse matches. `write(_:backupRoot:relativeTo:)`
  backs the original up and checks the copy, refuses a file changed since planning,
  writes atomically, reads back, and restores the backup on a mismatch.
- **Character evidence** (`EvidenceCorpus`, `CharacterEvidence`, VE-1–VE-8):
  each member's dialogue (with V.O., O.S., PRELAP and other cue extensions and
  parentheticals), ±3-block context windows clipped at the scene rule above,
  introductions, whole-word name variants, and group statements ("They each…"
  counts for everyone speaking in that scene). Every item cites its episode,
  line and SN-1 scene number.
- **Tier** (`CharacterTier`, VE-6): major at 8% of dialogue blocks or 15% of
  scenes, otherwise minor; a CAST.md `role` wins. Reported only, never written.
- **Project context and accent** (`ProjectContext`, `PersonajeSetting`,
  VE-7): title, genre, description and `setting.accent` from PROJECT.md. A
  member inherits the project accent unless their own evidence names a
  different one.
- **`personaje number-scenes [--project <dir>] [--dry-run] [--json]`** (SN-7):
  numbers unnumbered sluglines in every episode, with backups under
  `<project>/.personaje/backups/<timestamp>/`, and adds `.personaje/` to the
  project's `.gitignore`. It never commits. `--dry-run` writes nothing.
- **`personaje evidence <CHARACTER> [--project <dir>] [--json]`** (VE-9): a
  member's evidence grouped by kind, with tier and accent. Unknown names exit
  non-zero with `unknown character: <NAME>`.
- Synthetic CC0 fixture project, `Tests/Fixtures/evidence-project/`.

## [0.2.0] - 2026-11-15

### Added

- **Line counts** (RP-P10): discovery sets each discovered member's
  `lineCount` from SwiftCompartido's `extractAllCharacters()` (character cues),
  summed over every raw name that canonicalizes to the member, and replaces the
  old count on every run through `merging(_:)`. A member discovery doesn't find
  keeps its count.
- `CastDiscovery.LineCount` (`character`, `lineCount`, `previous`, `changed`)
  and `CastDiscovery.Report.lineCounts`, `changedLineCounts`,
  `updatedLineCounts`, so the Personaje app can preview old → new counts.

### Changed

- The writer writes when a member is added **or a `lineCount` changes**; a run
  that changes neither still leaves CAST.md's bytes alone.
- **`personaje cast-discover` is report-only** (REQUIREMENTS §2): it always runs
  as a dry run and never writes CAST.md; the Personaje app is the only builder.
  `--dry-run` is still accepted. The text report lists line counts for members
  it would add and old → new counts for existing members.
- Requires SwiftReparto 0.4.0 and SwiftProyecto 5.5.1.

## [0.1.0] - 2026-10-22

The first release: the CAST.md discovery writer (REQUIREMENTS §7.1). The rest of
SwiftPersonaje is requirements only.

### Added

- **`CastDiscovery`** (library): reads screenplays through SwiftCompartido's
  `extractAllCharacters()`, names each character with SwiftReparto's
  `CastMember.canonicalName(_:)`, merges into CAST.md with `merging(_:)`, and
  writes through `CastMarkdownParser`. Only `character` is set; counts are never
  written; different names are never merged. New members are slotted in by
  canonical name, so one run over every episode and one run per episode give
  the same CAST.md. Names with no canonical form are reported, not rewritten.
- **`personaje cast-discover [--project <dir>] [--dry-run] [--json]`**: finds
  PROJECT.md at or above the working directory, reads `episodesDir` and
  `filePattern`, and writes CAST.md beside it. It stops without writing when no
  screenplay matches, or when PROJECT.md still holds a legacy `cast:` block and
  there's no CAST.md yet.
- Requires SwiftReparto 0.2.0, SwiftCompartido 7.4.0, SwiftProyecto 5.3.2;
  macOS 26 / iOS 26.
