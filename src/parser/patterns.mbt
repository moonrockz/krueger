///|
/// Whether the next token can start a pattern.
fn starts_pattern(c : Cursor) -> Bool {
  match c.peek() {
    Some(
      {
        kind: LParen
        | LBrace
        | LBracket
        | Underscore
        | StringLiteral
        | CharLiteral
        | IntLiteral,
        ..
      }
    ) => true
    Some(t) => is_upper(t) || is_lower(t)
    None => false
  }
}

///|
/// `Elm.Parser.Patterns.pattern`: a pattern that may take constructor
/// arguments and be followed by `as name` or `:: pattern`.
fn pattern(c : Cursor) -> @ast.Node[@ast.Pattern] raise SyntaxError {
  let left = single_pattern(c, true)
  if c.is_keyword(As) {
    ignore(c.advance())
    let name = c.lower("a name after `as`")
    let name_node = token_node(name, name.lexeme)
    return node(
      combine(left.range, name_node.range),
      AsPattern(left, name_node),
    )
  }
  if c.at_kind(Operator("::")) {
    ignore(c.advance())
    let right = pattern(c)
    return node(combine(left.range, right.range), UnConsPattern(left, right))
  }
  left
}

///|
/// `patternNotDirectlyComposing`: used for function and lambda arguments;
/// constructors take no arguments here and there is no `as` or `::`.
fn argument_pattern(c : Cursor) -> @ast.Node[@ast.Pattern] raise SyntaxError {
  single_pattern(c, false)
}

///|
fn single_pattern(
  c : Cursor,
  constructor_args : Bool,
) -> @ast.Node[@ast.Pattern] raise SyntaxError {
  guard c.peek() is Some(t) else { raise c.fail("a pattern") }
  match t.kind {
    Underscore => {
      ignore(c.advance())
      token_node(t, AllPattern)
    }
    StringLiteral => {
      ignore(c.advance())
      token_node(t, StringPattern(string_value(t)))
    }
    CharLiteral => {
      ignore(c.advance())
      token_node(t, CharPattern(char_value(t)))
    }
    IntLiteral => {
      ignore(c.advance())
      match int_value(t) {
        Ok(n) => token_node(t, IntPattern(n))
        Err(n) => token_node(t, HexPattern(n))
      }
    }
    LParen => parens_pattern(c)
    LBracket => list_pattern(c)
    LBrace => record_pattern(c)
    Identifier if is_lower(t) => {
      ignore(c.advance())
      token_node(t, VarPattern(t.lexeme))
    }
    Identifier => {
      let name = qualified_type_name(c)
      let (module_name, value) = name.value
      let name_ref : @ast.QualifiedNameRef = { module_name, name: value, }
      if !constructor_args {
        return node(name.range, NamedPattern(name_ref, []))
      }
      let args = []
      while c.positively_indented() && starts_pattern(c) {
        args.push(argument_pattern(c))
      }
      let range = match args.last() {
        Some(last) => combine(name.range, last.range)
        None => name.range
      }
      node(range, NamedPattern(name_ref, args))
    }
    _ => raise c.fail("a pattern")
  }
}

///|
fn parens_pattern(c : Cursor) -> @ast.Node[@ast.Pattern] raise SyntaxError {
  let open = c.advance()
  if c.at_kind(RParen) {
    // `(  )` is a valid pattern, unlike a unit type or expression.
    let close = c.advance()
    return node(range_from(open, close), UnitPattern)
  }
  let first = pattern(c)
  if c.at_kind(RParen) {
    let close = c.advance()
    return node(range_from(open, close), ParenthesizedPattern(first))
  }
  ignore(c.expect(Comma, "`,` or `)`"))
  let parts = [first, pattern(c)]
  if c.at_kind(Comma) {
    ignore(c.advance())
    parts.push(pattern(c))
  }
  let close = c.expect(RParen, "`)`")
  node(range_from(open, close), TuplePattern(parts))
}

///|
fn list_pattern(c : Cursor) -> @ast.Node[@ast.Pattern] raise SyntaxError {
  let open = c.advance()
  let items = []
  if !c.at_kind(RBracket) {
    items.push(pattern(c))
    while c.at_kind(Comma) {
      ignore(c.advance())
      items.push(pattern(c))
    }
  }
  let close = c.expect(RBracket, "`]`")
  node(range_from(open, close), ListPattern(items))
}

///|
fn record_pattern(c : Cursor) -> @ast.Node[@ast.Pattern] raise SyntaxError {
  let open = c.advance()
  let fields = []
  if !c.at_kind(RBrace) {
    let first = c.lower("a field name")
    fields.push(token_node(first, first.lexeme))
    while c.at_kind(Comma) {
      ignore(c.advance())
      let field = c.lower("a field name")
      fields.push(token_node(field, field.lexeme))
    }
  }
  let close = c.expect(RBrace, "`}`")
  node(range_from(open, close), RecordPattern(fields))
}
