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

### Auto-Sync

bd automatically syncs with git:

- Exports to `.beads/issues.jsonl` after changes (5s debounce)
- Imports from JSONL when newer (e.g., after `git pull`)
- No manual export/import needed!

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
