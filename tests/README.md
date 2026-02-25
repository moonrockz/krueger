# Tests

Test artifacts **grow with each implementation story**; they are not all created up front.

- **BDD (Gherkin)**: Add or extend `.feature` files under `tests/features/` when implementing each capability (e.g. tokenizer story adds tokenization scenarios; CLI story adds subcommand scenarios).
- Seed BDD files for design phase:
  - `tests/features/tokenizer.feature`
  - `tests/features/parser.feature`
- **Unit tests**: Whitebox (`*_wbtest.mbt`) and blackbox (`*_test.mbt`) live next to source in `src/` and are added per package per story.
- **E2E**: CLI and WASM component stories add end-to-end tests as part of those issues.

See [docs/plans/elm-parser-initiative.md](../docs/plans/elm-parser-initiative.md) for the full test strategy.
