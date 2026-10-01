///|
/// A tokenizer for Elm source. `@parser.parse_module` takes any `Scanner`;
/// `DefaultScanner` is the built-in one.
pub trait Scanner {
  fn tokenize(Self, SourceText) -> Result[TokenStream, ScanErrorList]
}

///|
/// The built-in Elm 0.19.1 scanner. Make one with `DefaultScanner::new`.
pub struct DefaultScanner {
  dialect : @dialect.Dialect
}

///|
/// A scanner for `dialect` (reserved words and operator symbols). Without
/// `dialect` it uses `Dialect::elm_0_19_1()`. Give the parser the same
/// dialect.
///
/// ```mbt check
/// test {
///   let scanner = @scanner.DefaultScanner::new()
///   let source = @scanner.SourceText::new(
///     "module Main exposing (main)\n\nmain = 1 + 2\n",
///   )
///   guard scanner.tokenize(source) is Ok(stream) else { fail("scan failed") }
///   debug_inspect(
///     stream.tokens.map(t => (t.kind, t.lexeme)),
///     content=(
///       #|[
///       #|  (Keyword(Module), "module"),
///       #|  (Identifier, "Main"),
///       #|  (Keyword(Exposing), "exposing"),
///       #|  (LParen, "("),
///       #|  (Identifier, "main"),
///       #|  (RParen, ")"),
///       #|  (Identifier, "main"),
///       #|  (Equals, "="),
///       #|  (IntLiteral, "1"),
///       #|  (Operator("+"), "+"),
///       #|  (IntLiteral, "2"),
///       #|]
///     ),
///   )
/// }
/// ```
pub fn DefaultScanner::new(
  dialect? : @dialect.Dialect = @dialect.Dialect::elm_0_19_1(),
) -> DefaultScanner {
  { dialect, }
}

///|
/// Split `source` into tokens and attach the trivia to them (see `Token`).
///
/// Returns `Err` with every scan problem (`KR-SCAN-001` to `KR-SCAN-004`)
/// when there is one; then there is no token stream. The scan is lossless:
/// the tokens and their trivia give `source.text` back.
pub fn DefaultScanner::tokenize(
  self : DefaultScanner,
  _source : SourceText,
) -> Result[TokenStream, ScanErrorList] {
  match lex_raw(_source, dialect=self.dialect) {
    Ok(raw_tokens) => Ok(normalize_tokens(raw_tokens))
    Err(errs) => Err(errs)
  }
}

///|
pub impl Scanner for DefaultScanner with fn tokenize(self, source) {
  DefaultScanner::tokenize(self, source)
}
