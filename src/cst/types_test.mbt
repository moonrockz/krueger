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
test "module cst captures header imports and typed declarations" {
  let header = ModuleHeaderCst::{
    module_name: Some("Main"),
    exposing: ["add"],
    span: span(),
    tokens: [
      token(@scanner.TokenKind::module_kw(), "module"),
      token(@scanner.TokenKind::Identifier, "Main"),
      token(@scanner.TokenKind::exposing_kw(), "exposing"),
    ],
  }
  let import_node = ImportCst::{
    module_name: "Html",
    exposing: Some(["text"]),
    span: span(),
    tokens: [
      token(@scanner.TokenKind::import_kw(), "import"),
      token(@scanner.TokenKind::Identifier, "Html"),
    ],
  }
  let cst = ModuleCst::{
    tokens: header.tokens + import_node.tokens,
    header: Some(header),
    imports: [import_node],
    declarations: [
      DeclarationCst::Function(FunctionCst::{
        name: "add",
        args: ["x"],
        span: span(),
        tokens: [token(@scanner.TokenKind::Identifier, "add")],
      }),
      DeclarationCst::TypeAlias(TypeAliasCst::{
        name: "User",
        type_params: ["a"],
        span: span(),
        tokens: [token(@scanner.TokenKind::Identifier, "User")],
      }),
      DeclarationCst::UnionType(UnionTypeCst::{
        name: "Color",
        type_params: [],
        span: span(),
        tokens: [token(@scanner.TokenKind::Identifier, "Color")],
      }),
    ],
    span: Some(span()),
  }

  match cst.header {
    Some(module_header) => {
      assert_eq(module_header.module_name, Some("Main"))
      assert_eq(module_header.exposing, ["add"])
      assert_eq(module_header.tokens.length(), 3)
    }
    None => fail("expected header")
  }
  assert_eq(cst.imports.length(), 1)
  assert_eq(cst.declarations.length(), 3)
}

///|
test "typed declaration variants expose payload contracts" {
  let function_decl = DeclarationCst::Function(FunctionCst::{
    name: "add",
    args: ["x", "y"],
    span: span(),
    tokens: [token(@scanner.TokenKind::Identifier, "add")],
  })
  let type_alias_decl = DeclarationCst::TypeAlias(TypeAliasCst::{
    name: "User",
    type_params: ["a"],
    span: span(),
    tokens: [token(@scanner.TokenKind::Identifier, "User")],
  })
  let union_decl = DeclarationCst::UnionType(UnionTypeCst::{
    name: "Color",
    type_params: ["a"],
    span: span(),
    tokens: [token(@scanner.TokenKind::Identifier, "Color")],
  })

  match function_decl {
    DeclarationCst::Function(fn_decl) => {
      assert_eq(fn_decl.name, "add")
      assert_eq(fn_decl.args, ["x", "y"])
    }
    _ => fail("expected function declaration cst")
  }
  match type_alias_decl {
    DeclarationCst::TypeAlias(alias_decl) => {
      assert_eq(alias_decl.name, "User")
      assert_eq(alias_decl.type_params, ["a"])
    }
    _ => fail("expected type alias declaration cst")
  }
  match union_decl {
    DeclarationCst::UnionType(union_type_decl) => {
      assert_eq(union_type_decl.name, "Color")
      assert_eq(union_type_decl.type_params, ["a"])
    }
    _ => fail("expected union type declaration cst")
  }
}
