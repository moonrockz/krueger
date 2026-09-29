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

///|
test "keeps comments after the last token as its trailing trivia" {
  let source = SourceText::{
    module_name: None,
    text: "module A exposing (T) -- end\n\n-- last\n",
  }
  guard DefaultScanner::new().tokenize(source) is Ok(stream) else {
    fail("expected tokenization success")
  }
  let last = stream.tokens[stream.tokens.length() - 1]
  let comments = last.trivia_after.filter_map(t => {
    match t {
      Comment(c) => Some(c.text)
      _ => None
    }
  })
  @expect.expect(comments).to_equal(["-- end", "-- last"])
}
