///|
/// `[ a, b ]` on one line, or one item per line with leading commas (the
/// elm-format form): `[ a\n, b\n]`. With no items: `[]`.
fn sequence(
  open : String,
  close : String,
  items : Array[@pretty.Doc],
) -> @pretty.Doc {
  guard !items.is_empty() else { return @pretty.text(open + close) }
  let mut body = @pretty.text(open + " ") + @pretty.nest(2, items[0])
  for i in 1..<items.length() {
    body = body +
      @pretty.softline() +
      @pretty.text(", ") +
      @pretty.nest(2, items[i])
  }
  @pretty.group(@pretty.align(body + @pretty.line() + @pretty.text(close)))
}

///|
/// `{ r | a = 1, b = 2 }`, or `{ r\n    | a = 1\n    , b = 2\n}`. `fields`
/// is not empty.
fn extension(base : @pretty.Doc, fields : Array[@pretty.Doc]) -> @pretty.Doc {
  let mut body = @pretty.text("| ") + @pretty.nest(2, fields[0])
  for i in 1..<fields.length() {
    body = body +
      @pretty.softline() +
      @pretty.text(", ") +
      @pretty.nest(2, fields[i])
  }
  @pretty.group(
    @pretty.align(
      @pretty.text("{ ") +
      base +
      @pretty.nest(4, @pretty.line() + body) +
      @pretty.line() +
      @pretty.text("}"),
    ),
  )
}

///|
/// `label = value` (or `label : value`) inside a record. A value that does
/// not fit goes on the next line, 4 columns right of the `{`.
fn field(
  label : @pretty.Doc,
  separator : String,
  value : @pretty.Doc,
) -> @pretty.Doc {
  label +
  @pretty.text(" " + separator) +
  @pretty.group(@pretty.nest(2, @pretty.line() + value))
}

///|
/// `(d)`; when `d` breaks, the `)` goes on its own line.
fn parens(d : @pretty.Doc) -> @pretty.Doc {
  @pretty.group(@pretty.text("(") + d + @pretty.softline() + @pretty.text(")"))
}

///|
/// `head a b` on one line, or each item on its own line, indented by 4.
fn spaced(head : @pretty.Doc, items : Array[@pretty.Doc]) -> @pretty.Doc {
  let mut rest = @pretty.empty()
  for x in items {
    rest = rest + @pretty.line() + x
  }
  @pretty.group(head + @pretty.nest(4, rest))
}
