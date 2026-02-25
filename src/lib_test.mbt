///|
/// Tests for krueger library (placeholder until scanner/parser/AST exist).
test "version returns 0.1.0" {
  assert_eq(version(), "0.1.0")
}

test "root package exposes scanner tokenize entrypoint" {
  let source = SourceText::{ module_name: Some("Main"), text: "module Main exposing (..)" }
  let result = tokenize(source)
  match result {
    Ok(stream) => {
      assert_true(stream.tokens.any(fn(token) { token.kind == TokenKind::ModuleKw }))
      assert_true(stream.tokens.any(fn(token) { token.kind == TokenKind::ExposingKw }))
      assert_true(stream.tokens.any(fn(token) { token.kind == TokenKind::DotDot }))
    }
    Err(_) => fail("expected tokenize to succeed for default scanner placeholder")
  }
}
