///|
/// What the printer knows about the source of a parsed file. Empty for an
/// AST built by hand.
priv struct SourceFacts {
  /// The start of each token, in source order.
  starts : Array[@ast.Location]
  /// The text of each token.
  lexemes : Array[String]
  /// `prefix[i]` is the number of gaps with a break among gaps `0..<i`.
  /// Gap `i` is the trivia before token `i`.
  prefix : Array[Int]
}

///|
fn gap_has_break(trivia : Array[@scanner.Trivia]) -> Bool {
  trivia
  .iter()
  .any(t => t is Newline(_, _) || (t is Comment(c) && c.kind is Line))
}

///|
fn SourceFacts::from_tokens(tokens : Array[@scanner.Token]) -> SourceFacts {
  let starts = []
  let lexemes = []
  let prefix = [0]
  for i, t in tokens {
    starts.push(@ast.Location::{
      row: t.span.start.line,
      column: t.span.start.column,
    })
    lexemes.push(t.lexeme)
    let gap = if i == 0 {
      t.trivia_before
    } else {
      tokens[i - 1].trivia_after + t.trivia_before
    }
    prefix.push(prefix[i] + (if gap_has_break(gap) { 1 } else { 0 }))
  }
  { starts, lexemes, prefix, }
}

///|
/// How the formatter chooses line breaks.
///
/// - `ElmFormat`: as elm-format 0.8.7: a construct is multi-line when the
///   source has a line break where elm-format looks, or when a part of it
///   is multi-line. There is no line width. Literals keep the form of
///   their source text: a triple-quoted string stays triple-quoted, and a
///   float with an exponent keeps one (`1E3` gives `1.0e3`).
/// - `Width(n)`: a construct is multi-line when it does not fit in `n`
///   columns (the layout of `print_file`). Literals print from their
///   value.
pub(all) enum Layout {
  ElmFormat
  Width(Int)
} derive(Eq, Debug)

///|
fn Layout::render_width(self : Layout) -> Int {
  match self {
    ElmFormat => @int.MAX_VALUE
    Width(n) => n
  }
}
