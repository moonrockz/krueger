///|
/// `Elm.Parser.TypeAnnotation.typeAnnotation`: a type, optionally followed by
/// `-> type` (right-nested).
fn type_annotation(
  c : Cursor,
) -> @ast.Node[@ast.TypeAnnotation] raise SyntaxError {
  let input = type_no_fn(c, true)
  if c.at_kind(Arrow) && c.positively_indented() {
    ignore(c.advance())
    let output = c.chain(() => type_annotation(c))
    node(
      combine(input.range, output.range),
      FunctionTypeAnnotation(input, output),
    )
  } else {
    input
  }
}

///|
fn starts_type(c : Cursor) -> Bool {
  match c.peek() {
    Some({ kind: LParen | LBrace, .. }) => true
    Some(t) => is_upper(t) || is_lower(t)
    None => false
  }
}

///|
/// A type without a top-level arrow. `with_args` lets a named type take
/// arguments (`Maybe Int`); arguments themselves are parsed without.
fn type_no_fn(
  c : Cursor,
  with_args : Bool,
) -> @ast.Node[@ast.TypeAnnotation] raise SyntaxError {
  c.nested(() => type_no_fn_at_depth(c, with_args))
}

///|
fn type_no_fn_at_depth(
  c : Cursor,
  with_args : Bool,
) -> @ast.Node[@ast.TypeAnnotation] raise SyntaxError {
  guard c.peek() is Some(t) else { raise c.fail("a type") }
  match t.kind {
    LParen => c.within(ParensType, () => parens_type(c))
    LBrace => c.within(RecordType, () => record_type(c))
    Identifier if is_lower(t) => {
      ignore(c.advance())
      token_node(t, GenericType(t.lexeme))
    }
    Identifier => {
      let name = qualified_type_name(c)
      if !with_args {
        return node(name.range, Typed(name, []))
      }
      let args = []
      while c.positively_indented() && starts_type(c) {
        args.push(type_no_fn(c, false))
      }
      let range = match args.last() {
        Some(last) => combine(name.range, last.range)
        None => name.range
      }
      node(range, Typed(name, args))
    }
    _ => raise c.fail("a type")
  }
}

///|
/// `Name` or `Module.Name`, with the dots touching the names.
fn qualified_type_name(
  c : Cursor,
) -> @ast.Node[(Array[String], String)] raise SyntaxError {
  let first = c.upper("a type name")
  let parts = [first.lexeme]
  let mut last = first
  while c.dotted_name(is_upper) is Some(_) {
    ignore(c.advance())
    last = c.advance()
    parts.push(last.lexeme)
  }
  let name = parts.pop().unwrap()
  node(range_from(first, last), (parts, name))
}

///|
fn parens_type(c : Cursor) -> @ast.Node[@ast.TypeAnnotation] raise SyntaxError {
  let open = c.advance()
  if c.at_kind(RParen) && c.next_touches() {
    let close = c.advance()
    return node(range_from(open, close), Unit)
  }
  let first = type_annotation(c)
  if c.at_kind(RParen) {
    // A parenthesized type is the inner type, with a range over the parens.
    let close = c.advance()
    return node(range_from(open, close), first.value)
  }
  ignore(c.expect(Comma, "`,` or `)`"))
  let second = type_annotation(c)
  let parts = [first, second]
  if c.at_kind(Comma) {
    ignore(c.advance())
    parts.push(type_annotation(c))
  }
  let close = c.expect(RParen, "`)`")
  node(range_from(open, close), Tupled(parts))
}

///|
/// A record field definition whose range ends where the next token starts
/// (elm-syntax includes the trailing whitespace).
fn record_field(c : Cursor) -> @ast.Node[@ast.RecordField] raise SyntaxError {
  let name = c.lower("a field name")
  ignore(c.expect(Colon, "`:`"))
  let value = type_annotation(c)
  let end = match c.peek() {
    Some(next) => location(next.span.start)
    None => value.range.end
  }
  node({ start: location(name.span.start), end, }, {
    name: token_node(name, name.lexeme),
    type_annotation: value,
  })
}

///|
fn record_type(c : Cursor) -> @ast.Node[@ast.TypeAnnotation] raise SyntaxError {
  let open = c.advance()
  if c.at_kind(RBrace) {
    let close = c.advance()
    return node(range_from(open, close), Record([]))
  }
  let first_name = c.lower("a field name")
  if c.at_kind(Pipe) {
    let pipe = c.advance()
    let fields = [record_field(c)]
    while c.at_kind(Comma) {
      ignore(c.advance())
      fields.push(record_field(c))
    }
    let fields_end = fields.last().unwrap().range.end
    let close = c.expect(RBrace, "`}`")
    return node(
      range_from(open, close),
      GenericRecord(
        token_node(first_name, first_name.lexeme),
        node({ start: location(pipe.span.end), end: fields_end, }, fields),
      ),
    )
  }
  ignore(c.expect(Colon, "`:` or `|`"))
  let first_value = type_annotation(c)
  // elm-syntax quirk: the first field ends at its type; later fields end
  // where the next token starts (see record_field).
  let fields : Array[@ast.Node[@ast.RecordField]] = [
    node(combine(range_of(first_name), first_value.range), {
      name: token_node(first_name, first_name.lexeme),
      type_annotation: first_value,
    }),
  ]
  while c.at_kind(Comma) {
    ignore(c.advance())
    fields.push(record_field(c))
  }
  let close = c.expect(RBrace, "`}`")
  node(range_from(open, close), Record(fields))
}
