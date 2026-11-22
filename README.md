---
type: doc
updated: 2026-11-15
status: draft
---

# SwiftPersonaje

One command per step from a name in the screenplay to a finished .dossier character bundle: the `personaje` CLI and the library behind the Personaje app.

Each `personaje` command produces one file in a character's `.dossier` bundle and records enough to regenerate it. Bundles follow [dossier-format](https://github.com/intrusive-memory/dossier-format) and are written through [SwiftDossier](https://github.com/intrusive-memory/SwiftDossier). Images, voices and samples are made by the signed `vinetas`, `echada` and `diga` binaries.

> **Status: early.** Three commands so far: `personaje cast-discover`, a
> report on the CAST.md discovery writer ([REQUIREMENTS.md](REQUIREMENTS.md)
> §7.1), `personaje number-scenes` and `personaje evidence`. The rest is requirements only.
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

## `personaje number-scenes`

```
personaje number-scenes [--project <dir>] [--dry-run] [--json]
```

Appends ` #n#` to every unnumbered slugline in the project's screenplays
(the same files `cast-discover` reads). Numbers continue from the last
numbered heading in the file; every other byte is kept as read.

Each file that changes is first copied to
`<project>/.personaje/backups/<timestamp>/<path relative to the project>`,
where `<timestamp>` is UTC ISO 8601 basic form without colons
(`20261118T120000Z`), one per run. Nothing is pruned. The first time there is
something to number, `.personaje/` is appended to the project's `.gitignore`
(created if needed) unless it already ignores it. The command never commits.

`--dry-run` prints, per file, how many headings would be numbered and the new
heading lines, and writes nothing: no file, no backup, no `.gitignore`. If a
file fails, it is left as it was (restored from its backup if the write had
started), the other files are still processed, and the command exits
non-zero. `--json` prints the same report as JSON (`files[].status`,
`count`, `headings`, `backup`; `backupDirectory`; `gitignore`; `failed`).

## `personaje evidence`

```
personaje evidence <CHARACTER> [--project <dir>] [--json]
```

Everything the screenplays say about one CAST.md member, each item with its
source. The text output gives the tier (the CAST.md `role` when set,
otherwise computed from dialogue and scene share), the accent and where it
came from, then the items grouped by kind (dialogue, introductions, group
statements), each quoted with `<episode> sc <n>`.

`CHARACTER` must be a CAST.md member; the match ignores case. An unknown name
prints `unknown character: <NAME>` to stderr and exits non-zero. Read only.

`--json` prints only JSON on stdout: `{"member", "role"?, "tier",
"evidence"}`, where `evidence` is the `CharacterEvidence` Codable form
(`member`, `items`, `windows`, `accent`). Context windows are emitted whole;
the output stays under 12,000 characters (about 3k tokens) for every member of
the test fixture.

## Build

```
make build    # xcodebuild, macOS arm64
make test
make test-eval  # model-backed character-summary evaluation; local only
make install  # ./bin/personaje
make help
```

See [Docs/build-and-test.md](Docs/build-and-test.md).

Part of the [intrusive-memory](https://github.com/intrusive-memory) ecosystem.
