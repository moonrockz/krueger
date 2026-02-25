# Tokenizer (Scanner) q56.2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement `krueger-q56.2` with a hybrid scanner that produces a token stream with trivia/comments, scanner diagnostics, and MoonSpec-backed BDD coverage.

**Architecture:** Build `src/scanner/` as a backend-agnostic scanner facade and a default `bobzhang/lexer` adapter path. Keep token normalization, trivia attachment, and diagnostics as separate modules so parser integration (`q56.3`) can depend only on scanner contracts. Add dedicated `test:bdd`, `test:e2e`, and aggregate `test` mise tasks.

**Tech Stack:** MoonBit, `bobzhang/lexer`, `moonrockz/moonspec`, `moonbitlang/async`, file-based `mise` tasks.

---

### Task 1: Add Dependencies and Test Task Skeleton

**Files:**
- Modify: `moon.mod.json`
- Modify: `mise-tasks/test/unit`
- Create: `mise-tasks/test/bdd`
- Create: `mise-tasks/test/e2e`
- Create: `mise-tasks/test/_default`

**Step 1: Write the failing test**

Run:
```bash
mise run test:bdd
```

Expected: task missing error (`No task named test:bdd`).

**Step 2: Run test to verify it fails**

Run:
```bash
mise run test
```

Expected: task missing error for aggregate `test`.

**Step 3: Write minimal implementation**

Use these scripts:

```bash
#!/usr/bin/env bash
# mise-tasks/test/bdd
#MISE description="Run MoonSpec BDD tests"
set -euo pipefail
moon test tests/bdd --target js
```

```bash
#!/usr/bin/env bash
# mise-tasks/test/e2e
#MISE description="Run e2e tests"
set -euo pipefail
moon test tests/e2e --target js
```

```bash
#!/usr/bin/env bash
# mise-tasks/test/_default
#MISE description="Run all tests"
#MISE depends=["test:unit", "test:bdd", "test:e2e"]
set -euo pipefail
echo "All tests passed."
```

Update `mise-tasks/test/unit` to run only unit tests:

```bash
moon test src --target js
```

Update `moon.mod.json` deps:

```json
{
  "deps": {
    "moonbitlang/x": "0.4.40",
    "moonbitlang/async": "0.16.6",
    "bobzhang/lexer": "<latest-compatible>",
    "moonrockz/moonspec": "<latest-compatible>"
  }
}
```

Local dev override option (optional while iterating):

```json
"moonrockz/moonspec": { "path": "/home/damian/code/repos/github/moonrockz/moonspec" }
```

**Step 4: Run test to verify it passes**

Run:
```bash
mise run test:unit
```

Expected: existing unit suite passes.

**Step 5: Commit**

```bash
git add moon.mod.json mise-tasks/test/unit mise-tasks/test/bdd mise-tasks/test/e2e mise-tasks/test/_default
git commit -m "build(test): add bdd e2e and aggregate mise tasks"
```

### Task 2: Scaffold BDD and E2E Test Packages

**Files:**
- Create: `tests/bdd/moon.pkg`
- Create: `tests/bdd/tokenizer_world_wbtest.mbt`
- Create: `tests/e2e/moon.pkg`
- Create: `tests/e2e/smoke_test.mbt`

**Step 1: Write the failing test**

Add a BDD world test that calls a non-existent tokenizer API:

```moonbit
async test "Feature: Elm tokenizer baseline" {
  let options = @moonspec.RunOptions::new([@moonspec.FeatureSource::File("tests/features/tokenizer.feature")])
  @moonspec.run_or_fail(TokenizerWorld::default, options) |> ignore
}
```

Expected compile failure because `TokenizerWorld` and scanner API are not implemented yet.

**Step 2: Run test to verify it fails**

Run:
```bash
mise run test:bdd
```

Expected: compile error referencing missing world or scanner symbols.

**Step 3: Write minimal implementation**

Add package manifests:

```moonbit
// tests/bdd/moon.pkg
import {
  "moonrockz/krueger",
  "moonrockz/moonspec",
  "moonbitlang/async",
}
```

```moonbit
// tests/e2e/moon.pkg
import {
  "moonrockz/krueger",
}
```

Add placeholder e2e test:

```moonbit
test "e2e placeholder until CLI/WASM tasks land" {
  assert_true(true)
}
```

**Step 4: Run test to verify it passes**

Run:
```bash
mise run test:e2e
```

Expected: e2e package passes with placeholder test.

**Step 5: Commit**

```bash
git add tests/bdd/moon.pkg tests/bdd/tokenizer_world_wbtest.mbt tests/e2e/moon.pkg tests/e2e/smoke_test.mbt
git commit -m "test(bdd): scaffold moonspec and e2e test packages"
```

### Task 3: Define Scanner Contracts and Domain Types (@superpowers:test-driven-development)

**Files:**
- Create: `src/scanner/moon.pkg`
- Create: `src/scanner/types.mbt`
- Create: `src/scanner/lib.mbt`
- Create: `src/scanner/types_test.mbt`
- Create: `src/scanner/lib_test.mbt`

**Step 1: Write the failing test**

Create tests that assert type construction and scanner contract usage:

```moonbit
test "token stream contains tokens in order" {
  let t1 = Token::{ kind: TokenKind::Identifier, lexeme: "add", span: dummy_span(), trivia_before: [], trivia_after: [] }
  let t2 = Token::{ kind: TokenKind::IntLiteral, lexeme: "1", span: dummy_span(), trivia_before: [], trivia_after: [] }
  let stream = TokenStream::{ tokens: [t1, t2] }
  assert_eq(stream.tokens.length(), 2)
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
moon test src/scanner --target js
```

Expected: type/symbol not found errors for scanner contracts.

**Step 3: Write minimal implementation**

Add minimal enums/structs/trait:

```moonbit
pub enum CommentKind { Line Block Doc }
pub enum Trivia { Whitespace(String, Span) Newline(String, Span) Comment(Comment) }
pub trait Scanner {
  tokenize(source : SourceText) -> Result[TokenStream, ScanErrorList]
}
```

**Step 4: Run test to verify it passes**

Run:
```bash
moon test src/scanner --target js
```

Expected: scanner contract tests pass.

**Step 5: Commit**

```bash
git add src/scanner/moon.pkg src/scanner/types.mbt src/scanner/lib.mbt src/scanner/types_test.mbt src/scanner/lib_test.mbt
git commit -m "feat(scanner): add scanner contracts and domain types"
```

### Task 4: Expose Scanner Facade from Root Package

**Files:**
- Modify: `src/lib.mbt`
- Create: `src/lib_test.mbt` (replace placeholder with scanner-facing tests)

**Step 1: Write the failing test**

Add root-level test expecting exported tokenize API:

```moonbit
test "root package exposes scanner tokenize entrypoint" {
  let source = SourceText::{ module_name: None, text: "module Main exposing (..)" }
  let _ = tokenize(source)
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
mise run test:unit
```

Expected: `tokenize` symbol missing from root package.

**Step 3: Write minimal implementation**

Expose scanner types and entrypoint in `src/lib.mbt` by delegating to default scanner.

**Step 4: Run test to verify it passes**

Run:
```bash
mise run test:unit
```

Expected: root package tests compile and pass.

**Step 5: Commit**

```bash
git add src/lib.mbt src/lib_test.mbt
git commit -m "feat(scanner): expose scanner facade from root package"
```

### Task 5: Implement Token Normalization and Basic Lexing Path (@superpowers:test-driven-development)

**Files:**
- Create: `src/scanner/bobzhang_adapter.mbt`
- Create: `src/scanner/normalize.mbt`
- Create: `src/scanner/normalize_wbtest.mbt`
- Modify: `src/scanner/lib.mbt`

**Step 1: Write the failing test**

Add normalization tests for v1 anchors:

```moonbit
test "normalizes module declaration tokens" {
  let source = SourceText::{ module_name: None, text: "module Main exposing (add)" }
  let stream = tokenize_or_fail(source)
  assert_true(has_token(stream, TokenKind::ModuleKw))
  assert_true(has_token(stream, TokenKind::Identifier))
  assert_true(has_token(stream, TokenKind::LParen))
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
moon test src/scanner --target js
```

Expected: failing assertions for missing token mapping.

**Step 3: Write minimal implementation**

Implement adapter + normalization map for initial token set:
- keywords (`module`, `import`, `type`, `alias`, `if`, `then`, `else`, `let`, `in`, `case`, `of`)
- identifiers
- integer/string literals
- punctuation/operators needed by current scenarios

**Step 4: Run test to verify it passes**

Run:
```bash
moon test src/scanner --target js
```

Expected: normalization tests pass.

**Step 5: Commit**

```bash
git add src/scanner/bobzhang_adapter.mbt src/scanner/normalize.mbt src/scanner/normalize_wbtest.mbt src/scanner/lib.mbt
git commit -m "feat(scanner): implement initial token normalization"
```

### Task 6: Implement Trivia and Comment/Doc-Comment Classification

**Files:**
- Create: `src/scanner/trivia.mbt`
- Create: `src/scanner/trivia_wbtest.mbt`
- Modify: `src/scanner/lib.mbt`
- Modify: `tests/features/tokenizer.feature`

**Step 1: Write the failing test**

Add whitebox and BDD assertions for comment kinds and trivia placement:

```moonbit
test "classifies doc comment and preserves as trivia" {
  let src = SourceText::{ module_name: None, text: "{-| Adds one -}\nadd x = x + 1" }
  let stream = tokenize_or_fail(src)
  assert_true(first_token_has_doc_comment(stream))
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
mise run test:bdd
```

Expected: undefined step or failed assertion for doc-comment/trivia behavior.

**Step 3: Write minimal implementation**

Implement `Trivia` attachment rules:
- preserve whitespace/newline/comment between significant tokens,
- classify `--`, `{- -}`, and `{-| -}` comment forms,
- attach to `trivia_before` of next token.

Implement/update MoonSpec step definitions in `tests/bdd/tokenizer_world_wbtest.mbt`.

**Step 4: Run test to verify it passes**

Run:
```bash
mise run test:bdd
```

Expected: tokenizer feature scenarios for success + comment/doc-comment pass.

**Step 5: Commit**

```bash
git add src/scanner/trivia.mbt src/scanner/trivia_wbtest.mbt src/scanner/lib.mbt tests/features/tokenizer.feature tests/bdd/tokenizer_world_wbtest.mbt
git commit -m "feat(scanner): preserve trivia and classify comments"
```

### Task 7: Implement Scanner Diagnostics (`KR-SCAN-001..003`)

**Files:**
- Create: `src/scanner/diagnostics.mbt`
- Create: `src/scanner/diagnostics_wbtest.mbt`
- Modify: `src/scanner/lib.mbt`
- Modify: `tests/features/tokenizer.feature`

**Step 1: Write the failing test**

Add tests for malformed block comment and invalid sequence diagnostics:

```moonbit
test "unterminated block comment returns KR-SCAN-001 with eof span" {
  let src = SourceText::{ module_name: None, text: "{- missing close" }
  let err = tokenize_err_or_fail(src)
  assert_eq(err.diagnostics[0].code, "KR-SCAN-001")
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
moon test src/scanner --target js
```

Expected: diagnostic code/span assertions fail.

**Step 3: Write minimal implementation**

Emit diagnostics:
- `KR-SCAN-001`: unterminated block comment,
- `KR-SCAN-002`: malformed doc comment form,
- `KR-SCAN-003`: invalid/unknown lexeme.

Ensure deterministic ordering and span accuracy.

**Step 4: Run test to verify it passes**

Run:
```bash
mise run test:bdd
mise run test:unit
```

Expected: malformed comment BDD scenario and unit diagnostic tests pass.

**Step 5: Commit**

```bash
git add src/scanner/diagnostics.mbt src/scanner/diagnostics_wbtest.mbt src/scanner/lib.mbt tests/features/tokenizer.feature tests/bdd/tokenizer_world_wbtest.mbt
git commit -m "fix(scanner): add malformed comment and invalid token diagnostics"
```

### Task 8: Full Verification and Issue Closure Prep (@superpowers:verification-before-completion)

**Files:**
- Modify: `tests/README.md` (document MoonSpec and new test tasks)
- Modify: `docs/plans/elm-parser-initiative.md` (mark q56.2 completion criteria evidence if needed)

**Step 1: Write the failing test**

Run aggregate test before docs updates:

```bash
mise run test
```

Expected: if any suite fails, capture and fix before finalizing docs.

**Step 2: Run test to verify it fails**

If failing, fix only failing behavior and re-run until green.

**Step 3: Write minimal implementation**

Update docs with exact commands:
- `mise run test:unit`
- `mise run test:bdd`
- `mise run test:e2e`
- `mise run test`

**Step 4: Run test to verify it passes**

Run:
```bash
moon info
moon fmt
moon check
mise run test:unit
mise run test:bdd
mise run test:e2e
mise run test
```

Expected: all commands succeed.

**Step 5: Commit**

```bash
git add tests/README.md docs/plans/elm-parser-initiative.md
git commit -m "docs(test): document moonspec bdd and aggregate test tasks"
```

## Final Landing Sequence

1. `bd show krueger-q56.2 --json` and confirm acceptance criteria are met.
2. `bd close krueger-q56.2 --reason "Completed" --json`.
3. `git pull --rebase`.
4. `git push`.
5. Confirm clean status: `git status --short`.
