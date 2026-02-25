# Tokenizer (Scanner) Design for `krueger-q56.2`

Date: 2026-02-25
Status: Approved
Issue: `krueger-q56.2`

## Scope

Tokenizer implementation for the moderate v1 language scope from
`docs/plans/elm-parser-initiative.md`:

1. Module declaration and exposing clause tokens.
2. Import declaration tokens.
3. Type alias and simple union type tokens.
4. Function declarations and type annotation tokens.
5. Core expression tokens (literals, refs, calls, lambda, let-in, if-then-else, case-of).
6. Comments/doc-comments and malformed comment diagnostics.

## Approach Decision

Chosen approach: **hybrid scanner**.

- Use `bobzhang/lexer` for base lexeme recognition.
- Add a Krueger scanner layer for:
  - token kind normalization,
  - trivia/comment/doc-comment classification,
  - source span tracking,
  - scanner diagnostics.
- Keep parser integration behind scanner facade so backend can be swapped later.

## Architecture

Add `src/scanner/` package boundary with a default `BobzhangScanner` adapter.

Planned internal modules:

- `types.mbt`: `TokenKind`, `Token`, `Trivia`, `Comment`, span-related types.
- `bobzhang_adapter.mbt`: wraps raw lexing from `bobzhang/lexer`.
- `normalize.mbt`: maps raw categories to Krueger `TokenKind`.
- `trivia.mbt`: attaches whitespace/newline/comment trivia to tokens.
- `diagnostics.mbt`: scanner diagnostic codes/messages/builders.

Scanner contract:

```moonbit
pub trait Scanner {
  tokenize(source : SourceText) -> Result[TokenStream, ScanErrorList]
}
```

## Data Flow

Pipeline (single pass over source):

1. Raw lexing via adapter.
2. Normalize into Krueger token kinds with stable lexemes.
3. Classify trivia (`Whitespace`, `Newline`, `Comment`).
4. Attach trivia primarily to `token.trivia_before`.
5. Collect diagnostics and decide `Ok(TokenStream)` vs `Err(ScanErrorList)`.

Span requirements:

- `offset/line/column` monotonic across all emitted tokens/trivia/diagnostics.
- Unterminated constructs span from opening delimiter to EOF.

Comment mapping:

- `-- ...` => `CommentKind::Line`
- `{- ... -}` => `CommentKind::Block`
- `{-| ... -}` => `CommentKind::Doc`

## Diagnostics

Initial scanner diagnostic codes:

- `KR-SCAN-001`: unterminated block comment
- `KR-SCAN-002`: malformed doc comment form
- `KR-SCAN-003`: invalid or unknown character sequence

Rules:

- Deterministic ordering.
- `Severity::Error` for hard scan failures.
- No panics on malformed source.

## Testing Strategy (MoonSpec + Unit Tests)

BDD runner requirement: use `moonrockz/moonspec`.

BDD layer:

- Keep features in `tests/features/tokenizer.feature`.
- Execute via MoonSpec world/steps and `FeatureSource::File(...)`.
- Add scenarios for:
  - existing success and malformed comment cases,
  - comment kind classification,
  - v1 token coverage anchors,
  - invalid character diagnostics.

Unit layers:

- Whitebox (`*_wbtest.mbt`): normalization, trivia ordering, span monotonicity.
- Blackbox (`*_test.mbt`): public tokenize API behavior.

TDD sequence:

1. Add failing BDD scenarios.
2. Add failing unit tests.
3. Implement minimal scanner behavior.
4. Refactor with all tests green.

## Mise Task Topology

Create/standardize test tasks:

- `test:unit` -> MoonBit unit tests.
- `test:bdd` -> MoonSpec BDD execution.
- `test:e2e` -> integration/e2e tests (CLI/WASM as implemented; placeholder allowed for now).
- `test` -> aggregate default task via `mise-tasks/test/_default`:
  - `#MISE depends=["test:unit", "test:bdd", "test:e2e"]`

This gives one canonical full-check command: `mise run test`.

## Exit Criteria for `krueger-q56.2`

1. Scanner contract implemented with backend abstraction boundary preserved.
2. Comments and doc comments preserved in trivia with correct classification.
3. Malformed comment and invalid-sequence diagnostics emitted with spans/codes.
4. `test:unit`, `test:bdd`, and aggregate `test` pass.
5. `moon check`, `moon fmt`, and `moon info` pass.
6. Output is consumable by upcoming parser issue `krueger-q56.3` without changing scanner contract.
