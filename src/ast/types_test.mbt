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
  let identifier = Identifier::{ value: "Main" }
  let module_name = ModuleName::{ value: identifier }
  let value_name = ValueName::{ value: Identifier::{ value: "add" } }
  let type_name = TypeName::{ value: Identifier::{ value: "User" } }
  let type_var = TypeVarName::{ value: Identifier::{ value: "a" } }
  let ctor_name = ConstructorName::{ value: Identifier::{ value: "Just" } }
  let op_name = OperatorName::{ value: "+" }

  assert_eq(module_name.value.value, "Main")
  assert_eq(value_name.value.value, "add")
  assert_eq(type_name.value.value, "User")
  assert_eq(type_var.value.value, "a")
  assert_eq(ctor_name.value.value, "Just")
  assert_eq(op_name.value, "+")
}

///|
test "ast supports hybrid expression and type expression nodes" {
  let expr = Expr::BinaryOp(
    Expr::Var(ValueName::{ value: Identifier::{ value: "x" } }),
    OperatorName::{ value: "+" },
    Expr::IntLiteral(1),
  )
  let type_expr = TypeExpr::TypeApp(
    TypeName::{ value: Identifier::{ value: "List" } },
    [TypeExpr::TypeVar(TypeVarName::{ value: Identifier::{ value: "a" } })],
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
    name: ValueName::{ value: Identifier::{ value: "add" } },
    args: [ValueName::{ value: Identifier::{ value: "x" } }],
    body: Expr::Unparsed(UnparsedExpr::{ tokens: [] }),
    meta,
  })
  let module_ast = ModuleAst::{
    module_name: Some(ModuleName::{ value: Identifier::{ value: "Main" } }),
    exposing: [
      ExposedName::Value(ValueName::{ value: Identifier::{ value: "add" } }),
    ],
    imports: [],
    declarations: [fn_decl],
    span: None,
  }

  assert_eq(module_ast.declarations.length(), 1)
  assert_eq(module_ast.exposing.length(), 1)
}
