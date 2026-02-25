///|
pub using @scanner {
  trait Scanner,
  type Severity,
  type Position,
  type Span,
  type SourceText,
  type Diagnostic,
  type CommentKind,
  type KeywordKind,
  type Comment,
  type Trivia,
  type TokenKind,
  type Token,
  type TokenStream,
  type ScanErrorList,
}

///|
pub using @parser {type ParseResult, type ModuleAst, type ModuleCst}

///|
/// Krueger — Parser and parsing utilities for Elm and Elm-like dialects (e.g. Morphir).
///
/// This module will provide scanner, parser, AST, and visitor interfaces
/// with flexibility similar to moonrockz/gherkin. Project setup only;
/// scanner/parser/AST/visitor design in a follow-up.
pub fn version() -> String {
  "0.1.0"
}

///|
pub fn tokenize(source : SourceText) -> Result[TokenStream, ScanErrorList] {
  @scanner.DefaultScanner::new().tokenize(source)
}

///|
pub fn parse_module(source : SourceText) -> ParseResult {
  @parser.parse_module(source, @scanner.DefaultScanner::new())
}

///|
pub fn parse_tokens(tokens : TokenStream) -> ParseResult {
  @parser.parse_tokens(tokens)
}
