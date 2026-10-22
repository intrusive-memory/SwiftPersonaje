---
type: doc
title: SwiftPersonaje — Agent Instructions
updated: 2026-10-22
---

# AGENTS.md

Canonical project context for AI agents. `CLAUDE.md` and `GEMINI.md` are
symlinks to this file.

## What this package is

One command per step from a name in the screenplay to a finished .dossier character bundle: the `personaje` CLI and the library behind the Personaje app. See [REQUIREMENTS.md](REQUIREMENTS.md).

## Rules

- **The format is dossier-format's.** Every rule about what a bundle is lives in
  `dossier-format/docs/DOSSIER-FORMAT.md`. If it's silent, raise the question
  there; don't decide it here.
- **Builds and tests** go through the Makefile and `xcodebuild` (XcodeBuildMCP
  locally). Never `swift build` or `swift test`.
- macOS 26, Swift 6.2, strict concurrency. intrusive-memory dependencies use
  the sibling pattern on `development`; releases ship remote-only
  (SwiftReparto `.upToNextMajor(from: "0.2.0")`).
- **Tests use synthetic screenplays only.** This repo is public; never copy
  content from the private podcast repos (REQUIREMENTS §9).
- Work on `development`; `main` takes releases.
