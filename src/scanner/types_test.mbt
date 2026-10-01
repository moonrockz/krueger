///|
fn pos(offset : Int, line : Int, column : Int) -> @scanner.Position {
  @scanner.Position::{ offset, line, column, }
}

///|
fn span() -> @scanner.Span {
  @scanner.Span::{ start: pos(0, 1, 1), end: pos(1, 1, 2), }
}

///|
test "token stream keeps tokens in order" {
  let t1 = @scanner.Token::{
    kind: @scanner.TokenKind::Identifier,
    lexeme: "add",
    span: span(),
    trivia_before: [],
    trivia_after: [],
  }
  let t2 = @scanner.Token::{
    kind: @scanner.TokenKind::IntLiteral,
    lexeme: "1",
    span: span(),
    trivia_before: [],
    trivia_after: [],
  }
  let stream = @scanner.TokenStream::{ tokens: [t1, t2], trivia: [], }
  assert_eq(stream.tokens.length(), 2)
  assert_eq(stream.tokens[0].lexeme, "add")
  assert_eq(stream.tokens[1].lexeme, "1")
}

///|
test "comment trivia preserves doc kind" {
  let trivia = @scanner.Trivia::Comment(@scanner.Comment::{
    kind: @scanner.CommentKind::Doc,
    text: "Adds one",
    span: span(),
  })
  match trivia {
    @scanner.Trivia::Comment(comment) =>
      assert_eq(comment.kind, @scanner.CommentKind::Doc)
    _ => fail("expected comment trivia")
  }
}

///|
test "token kind keyword helpers create keyword token kinds" {
  assert_eq(
    @scanner.TokenKind::keyword(@scanner.KeywordKind::Module),
    @scanner.TokenKind::Keyword(@scanner.KeywordKind::Module),
  )
  assert_eq(
    @scanner.TokenKind::module_kw(),
    @scanner.TokenKind::Keyword(@scanner.KeywordKind::Module),
  )
  assert_eq(
    @scanner.TokenKind::exposing_kw(),
    @scanner.TokenKind::Keyword(@scanner.KeywordKind::Exposing),
  )
  assert_eq(
    @scanner.TokenKind::import_kw(),
    @scanner.TokenKind::Keyword(@scanner.KeywordKind::Import),
  )
  assert_eq(
    @scanner.TokenKind::type_kw(),
    @scanner.TokenKind::Keyword(@scanner.KeywordKind::Type),
  )
  assert_eq(
    @scanner.TokenKind::as_kw(),
    @scanner.TokenKind::Keyword(@scanner.KeywordKind::As),
  )
  assert_eq(
    @scanner.TokenKind::port_kw(),
    @scanner.TokenKind::Keyword(@scanner.KeywordKind::Port),
  )
  assert_eq(
    @scanner.TokenKind::where_kw(),
    @scanner.TokenKind::Keyword(@scanner.KeywordKind::Where),
  )
  assert_eq(
    @scanner.TokenKind::if_kw(),
    @scanner.TokenKind::Keyword(@scanner.KeywordKind::If),
  )
  assert_eq(
    @scanner.TokenKind::then_kw(),
    @scanner.TokenKind::Keyword(@scanner.KeywordKind::Then),
  )
  assert_eq(
    @scanner.TokenKind::else_kw(),
    @scanner.TokenKind::Keyword(@scanner.KeywordKind::Else),
  )
  assert_eq(
    @scanner.TokenKind::let_kw(),
    @scanner.TokenKind::Keyword(@scanner.KeywordKind::Let),
  )
  assert_eq(
    @scanner.TokenKind::in_kw(),
    @scanner.TokenKind::Keyword(@scanner.KeywordKind::In),
  )
  assert_eq(
    @scanner.TokenKind::case_kw(),
    @scanner.TokenKind::Keyword(@scanner.KeywordKind::Case),
  )
  assert_eq(
    @scanner.TokenKind::of_kw(),
    @scanner.TokenKind::Keyword(@scanner.KeywordKind::Of),
  )
}
