# Tests

Test artifacts **grow with each implementation story**; they are not all created up front.

- **BDD (Gherkin + MoonSpec)**:
  - Feature files live under `tests/features/`.
  - MoonSpec world tests live in `src/bdd/` and run feature scenarios via
    `@moonspec.FeatureSource::File(...)`.
  - `test:bdd` executes the MoonSpec BDD suite.
- Seed BDD files for design phase:
  - `tests/features/tokenizer.feature`
  - `tests/features/parser.feature`
- **Unit tests**: Whitebox (`*_wbtest.mbt`) and blackbox (`*_test.mbt`) live next to source in `src/` and are added per package per story.
- **E2E**: CLI and WASM component stories add end-to-end tests as part of those issues.
  Current e2e placeholder tests live in `src/e2e/` and run via `test:e2e`.

## Commands

- `mise run test:unit` - unit/whitebox/blackbox package tests
- `mise run test:bdd` - MoonSpec-driven BDD scenarios from `tests/features/`
- `mise run test:e2e` - end-to-end test package(s)
- `mise run test` - aggregate test command (depends on all test task types)

See [docs/plans/elm-parser-initiative.md](../docs/plans/elm-parser-initiative.md) for the full test strategy.
