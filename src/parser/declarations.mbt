///|
/// Which kind of declaration starts at the cursor, for diagnostics.
priv enum DeclarationKind {
  FunctionKind
  TypeKind
  PortKind
  InfixKind
}

///|
fn declaration_kind(c : Cursor) -> DeclarationKind {
  match c.peek() {
    Some({ kind: Keyword(Type), .. }) => TypeKind
    Some({ kind: Keyword(Port), .. }) => PortKind
    Some({ kind: Identifier, lexeme: "infix", .. }) => InfixKind
    _ => FunctionKind
  }
}

///|
/// Type variables of a type or alias declaration, up to `=`.
fn type_parameters(c : Cursor) -> Array[@ast.Node[String]] raise SyntaxError {
  let params = []
  while !c.at_kind(Equals) {
    let p = c.lower("a type variable or `=`")
    params.push(token_node(p, p.lexeme))
  }
  ignore(c.advance())
  params
}

///|
fn value_constructor(
  c : Cursor,
) -> @ast.Node[@ast.ValueConstructor] raise SyntaxError {
  let name = c.upper("a constructor name")
  let arguments = []
  while c.positively_indented() && starts_type(c) {
    arguments.push(type_no_fn(c, false))
  }
  let range = match arguments.last() {
    Some(last) => combine(range_of(name), last.range)
    None => range_of(name)
  }
  node(range, { name: token_node(name, name.lexeme), arguments, })
}

///|
/// `type alias Name a = type` or `type Name a = A x | B`.
fn type_declaration(
  c : Cursor,
  documentation : @ast.Node[String]?,
) -> @ast.Node[@ast.Declaration] raise SyntaxError {
  let type_token = c.expect(Keyword(Type), "`type`")
  let start = match documentation {
    Some(doc) => doc.range.start
    None => location(type_token.span.start)
  }
  if c.peek() is Some({ kind: Identifier, lexeme: "alias", .. }) {
    ignore(c.advance())
    let name = c.upper("a type name")
    let generics = type_parameters(c)
    let annotation = type_annotation(c)
    return node(
      { start, end: annotation.range.end, },
      AliasDeclaration({
        documentation,
        name: token_node(name, name.lexeme),
        generics,
        type_annotation: annotation,
      }),
    )
  }
  let name = c.upper("a type name")
  let generics = type_parameters(c)
  let constructors = [value_constructor(c)]
  while c.at_kind(Pipe) && c.positively_indented() {
    ignore(c.advance())
    constructors.push(value_constructor(c))
  }
  node(
    { start, end: constructors.last().unwrap().range.end, },
    CustomTypeDeclaration({
      documentation,
      name: token_node(name, name.lexeme),
      generics,
      constructors,
    }),
  )
}

///|
/// `port name : type`. elm-syntax starts the range at column 1 of the name's
/// row, and a doc comment before a port goes to `File.comments`.
fn port_declaration(
  c : Cursor,
) -> @ast.Node[@ast.Declaration] raise SyntaxError {
  ignore(c.expect(Keyword(Port), "`port`"))
  let name = c.lower("a port name")
  ignore(c.expect(Colon, "`:`"))
  let annotation = type_annotation(c)
  node(
    {
      start: { row: name.span.start.line, column: 1, },
      end: annotation.range.end,
    },
    PortDeclaration({
      name: token_node(name, name.lexeme),
      type_annotation: annotation,
    }),
  )
}

///|
/// `infix left 6 (+) = add`.
fn infix_declaration(
  c : Cursor,
) -> @ast.Node[@ast.Declaration] raise SyntaxError {
  let infix_token = c.advance()
  let direction_token = c.lower("`left`, `right` or `non`")
  let direction : @ast.InfixDirection = match direction_token.lexeme {
    "left" => Left
    "right" => Right
    "non" => Non
    _ =>
      raise SyntaxError(
        "expected `left`, `right` or `non`",
        direction_token.span,
      )
  }
  let precedence_token = c.expect(IntLiteral, "a precedence")
  let precedence = match int_value(precedence_token) {
    Ok(n) => n.to_int()
    Err(_) =>
      raise SyntaxError("expected a decimal precedence", precedence_token.span)
  }
  let open = c.expect(LParen, "`(`")
  guard c.peek() is Some({ kind: Operator(op), .. }) else {
    raise c.fail("an operator")
  }
  ignore(c.advance())
  let close = c.expect(RParen, "`)`")
  ignore(c.expect(Equals, "`=`"))
  let function = c.lower("a function name")
  node(
    range_from(infix_token, function),
    InfixDeclaration({
      direction: token_node(direction_token, direction),
      precedence: token_node(precedence_token, precedence),
      operator: node(range_from(open, close), op),
      function: token_node(function, function.lexeme),
    }),
  )
}

///|
/// A top-level declaration. `documentation` is the doc comment attached to
/// it, when there is one (never for ports and infix declarations).
fn declaration(
  c : Cursor,
  documentation : @ast.Node[String]?,
) -> @ast.Node[@ast.Declaration] raise SyntaxError {
  match declaration_kind(c) {
    TypeKind => type_declaration(c, documentation)
    PortKind => port_declaration(c)
    InfixKind => infix_declaration(c)
    FunctionKind => {
      let f = function_parts(c, documentation)
      node(f.range, FunctionDeclaration(f.value))
    }
  }
}
