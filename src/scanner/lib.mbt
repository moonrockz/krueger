///|
pub trait Scanner {
  tokenize(Self, SourceText) -> Result[TokenStream, ScanErrorList]
}

///|
pub struct DefaultScanner {}

///|
pub fn DefaultScanner::new() -> DefaultScanner {
  DefaultScanner::{  }
}

///|
pub fn DefaultScanner::tokenize(
  self : DefaultScanner,
  _source : SourceText,
) -> Result[TokenStream, ScanErrorList] {
  ignore(self)
  match lex_raw(_source) {
    Ok(raw_tokens) => Ok(normalize_tokens(raw_tokens))
    Err(errs) => Err(errs)
  }
}

///|
pub impl Scanner for DefaultScanner with tokenize(self, source) {
  DefaultScanner::tokenize(self, source)
}
