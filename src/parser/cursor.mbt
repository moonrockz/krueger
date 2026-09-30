///|
/// A syntax error inside a declaration: a one-line message, where, and the
/// Elm-style title and report.
priv suberror SyntaxError {
  SyntaxError(String, @scanner.Span, Problem)
}

///|
/// Token cursor with the layout state elm-syntax keeps: `indent` is the column
/// that continuation lines must be deeper than (1 at module level).
priv struct Cursor {
  tokens : Array[@scanner.Token]
  mut pos : Int
  mut indent : Int
  mut depth : Int
  dialect : @dialect.Dialect
  contexts : Array[Frame]
  /// Position of the token that starts the current item (declaration, let
  /// declaration, case branch): it may sit at the indent column.
  mut item_start : Int
  /// Set while building a layout failure: the problem is marked right after
  /// the previous token, as elm make does.
  mut layout_failure : Bool
  /// Warnings found while parsing (for example `KR-PARSE-009`).
  warnings : Array[@scanner.Diagnostic]
  /// Whether the module header says `port module`.
  mut port_module : Bool
}

///|
fn Cursor::new(
  tokens : Array[@scanner.Token],
  dialect : @dialect.Dialect,
) -> Cursor {
  {
    tokens,
    pos: 0,
    indent: 1,
    depth: 0,
    dialect,
    contexts: [],
    item_start: 0,
    layout_failure: false,
    warnings: [],
    port_module: false,
  }
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
  SyntaxError(
    "expected \{expected}, found \{found}",
    self.here(),
    self.problem(expected),
  )
}

///|
/// Where `elm make` marks a failure: right after the previous token when the
/// input ends, or when the next token is on a later line and too little
/// indented to continue (the construct was cut short); else at the next token.
fn Cursor::error_point(self : Cursor) -> @scanner.Span {
  if self.layout_failure && self.previous() is Some(p) {
    return point(p.span.end)
  }
  match (self.previous(), self.peek()) {
    // Outside any construct (a top-level item's first token), mark the token.
    (_, Some(t)) if self.contexts.is_empty() => point(t.span.start)
    (Some(p), Some(t)) if t.span.start.line > p.span.end.line &&
      (t.span.start.column == 1 || t.span.start.column < self.indent) =>
      point(p.span.end)
    (Some(p), None) => point(p.span.end)
    (_, Some(t)) => point(t.span.start)
    (None, None) => self.here()
  }
}

///|
/// The excerpt context for a failure at `highlight`: from the start of the
/// innermost construct, at most four lines.
fn Cursor::excerpt_context(
  self : Cursor,
  highlight : @scanner.Span,
) -> @scanner.Span {
  let start = match self.contexts.last() {
    Some(frame) if frame.start.start.line <= highlight.start.line =>
      if highlight.start.line - frame.start.start.line > 3 {
        { ..highlight.start, line: highlight.start.line - 3, }
      } else {
        frame.start.start
      }
    _ => highlight.start
  }
  { start, end: highlight.end, }
}

///|
/// A problem with an explicit title, marked at the failure point.
fn Cursor::titled(
  self : Cursor,
  title : String,
  opening : Array[@scanner.Chunk],
  after : Array[@scanner.Block],
) -> Problem {
  let highlight = self.error_point()
  make_problem(
    title,
    opening,
    self.excerpt_context(highlight),
    highlight,
    after,
  )
}

///|
/// A syntax error with an explicit title.
fn Cursor::fail_titled(
  self : Cursor,
  message : String,
  title : String,
  opening : Array[@scanner.Chunk],
  after : Array[@scanner.Block],
) -> SyntaxError {
  SyntaxError(message, self.here(), self.titled(title, opening, after))
}

///|
/// The Elm-style problem for a failure that expected `expected`. Rules on the
/// token found come first, then the innermost context.
fn Cursor::problem(self : Cursor, expected : String) -> Problem {
  let found = self.peek()
  let previous = self.previous()
  let context = self.contexts.last().map(f => f.context)
  let stuck : Array[@scanner.Chunk] = [Plain("I got stuck here:")]
  match (found, context) {
    (Some({ kind: Keyword(_), .. }), _) if expected == "an expression" &&
      previous is Some({ kind: Keyword(Then | Case), .. }) =>
      self.titled(
        "MISSING EXPRESSION",
        [
          Plain(
            "I am partway through parsing an expression, but I got stuck here:",
          ),
        ],
        [
          plain(
            "I was expecting to see an expression here, before this keyword.",
          ),
        ],
      )
    (Some({ kind: Keyword(k), lexeme, .. }), _) if !(k is Custom(_)) &&
      !expected.has_prefix("`") &&
      expected != "an expression" =>
      self.titled(
        "RESERVED WORD",
        [
          Plain("It looks like you are using "),
          @scanner.Chunk::keyword(lexeme),
          Plain(" as a name or an expression, but it is a reserved word:"),
        ],
        [
          plain(
            "Try a different name, or check the lines above for a missing part.",
          ),
        ],
      )
    (Some({ kind: RBrace, .. }), Some(Record | RecordType)) if previous
      is Some({ kind: Comma, .. }) =>
      self.titled(
        "EXTRA COMMA",
        [
          Plain(
            "I am partway through parsing a record, but I got stuck after that last comma:",
          ),
        ],
        [
          plain(
            "Trailing commas are not allowed in records. Try deleting the comma?",
          ),
        ],
      )
    (Some({ kind: Operator(second), .. } as t), _) if previous
      is Some({ kind: Operator(first), .. } as p) &&
      touching(p, t) =>
      self.titled(
        "UNKNOWN OPERATOR",
        [
          Plain("I do not recognize the "),
          @scanner.Chunk::code(first + second),
          Plain(" operator:"),
        ],
        [
          plain(
            "Elm has a fixed set of operators; this is not one of them. Is there a typo, or a missing space between two operators?",
          ),
        ],
      )
    (Some(t), _) if expected == "an expression" &&
      !(t.kind is Keyword(_)) &&
      previous is Some({ kind: Equals | Arrow | LParen, .. }) =>
      self.titled(
        "MISSING EXPRESSION",
        [
          Plain(
            "I am partway through parsing an expression, but I got stuck here:",
          ),
        ],
        [
          Text([
            Plain("I was expecting to see an expression like "),
            @scanner.Chunk::code("42"),
            Plain(" or "),
            @scanner.Chunk::code("\"hello\""),
            Plain(" here."),
          ]),
        ],
      )
    (Some(t), None) if is_upper(t) && expected.contains("function name") =>
      self.titled(
        "UNEXPECTED CAPITAL LETTER",
        [
          Plain(
            "Declarations always start with a lower-case letter, so I am getting stuck here:",
          ),
        ],
        [
          Text([
            Plain("Try a name like "),
            @scanner.Chunk::code("view"),
            Plain(" or "),
            @scanner.Chunk::code("update"),
            Plain(" instead. Type declarations start with "),
            @scanner.Chunk::keyword("type"),
            Plain("."),
          ]),
        ],
      )
    (Some({ kind: Operator(_), .. }), _) if expected == "an expression" =>
      self.titled(
        "MISSING EXPRESSION",
        [
          Plain(
            "I am partway through parsing an expression, but I got stuck here:",
          ),
        ],
        [
          Text([
            Plain("I was expecting to see an expression like "),
            @scanner.Chunk::code("42"),
            Plain(" or "),
            @scanner.Chunk::code("\"hello\""),
            Plain(" here."),
          ]),
        ],
      )
    (None, _) if expected == "an expression" &&
      previous is Some({ kind: Operator(_), .. }) =>
      self.titled(
        "MISSING EXPRESSION",
        [Plain("I just saw an operator, so I am getting stuck here:")],
        [plain("I was expecting to see an expression next.")],
      )
    (Some(t), Some(Record)) if is_upper(t) && expected.contains("field name") =>
      self.titled(
        "PROBLEM IN RECORD",
        [Plain("I am partway through parsing a record, but I got stuck here:")],
        [
          Text([
            Plain("I was expecting to see a field name like "),
            @scanner.Chunk::code("name"),
            Plain(". A record update like "),
            @scanner.Chunk::code("{ person | age = 42 }"),
            Plain(" needs a plain lowercase name before the "),
            @scanner.Chunk::code("|"),
            Plain("."),
          ]),
        ],
      )
    (Some({ kind: FloatLiteral, .. }), _) if expected == "a pattern" =>
      self.titled(
        "UNEXPECTED PATTERN",
        [Plain("I cannot pattern match on floating point numbers:")],
        [
          plain(
            "Patterns can match integers, characters, strings and other exact values, but not floats. Try an `if` expression with a comparison instead?",
          ),
        ],
      )
    (_, Some(ctx)) => {
      let after = [expecting(expected)]
      if ctx.example() is Some((what, code)) {
        after.push(
          Note([Plain("Here is an example of \{what} for reference:")]),
        )
        after.push(Example(code))
      }
      self.titled(
        ctx.title(),
        [
          Plain("I was partway through parsing "),
          ..ctx.construct(),
          Plain(", but I got stuck here:"),
        ],
        after,
      )
    }
    (_, None) => self.titled("SYNTAX PROBLEM", stuck, [expecting(expected)])
  }
}

///|
/// A syntax error at `span` with an explicit title; the excerpt marks `span`.
fn Cursor::error_at(
  self : Cursor,
  message : String,
  span : @scanner.Span,
  title : String,
  opening : String,
  after : Array[@scanner.Block],
) -> SyntaxError {
  // A token-level problem: the excerpt is the token's line, as elm make shows.
  ignore(self)
  let highlight = point(span.start)
  SyntaxError(
    message,
    span,
    make_problem(title, [Plain(opening)], highlight, highlight, after),
  )
}

///|
/// Run `body` inside `context` (for error titles). The context starts at the
/// next token.
fn[T] Cursor::within(
  self : Cursor,
  context : Context,
  body : () -> T raise SyntaxError,
) -> T raise SyntaxError {
  self.contexts.push({ context, start: self.here(), })
  let result = body() catch {
    SyntaxError(message, span, problem) => {
      ignore(self.contexts.pop())
      raise SyntaxError(message, span, problem)
    }
  }
  ignore(self.contexts.pop())
  result
}

///|
fn Cursor::advance(self : Cursor) -> @scanner.Token raise SyntaxError {
  guard self.peek() is Some(t) else { raise self.fail("more input") }
  if self.dialect.has(IndentedContinuation) &&
    self.pos != self.item_start &&
    t.span.start.column <= self.indent {
    raise self.layout_fail(t)
  }
  self.pos += 1
  t
}

///|
/// Mark the next token as the start of an item, which may sit at the indent
/// column.
fn Cursor::start_item(self : Cursor) -> Unit {
  self.item_start = self.pos
}

///|
/// A token that is not indented enough to continue the current construct.
fn Cursor::layout_fail(self : Cursor, t : @scanner.Token) -> SyntaxError {
  let message = "`\{t.lexeme}` must be indented more [rule: \{@dialect.Rule::IndentedContinuation.name()}]"
  let context = self.contexts.last().map(f => f.context)
  if t.kind is Keyword(Else) && context is Some(If) {
    return SyntaxError(
      message,
      t.span,
      make_problem(
        "WEIRD ELSE BRANCH",
        [
          Plain("I was partway through an "),
          @scanner.Chunk::keyword("if"),
          Plain(" expression when I got stuck here:"),
        ],
        self.excerpt_context(t.span),
        t.span,
        [
          Text([
            Plain("I think this "),
            @scanner.Chunk::keyword("else"),
            Plain(
              " keyword needs to be indented more. Try adding some spaces before it.",
            ),
          ]),
        ],
      ),
    )
  }
  self.layout_failure = true
  let problem = self.problem("`\{t.lexeme}` indented more")
  self.layout_failure = false
  let report = problem.report.map(b => {
    match b {
      Text([Plain(s)]) if s.has_prefix("I was expecting to see") =>
        @scanner.Block::Text([
          @scanner.Chunk::Plain("I was expecting "),
          @scanner.Chunk::code(t.lexeme),
          @scanner.Chunk::Plain(
            " to be indented more. Try adding some spaces before it?",
          ),
        ])
      other => other
    }
  })
  SyntaxError(message, t.span, { ..problem, report, })
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
    SyntaxError(message, span, problem) => {
      self.indent = saved
      raise SyntaxError(message, span, problem)
    }
  }
  self.indent = saved
  result
}

///|
/// Deepest nesting of expressions, types and patterns the parser accepts.
/// Deeper input gives a syntax error instead of a stack overflow.
const MAX_DEPTH : Int = 150

///|
/// Most operators in one left-associative chain (`a + b + c ...`).
const MAX_CHAIN : Int = 400

///|
/// Run `body` one nesting level deeper; fail above `MAX_DEPTH`.
fn[T] Cursor::nested(
  self : Cursor,
  body : () -> T raise SyntaxError,
) -> T raise SyntaxError {
  if self.depth >= MAX_DEPTH {
    raise self.fail_titled(
      "nesting too deep",
      "TOO MUCH NESTING",
      [Plain("This expression, type or pattern is nested too deeply for me:")],
      [plain("Try moving part of it into a separate definition.")],
    )
  }
  self.depth += 1
  let result = body() catch {
    SyntaxError(message, span, problem) => {
      self.depth -= 1
      raise SyntaxError(message, span, problem)
    }
  }
  self.depth -= 1
  result
}

///|
/// Whether two tokens touch (no whitespace or comment between them).
fn touching(a : @scanner.Token, b : @scanner.Token) -> Bool {
  a.span.end.offset == b.span.start.offset
}

///|
/// Whether the next token touches the previous one.
/// The name after a `.` at the cursor, when the dot touches the token before
/// it and the name (`List.map`, `record.field`) and `wanted` accepts it.
fn Cursor::dotted_name(
  self : Cursor,
  wanted : (@scanner.Token) -> Bool,
) -> @scanner.Token? {
  if self.at_kind(Dot) &&
    self.next_touches() &&
    self.peek_at(1) is Some(n) &&
    touching(self.peek().unwrap(), n) &&
    wanted(n) {
    Some(n)
  } else {
    None
  }
}

///|
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
    Some(c) => @scanner.is_lower_start(c)
    None => false
  })
}

///|
fn is_upper(token : @scanner.Token) -> Bool {
  token.kind == Identifier &&
  (match token.lexeme.get_char(0) {
    Some(c) => @scanner.is_upper_start(c)
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
