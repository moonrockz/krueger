///|
fn pos(offset : Int, line : Int, column : Int) -> Position {
  Position::{ offset, line, column }
}

///|
fn span() -> Span {
  Span::{ start: pos(0, 1, 1), end: pos(1, 1, 2) }
}

///|
test "token stream keeps tokens in order" {
  let t1 = Token::{
    kind: TokenKind::Identifier,
    lexeme: "add",
    span: span(),
    trivia_before: [],
    trivia_after: [],
  }
  let t2 = Token::{
    kind: TokenKind::IntLiteral,
    lexeme: "1",
    span: span(),
    trivia_before: [],
    trivia_after: [],
  }
  let stream = TokenStream::{ tokens: [t1, t2] }
  assert_eq(stream.tokens.length(), 2)
  assert_eq(stream.tokens[0].lexeme, "add")
  assert_eq(stream.tokens[1].lexeme, "1")
}

///|
test "comment trivia preserves doc kind" {
  let trivia = Trivia::Comment(Comment::{
    kind: CommentKind::Doc,
    text: "Adds one",
    span: span(),
  })
  match trivia {
    Trivia::Comment(comment) => assert_eq(comment.kind, CommentKind::Doc)
    _ => fail("expected comment trivia")
  }
}
