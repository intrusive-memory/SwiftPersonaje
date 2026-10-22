---
type: doc
---

# Changelog

All notable changes to SwiftPersonaje are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
