---
type: doc
updated: 2026-10-22
status: draft
---

# SwiftPersonaje

One command per step from a name in the screenplay to a finished .dossier character bundle: the `personaje` CLI and the library behind the Personaje app.

Each `personaje` command produces one file in a character's `.dossier` bundle and records enough to regenerate it. Bundles follow [dossier-format](https://github.com/intrusive-memory/dossier-format) and are written through [SwiftDossier](https://github.com/intrusive-memory/SwiftDossier). Images, voices and samples are made by the signed `vinetas`, `echada` and `diga` binaries.

> **Status: early.** One command so far: `personaje cast-discover`, the
> CAST.md discovery writer ([REQUIREMENTS.md](REQUIREMENTS.md) §7.1). The
> rest is requirements only.
>
> Requires SwiftReparto 0.2.0 (`canonicalName`).

## `personaje cast-discover`

```
personaje cast-discover [--project <dir>] [--dry-run] [--json]
```

Adds every character who speaks in the project's screenplays to `CAST.md`,
beside `PROJECT.md`. The screenplays are the files under `episodesDir`
(default `episodes`) that match `filePattern` (default `*.fountain`; a
comma-separated string names episode files one by one). Only the character
name is written. Nothing already in `CAST.md` is changed, reordered or
removed, and two different names are never joined. One run over every
episode and one run per episode, in any order, give the same file.
`--dry-run` prints what it would add and writes nothing.

From code, `CastDiscovery.discover(screenplays:castFile:dryRun:)` does the
same thing, and `CastDiscovery.discover(from:castFile:dryRun:)` takes a
SwiftCompartido `CharacterCollectionResult` you already have.

## Build

```
make build    # xcodebuild, macOS arm64
make test
make install  # ./bin/personaje
make help
```

Part of the [intrusive-memory](https://github.com/intrusive-memory) ecosystem.
