---
type: doc
title: Build and test
updated: 2026-11-21
---

# Build and test

Every build and test goes through the Makefile and `xcodebuild`. Never
`swift build` or `swift test`.

| Command | What it runs | Where |
|---|---|---|
| `make test` | `SwiftPersonajeTests`: everything model-free | locally and in CI |
| `make test-eval` | `Evals/`: the model-backed character-summary evaluation | locally only, never CI |

## `make test`: the deterministic pieces

The character-summary pipeline (`Sources/SwiftPersonaje/Summary/`) is tested
here with no model:

- `QuoteVerifierTests`: a quote is verified only inside one block of the
  scene it cites, after normalization (quotation marks, dashes, emphasis,
  whitespace). Paraphrases, a quote that crosses a cue, the wrong scene and
  a missing scene are rejected.
- `SceneChunkerTests`: chunks fit the token budget, leave the output's share
  free, never cut a line, and keep the citation on every part of a split
  scene. Only scenes the character speaks in or is named in are chunked.
- `SummaryTraceabilityTests`: summary sentences with no supporting fact are
  flagged. The check is lexical (shared content words); it doesn't prove a
  fact entails the sentence.
- `CharacterSummaryPipelineTests`: the whole pipeline with a stubbed model.

All of them use the synthetic, CC0 lighthouse screenplay in
`Tests/SwiftPersonajeTests/SummarySupport.swift`.

## `make test-eval`: the model-backed evaluation

`Evals/` is a package of its own (macOS 27): it needs SwiftLlavero (the one
path to a model) and Apple's Evaluations framework, and it keeps both, and
Firebase, out of the library's dependency graph.

It runs the pipeline with a deliberately plain baseline extractor and
summarizer (`Evals/Sources/PersonajeEvalKit/BaselineModel.swift`) for each
character fixture, scores the runs, prints a table, and writes two reports
to `.build/eval/`:

- `character-summaries-<UTC time>.json`: the scores, the OS version, the
  model, the threshold misses, and every run in full (chunks, facts, dropped
  facts with their verdicts, summaries). Compare these across runs.
- `character-summaries-<id>.xcevalresult`: the Evaluations framework's own
  result.

The model-backed test is enabled only when Apple Intelligence is available
(`SystemLanguageModel.default.isAvailable`) and `GITHUB_ACTIONS` isn't
`true`; the Makefile target refuses to start in GitHub Actions too. The
scoring tests in the same target run either way.

### Running it

```
make test-eval                                            # the CC0 example (WREN)
make test-eval PROJECT=~/Projects/podcasts/granville      # Granville's fixtures
make test-eval PROJECT=~/Projects/podcasts/granville MODEL=pcc
make test-eval PROJECT=~/Projects/podcasts/mr-mr-charles EPISODES='0*.fountain'
```

Use `EPISODES` when `episodes/` holds more than the episodes: mr-mr-charles
keeps a compiled full script there, which would count every scene twice.

| Variable | Meaning | Default |
|---|---|---|
| `PROJECT` | Folder holding `episodes/*.fountain` | `Evals/Fixtures/example` |
| `FIXTURES` | Folder of `<CHARACTER>/` fixture folders | `$PROJECT/evals/character-summaries` |
| `EPISODES` | Glob over the files in `episodes/` | `*.fountain` |
| `MODEL` | `on-device`, `pcc`, a configured `account:model`, or `bruja:<MLX model id>` | `on-device` |

Token budgets are measured with the on-device tokenizer whatever `MODEL`
is: its context is the smallest, so a chunk that fits it fits the others,
and every model sees the same chunks.

Every model runs with greedy decoding, so a run repeats and two models can
be compared. `bruja:<id>` runs a local MLX model in-process through
SwiftBruja (temperature 0, thinking off); download it first with
`bruja download -m <id>`. The Makefile passes `ACERVO_APP_GROUP_ID`
(default `group.intrusive-memory.models`) so the test runner finds the
shared models.

```
make test-eval PROJECT=~/Projects/podcasts/mr-mr-charles EPISODES='0*.fountain' \
  MODEL=bruja:mlx-community/Qwen3.5-9B-MLX-4bit
```

### Fixtures

Real fixtures quote private scripts, so they live with the project they
quote, never in this public repository. Each character is a folder:

```
<FIXTURES>/<CHARACTER>/
  gold-facts.yaml     facts: hand-written facts, each with a verbatim quote,
                      the episode file and the SN-1 scene number.
                      acceptable: facts a run found that are right but not
                      in facts:, copied in from a report.
  gold-summary.md     a hand-written two- or three-sentence summary.
  must-not-say.yaml   claims: plausible but wrong claims, each with the
                      phrases that would show a run made it.
```

`Evals/Fixtures/example/evals/character-summaries/WREN/` is a complete,
invented example of the format.

Gold content is written by hand. A fixture holding a `TODO` marker, or no
facts, is reported as `TODO`: its precision, recall and hallucinations
aren't scored, but its quote verification rate and summary traceability
are. Every gold quote is itself checked against the episodes; one that
doesn't verify is reported as a fixture error.

### Metrics

Per character:

| Metric | Definition | Bar |
|---|---|---|
| quote verification rate | extracted facts whose quote verifies, over extracted facts | 0.5 |
| precision | verified facts matching a gold or acceptable fact, over verified facts | 0.3 |
| recall | gold facts matched by a verified fact, over gold facts | 0.2 |
| hallucinations | `must-not-say` claims found in a verified fact's statement or the summary | 0, always |
| summary traceability | summary sentences with a supporting fact, over sentences; a sentence that cites no fact is unsupported | 0.5 |
| gold summary coverage | sentences of `gold-summary.md` the run's facts support | none |

A run's fact matches a gold fact when both cite the same scene and their
quotes overlap (one contains the other, or a word Jaccard of 0.5 or more).

The bars are in `Evals/Sources/PersonajeEvalKit/EvalThresholds.swift`. They
start loose; tighten them after the first runs. A missed bar is reported as a
test issue, which is expected while the baseline stands in for the real
summarizer.

The baseline keeps a summary to three sentences, splitting a line that
holds several. When a model writes more, the report says how many came back
(`summarySentencesReturned`) and lists it under the bars. Within one
response, a repeated quote is kept once: a small model under greedy decoding
can loop on one line.

### What the metrics don't check

The quote is verified; the **statement** built on it isn't. A run can quote
the script correctly and still claim something the quote doesn't show. The
`must-not-say` lists catch the wrong claims you thought of. Nothing yet
catches the rest; a model-judged statement-support metric (Evaluations'
`ModelJudgeEvaluator`) is the likely next addition.

### After an OS update

The on-device model ships with the OS, so re-run after every macOS update:

1. `make test-eval PROJECT=<project>`
2. Compare the new `.build/eval/character-summaries-*.json` with the last
   one: `operatingSystem` names the build each was run on.
3. Review new `unmatchedFactIDs`: copy the right ones into `acceptable:`,
   and add the wrong ones' claims to `must-not-say.yaml`.
