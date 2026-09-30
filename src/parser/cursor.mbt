///|
/// A syntax error inside a declaration: what was expected, and where.
priv suberror SyntaxError {
  SyntaxError(String, @scanner.Span)
}

///|
/// Token cursor with the layout state elm-syntax keeps: `indent` is the column
/// that continuation lines must be deeper than (1 at module level).
priv struct Cursor {
  tokens : Array[@scanner.Token]
  mut pos : Int
  mut indent : Int
}

///|
fn Cursor::new(tokens : Array[@scanner.Token]) -> Cursor {
  { tokens, pos: 0, indent: 1, }
}

///|
fn Cursor::peek(self : Cursor) -> @scanner.Token? {
  self.tokens.get(self.pos)
}

///|
fn Cursor::peek_at(self : Cursor, ahead : Int) -> @scanner.Token? {
  self.tokens.get(self.pos + ahead)
}

///|
fn Cursor::at_end(self : Cursor) -> Bool {
  self.pos >= self.tokens.length()
}

///|
fn Cursor::previous(self : Cursor) -> @scanner.Token? {
  if self.pos > 0 {
    self.tokens.get(self.pos - 1)
  } else {
    None
  }
}

///|
/// Span to report an error at: the current token, or the end of the input.
fn Cursor::here(self : Cursor) -> @scanner.Span {
  match self.peek() {
    Some(t) => t.span
    None =>
      match self.tokens.last() {
        Some(t) => { start: t.span.end, end: t.span.end, }
        None =>
          {
            start: { offset: 0, line: 1, column: 1, },
            end: { offset: 0, line: 1, column: 1, },
          }
      }
  }
}

///|
fn Cursor::fail(self : Cursor, expected : String) -> SyntaxError {
  let found = match self.peek() {
    Some(t) => "`\{t.lexeme}`"
    None => "end of input"
  }
  SyntaxError("expected \{expected}, found \{found}", self.here())
}

///|
fn Cursor::advance(self : Cursor) -> @scanner.Token raise SyntaxError {
  guard self.peek() is Some(t) else { raise self.fail("more input") }
  self.pos += 1
  t
}

///|
fn Cursor::at_kind(self : Cursor, kind : @scanner.TokenKind) -> Bool {
  self.peek() is Some(t) && t.kind == kind
}

///|
fn Cursor::is_keyword(self : Cursor, keyword : @scanner.KeywordKind) -> Bool {
  self.at_kind(Keyword(keyword))
}

///|
fn Cursor::expect(
  self : Cursor,
  kind : @scanner.TokenKind,
  what : String,
) -> @scanner.Token raise SyntaxError {
  if self.at_kind(kind) {
    self.advance()
  } else {
    raise self.fail(what)
  }
}

///|
/// Whether the next token is on a deeper column than the current indent.
fn Cursor::positively_indented(self : Cursor) -> Bool {
  self.peek() is Some(t) && t.span.start.column > self.indent
}

///|
/// Run `body` with the indent set to `column`, then restore it.
fn[T] Cursor::with_indent(
  self : Cursor,
  column : Int,
  body : () -> T raise SyntaxError,
) -> T raise SyntaxError {
  let saved = self.indent
  self.indent = column
  let result = body() catch {
    SyntaxError(message, span) => {
      self.indent = saved
      raise SyntaxError(message, span)
    }
  }
  self.indent = saved
  result
}

///|
/// Whether two tokens touch (no whitespace or comment between them).
fn touching(a : @scanner.Token, b : @scanner.Token) -> Bool {
  a.span.end.offset == b.span.start.offset
}

///|
/// Whether the next token touches the previous one.
fn Cursor::next_touches(self : Cursor) -> Bool {
  match (self.previous(), self.peek()) {
    (Some(a), Some(b)) => touching(a, b)
    _ => false
  }
}

///|
fn is_lower(token : @scanner.Token) -> Bool {
  token.kind == Identifier &&
  (match token.lexeme.get_char(0) {
    Some(c) => c.is_ascii_lowercase()
    None => false
  })
}

///|
fn is_upper(token : @scanner.Token) -> Bool {
  token.kind == Identifier &&
  (match token.lexeme.get_char(0) {
    Some(c) => c.is_ascii_uppercase()
    None => false
  })
}

///|
fn Cursor::at_lower(self : Cursor) -> Bool {
  self.peek() is Some(t) && is_lower(t)
}

///|
fn Cursor::at_upper(self : Cursor) -> Bool {
  self.peek() is Some(t) && is_upper(t)
}

///|
fn Cursor::lower(
  self : Cursor,
  what : String,
) -> @scanner.Token raise SyntaxError {
  if self.at_lower() {
    self.advance()
  } else {
    raise self.fail(what)
  }
}

///|
fn Cursor::upper(
  self : Cursor,
  what : String,
) -> @scanner.Token raise SyntaxError {
  if self.at_upper() {
    self.advance()
  } else {
    raise self.fail(what)
  }
}

///|
fn location(position : @scanner.Position) -> @ast.Location {
  { row: position.line, column: position.column, }
}

///|
fn range_of(token : @scanner.Token) -> @ast.Range {
  { start: location(token.span.start), end: location(token.span.end), }
}

///|
fn range_from(first : @scanner.Token, last : @scanner.Token) -> @ast.Range {
  { start: location(first.span.start), end: location(last.span.end), }
}

///|
fn combine(a : @ast.Range, b : @ast.Range) -> @ast.Range {
  { start: a.start, end: b.end, }
}

///|
fn shift(loc : @ast.Location, columns : Int) -> @ast.Location {
  { row: loc.row, column: loc.column + columns, }
}

///|
fn[T] node(range : @ast.Range, value : T) -> @ast.Node[T] {
  { range, value, }
}

///|
fn[T] token_node(token : @scanner.Token, value : T) -> @ast.Node[T] {
  { range: range_of(token), value, }
}
