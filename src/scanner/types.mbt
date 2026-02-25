pub(all) enum Severity {
  Error
  Warning
  Info
} derive(Eq, Show)

pub(all) struct Position {
  offset : Int
  line : Int
  column : Int
} derive(Eq, Show)

pub(all) struct Span {
  start : Position
  end : Position
} derive(Eq, Show)

pub(all) struct SourceText {
  module_name : Option[String]
  text : String
} derive(Eq, Show)

pub(all) struct Diagnostic {
  code : String
  severity : Severity
  message : String
  span : Span
} derive(Eq, Show)

pub(all) enum CommentKind {
  Line
  Block
  Doc
} derive(Eq, Show)

pub(all) struct Comment {
  kind : CommentKind
  text : String
  span : Span
} derive(Eq, Show)

pub(all) enum Trivia {
  Whitespace(String, Span)
  Newline(String, Span)
  Comment(Comment)
} derive(Eq, Show)

pub(all) enum TokenKind {
  Identifier
  IntLiteral
} derive(Eq, Show)

pub(all) struct Token {
  kind : TokenKind
  lexeme : String
  span : Span
  trivia_before : Array[Trivia]
  trivia_after : Array[Trivia]
} derive(Eq, Show)

pub(all) struct TokenStream {
  tokens : Array[Token]
} derive(Eq, Show)

pub(all) struct ScanErrorList {
  diagnostics : Array[Diagnostic]
} derive(Eq, Show)
