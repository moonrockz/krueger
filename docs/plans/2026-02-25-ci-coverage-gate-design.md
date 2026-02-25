# CI Coverage Reporting And PR Coverage Gate Design

## Context

The repository currently has CI jobs for formatting, checking, and unit tests, but no code coverage reporting or threshold enforcement.

The request is:

1. Increase code coverage by adding tests.
2. Add a coverage gate to CI.
3. On push, still calculate coverage but do not fail for low coverage (warn only).
4. Gate threshold is 80%.
5. Blocking behavior should apply to pull requests only.

## Goals

1. Compute coverage in CI from MoonBit coverage artifacts.
2. Enforce project-wide minimum branch coverage of 80% for `pull_request` runs.
3. Emit visible warning (without failing) for low coverage on `push` runs.
4. Improve baseline coverage by adding targeted missing tests.

## Constraints

1. Local developer checks should not fail on coverage.
2. `moon coverage report` may not be available in all environments due missing `moon_cove_report` utility.
3. Coverage pipeline should stay toolchain-native and lightweight.

## Options Considered

### Option A: `moon coverage report` + built-in fail flags

- Pros: Native formatted reports and threshold options.
- Cons: Depends on `moon_cove_report` binary being present in every environment.

### Option B: Parse MoonBit raw coverage artifacts directly (chosen)

- Pros: Works wherever `moon test --enable-coverage` works, no external service needed.
- Cons: Requires a small custom parser script.

### Option C: External hosted coverage service

- Pros: Nice dashboards and trend history.
- Cons: Extra integration complexity and dependency on external service.

## Chosen Design

1. Add a script that:
   - runs tests with coverage instrumentation for unit, BDD, and E2E packages,
   - parses `_build/moonbit_coverage_*.txt` artifacts,
   - aggregates counters and computes overall covered/total branch points,
   - supports `warn` and `gate` modes with configurable threshold.
2. Add mise tasks for CI coverage commands.
3. Add a CI `coverage` job in `.github/workflows/ci.yml`:
   - for `pull_request`: run in `gate` mode with threshold 80 (blocking),
   - for `push`: run in `warn` mode with threshold 80 (non-blocking for low coverage).
4. Add additional tests around parser scanner-diagnostic passthrough and parser surface behavior to increase baseline coverage.

## Success Criteria

1. CI prints a coverage summary on push and pull request.
2. Pull requests fail when coverage is below 80%.
3. Push builds do not fail solely for low coverage.
4. Coverage-related tests and checks pass in local verification.
