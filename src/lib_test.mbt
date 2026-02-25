///|
/// Tests for krueger library (placeholder until scanner/parser/AST exist).
test "version returns 0.1.0" {
  assert_eq(version(), "0.1.0")
}

test "root package exposes scanner tokenize entrypoint" {
  let source = SourceText::{ module_name: Some("Main"), text: "module Main exposing (..)" }
  let result = tokenize(source)
  match result {
    Ok(stream) => assert_eq(stream.tokens.length(), 0)
    Err(_) => fail("expected tokenize to succeed for default scanner placeholder")
  }
}
