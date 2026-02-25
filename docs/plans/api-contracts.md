# API Contracts (Design Phase)

This document defines implementation-facing contracts for the
`moonrockz/krueger` design phase (`krueger-q56.1`). Signatures are design
sketches and may be refined for idiomatic MoonBit syntax during implementation,
but behavior contracts and invariants are normative.

## Goals

1. Keep scanner backend pluggable.
2. Separate semantic AST from source-faithful CST.
3. Make diagnostics stable and machine-readable.
4. Preserve comments and doc comments without losing source fidelity.

## Common types

```moonbit
pub enum Severity {
  Error
  Warning
  Info
}

pub struct Position {
  offset : Int
  line : Int
  column : Int
}

pub struct Span {
  start : Position
  end : Position
}

pub struct SourceText {
  module_name : Option[String]
  text : String
}

pub struct Diagnostic {
  code : String
  severity : Severity
  message : String
  span : Span
}
```

## Scanner contracts (`krueger-q56.2`)

### Scanner facade

```moonbit
pub trait Scanner {
  tokenize(source : SourceText) -> Result[TokenStream, ScanErrorList]
}
```

### Tokens, trivia, and comments

```moonbit
pub enum CommentKind {
  Line
  Block
  Doc
}

pub struct Comment {
  kind : CommentKind
  text : String
  span : Span
}

pub enum Trivia {
  Whitespace(String, Span)
  Newline(String, Span)
  Comment(Comment)
}

pub enum TokenKind {
  // Keywords, operators, punctuation, identifiers, literals...
}

pub struct Token {
  kind : TokenKind
  lexeme : String
  span : Span
  trivia_before : Array[Trivia]
  trivia_after : Array[Trivia]
}

pub struct TokenStream {
  tokens : Array[Token]
}

pub struct ScanErrorList {
  diagnostics : Array[Diagnostic]
}
```

### Scanner invariants

1. `Token.span` and diagnostic spans are source-accurate and monotonic.
2. All comments are preserved in trivia.
3. Malformed comment constructs produce diagnostics with error code and span.
4. Scanner implementation is swappable behind `Scanner` trait.

## Parser contracts (`krueger-q56.3`)

```moonbit
pub struct ParseResult {
  ast : Option[ModuleAst]
  cst : Option[ModuleCst]
  diagnostics : Array[Diagnostic]
}

pub fn parse_module(source : SourceText, scanner : Scanner) -> ParseResult
pub fn parse_tokens(tokens : TokenStream) -> ParseResult
```

### Parser invariants

1. Parser never panics on malformed source; errors flow through diagnostics.
2. Partial recovery is allowed; parser may return partial AST/CST plus errors.
3. AST and CST spans are internally consistent with token spans.

## AST contracts (`krueger-q56.4`)

```moonbit
pub struct DocComment {
  text : String
  span : Span
}

pub struct DeclMeta {
  doc_comment : Option[DocComment]
  span : Span
}

pub enum Declaration {
  // FunctionDecl(meta, ...)
  // TypeAliasDecl(meta, ...)
  // UnionTypeDecl(meta, ...)
}

pub struct ModuleAst {
  // module header, imports, declarations
}
```

### Doc comment attachment rule

Doc comments are attached to the next declaration only when no token other than
whitespace/newlines exists between the doc comment and declaration. If a regular
comment appears between them, the doc comment is not attached to AST metadata.

## CST contracts (`krueger-q56.5`)

```moonbit
pub struct ModuleCst {
  // concrete nodes preserving source order/layout/comments
}
```

### CST invariants

1. All comments remain recoverable in source order.
2. Layout/trivia fidelity is maintained for tooling use cases.
3. CST preserves enough information for precise source mapping.

## Visitor contracts (`krueger-q56.6..q56.10`)

### DOM

Tree-centric traversal on full AST/CST structures.

### Accept visitor

`node.accept(visitor)` depth-first callbacks with overridable hooks.

### Fold

Fold traversal with accumulator and explicit control:
`Continue`, `SkipChildren`, `Stop`.

### Push SAX

Push events emitted during traversal/parsing; no full tree required.

### Pull cursor

Iterator-style event stream consumed on demand.

## WASM contracts (`krueger-q56.11`, `krueger-q56.12`)

1. Core wasm exports scanner/parser operations with deterministic serialization.
2. Component model wraps core with WIT-defined interfaces.
3. Host e2e tests validate token/parse outputs and diagnostics.

## CLI contracts (`krueger-q56.13`)

1. `krueger tokenize` and `krueger lex` accept source input.
2. Output is stable and machine-readable (schema to be finalized during
   implementation).
3. Non-zero exit status for unrecoverable errors.
4. Diagnostics include code, message, and span.
