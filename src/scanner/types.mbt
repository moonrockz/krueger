///|
pub(all) enum Severity {
  Error
  Warning
  Info
} derive(Eq, Debug)

///|
pub(all) struct Position {
  offset : Int
  line : Int
  column : Int
} derive(Eq, Debug)

///|
pub(all) struct Span {
  start : Position
  end : Position
} derive(Eq, Debug)

///|
pub(all) struct SourceText {
  module_name : String?
  text : String
} derive(Eq, Debug)

///|
pub(all) struct Diagnostic {
  code : String
  severity : Severity
  /// One-line summary.
  message : String
  span : Span
  /// The `elm make` title for the same problem, for example `UNFINISHED LET`.
  title : String
  /// The long message, as `elm make` shows it (render with `@report`).
  report : Array[Block]
} derive(Eq, Debug)

///|
pub(all) enum CommentKind {
  Line
  Block
  Doc
} derive(Eq, Debug)

///|
pub(all) struct Comment {
  kind : CommentKind
  text : String
  span : Span
} derive(Eq, Debug)

///|
pub(all) enum Trivia {
  Whitespace(String, Span)
  Newline(String, Span)
  Comment(Comment)
} derive(Eq, Debug)

///|
/// Reserved words of Elm 0.19.1 as elm-syntax 7.3.9 treats them. `alias`,
/// `infix` and `effect` are not reserved; they are identifiers.
pub(all) enum KeywordKind {
  Module
  Exposing
  Import
  As
  Type
  If
  Then
  Else
  Let
  In
  Case
  Of
  Port
  Where
  /// An extra reserved word from the dialect.
  Custom(String)
} derive(Eq, Debug)

///|
pub(all) enum TokenKind {
  Keyword(KeywordKind)
  /// A lowercase or uppercase name; the first character tells which.
  Identifier
  /// A decimal or hexadecimal (`0x`) integer; the sign is a separate `-`.
  IntLiteral
  FloatLiteral
  /// A single- or triple-quoted string, lexeme including the quotes.
  StringLiteral
  /// A char literal, lexeme including the quotes.
  CharLiteral
  /// A `[glsl| ... |]` block, lexeme including the delimiters.
  Glsl
  LParen
  RParen
  LBracket
  RBracket
  LBrace
  RBrace
  Comma
  Equals
  Dot
  DotDot
  Colon
  Pipe
  Arrow
  Backslash
  Underscore
  /// One of the 24 infix operators elm-syntax allows.
  Operator(String)
} derive(Eq, Debug)

///|
pub fn TokenKind::keyword(kind : KeywordKind) -> TokenKind {
  TokenKind::Keyword(kind)
}

///|
pub fn TokenKind::module_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Module)
}

///|
pub fn TokenKind::exposing_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Exposing)
}

///|
pub fn TokenKind::import_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Import)
}

///|
pub fn TokenKind::type_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Type)
}

///|
pub fn TokenKind::as_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::As)
}

///|
pub fn TokenKind::port_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Port)
}

///|
pub fn TokenKind::where_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Where)
}

///|
pub fn TokenKind::if_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::If)
}

///|
pub fn TokenKind::then_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Then)
}

///|
pub fn TokenKind::else_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Else)
}

///|
pub fn TokenKind::let_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Let)
}

///|
pub fn TokenKind::in_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::In)
}

///|
pub fn TokenKind::case_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Case)
}

///|
pub fn TokenKind::of_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Of)
}

///|
pub(all) struct Token {
  kind : TokenKind
  lexeme : String
  span : Span
  trivia_before : Array[Trivia]
  trivia_after : Array[Trivia]
} derive(Eq, Debug)

///|
pub(all) struct TokenStream {
  tokens : Array[Token]
} derive(Eq, Debug)

///|
pub(all) struct ScanErrorList {
  diagnostics : Array[Diagnostic]
} derive(Eq, Debug)
