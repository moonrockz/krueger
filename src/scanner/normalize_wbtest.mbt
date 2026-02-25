///|
fn contains_kind(stream : TokenStream, kind : TokenKind) -> Bool {
  stream.tokens.any(fn(token) { token.kind == kind })
}

///|
fn unwrap_ok(result : Result[TokenStream, ScanErrorList]) -> TokenStream? {
  match result {
    Ok(stream) => Some(stream)
    Err(_) => None
  }
}

///|
test "normalizes module declaration tokens" {
  let source = SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing (add)",
  }
  let scanner = DefaultScanner::new()
  let stream = match unwrap_ok(scanner.tokenize(source)) {
    Some(stream) => stream
    None => fail("expected tokenization success")
  }
  assert_true(contains_kind(stream, TokenKind::module_kw()))
  assert_true(contains_kind(stream, TokenKind::exposing_kw()))
  assert_true(contains_kind(stream, TokenKind::Identifier))
  assert_true(contains_kind(stream, TokenKind::LParen))
  assert_true(contains_kind(stream, TokenKind::RParen))
}
