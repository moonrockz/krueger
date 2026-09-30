///|
fn scanner_error(
  code : String,
  message : String,
  span : Span,
  title~ : String,
  report~ : Array[Block],
) -> Diagnostic {
  Diagnostic::{ code, severity: Severity::Error, message, span, title, report, }
}

///|
/// An excerpt of the line of `highlight`, marking `highlight`.
fn line_excerpt(highlight : Span) -> Block {
  Excerpt(context={ start: highlight.start, end: highlight.start, }, highlight~)
}

///|
/// `span` moved `columns` code units to the right on the same line.
fn shift(p : Position, columns : Int) -> Position {
  { offset: p.offset + columns, line: p.line, column: p.column + columns, }
}

///|
fn text(s : String) -> Block {
  Text([Plain(s)])
}

///|
/// A block comment with no end. `span` runs from `{-` to the end of the input.
pub fn unterminated_block_comment(span : Span) -> Diagnostic {
  scanner_error(
    "KR-SCAN-001",
    "Unterminated block comment",
    span,
    title="ENDLESS COMMENT",
    report=endless_comment_report(span),
  )
}

///|
fn endless_comment_report(span : Span) -> Array[Block] {
  [
    text("I cannot find the end of this multi-line comment:"),
    line_excerpt({ start: span.start, end: shift(span.start, 2), }),
    Text([
      Plain("Add a "),
      Chunk::code("-}"),
      Plain(" somewhere after this to end the comment."),
    ]),
    Hint([
      Plain("Multi-line comments can be nested in Elm, so "),
      Chunk::code("{- {- -} -}"),
      Plain(
        " is a comment that happens to contain another comment. The start and end markers must always be balanced.",
      ),
    ]),
  ]
}

///|
/// A doc comment with no end. `span` runs from `{-|` to the end of the input.
pub fn malformed_doc_comment(span : Span) -> Diagnostic {
  scanner_error(
    "KR-SCAN-002",
    "Malformed doc comment",
    span,
    title="ENDLESS COMMENT",
    report=endless_comment_report(span),
  )
}

///|
/// A character Elm does not allow here.
pub fn invalid_sequence(span : Span) -> Diagnostic {
  scanner_error(
    "KR-SCAN-003",
    "Invalid or unknown character sequence",
    span,
    title="UNEXPECTED SYMBOL",
    report=[
      text("I got stuck on this symbol:"),
      line_excerpt(span),
      text("It is not used for anything in Elm syntax. Try removing it?"),
    ],
  )
}

///|
/// A tab character.
pub fn tab_character(span : Span) -> Diagnostic {
  scanner_error("KR-SCAN-003", "Tab character", span, title="NO TABS", report=[
    text("I ran into a tab, but tabs are not allowed in Elm files."),
    line_excerpt({ start: span.start, end: span.start, }),
    text("Replace the tab with spaces."),
  ])
}

///|
/// A semicolon.
pub fn unexpected_semicolon(span : Span) -> Diagnostic {
  scanner_error(
    "KR-SCAN-003",
    "Unexpected semicolon",
    span,
    title="UNEXPECTED SEMICOLON",
    report=[
      text("I got stuck on this semicolon:"),
      line_excerpt(span),
      text("Try removing it? Elm does not use semicolons to end statements."),
    ],
  )
}

///|
/// A character that is not a symbol and is not used in Elm, such as a backtick
/// or a non-ASCII letter outside a string.
pub fn unexpected_character(span : Span) -> Diagnostic {
  scanner_error(
    "KR-SCAN-003",
    "Unexpected character",
    span,
    title="UNEXPECTED CHARACTER",
    report=[
      text("I got stuck on this character:"),
      line_excerpt(span),
      text("It is not used for anything in Elm syntax. Try removing it?"),
    ],
  )
}

///|
/// A string with no closing quote. `span` runs from the opening quote to where
/// the scanner stopped (the end of the line, or of the input).
pub fn unterminated_string(span : Span) -> Diagnostic {
  scanner_error(
    "KR-SCAN-004",
    "Unterminated string literal",
    span,
    title="ENDLESS STRING",
    report=[
      text(
        "I got to the end of the line without seeing the closing double quote:",
      ),
      line_excerpt({ start: span.end, end: span.end, }),
      Text([
        Plain("Strings look like "),
        Chunk::code("\"this\""),
        Plain(
          " with double quotes on each end. Is the closing double quote missing in your code?",
        ),
      ]),
    ],
  )
}

///|
/// A multi-line string with no closing `"""`.
pub fn unterminated_multiline_string(span : Span) -> Diagnostic {
  scanner_error(
    "KR-SCAN-004",
    "Unterminated multi-line string literal",
    span,
    title="ENDLESS STRING",
    report=[
      text("I cannot find the end of this multi-line string:"),
      line_excerpt({ start: span.start, end: shift(span.start, 3), }),
      Text([
        Plain("Add a "),
        Chunk::code("\"\"\""),
        Plain(" somewhere after this to end the string."),
      ]),
    ],
  )
}

///|
/// A character literal with no closing quote.
pub fn unterminated_char(span : Span) -> Diagnostic {
  scanner_error(
    "KR-SCAN-004",
    "Unterminated char literal",
    span,
    title="MISSING SINGLE QUOTE",
    report=[
      text(
        "I thought I was parsing a character, but I got to the end of the line without seeing the closing single quote:",
      ),
      line_excerpt({ start: span.end, end: span.end, }),
      text("Add a closing single quote here!"),
    ],
  )
}

///|
/// A GLSL block with no closing `|]`.
pub fn unterminated_glsl(span : Span) -> Diagnostic {
  scanner_error(
    "KR-SCAN-004",
    "Unterminated GLSL literal",
    span,
    title="ENDLESS SHADER",
    report=[
      text("I cannot find the end of this shader:"),
      line_excerpt({ start: span.start, end: shift(span.start, 6), }),
      Text([
        Plain("Add a "),
        Chunk::code("|]"),
        Plain(" somewhere after this to end the shader."),
      ]),
    ],
  )
}
