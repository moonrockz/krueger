///|
/// How serious a `Diagnostic` is. Only an `Error` makes a file fail to
/// parse; a `Warning` (for example `KR-PARSE-009`) keeps the result.
pub(all) enum Severity {
  Error
  Warning
  Info
} derive(Eq, Debug)

///|
/// A place in the source, between two characters.
///
/// - `offset` counts UTF-16 code units from the start of the text, from 0.
/// - `line` counts lines from 1. LF and CRLF end a line.
/// - `column` counts code points from the start of the line, from 1. A
///   surrogate pair is one column, a lone surrogate one, a lone `\r` one.
///
/// So outside ASCII the offset and the column differ:
///
/// ```mbt check
/// test {
///   let source = @scanner.SourceText::new("x = \"😀😀\" ++ y\n")
///   guard @scanner.DefaultScanner::new().tokenize(source) is Ok(stream) else {
///     fail("scan failed")
///   }
///   // The string literal: 6 UTF-16 units (two surrogate pairs and two
///   // quotes), but 4 columns.
///   let string = stream.tokens[2].span
///   debug_inspect((string.start.offset, string.end.offset), content="(4, 10)")
///   debug_inspect((string.start.column, string.end.column), content="(5, 9)")
///   // The `++` after it.
///   let plus = stream.tokens[3].span.start
///   debug_inspect((plus.offset, plus.line, plus.column), content="(11, 1, 10)")
/// }
/// ```
pub(all) struct Position {
  offset : Int
  line : Int
  column : Int
} derive(Eq, Debug)

///|
/// The part of the source from `start` to `end`. `end` is the position just
/// after the last character, so an empty span has `start == end`. See
/// `Position` for how offsets, lines and columns count.
pub(all) struct Span {
  start : Position
  end : Position
} derive(Eq, Debug)

///|
/// The text of one Elm source file. `module_name` is the optional Elm module
/// name (for example `Main`). `render_elm_json` writes it as `name`; the
/// parser does not use it.
pub(all) struct SourceText {
  module_name : String?
  text : String
} derive(Eq, Debug)

///|
/// Make a `SourceText` from `text`, with an optional Elm module name (for
/// example `Main`). `render_elm_json` writes `module_name` as `name`; the
/// parser does not use it.
///
/// ```mbt check
/// test {
///   let source = @scanner.SourceText::new("module Main exposing (..)\n")
///   debug_inspect(source.module_name, content="None")
///   let named = @scanner.SourceText::new("x = 1\n", module_name="Main")
///   debug_inspect(named.module_name, content="Some(\"Main\")")
/// }
/// ```
pub fn SourceText::new(text : String, module_name? : String) -> SourceText {
  { module_name, text, }
}

///|
/// A problem found in the source.
///
/// - `code` names the problem: `KR-SCAN-*` from the scanner, `KR-PARSE-*` and
///   `KR-ATTR-*` from the parser.
/// - `severity`: an `Error` makes the source invalid; a `Warning` or an
///   `Info` does not.
/// - `span` is where the problem is.
///
/// The scanner reports its problems as a `ScanErrorList`:
///
/// ```mbt check
/// test {
///   let source = @scanner.SourceText::new("x = \"abc\n")
///   guard @scanner.DefaultScanner::new().tokenize(source) is Err(errors) else {
///     fail("expected a scan error")
///   }
///   let d = errors.diagnostics[0]
///   inspect(d.code, content="KR-SCAN-004")
///   debug_inspect(d.severity, content="Error")
///   inspect(d.title, content="ENDLESS STRING")
///   inspect(d.message, content="Unterminated string literal")
///   debug_inspect((d.span.start.column, d.span.end.column), content="(5, 9)")
/// }
/// ```
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
/// The kind of a comment: `Line` is `-- ...`, `Block` is `{- ... -}` and
/// `Doc` is `{-| ... -}`.
pub(all) enum CommentKind {
  Line
  Block
  Doc
} derive(Eq, Debug)

///|
/// A comment in the source. `text` is the comment exactly as written,
/// delimiters included (`-- note`, `{- note -}`). A line comment does not
/// include its line break.
pub(all) struct Comment {
  kind : CommentKind
  text : String
  span : Span
} derive(Eq, Debug)

///|
/// Source text that is not a token: a run of spaces (or a lone `\r`), one
/// line break (`\n` or `\r\n`) or a comment. Each case keeps its exact
/// text, so trivia and tokens together give the source back (see `Token`).
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
/// The kind of a significant token. Keywords come from the dialect, so a
/// dialect with extra reserved words gives `Keyword(Custom(...))`.
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
/// The token kind of the keyword `kind`.
pub fn TokenKind::keyword(kind : KeywordKind) -> TokenKind {
  TokenKind::Keyword(kind)
}

///|
/// The token kind of the `module` keyword.
pub fn TokenKind::module_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Module)
}

///|
/// The token kind of the `exposing` keyword.
pub fn TokenKind::exposing_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Exposing)
}

///|
/// The token kind of the `import` keyword.
pub fn TokenKind::import_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Import)
}

///|
/// The token kind of the `type` keyword.
pub fn TokenKind::type_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Type)
}

///|
/// The token kind of the `as` keyword.
pub fn TokenKind::as_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::As)
}

///|
/// The token kind of the `port` keyword.
pub fn TokenKind::port_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Port)
}

///|
/// The token kind of the `where` keyword.
pub fn TokenKind::where_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Where)
}

///|
/// The token kind of the `if` keyword.
pub fn TokenKind::if_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::If)
}

///|
/// The token kind of the `then` keyword.
pub fn TokenKind::then_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Then)
}

///|
/// The token kind of the `else` keyword.
pub fn TokenKind::else_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Else)
}

///|
/// The token kind of the `let` keyword.
pub fn TokenKind::let_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Let)
}

///|
/// The token kind of the `in` keyword.
pub fn TokenKind::in_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::In)
}

///|
/// The token kind of the `case` keyword.
pub fn TokenKind::case_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Case)
}

///|
/// The token kind of the `of` keyword.
pub fn TokenKind::of_kw() -> TokenKind {
  TokenKind::keyword(KeywordKind::Of)
}

///|
/// A significant token with the trivia around it.
///
/// - `lexeme` is the exact source text of the token, and `span` is where it
///   is.
/// - `trivia_before` is all the trivia between the previous token and this
///   one.
/// - `trivia_after` is empty, except on the last token: there it holds the
///   trivia up to the end of the text.
///
/// The scan is lossless. Join `trivia_before`, `lexeme` and `trivia_after`
/// of every token, in order, and you get the source back. A text with no
/// tokens keeps its trivia in `TokenStream::trivia`.
///
/// ```mbt check
/// test {
///   fn trivia_text(t : @scanner.Trivia) -> String {
///     match t {
///       Whitespace(text, _) | Newline(text, _) => text
///       Comment(comment) => comment.text
///     }
///   }
///
///   let text = "module Main exposing (..)\n\n-- The answer.\nanswer = 42 {- end -}\n"
///   guard @scanner.DefaultScanner::new().tokenize(@scanner.SourceText::new(text))
///     is Ok(stream) else {
///     fail("scan failed")
///   }
///   let out = StringBuilder()
///   for t in stream.trivia {
///     out.write_string(trivia_text(t))
///   }
///   for token in stream.tokens {
///     for t in token.trivia_before {
///       out.write_string(trivia_text(t))
///     }
///     out.write_string(token.lexeme)
///     for t in token.trivia_after {
///       out.write_string(trivia_text(t))
///     }
///   }
///   inspect(out.to_string() == text, content="true")
///   // The line comment is trivia before `answer`.
///   let answer = stream.tokens[6]
///   inspect(answer.lexeme, content="answer")
///   debug_inspect(
///     answer.trivia_before.map(trivia_text),
///     content=(
///       #|["\n", "\n", "-- The answer.", "\n"]
///     ),
///   )
/// }
/// ```
pub(all) struct Token {
  kind : TokenKind
  lexeme : String
  span : Span
  trivia_before : Array[Trivia]
  trivia_after : Array[Trivia]
} derive(Eq, Debug)

///|
/// The result of a scan: the significant tokens in source order, each with
/// its trivia.
pub(all) struct TokenStream {
  tokens : Array[Token]
  /// The trivia of a text that has no tokens (only whitespace and comments).
  /// Empty otherwise: when there is a token, all trivia attaches to tokens.
  /// The parser's CST does not keep it.
  trivia : Array[Trivia]
} derive(Eq, Debug)

///|
/// All the problems that a scan found, in source order. A scan that finds
/// a problem gives no tokens.
pub(all) struct ScanErrorList {
  diagnostics : Array[Diagnostic]
} derive(Eq, Debug)
