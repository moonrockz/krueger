///|
fn pos(offset : Int, line : Int, column : Int) -> @scanner.Position {
  @scanner.Position::{ offset, line, column }
}

///|
fn span() -> @scanner.Span {
  @scanner.Span::{ start: pos(0, 1, 1), end: pos(1, 1, 2) }
}

///|
test "parse result can hold ast cst and diagnostics" {
  let result = ParseResult::{ ast: None, cst: None, diagnostics: [] }
  assert_eq(result.diagnostics.length(), 0)
}

///|
test "declaration metadata can hold optional doc comment" {
  let meta = DeclMeta::{
    doc_comment: Some(DocComment::{ text: "Adds one", span: span() }),
    span: span(),
  }
  let decl = Declaration::FunctionDecl(FunctionDeclaration::{
    name: "add",
    args: ["x"],
    body_tokens: [],
    meta,
  })
  match decl {
    Declaration::FunctionDecl(fn_decl) =>
      match fn_decl.meta.doc_comment {
        Some(comment) => assert_eq(comment.text, "Adds one")
        None => fail("expected doc comment")
      }
    _ => fail("expected function declaration")
  }
}
