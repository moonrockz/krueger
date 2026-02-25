///|
pub(all) enum Severity {
  Error
  Warning
  Info
} derive(Eq, Show)

///|
pub(all) struct Position {
  offset : Int
  line : Int
  column : Int
} derive(Eq, Show)

///|
pub(all) struct Span {
  start : Position
  end : Position
} derive(Eq, Show)

///|
pub(all) struct SourceText {
  module_name : String?
  text : String
} derive(Eq, Show)

///|
pub(all) struct Diagnostic {
  code : String
  severity : Severity
  message : String
  span : Span
} derive(Eq, Show)

///|
pub(all) enum CommentKind {
  Line
  Block
  Doc
} derive(Eq, Show)

///|
pub(all) struct Comment {
  kind : CommentKind
  text : String
  span : Span
} derive(Eq, Show)

///|
pub(all) enum Trivia {
  Whitespace(String, Span)
  Newline(String, Span)
  Comment(Comment)
} derive(Eq, Show)

///|
pub(all) enum KeywordKind {
  Module
  Exposing
  Import
  Type
  Alias
  If
  Then
  Else
  Let
  In
  Case
  Of
} derive(Eq, Show)

///|
pub(all) enum TokenKind {
  Keyword(KeywordKind)
  Identifier
  IntLiteral
  LParen
  RParen
  Comma
  Equals
  Plus
  DotDot
  Arrow
  Unknown
} derive(Eq, Show)

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
pub fn TokenKind::alias_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Alias)
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
} derive(Eq, Show)

///|
pub(all) struct TokenStream {
  tokens : Array[Token]
} derive(Eq, Show)

///|
pub(all) struct ScanErrorList {
  diagnostics : Array[Diagnostic]
} derive(Eq, Show)
