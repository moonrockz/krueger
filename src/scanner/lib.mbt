///|
pub trait Scanner {
  fn tokenize(Self, SourceText) -> Result[TokenStream, ScanErrorList]
}

///|
pub struct DefaultScanner {
  dialect : @dialect.Dialect
}

///|
/// A scanner for `dialect` (reserved words and operator symbols).
pub fn DefaultScanner::new(
  dialect? : @dialect.Dialect = @dialect.Dialect::elm_0_19_1(),
) -> DefaultScanner {
  { dialect, }
}

///|
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
