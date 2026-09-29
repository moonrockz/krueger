# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Overview

This module (`moonrockz/krueger`) is a **parser and parsing utilities** library for
[Elm](https://elm-lang.org/) and Elm-like dialects (e.g.
[Morphir](https://github.com/finos/morphir)). It will provide:

- **Scanner** — tokenization of Elm/Elm-like source
- **Parser** — grammar-driven parsing into an AST
- **AST** — algebraic data types for Elm/Elm-like syntax (with flexibility similar to moonrockz/gherkin)
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
├── docs/plans/           # Older committed plans (new work documents go in .dev/)
├── .dev/                 # Gitignored working area for specs, plans and scratch files
├── .beads/               # Issue tracking (optional)
└── mise-tasks/          # File-based mise tasks
```

## Library Dependencies

### MoonBit Core Library

Treat these three official `moonbitlang` modules together as the MoonBit core library.
Look in them first before you write a helper or add a third-party dependency.

| Module | Purpose |
|--------|---------|
| `moonbitlang/core` | Standard library that ships with the toolchain (builtin, debug, collections, strings, etc.) |
| [`moonbitlang/x`](https://mooncakes.io/docs/moonbitlang/x) | Official standard library extensions (fs, sys, path, time, json5, crypto, codec, encoding, uuid, decimal, etc.) |
| [`moonbitlang/async`](https://mooncakes.io/docs/moonbitlang/async) | Official async runtime (tasks, task groups, I/O, process, HTTP); native target preferred |

`moonbitlang/core` comes with the toolchain. `moonbitlang/x` and `moonbitlang/async` are
versioned on mooncakes.io, so keep them on the latest release when you bump the toolchain.

### Third-Party Dependencies

| Module | Purpose |
|--------|---------|
| [bobzhang/lexer](https://mooncakes.io/docs/bobzhang/lexer) | Lexer library (scanner/tokenization) |
| [moonrockz/moonspec](https://mooncakes.io/docs/moonrockz/moonspec) | BDD test framework (`src/bdd`, test-only) |

Module dependencies are declared in the `import` block of `moon.mod`. Each package lists
what it uses in its `moon.pkg`. Use `import { ... } for "test"` or `for "wbtest"` for
test-only dependencies.

### Toolchain

- The MoonBit toolchain version is pinned in `.github/workflows/*.yml` (`MOONBIT_VERSION`).
  Keep your local toolchain on the same version (`moon version --all`, `moon upgrade`).
- To upgrade: run `moon upgrade`, bump `MOONBIT_VERSION`, bump the `import` versions in
  `moon.mod`, then run `moon update && moon check && mise run test`. Fix all new
  warnings, not only errors.
- Use `derive(Debug)` (not `derive(Show)`) for data types. `assert_eq` requires `Debug`.
  Implement `Show` by hand only for real text formats.

## Project Structure

- MoonBit packages are organized per directory; each has a `moon.pkg` listing dependencies.
- Blackbox tests: `*_test.mbt`; whitebox tests: `*_wbtest.mbt`. In blackbox tests,
  qualify names from the package under test (for example `@scanner.TokenKind`).
- Top-level `moon.mod` describes the module and metadata (the legacy `moon.mod.json`
  format is deprecated).

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
| `hooks:install`     | Install project git hooks via lefthook         |
| `info:generate`     | Run `moon info` to generate interfaces         |
| `lint:check`        | Run lint/type checks (`moon check`)            |
| `format:check`      | Run formatting checks (`moon fmt --check`)     |
| `check`             | Run all checks (lint + format + tests)         |
| `test:unit`         | Run MoonBit unit tests                         |
| `test:bdd`          | Run MoonSpec BDD tests                         |
| `test:e2e`          | Run end-to-end tests                           |
| `test`              | Run all tests (unit + bdd + e2e)               |
| `release:version`   | Compute next version from conventional commits |
| `release:credentials` | Set up mooncakes.io credentials (CI only)    |
| `release:publish`   | Publish package to mooncakes.io               |

## Tooling

- `moon fmt` — format code.
- `moon info` — update generated `.mbti` interface.
- `moon check` — typecheck.
- Run `moon info && moon fmt` before committing when API or formatting may have changed.

## The `.dev/` Working Area

`.dev/` is a gitignored scratch area for AI-assisted development: temporary scripts, agent and
script outputs, and working documents. Nothing in it is committed. Layout:

- Specs from the superpowers `brainstorming` skill: `.dev/docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
- Plans from the superpowers `writing-plans` skill: `.dev/docs/superpowers/plans/YYYY-MM-DD-<topic>-plan.md`
- Scratch scripts and their outputs: `.dev/scripts/`, `.dev/out/`

This layout overrides the default location of any skill or tool. Never place specs, plans or
other working documents under `docs/`, and never `git add` anything under `.dev/`. When a
design is final and meant for readers, write it up in a committed location on purpose.

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
4. **PUSH TO REMOTE** — mandatory: `bd sync`, then `git pull --rebase` and `git push`. Work is not complete until both pushes succeed.
5. Clean up; verify all changes committed and pushed; hand off context for next session.


<!-- BEGIN BEADS INTEGRATION -->
## Issue Tracking with bd (beads)

**IMPORTANT**: This project uses **bd (beads)** for ALL issue tracking. Do NOT use markdown TODOs, task lists, or other tracking methods.

### Why bd?

- Dependency-aware: Track blockers and relationships between issues
- Git-friendly: Auto-syncs to JSONL for version control
- Agent-optimized: JSON output, ready work detection, discovered-from links
- Prevents duplicate tracking systems and confusion

### Quick Start

**Check for ready work:**

```bash
bd ready --json
```

**Create new issues:**

```bash
bd create "Issue title" --description="Detailed context" -t bug|feature|task -p 0-4 --json
bd create "Issue title" --description="What this issue is about" -p 1 --deps discovered-from:bd-123 --json
```

**Claim and update:**

```bash
bd update bd-42 --status in_progress --json
bd update bd-42 --priority 1 --json
```

**Complete work:**

```bash
bd close bd-42 --reason "Completed" --json
```

### Issue Types

- `bug` - Something broken
- `feature` - New functionality
- `task` - Work item (tests, docs, refactoring)
- `epic` - Large feature with subtasks
- `chore` - Maintenance (dependencies, tooling)

### Priorities

- `0` - Critical (security, data loss, broken builds)
- `1` - High (major features, important bugs)
- `2` - Medium (default, nice-to-have)
- `3` - Low (polish, optimization)
- `4` - Backlog (future ideas)

### Workflow for AI Agents

1. **Check ready work**: `bd ready` shows unblocked issues
2. **Claim your task**: `bd update <id> --status in_progress`
3. **Work on it**: Implement, test, document
4. **Discover new work?** Create linked issue:
   - `bd create "Found bug" --description="Details about what was found" -p 1 --deps discovered-from:<parent-id>`
5. **Complete**: `bd close <id> --reason "Done"`

### Storage and Sync

- bd stores issues in an embedded Dolt database at `.beads/embeddeddolt/` (not committed).
- Git worktrees share the database of the main checkout. Do not create a
  database inside a worktree.
- Cross-machine sync uses a Dolt remote on the GitHub origin. Dolt keeps issue
  history under `refs/dolt/data`, separate from source branches:
  - `bd sync` — pull, check for conflicts, and push in one step.
  - `bd dolt pull` / `bd dolt push` — the individual steps.
- `.beads/issues.jsonl` is a readable snapshot for code review. It is not the
  source of truth. Refresh it before you commit issue changes:
  `bd export -o .beads/issues.jsonl`.

### Setup on a Fresh Clone

```bash
bd bootstrap            # clones refs/dolt/data from origin and wires the Dolt remote
mise run hooks:install  # installs lefthook git hooks (these call `bd hooks run <hook>`)
git config beads.role maintainer   # or contributor
```

### Important Rules

- ✅ Use bd for ALL task tracking
- ✅ Always use `--json` flag for programmatic use
- ✅ Link discovered work with `discovered-from` dependencies
- ✅ Check `bd ready` before asking "what should I work on?"
- ❌ Do NOT create markdown TODO lists
- ❌ Do NOT use external issue trackers
- ❌ Do NOT duplicate tracking systems

For more details, see README.md and docs/QUICKSTART.md.

<!-- END BEADS INTEGRATION -->
