///|
/// `[ a, b ]` on one line, or one item per line with leading commas (the
/// elm-format form): `[ a\n, b\n]`. With no items: `[]`. `leads[i]` (for
/// `i >= 1`) comes before the `,` of item `i` (see `Ctx::before_item`).
/// `inner` comes before the closing token (see `Ctx::inner`, and
/// `Ctx::inner_alone` for no items).
fn sequence(
  split : Split,
  open : String,
  close : String,
  items : Array[@pretty.Doc],
  leads? : Array[@pretty.Doc] = [],
  inner? : @pretty.Doc = @pretty.empty(),
) -> @pretty.Doc {
  guard !items.is_empty() else {
    return @pretty.text(open) + inner + @pretty.text(close)
  }
  let mut body = @pretty.text(open + " ") + @pretty.nest(2, items[0])
  for i in 1..<items.length() {
    body = body +
      split_softline(split) +
      leads.get(i).unwrap_or(@pretty.empty()) +
      @pretty.text(", ") +
      @pretty.nest(2, items[i])
  }
  @pretty.group(
    @pretty.align(body + inner + split_line(split) + @pretty.text(close)),
  )
}

///|
/// `{ r | a = 1, b = 2 }`, or `{ r\n    | a = 1\n    , b = 2\n}`. `fields`
/// is not empty. `leads` and `inner` are as for `sequence`.
fn extension(
  split : Split,
  base : @pretty.Doc,
  fields : Array[@pretty.Doc],
  leads? : Array[@pretty.Doc] = [],
  inner? : @pretty.Doc = @pretty.empty(),
) -> @pretty.Doc {
  let mut body = @pretty.text("| ") + @pretty.nest(2, fields[0])
  for i in 1..<fields.length() {
    body = body +
      split_softline(split) +
      leads.get(i).unwrap_or(@pretty.empty()) +
      @pretty.text(", ") +
      @pretty.nest(2, fields[i])
  }
  @pretty.group(
    @pretty.align(
      @pretty.text("{ ") +
      base +
      @pretty.tab(4, split_line(split) + body + inner) +
      split_line(split) +
      @pretty.text("}"),
    ),
  )
}

///|
/// `label = value` (or `label : value`) inside a record. A value that does
/// not fit goes on the next line, at the next tab stop (a multiple of 4)
/// right of the indentation of the field. `separator` is ` =` or ` :` (see
/// `Ctx::after`).
fn field(
  split : Split,
  label : @pretty.Doc,
  separator : @pretty.Doc,
  value : @pretty.Doc,
) -> @pretty.Doc {
  label + separator + @pretty.group(@pretty.tab(4, split_line(split) + value))
}

///|
/// `(d)`; when `d` breaks, the `)` goes on its own line in the column of
/// the `(`, and the lines of `d` are indented from the column after the `(`
/// (the elm-format form). `inner` comes before the `)`.
fn parens(
  split : Split,
  d : @pretty.Doc,
  inner? : @pretty.Doc = @pretty.empty(),
) -> @pretty.Doc {
  @pretty.group(
    @pretty.align(
      @pretty.text("(") +
      @pretty.nest(1, d + inner) +
      split_softline(split) +
      @pretty.text(")"),
    ),
  )
}

///|
/// `head a b` on one line, or each item on its own line at the next tab
/// stop (a multiple of 4), as elm-format indents.
fn spaced(
  split : Split,
  head : @pretty.Doc,
  items : Array[@pretty.Doc],
) -> @pretty.Doc {
  let mut rest = @pretty.empty()
  for x in items {
    rest = rest + split_line(split) + x
  }
  @pretty.group(head + @pretty.tab(4, rest))
}

///|
/// `[ a, b ]` always on one line: a pattern never breaks (elm-format keeps
/// patterns on one line, and a broken pattern in a case branch puts `,` in
/// the branch column). With no items: `[]`. `inner` comes before the
/// closing token.
fn flat_sequence(
  open : String,
  close : String,
  items : Array[@pretty.Doc],
  inner? : @pretty.Doc = @pretty.empty(),
) -> @pretty.Doc {
  guard !items.is_empty() else {
    return @pretty.text(open) + inner + @pretty.text(close)
  }
  let mut body = @pretty.text(open + " ") + items[0]
  for i in 1..<items.length() {
    body = body + @pretty.text(", ") + items[i]
  }
  body + inner + @pretty.text(" " + close)
}

///|
/// `(d)` always on one line (see `flat_sequence`).
fn flat_parens(d : @pretty.Doc) -> @pretty.Doc {
  @pretty.text("(") + d + @pretty.text(")")
}

///|
/// `n` line breaks.
fn line_breaks(n : Int) -> @pretty.Doc {
  let mut d = @pretty.empty()
  for _ in 0..<n {
    d = d + @pretty.hardline()
  }
  d
}
