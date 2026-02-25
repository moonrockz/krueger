///|

///|
fn pos(offset : Int, line : Int, column : Int) -> @scanner.Position {
  @scanner.Position::{ offset, line, column }
}

///|
fn span() -> @scanner.Span {
  @scanner.Span::{ start: pos(0, 1, 1), end: pos(1, 1, 2) }
}

///|
test "ast domain wrappers compose around identifiers" {
  let identifier = Identifier::Identifier("Main")
  let module_name = ModuleName::ModuleName(identifier)
  let value_name = ValueName::ValueName(Identifier::Identifier("add"))
  let type_name = TypeName::TypeName(Identifier::Identifier("User"))
  let type_var = TypeVarName::TypeVarName(Identifier::Identifier("a"))
  let ctor_name = ConstructorName::ConstructorName(
    Identifier::Identifier("Just"),
  )
  let op_name = OperatorName::OperatorName("+")

  assert_eq(module_name.0.0, "Main")
  assert_eq(value_name.0.0, "add")
  assert_eq(type_name.0.0, "User")
  assert_eq(type_var.0.0, "a")
  assert_eq(ctor_name.0.0, "Just")
  assert_eq(op_name.0, "+")
}

///|
test "ast supports hybrid expression and type expression nodes" {
  let expr = Expr::BinaryOp(
    Expr::Var(ValueName::ValueName(Identifier::Identifier("x"))),
    OperatorName::OperatorName("+"),
    Expr::IntLiteral(1),
  )
  let type_expr = TypeExpr::TypeApp(
    TypeName::TypeName(Identifier::Identifier("List")),
    [TypeExpr::TypeVar(TypeVarName::TypeVarName(Identifier::Identifier("a")))],
  )
  let fallback_expr = Expr::Unparsed(UnparsedExpr::{ tokens: [] })
  let fallback_type = TypeExpr::Unparsed(UnparsedTypeExpr::{ tokens: [] })

  assert_true(expr != fallback_expr)
  assert_true(type_expr != fallback_type)
}

///|
test "module ast stores typed declarations and exposing names" {
  let meta = DeclMeta::{ doc_comment: None, span: span() }
  let fn_decl = Declaration::FunctionDecl(FunctionDeclaration::{
    name: ValueName::ValueName(Identifier::Identifier("add")),
    args: [ValueName::ValueName(Identifier::Identifier("x"))],
    body: Expr::Unparsed(UnparsedExpr::{ tokens: [] }),
    meta,
  })
  let module_ast = ModuleAst::{
    module_name: Some(ModuleName::ModuleName(Identifier::Identifier("Main"))),
    exposing: [
      ExposedName::Value(ValueName::ValueName(Identifier::Identifier("add"))),
    ],
    imports: [],
    declarations: [fn_decl],
    span: None,
  }

  assert_eq(module_ast.declarations.length(), 1)
  assert_eq(module_ast.exposing.length(), 1)
}
