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
test "root package exposes ast domain wrappers" {
  let identifier = @krueger.Identifier::Identifier("Main")
  assert_eq(identifier.0, "Main")
}

///|
test "root package parse_module uses default scanner and captures declarations" {
  let source = @krueger.SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing (add)\nadd x = x + 1",
  }
  let result = @krueger.parse_module(source)
  match result.ast {
    Some(ast) => {
      match ast.module_name {
        Some(module_name) => assert_eq(module_name.0.0, "Main")
        None => fail("expected module name")
      }
      assert_true(
        ast.declarations.any(fn(decl) {
          match decl {
            @krueger.Declaration::FunctionDecl(fn_decl) =>
              fn_decl.name.0.0 == "add"
            _ => false
          }
        }),
      )
    }
    None => fail("expected ast")
  }
}

///|
test "root package parse_tokens wraps parser parse_tokens" {
  let source = @krueger.SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing (add)\nadd x = x + 1",
  }
  let stream = match @krueger.tokenize(source) {
    Ok(stream) => stream
    Err(_) => fail("expected tokenize success")
  }
  let result = @krueger.parse_tokens(stream)
  match result.ast {
    Some(ast) =>
      assert_true(
        ast.declarations.any(fn(decl) {
          match decl {
            @krueger.Declaration::FunctionDecl(fn_decl) =>
              match fn_decl.body {
                @ast.Expr::Unparsed(unparsed) =>
                  fn_decl.name.0.0 == "add" && unparsed.tokens.length() > 0
                _ => false
              }
            _ => false
          }
        }),
      )
    None => fail("expected ast")
  }
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
