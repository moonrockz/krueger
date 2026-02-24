# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Overview

This module (`moonrockz/krueger`) is a **parser and parsing utilities** library for
[Elm](https://elm-lang.org/) and [Elmish](https://elmish.github.io/) dialects (e.g.
[Morphir](https://github.com/finos/morphir)). It will provide:

- **Scanner** — tokenization of Elm/Elmish source
- **Parser** — grammar-driven parsing into an AST
- **AST** — algebraic data types for Elm/Elmish syntax (with flexibility similar to moonrockz/gherkin)
- **Visitor interfaces** — pluggable traversal with multiple styles (DOM, fold, SAX-style, etc.)

The design of scanner, parser, AST, and visitor APIs will be done in a follow-up phase;
this repository is set up for CI, release, mise, and moonrockz conventions.

### Architecture Summary (Planned)

```
moonrockz/krueger
├── src/                  # The library (sole artifact for now)
│   ├── lib.mbt           # Package entry point
│   ├── (scanner/)        # Tokenizer — to be designed
│   ├── (parser/)         # Parser — to be designed
│   ├── (ast/)            # AST types — to be designed
│   ├── (visitor/)        # Visitor / fold / SAX APIs — to be designed
│   └── moon.pkg          # Package config
├── docs/plans/           # Design and implementation plans
├── .beads/               # Issue tracking (optional)
└── mise-tasks/          # File-based mise tasks
```

## Library Dependencies

From a library perspective, krueger uses:

| Package | Purpose |
|---------|---------|
| `moonbitlang/core` | Core standard library (builtin, etc.) |
| `moonbitlang/x` | Standard library extensions |
| `moonbitlang/async` | Async execution primitives |
| [bobzhang/lexer](https://mooncakes.io/docs/bobzhang/lexer) | Lexer library (scanner/tokenization) |

These are declared in `moon.mod.json` and in each package’s `moon.pkg` as needed.

## Project Structure

- MoonBit packages are organized per directory; each has a `moon.pkg` (or `moon.pkg.json`) listing dependencies.
- Blackbox tests: `*_test.mbt`; whitebox tests: `*_wbtest.mbt`.
- Top-level `moon.mod.json` describes the module and metadata.

## Design Philosophy

This project follows **functional design principles** (aligned with moonrockz/gherkin and moonrockz/cucumber-expressions):

- **Algebraic data types (ADTs)** for domain concepts (enums + structs).
- **Make invalid states unrepresentable** — use the type system to prevent illegal states.
- **Avoid primitive obsession** — use domain types (e.g. `Token`, `Span`) instead of raw strings/ints.
- **Prefer immutability** — minimal `mut`; favor returning new values.
- **Pattern matching over conditionals** — exhaustive `match` on enums.
- **Total functions** — use `Option`/`Result` or typed `raise` for failures; avoid panic.

Visitor and AST design will aim for **flexibility** similar to moonrockz/gherkin (multiple traversal styles, composable visitors).

## Test-Driven Development (TDD)

- **Red–Green–Refactor**: Write a failing test first, then minimal implementation, then refactor.
- Use `#declaration_only` to sketch public APIs before implementation.
- Use `inspect(...)` for snapshot tests and `assert_eq` for stable results.
- Run `mise run test:unit` for tests; `moon test --update` to refresh snapshots.

## Coding Convention

- MoonBit block style: blocks separated by `///|`; block order irrelevant.
- Deprecated code in `deprecated.mbt` per directory.

## Conventional Commits

All commits MUST use **[Conventional Commits](https://www.conventionalcommits.org)**:

```
type(scope): description
```

Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `style`.
Breaking changes: add `!` after type (e.g. `feat(parser)!: change return type`).

Scopes (examples): `scanner`, `parser`, `ast`, `visitor`, `ci`, `build`.

## Mise Tasks

All operations use **file-based mise tasks** in `mise-tasks/`. Do not add inline `[tasks]` to `.mise.toml`.

| Task                | Purpose                                        |
|---------------------|------------------------------------------------|
| `test:unit`         | Run MoonBit unit tests                         |
| `release:version`   | Compute next version from conventional commits |
| `release:credentials` | Set up mooncakes.io credentials (CI only)    |
| `release:publish`   | Publish package to mooncakes.io               |

## Tooling

- `moon fmt` — format code.
- `moon info` — update generated `.mbti` interface.
- `moon check` — typecheck.
- Run `moon info && moon fmt` before committing when API or formatting may have changed.

## Release Process

- Publishes to **mooncakes.io** and **GitHub Releases**.
- Trigger: push tag `v*` or workflow_dispatch.
- Requires `MOONCAKES_USER_TOKEN` org secret for publish.
- Pre-publish: `moon check`, `moon fmt`, `mise run test:unit`.

## Landing the Plane (Session Completion)

When ending a work session:

1. File issues for remaining work.
2. Run quality gates (tests, fmt, check) if code changed.
3. Update issue status (e.g. bd close / bd update).
4. **PUSH TO REMOTE** — mandatory: `git pull --rebase`, then `git push`. Work is not complete until push succeeds.
5. Clean up; verify all changes committed and pushed; hand off context for next session.
