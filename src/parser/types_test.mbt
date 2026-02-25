///|
fn pos(offset : Int, line : Int, column : Int) -> @scanner.Position {
  @scanner.Position::{ offset, line, column }
}

///|
fn span() -> @scanner.Span {
  @scanner.Span::{ start: pos(0, 1, 1), end: pos(1, 1, 2) }
}

///|
fn token(kind : @scanner.TokenKind, lexeme : String) -> @scanner.Token {
  @scanner.Token::{
    kind,
    lexeme,
    span: span(),
    trivia_before: [],
    trivia_after: [],
  }
}

///|
test "parse result ast uses ast package module type" {
  let ast = @ast.ModuleAst::{
    module_name: Some(
      @ast.ModuleName::ModuleName(@ast.Identifier::Identifier("Main")),
    ),
    exposing: [],
    imports: [],
    declarations: [],
    span: Some(span()),
  }
  let result = ParseResult::{ ast: Some(ast), cst: None, diagnostics: [] }
  match result.ast {
    Some(module_ast) => assert_eq(module_ast.module_name, ast.module_name)
    None => fail("expected ast")
  }
}

///|
test "parse result supports typed declarations through ast wrappers" {
  let fn_decl = @ast.FunctionDeclaration::{
    name: @ast.ValueName::ValueName(@ast.Identifier::Identifier("add")),
    args: [@ast.ValueName::ValueName(@ast.Identifier::Identifier("x"))],
    body: @ast.Expr::Unparsed(@ast.UnparsedExpr::{
      tokens: [token(@scanner.TokenKind::Identifier, "x")],
    }),
    meta: @ast.DeclMeta::{ doc_comment: None, span: span() },
  }
  let declaration = @ast.Declaration::FunctionDecl(fn_decl)
  match declaration {
    @ast.Declaration::FunctionDecl(function_decl) =>
      assert_eq(function_decl.name.0.0, "add")
    _ => fail("expected function declaration")
  }
}
