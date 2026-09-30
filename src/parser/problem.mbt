///|
/// The construct the parser is inside, innermost last. A failure takes its
/// `elm make` title from the innermost context, as Elm's parser does.
priv enum Context {
  ModuleHeader
  Exposing
  Import
  Definition(String)
  TypeAlias
  CustomType
  Port
  Infix
  Let
  Case
  If
  Lambda
  List
  Record
  Parens
  RecordType
  ParensType
  ListPattern
  RecordPattern
  ParensPattern
}

///|
/// A context and the span of its first token.
priv struct Frame {
  context : Context
  start : @scanner.Span
}

///|
/// The title and report of a syntax error, as `elm make` would show them.
priv struct Problem {
  title : String
  report : Array[@scanner.Block]
}

///|
fn Context::title(self : Context) -> String {
  match self {
    ModuleHeader => "UNFINISHED MODULE DECLARATION"
    Exposing => "PROBLEM IN EXPOSING"
    Import => "UNFINISHED IMPORT"
    Definition(_) => "UNFINISHED DEFINITION"
    TypeAlias => "UNFINISHED TYPE ALIAS"
    CustomType => "UNFINISHED CUSTOM TYPE"
    Port => "UNFINISHED PORT"
    Infix => "SYNTAX PROBLEM"
    Let => "UNFINISHED LET"
    Case => "UNFINISHED CASE"
    If => "UNFINISHED IF"
    Lambda => "UNFINISHED ANONYMOUS FUNCTION"
    List => "UNFINISHED LIST"
    Record => "UNFINISHED RECORD"
    Parens => "UNFINISHED PARENTHESES"
    RecordType => "UNFINISHED RECORD TYPE"
    ParensType => "UNFINISHED PARENTHESES"
    ListPattern => "UNFINISHED LIST PATTERN"
    RecordPattern => "UNFINISHED RECORD PATTERN"
    ParensPattern => "UNFINISHED PARENTHESES"
  }
}

///|
/// How the report names the construct: "I was partway through parsing <this>".
fn Context::construct(self : Context) -> Array[@scanner.Chunk] {
  match self {
    ModuleHeader => [Plain("the module declaration")]
    Exposing =>
      [Plain("an "), @scanner.Chunk::keyword("exposing"), Plain(" list")]
    Import => [Plain("an "), @scanner.Chunk::keyword("import")]
    Definition(name) =>
      [Plain("the "), @scanner.Chunk::code(name), Plain(" definition")]
    TypeAlias => [Plain("a type alias")]
    CustomType => [Plain("a custom type")]
    Port =>
      [Plain("a "), @scanner.Chunk::keyword("port"), Plain(" declaration")]
    Infix => [Plain("an infix declaration")]
    Let => [Plain("a "), @scanner.Chunk::keyword("let"), Plain(" expression")]
    Case => [Plain("a "), @scanner.Chunk::keyword("case"), Plain(" expression")]
    If => [Plain("an "), @scanner.Chunk::keyword("if"), Plain(" expression")]
    Lambda => [Plain("an anonymous function")]
    List => [Plain("a list")]
    Record => [Plain("a record")]
    Parens => [Plain("an expression in parentheses")]
    RecordType => [Plain("a record type")]
    ParensType => [Plain("a type in parentheses")]
    ListPattern => [Plain("a list pattern")]
    RecordPattern => [Plain("a record pattern")]
    ParensPattern => [Plain("a pattern in parentheses")]
  }
}

///|
/// A short valid example for the report's note, when one helps.
fn Context::example(self : Context) -> (String, String)? {
  match self {
    Let =>
      Some(
        (
          "a valid `let` expression", "viewPerson person =\n  let\n    fullName =\n      person.firstName ++ \" \" ++ person.lastName\n  in\n  div [] [ text fullName ]",
        ),
      )
    Case =>
      Some(
        (
          "a valid `case` expression", "case maybeWidth of\n  Just width ->\n    width + 10\n\n  Nothing ->\n    0",
        ),
      )
    If =>
      Some(
        (
          "a valid `if` expression", "if x < 0 then\n  \"negative\"\nelse\n  \"not negative\"",
        ),
      )
    Lambda => Some(("a valid anonymous function", "\\x -> x + 1"))
    _ => None
  }
}

///|
fn plain(text : String) -> @scanner.Block {
  Text([Plain(text)])
}

///|
/// The report sentence for what was expected: "I was expecting to see <x>
/// next." `expected` is the parser's description, for example "`,` or `]`".
fn expecting(expected : String) -> @scanner.Block {
  Text([Plain("I was expecting to see \{expected} next.")])
}

///|
/// A problem with a title, an opening sentence, an excerpt from `context` to
/// `highlight`, and more blocks after it.
fn make_problem(
  title : String,
  opening : Array[@scanner.Chunk],
  context : @scanner.Span,
  highlight : @scanner.Span,
  after : Array[@scanner.Block],
) -> Problem {
  { title, report: [Text(opening), Excerpt(context~, highlight~), ..after], }
}

///|
/// A problem whose excerpt is the line of `span`, marking `span`.
fn span_problem(
  title : String,
  opening : String,
  span : @scanner.Span,
  after : Array[@scanner.Block],
) -> Problem {
  make_problem(title, [Plain(opening)], span, span, after)
}

///|
/// A zero-width span at `p`.
fn point(p : @scanner.Position) -> @scanner.Span {
  { start: p, end: p, }
}
