# Evidence fixture: expected values

Hand-worked values for `Tests/Fixtures/evidence-project/`. Sorties 3 to 10
hard-code these in their tests. Everything in this project is invented and CC0.
Line numbers are 1-based, counted in the `.fountain` file as committed.

## The scene rule used

A scene starts only at a line beginning `INT.`, `EXT.`, `INT./EXT.` or `EST.`
followed by whitespace. Forced `.` lines (`.MUSIC CONTINUES`) never start a
scene. A slugline whose line lies inside `[[ ]]` or `/* */` is not a heading.
SN-1, per episode file: an existing `#n#` wins; a file with no numbers is
numbered 1…n; otherwise an unnumbered heading takes the previous number plus a
letter (or `0A` before the first number), skipping numbers already used.

## Scene headings

### `episodes/01-the-quay.fountain` (no `#n#` at all: numbered 1…n)

| Line | Heading | SN-1 |
|-----:|---------|------|
| 8  | `EXT. QUAYSIDE - DAWN` | 1 |
| 27 | `INT. CHANDLERY - DAY` | 2 |
| 47 | `EXT. SHINGLE BEACH - AFTERNOON` | 3 |
| 75 | `INT. LIGHTHOUSE KITCHEN - NIGHT` | 4 |

Not headings: line 43 `EXT. CLIFF PATH - NIGHT` (inside the `[[ ]]` note,
lines 42–45, in scene 2); line 62 `.MUSIC CONTINUES` (forced line, in scene 3).
4 scenes.

### `episodes/02-the-lamp.fountain` (partly numbered: `#1#`, `#2#`, `#2A#`, `#3#`)

| Line | Heading | Existing | SN-1 | Why |
|-----:|---------|----------|------|-----|
| 8  | `INT. HARBOURMASTER'S OFFICE - MORNING` | — | 0A | before the first number |
| 23 | `EXT. LIGHTHOUSE STEPS - DAY #1#` | 1 | 1 | existing |
| 33 | `INT. LAMP ROOM - CONTINUOUS` | — | 1A | 1 + A |
| 43 | `INT./EXT. FERRY - DUSK #2#` | 2 | 2 | existing |
| 62 | `EXT. QUAYSIDE - NIGHT` | — | 2B | 2 + A, but 2A is used (line 72), so 2B |
| 72 | `EST. HARBOUR TOWN - NIGHT #2A#` | 2A | 2A | existing |
| 79 | `INT. CONSTABLE'S COTTAGE - NIGHT #3#` | 3 | 3 | existing |

Not headings: line 57 `EXT. ROCKS - NIGHT` (inside the `/* */` boneyard,
lines 56–60, in scene 2). 7 scenes. Numbers to append for SN-3: line 8 ` #0A#`,
line 33 ` #1A#`, line 62 ` #2B#` (three headings); the other four are unchanged.

Project total: 11 scenes.

## Cases (a)–(i)

| Case | Character (cue) | Expected evidence kind | Episode file | Line | SN-1 scene |
|------|-----------------|------------------------|--------------|-----:|------------|
| (a) | CONSTABLE | introduction: `CONSTABLE HAROLD "HAL" BRISK, 40's, rain cape buttoned to the chin, strides the length of the quay. All six-foot-five of him.` (whole-word match of the cue inside the longer capitalised name) | `01-the-quay.fountain` | 16 | 1 |
| (b) | PIP, NED, TOBY | group statement: `They each speak with a thick coastal accent.` (names no one; counts for each character who speaks in the scene). The line before it, `PIP, NED and TOBY, three boys of about twelve, …` (line 49), names all three and is each boy's introduction, also scene 3 | `01-the-quay.fountain` | 51 | 3 |
| (c) | MARA | introduction, parenthetical style: `MARA OKAFOR (20's BLACK, CLOSE-CROPPED HAIR) counts coins into a ledger, lips moving.` | `01-the-quay.fountain` | 31 | 2 |
| (d) | FERRYMAN | dialogue only: no introduction anywhere, no error. Items: `01-the-quay.fountain` line 21 scene 1; `02-the-lamp.fountain` lines 47 and 53, scene 2 | both | 21, 47, 53 | 1; 2, 2 |
| (e) | NARRATOR | dialogue with cue extensions: `V.O.` with parenthetical `(quietly)` (line 12, scene 1); `O.S.` (line 36, scene 2); `PRELAP` (line 72, scene 3: it sits before the line-75 heading, so it belongs to scene 3) | `01-the-quay.fountain` | 12, 36, 72 | 1, 2, 3 |
| (f) | PIP, NED, TOBY (scene 3) | context: `.MUSIC CONTINUES` is a forced line mid-scene. It adds no scene and must not end a context window: a window around it holds blocks from both sides (TOBY line 59 before; action line 64 and PIP line 66 after) | `01-the-quay.fountain` | 62 | 3 |
| (g) | (scene numbers) | `01-the-quay.fountain` has no `#n#` (1–4); `02-the-lamp.fountain` is partly numbered, giving 0A, 1A and 2B (see tables) | both | — | — |
| (h) | WICK | whole-word miss: `WICKHAM & SONS` (line 29, scene 2) is **not** WICK's evidence. WICK's introduction is `WICK, 60's, the lighthouse keeper, wiry and salt-bleached, stirs a pot of something grey.` | `01-the-quay.fountain` | 77 (miss: 29) | 4 (miss: 2) |
| (i) | ODILE | introduction naming her own accent: `ODILE VANCE, 50's, the harbourmaster, sharp-eyed, speaks with a clipped Northern Highland accent.` Her accent is that evidence's "Northern Highland", overriding the project's "Lowland Coastal" | `02-the-lamp.fountain` | 12 | 0A |

## Project context (PROJECT.md)

- title: `The Lantern Coast`
- genre: `Mystery`
- description: `A small harbour town, a lighthouse keeper and a missing ledger. Invented for SwiftPersonaje's evidence tests; CC0.`
- `setting.accent`: `Lowland Coastal`

Accents: every member except ODILE inherits `Lowland Coastal` from the project.
Note for Sortie 8: the boys' group statement says "a thick coastal accent",
which is the project's own coastal accent, not a different one; PIP, NED and
TOBY are expected to inherit `Lowland Coastal` (source `project`). Only ODILE
overrides.

## Cast and tiers

CAST.md lists all nine speaking members; no `voicePrompt` anywhere. 31 dialogue
blocks and 11 scenes in total. Major: at least 8% of blocks (≥ 2.48, so 3 or
more) or at least 15% of scenes (≥ 1.65, so 2 or more).

| Member | Blocks | Scenes (episode: SN-1) | Computed tier | CAST.md `role` |
|--------|-------:|------------------------|---------------|----------------|
| CONSTABLE | 5 | 01: 1; 02: 0A, 2B, 3 (4) | major | — |
| FERRYMAN | 3 | 01: 1; 02: 2 (2) | major | — |
| MARA | 5 | 01: 2, 4; 02: 1, 3 (4) | major | — |
| NARRATOR | 5 | 01: 1, 2, 3; 02: 1A, 2A (5) | major | — |
| NED | 2 | 01: 3 (1) | minor | — |
| ODILE | 3 | 02: 0A, 2 (2) | major | — |
| PIP | 3 | 01: 3; 02: 2B (2) | major | — |
| TOBY | 1 | 01: 3 (1) | minor | `supporting` (wins: reported tier is major) |
| WICK | 4 | 01: 4; 02: 1, 1A (3) | major | — |

## Every dialogue block

| Episode | Cue line | Cue | Extension | Parenthetical | SN-1 | First dialogue line |
|---------|---------:|-----|-----------|---------------|------|---------------------|
| `01-the-quay.fountain` | 12 | NARRATOR | V.O. | (quietly) | 1 | Every town on this coast keeps one secret. Ours kept two. |
| `01-the-quay.fountain` | 18 | CONSTABLE |  |  | 1 | Who left these nets across the steps? |
| `01-the-quay.fountain` | 21 | FERRYMAN |  |  | 1 | Not me. I only carry people, Constable. |
| `01-the-quay.fountain` | 24 | CONSTABLE |  |  | 1 | Then carry yourself off my quay. |
| `01-the-quay.fountain` | 33 | MARA |  |  | 2 | Twelve shillings short. Again. |
| `01-the-quay.fountain` | 36 | NARRATOR | O.S. |  | 2 | Mara never trusted a ledger that balanced. |
| `01-the-quay.fountain` | 39 | MARA |  |  | 2 | Who said that? |
| `01-the-quay.fountain` | 53 | PIP |  |  | 3 | Last one in buys the chips! |
| `01-the-quay.fountain` | 56 | NED |  |  | 3 | You always say that and you never pay. |
| `01-the-quay.fountain` | 59 | TOBY |  |  | 3 | I'm not going in. It's freezing. |
| `01-the-quay.fountain` | 66 | PIP |  |  | 3 | Told you it was fine! |
| `01-the-quay.fountain` | 69 | NED |  |  | 3 | Liar! |
| `01-the-quay.fountain` | 72 | NARRATOR | PRELAP |  | 3 | That night, the lamp went dark. |
| `01-the-quay.fountain` | 79 | WICK |  |  | 4 | Lamp's out. First time in thirty years. |
| `01-the-quay.fountain` | 82 | MARA |  |  | 4 | Then someone put it out. |
| `01-the-quay.fountain` | 85 | WICK |  | (not looking up) | 4 | Or something. |
| `02-the-lamp.fountain` | 14 | ODILE |  |  | 0A | Nobody sails until that lamp is lit. |
| `02-the-lamp.fountain` | 17 | CONSTABLE |  |  | 0A | The fishermen won't like it. |
| `02-the-lamp.fountain` | 20 | ODILE |  |  | 0A | The fishermen can like it from the dock. |
| `02-the-lamp.fountain` | 27 | MARA |  |  | 1 | How many steps? |
| `02-the-lamp.fountain` | 30 | WICK |  |  | 1 | Two hundred and nine. I count them every morning. |
| `02-the-lamp.fountain` | 37 | WICK |  |  | 1A | Somebody's been up here. |
| `02-the-lamp.fountain` | 40 | NARRATOR | V.O. |  | 1A | Somebody had. |
| `02-the-lamp.fountain` | 47 | FERRYMAN |  |  | 2 | I saw a light on the rocks last night. Green, like a bottle. |
| `02-the-lamp.fountain` | 50 | ODILE |  |  | 2 | And you said nothing? |
| `02-the-lamp.fountain` | 53 | FERRYMAN |  |  | 2 | You never asked. |
| `02-the-lamp.fountain` | 66 | PIP |  |  | 2B | Constable! There's a boat with no lights! |
| `02-the-lamp.fountain` | 69 | CONSTABLE |  |  | 2B | Where? |
| `02-the-lamp.fountain` | 76 | NARRATOR | V.O. |  | 2A | And in that one window, someone was counting coins. |
| `02-the-lamp.fountain` | 83 | MARA |  |  | 3 | It was never short. Someone was paying for silence. |
| `02-the-lamp.fountain` | 86 | CONSTABLE |  |  | 3 | Then we find out whose. |
