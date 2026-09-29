///|

///|
fn pos(offset : Int, line : Int, column : Int) -> @scanner.Position {
  @scanner.Position::{ offset, line, column, }
}

///|
fn span() -> @scanner.Span {
  @scanner.Span::{ start: pos(0, 1, 1), end: pos(1, 1, 2), }
}

///|
test "ast domain wrappers compose around identifiers" {
  let identifier = @ast.Identifier::Identifier("Main")
  let module_name = @ast.ModuleName::ModuleName(identifier)
  let value_name = @ast.ValueName::ValueName(@ast.Identifier::Identifier("add"))
  let type_name = @ast.TypeName::TypeName(@ast.Identifier::Identifier("User"))
  let type_var = @ast.TypeVarName::TypeVarName(@ast.Identifier::Identifier("a"))
  let ctor_name = @ast.ConstructorName::ConstructorName(
    @ast.Identifier::Identifier("Just"),
  )
  let op_name = @ast.OperatorName::OperatorName("+")

  assert_eq(module_name.0.0, "Main")
  assert_eq(value_name.0.0, "add")
  assert_eq(type_name.0.0, "User")
  assert_eq(type_var.0.0, "a")
  assert_eq(ctor_name.0.0, "Just")
  assert_eq(op_name.0, "+")
}

///|
test "ast supports hybrid expression and type expression nodes" {
  let expr = @ast.Expr::BinaryOp(
    @ast.Expr::Var(@ast.ValueName::ValueName(@ast.Identifier::Identifier("x"))),
    @ast.OperatorName::OperatorName("+"),
    @ast.Expr::IntLiteral(1),
  )
  let type_expr = @ast.TypeExpr::TypeApp(
    @ast.TypeName::TypeName(@ast.Identifier::Identifier("List")),
    [
      @ast.TypeExpr::TypeVar(
        @ast.TypeVarName::TypeVarName(@ast.Identifier::Identifier("a")),
      ),
    ],
  )
  let fallback_expr = @ast.Expr::Unparsed(@ast.UnparsedExpr::{ tokens: [], })
  let fallback_type = @ast.TypeExpr::Unparsed(@ast.UnparsedTypeExpr::{
    tokens: [],
  })

  assert_true(expr != fallback_expr)
  assert_true(type_expr != fallback_type)
}

///|
test "module ast stores typed declarations and exposing names" {
  let meta = @ast.DeclMeta::{ doc_comment: None, span: span(), }
  let fn_decl = @ast.Declaration::FunctionDecl(@ast.FunctionDeclaration::{
    name: @ast.ValueName::ValueName(@ast.Identifier::Identifier("add")),
    args: [@ast.ValueName::ValueName(@ast.Identifier::Identifier("x"))],
    body: @ast.Expr::Unparsed(@ast.UnparsedExpr::{ tokens: [], }),
    meta,
  })
  let module_ast = @ast.ModuleAst::{
    module_name: Some(
      @ast.ModuleName::ModuleName(@ast.Identifier::Identifier("Main")),
    ),
    exposing: [
      @ast.ExposedName::Value(
        @ast.ValueName::ValueName(@ast.Identifier::Identifier("add")),
      ),
    ],
    imports: [],
    declarations: [fn_decl],
    span: None,
  }

  assert_eq(module_ast.declarations.length(), 1)
  assert_eq(module_ast.exposing.length(), 1)
}
