---
type: doc
updated: 2026-11-15
status: draft
---

# SwiftPersonaje

One command per step from a name in the screenplay to a finished .dossier character bundle: the `personaje` CLI and the library behind the Personaje app.

Each `personaje` command produces one file in a character's `.dossier` bundle and records enough to regenerate it. Bundles follow [dossier-format](https://github.com/intrusive-memory/dossier-format) and are written through [SwiftDossier](https://github.com/intrusive-memory/SwiftDossier). Images, voices and samples are made by the signed `vinetas`, `echada` and `diga` binaries.

> **Status: early.** One command so far: `personaje cast-discover`, a
> report on the CAST.md discovery writer ([REQUIREMENTS.md](REQUIREMENTS.md)
> §7.1). The rest is requirements only.
>
> Requires SwiftReparto 0.4.0 (`canonicalName`, `lineCount`).

## `personaje cast-discover`

```
personaje cast-discover [--project <dir>] [--dry-run] [--json]
```

Reports what discovery would do to `CAST.md`, beside `PROJECT.md`: every
character who speaks in the project's screenplays that it would add, and
each member's line count (character cues across every episode), old and
new. The screenplays are the files under `episodesDir` (default `episodes`)
that match `filePattern` (default `*.fountain`; a comma-separated string
names episode files one by one).

**Report only: it never writes `CAST.md`.** The Personaje app is the only
builder of `CAST.md`, through the same library writer. `--dry-run` is
accepted and changes nothing; `--json` prints the full report.

From code, `CastDiscovery.discover(screenplays:castFile:dryRun:)` builds or
extends `CAST.md`, and `CastDiscovery.discover(from:castFile:dryRun:)` takes a
SwiftCompartido `CharacterCollectionResult` you already have. The writer sets
`character` and `lineCount` on discovered members. Nothing already in
`CAST.md` is reordered or removed, nothing a person wrote is changed, and two
different names are never joined; only the derived `lineCount` is replaced.
It writes when a member is added or a count changes, and otherwise leaves the
file byte for byte as it was.

## Build

```
make build    # xcodebuild, macOS arm64
make test
make install  # ./bin/personaje
make help
```

Part of the [intrusive-memory](https://github.com/intrusive-memory) ecosystem.
