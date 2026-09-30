///|
/// A lexical unit before trivia is attached: a significant token or trivia.
pub(all) enum RawTokenKind {
  Significant(TokenKind)
  Whitespace
  Newline
  LineComment
  BlockComment
  DocComment
} derive(Eq, Debug)

///|
pub(all) struct RawToken {
  kind : RawTokenKind
  lexeme : String
  span : Span
} derive(Eq, Debug)

///|
/// Position in the source. Columns count code points, as elm-syntax does: the
/// low half of a surrogate pair does not add a column.
priv struct Cursor {
  text : String
  mut pos : Int
  mut line : Int
  mut column : Int
}

///|
fn Cursor::new(text : String) -> Cursor {
  { text, pos: 0, line: 1, column: 1, }
}

///|
/// Code unit `ahead` units after the cursor, or -1 at the end.
fn Cursor::at(self : Cursor, ahead? : Int = 0) -> Int {
  let i = self.pos + ahead
  if i < self.text.length() {
    self.text.code_unit_at(i).to_int()
  } else {
    -1
  }
}

///|
fn Cursor::done(self : Cursor) -> Bool {
  self.pos >= self.text.length()
}

///|
fn Cursor::position(self : Cursor) -> Position {
  { offset: self.pos, line: self.line, column: self.column, }
}

///|
/// Move one code unit forward, tracking lines and columns. Does nothing at
/// the end of the input.
fn Cursor::advance(self : Cursor) -> Unit {
  if self.done() {
    return
  }
  let c = self.at()
  if c == '\n'.to_int() {
    self.line += 1
    self.column = 1
  } else if c < 0xDC00 || c > 0xDFFF {
    self.column += 1
  }
  self.pos += 1
}

///|
fn Cursor::advance_by(self : Cursor, n : Int) -> Unit {
  for _ in 0..<n {
    self.advance()
  }
}

///|
fn Cursor::starts_with(self : Cursor, prefix : String) -> Bool {
  for i in 0..<prefix.length() {
    if self.at(ahead=i) != prefix.code_unit_at(i).to_int() {
      return false
    }
  }
  true
}

///|
fn Cursor::slice(self : Cursor, start : Int) -> String {
  self.text.unsafe_substring(start~, end=self.pos)
}

///|
fn is_ascii_letter(c : Int) -> Bool {
  (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
  (c >= 'A'.to_int() && c <= 'Z'.to_int())
}

///|
fn is_ascii_digit_code(c : Int) -> Bool {
  c >= '0'.to_int() && c <= '9'.to_int()
}

///|
fn is_hex_digit_code(c : Int) -> Bool {
  is_ascii_digit_code(c) ||
  (c >= 'a'.to_int() && c <= 'f'.to_int()) ||
  (c >= 'A'.to_int() && c <= 'F'.to_int())
}

///|
fn is_name_char(c : Int) -> Bool {
  is_ascii_letter(c) || is_ascii_digit_code(c) || c == '_'.to_int()
}

///|
fn is_symbol_char(c : Int) -> Bool {
  match c {
    '+'
    | '-'
    | '/'
    | '*'
    | '='
    | '.'
    | '<'
    | '>'
    | ':'
    | '&'
    | '|'
    | '^'
    | '?' => true
    _ => false
  }
}

///|
/// Tokens made of symbol characters, longest first so that the longest known
/// prefix of a run wins.
let symbol_tokens : Array[String] = [
  "</>", "<?>", "==", "/=", "::", "++", "<|", "|>", "||", "<=", ">=", "|=", "|.",
  "//", "<<", ">>", "&&", "->", "..", "+", "*", "^", "<", ">", "/", "-", "=", ".",
  ":", "|",
]

///|
fn symbol_kind(symbol : String) -> TokenKind {
  match symbol {
    "=" => Equals
    "." => Dot
    ".." => DotDot
    ":" => Colon
    "|" => Pipe
    "->" => Arrow
    op => Operator(op)
  }
}

///|
fn keyword_of(name : String) -> KeywordKind? {
  match name {
    "module" => Some(Module)
    "exposing" => Some(Exposing)
    "import" => Some(Import)
    "as" => Some(As)
    "type" => Some(Type)
    "if" => Some(If)
    "then" => Some(Then)
    "else" => Some(Else)
    "let" => Some(Let)
    "in" => Some(In)
    "case" => Some(Case)
    "of" => Some(Of)
    "port" => Some(Port)
    "where" => Some(Where)
    _ => None
  }
}

///|
/// Skip a block comment starting at `{-`, including nested block comments.
/// Returns whether the comment was closed.
fn skip_block_comment(cursor : Cursor) -> Bool {
  let mut depth = 0
  while !cursor.done() {
    if cursor.starts_with("{-") {
      depth += 1
      cursor.advance_by(2)
    } else if cursor.starts_with("-}") {
      depth -= 1
      cursor.advance_by(2)
      if depth == 0 {
        return true
      }
    } else {
      cursor.advance()
    }
  }
  false
}

///|
/// Skip a quoted literal body up to and including `close`. Backslash escapes
/// one code unit. Returns whether it was closed; a line break ends an
/// unclosed single-line literal.
fn skip_quoted(cursor : Cursor, close : String, multiline : Bool) -> Bool {
  while !cursor.done() {
    if cursor.starts_with(close) {
      cursor.advance_by(close.length())
      return true
    }
    let c = cursor.at()
    if c == '\\'.to_int() {
      cursor.advance_by(2)
    } else if !multiline && c == '\n'.to_int() {
      return false
    } else {
      cursor.advance()
    }
  }
  false
}

///|
/// Skip up to and including `close`, with no escapes (GLSL blocks). Returns
/// whether `close` was found.
fn skip_until(cursor : Cursor, close : String) -> Bool {
  while !cursor.done() {
    if cursor.starts_with(close) {
      cursor.advance_by(close.length())
      return true
    }
    cursor.advance()
  }
  false
}

///|
/// Skip a number: decimal or `0x` hexadecimal integer, or a float with an
/// optional fraction and exponent. Returns whether it is a float.
fn skip_number(cursor : Cursor) -> Bool {
  if cursor.starts_with("0x") && is_hex_digit_code(cursor.at(ahead=2)) {
    cursor.advance_by(2)
    while is_hex_digit_code(cursor.at()) {
      cursor.advance()
    }
    return false
  }
  while is_ascii_digit_code(cursor.at()) {
    cursor.advance()
  }
  let mut float = false
  if cursor.at() == '.'.to_int() && is_ascii_digit_code(cursor.at(ahead=1)) {
    float = true
    cursor.advance()
    while is_ascii_digit_code(cursor.at()) {
      cursor.advance()
    }
  }
  let e = cursor.at()
  if e == 'e'.to_int() || e == 'E'.to_int() {
    let sign = cursor.at(ahead=1)
    let digits_at = if sign == '+'.to_int() || sign == '-'.to_int() {
      2
    } else {
      1
    }
    if is_ascii_digit_code(cursor.at(ahead=digits_at)) {
      float = true
      cursor.advance_by(digits_at)
      while is_ascii_digit_code(cursor.at()) {
        cursor.advance()
      }
    }
  }
  float
}

///|
/// Split Elm source into significant tokens and trivia. Diagnostics:
/// `KR-SCAN-001` unterminated block comment, `KR-SCAN-002` malformed doc
/// comment, `KR-SCAN-003` a character Elm does not allow here, `KR-SCAN-004`
/// an unterminated string, char or GLSL literal.
pub fn lex_raw(source : SourceText) -> Result[Array[RawToken], ScanErrorList] {
  let cursor = Cursor::new(source.text)
  let tokens : Array[RawToken] = []
  let diagnostics = []
  while !cursor.done() {
    let start = cursor.position()
    let c = cursor.at()
    let kind : RawTokenKind? = if c == ' '.to_int() {
      while cursor.at() == ' '.to_int() {
        cursor.advance()
      }
      Some(Whitespace)
    } else if c == '\n'.to_int() || cursor.starts_with("\r\n") {
      cursor.advance_by(if c == '\n'.to_int() { 1 } else { 2 })
      Some(Newline)
    } else if cursor.starts_with("--") {
      while !cursor.done() &&
            cursor.at() != '\n'.to_int() &&
            cursor.at() != '\r'.to_int() {
        cursor.advance()
      }
      Some(LineComment)
    } else if cursor.starts_with("{-|") {
      if !skip_block_comment(cursor) {
        diagnostics.push(
          malformed_doc_comment({ start, end: cursor.position(), }),
        )
      }
      Some(DocComment)
    } else if cursor.starts_with("{-") {
      if !skip_block_comment(cursor) {
        diagnostics.push(
          unterminated_block_comment({ start, end: cursor.position(), }),
        )
      }
      Some(BlockComment)
    } else if cursor.starts_with("[glsl|") {
      cursor.advance_by(6)
      if !skip_until(cursor, "|]") {
        diagnostics.push(
          unterminated_literal({ start, end: cursor.position(), }),
        )
      }
      Some(Significant(Glsl))
    } else if cursor.starts_with("\"\"\"") {
      cursor.advance_by(3)
      if !skip_quoted(cursor, "\"\"\"", true) {
        diagnostics.push(
          unterminated_literal({ start, end: cursor.position(), }),
        )
      }
      Some(Significant(StringLiteral))
    } else if c == '"'.to_int() {
      cursor.advance()
      if !skip_quoted(cursor, "\"", false) {
        diagnostics.push(
          unterminated_literal({ start, end: cursor.position(), }),
        )
      }
      Some(Significant(StringLiteral))
    } else if c == '\''.to_int() {
      cursor.advance()
      if !skip_quoted(cursor, "'", false) {
        diagnostics.push(
          unterminated_literal({ start, end: cursor.position(), }),
        )
      }
      Some(Significant(CharLiteral))
    } else if is_ascii_digit_code(c) {
      Some(
        Significant(if skip_number(cursor) { FloatLiteral } else { IntLiteral }),
      )
    } else if is_ascii_letter(c) {
      while is_name_char(cursor.at()) {
        cursor.advance()
      }
      match keyword_of(cursor.slice(start.offset)) {
        Some(k) => Some(Significant(Keyword(k)))
        None => Some(Significant(Identifier))
      }
    } else if is_symbol_char(c) {
      match symbol_tokens.search_by(s => cursor.starts_with(s)) {
        Some(i) => {
          let symbol = symbol_tokens[i]
          cursor.advance_by(symbol.length())
          Some(Significant(symbol_kind(symbol)))
        }
        None => {
          cursor.advance()
          diagnostics.push(invalid_sequence({ start, end: cursor.position(), }))
          None
        }
      }
    } else {
      let punctuation : TokenKind? = match c {
        '(' => Some(LParen)
        ')' => Some(RParen)
        '[' => Some(LBracket)
        ']' => Some(RBracket)
        '{' => Some(LBrace)
        '}' => Some(RBrace)
        ',' => Some(Comma)
        '\\' => Some(Backslash)
        '_' => Some(Underscore)
        _ => None
      }
      match punctuation {
        Some(p) => {
          cursor.advance()
          Some(Significant(p))
        }
        None => {
          // A character outside the BMP is two code units.
          let width = if c >= 0xD800 && c <= 0xDBFF { 2 } else { 1 }
          cursor.advance_by(width)
          diagnostics.push(invalid_sequence({ start, end: cursor.position(), }))
          None
        }
      }
    }
    if kind is Some(k) {
      tokens.push({
        kind: k,
        lexeme: cursor.slice(start.offset),
        span: { start, end: cursor.position(), },
      })
    }
  }
  if diagnostics.is_empty() {
    Ok(tokens)
  } else {
    Err({ diagnostics, })
  }
}
