///|
pub fn[S : @scanner.Scanner] parse_module(
  source : @scanner.SourceText,
  scanner : S,
) -> ParseResult {
  match scanner.tokenize(source) {
    Ok(tokens) => parse_tokens(tokens)
    Err(errs) =>
      ParseResult::{ ast: None, cst: None, diagnostics: errs.diagnostics }
  }
}

///|
pub fn parse_tokens(tokens : @scanner.TokenStream) -> ParseResult {
  let module_name = if tokens.tokens.length() > 1 &&
    tokens.tokens[0].kind == @scanner.TokenKind::module_kw() {
    Some(tokens.tokens[1].lexeme)
  } else {
    None
  }
  ParseResult::{
    ast: Some(ModuleAst::{
      module_name,
      exposing: [],
      imports: [],
      declarations: [],
      span: None,
    }),
    cst: Some(ModuleCst::{ tokens: tokens.tokens, declarations: [], span: None }),
    diagnostics: [],
  }
}
