///|
pub using @scanner {
  trait Scanner,
  type Severity,
  type Position,
  type Span,
  type SourceText,
  type Diagnostic,
  type CommentKind,
  type Comment,
  type Trivia,
  type TokenKind,
  type Token,
  type TokenStream,
  type ScanErrorList,
}

///|
/// Krueger — Parser and parsing utilities for Elm and Elmish (e.g. Morphir).
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
