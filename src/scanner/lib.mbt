pub trait Scanner {
  tokenize(Self, SourceText) -> Result[TokenStream, ScanErrorList]
}

pub struct DefaultScanner {}

pub fn DefaultScanner::new() -> DefaultScanner {
  DefaultScanner::{}
}

pub fn DefaultScanner::tokenize(self : DefaultScanner, _source : SourceText) -> Result[TokenStream, ScanErrorList] {
  ignore(self)
  Ok(TokenStream::{ tokens: [] })
}
