fn to_comment_trivia(raw : RawToken, kind : CommentKind) -> Trivia {
  Trivia::Comment(Comment::{ kind, text: raw.lexeme, span: raw.span })
}

pub fn raw_to_trivia(raw : RawToken) -> Trivia? {
  match raw.kind {
    RawTokenKind::Whitespace => Some(Trivia::Whitespace(raw.lexeme, raw.span))
    RawTokenKind::Newline => Some(Trivia::Newline(raw.lexeme, raw.span))
    RawTokenKind::LineComment => Some(to_comment_trivia(raw, CommentKind::Line))
    RawTokenKind::BlockComment => Some(to_comment_trivia(raw, CommentKind::Block))
    RawTokenKind::DocComment => Some(to_comment_trivia(raw, CommentKind::Doc))
    _ => None
  }
}
