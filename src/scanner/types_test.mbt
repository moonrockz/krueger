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

///|
test "token kind keyword helpers create keyword token kinds" {
  assert_eq(
    TokenKind::keyword(KeywordKind::Module),
    TokenKind::Keyword(KeywordKind::Module),
  )
  assert_eq(TokenKind::module_kw(), TokenKind::Keyword(KeywordKind::Module))
  assert_eq(TokenKind::exposing_kw(), TokenKind::Keyword(KeywordKind::Exposing))
  assert_eq(TokenKind::import_kw(), TokenKind::Keyword(KeywordKind::Import))
  assert_eq(TokenKind::type_kw(), TokenKind::Keyword(KeywordKind::Type))
  assert_eq(TokenKind::alias_kw(), TokenKind::Keyword(KeywordKind::Alias))
  assert_eq(TokenKind::if_kw(), TokenKind::Keyword(KeywordKind::If))
  assert_eq(TokenKind::then_kw(), TokenKind::Keyword(KeywordKind::Then))
  assert_eq(TokenKind::else_kw(), TokenKind::Keyword(KeywordKind::Else))
  assert_eq(TokenKind::let_kw(), TokenKind::Keyword(KeywordKind::Let))
  assert_eq(TokenKind::in_kw(), TokenKind::Keyword(KeywordKind::In))
  assert_eq(TokenKind::case_kw(), TokenKind::Keyword(KeywordKind::Case))
  assert_eq(TokenKind::of_kw(), TokenKind::Keyword(KeywordKind::Of))
}
