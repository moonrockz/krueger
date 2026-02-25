# moonrockz/krueger

Parser and parsing utilities for [Elm](https://elm-lang.org/) and Elm-like dialects (such as [Morphir](https://github.com/finos/morphir)) in MoonBit.

## Status

**Project setup only.** Scanner, parser, AST, and visitor interfaces will be designed and implemented in a follow-up phase. The repository is configured with:

- MoonBit module and single-package layout
- CI (lint + unit tests) and Release (validate → publish → GitHub Release) pipelines
- Mise and file-based tasks (`lint:check`, `format:check`, `check`, `test:unit`, `test:bdd`, `test:e2e`, `test`, `release:version`, `release:credentials`, `release:publish`)
- AGENTS.md / CLAUDE.md and conventional commits

## Installation

```bash
moon add moonrockz/krueger
```

## Usage (future)

Once the library is implemented, you can expect APIs along the lines of:

- **Scanner**: tokenize Elm/Elm-like source into a token stream.
- **Parser**: parse tokens (or source) into an AST.
- **AST**: algebraic types for modules, declarations, expressions, etc.
- **Visitors**: flexible traversal (DOM, fold, SAX-style), similar to moonrockz/gherkin.

## License

Apache-2.0
