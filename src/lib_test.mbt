///|
/// Tests for krueger library (placeholder until scanner/parser/AST exist).
test "version returns 0.1.0" {
  assert_eq(@krueger.version(), "0.1.0")
}

///|
test "root package exposes scanner tokenize entrypoint" {
  let source = @krueger.SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing (..)",
  }
  let result = @krueger.tokenize(source)
  match result {
    Ok(stream) => {
      assert_true(
        stream.tokens.any(fn(token) {
          token.kind == @krueger.TokenKind::module_kw()
        }),
      )
      assert_true(
        stream.tokens.any(fn(token) {
          token.kind == @krueger.TokenKind::exposing_kw()
        }),
      )
      assert_true(
        stream.tokens.any(fn(token) { token.kind == @krueger.TokenKind::DotDot }),
      )
    }
    Err(_) =>
      fail("expected tokenize to succeed for default scanner placeholder")
  }
}

///|
test "root package exposes parser entrypoints" {
  let _ = @krueger.parse_module
  let _ = @krueger.parse_tokens
  assert_true(true)
}

///|
test "root package exposes the elm-syntax model" {
  let location = @krueger.Location::{ row: 1, column: 1, }
  let range = @krueger.Range::{ start: location, end: location, }
  let name : @krueger.Node[@krueger.ModuleName] = { range, value: ["Main"], }
  @expect.expect(name.value).to_equal(["Main"])
}

///|
test "root package parse_module uses default scanner and builds the module" {
  let source = @krueger.SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing (Msg)\ntype Msg = Inc",
  }
  let result = @krueger.parse_module(source)
  guard result.ast is Some(file) else { fail("expected an AST") }
  guard file.module_definition.value is @krueger.Module::NormalModule(data) else {
    fail("expected a normal module")
  }
  @expect.expect(data.module_name.value).to_equal(["Main"])
  @expect.expect(file.declarations.length()).to_equal(1)
}

///|
test "root package parse_tokens wraps parser parse_tokens" {
  let source = @krueger.SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing (add)\nadd x = x + 1",
  }
  guard @krueger.tokenize(source) is Ok(stream) else {
    fail("expected tokenize success")
  }
  let result = @krueger.parse_tokens(stream)
  @expect.expect(result.diagnostics.map(d => d.code)).to_equal(["KR-PARSE-005"])
  @expect.expect(result.cst.map(c => c.declarations.length())).to_equal(Some(1))
}

///|
test "root package exposes cst contracts" {
  let node_span = @krueger.Span::{
    start: @krueger.Position::{ offset: 0, line: 1, column: 1, },
    end: @krueger.Position::{ offset: 1, line: 1, column: 2, },
  }
  let header = @krueger.ModuleHeaderCst::{
    module_name: Some("Main"),
    exposing: ["add"],
    tokens: [],
    span: node_span,
  }
  let cst = @krueger.ModuleCst::{
    tokens: [],
    header: Some(header),
    imports: [],
    declarations: [
      @krueger.DeclarationCst::Function(@krueger.FunctionCst::{
        name: "add",
        args: ["x"],
        tokens: [],
        span: node_span,
      }),
    ],
    span: None,
  }
  assert_eq(cst.declarations.length(), 1)
}

///|
test "diagnostic_description describes every scanner and parser code" {
  let codes = [
    "KR-SCAN-001", "KR-SCAN-002", "KR-SCAN-003", "KR-PARSE-001", "KR-PARSE-002",
    "KR-PARSE-003", "KR-PARSE-004", "KR-PARSE-005", "KR-PARSE-006", "KR-PARSE-007",
  ]
  for code in codes {
    @expect.expect(@krueger.diagnostic_description(code) is Some(_)).to_be_true()
  }
  @expect.expect(@krueger.diagnostic_description("KR-SCAN-003")).to_equal(
    Some("Invalid or unknown character sequence"),
  )
  @expect.expect(@krueger.diagnostic_description("KR-NOPE-999")).to_equal(None)
}
