///|
/// `Elm.Parser.Base.moduleName`: `Name` or `Name.Name...` with touching dots.
fn module_name(c : Cursor) -> @ast.Node[Array[String]] raise SyntaxError {
  let first = c.upper("a module name")
  let parts = [first.lexeme]
  let mut last = first
  while c.at_kind(Dot) &&
        c.next_touches() &&
        (match c.peek_at(1) {
          Some(n) => is_upper(n) && touching(c.peek().unwrap(), n)
          None => false
        }) {
    ignore(c.advance())
    last = c.advance()
    parts.push(last.lexeme)
  }
  node(range_from(first, last), parts)
}

///|
/// One exposed item: `value`, `Type`, `Type(..)` or `(op)`.
fn exposable(c : Cursor) -> @ast.Node[@ast.TopLevelExpose] raise SyntaxError {
  guard c.peek() is Some(t) else { raise c.fail("an exposed name") }
  if is_lower(t) {
    ignore(c.advance())
    return token_node(t, FunctionExpose(t.lexeme))
  }
  if is_upper(t) {
    ignore(c.advance())
    if c.at_kind(LParen) && c.peek_at(1) is Some({ kind: DotDot, .. }) {
      let open = c.advance()
      ignore(c.advance())
      let close = c.expect(RParen, "`)`")
      let open_range = range_from(open, close)
      return node(
        { start: location(t.span.start), end: open_range.end, },
        TypeExpose({ name: t.lexeme, open: Some(open_range), }),
      )
    }
    return token_node(t, TypeOrAliasExpose(t.lexeme))
  }
  if t.kind == LParen {
    let open = c.advance()
    guard c.peek() is Some({ kind: Operator(op), .. }) else {
      raise c.fail("an operator")
    }
    ignore(c.advance())
    let close = c.expect(RParen, "`)`")
    return node(range_from(open, close), InfixExpose(op))
  }
  raise c.fail("an exposed name")
}

///|
/// `exposing (..)` or `exposing (a, B, C(..), (+))`; the range runs from
/// `exposing` to `)`.
fn exposing_list(c : Cursor) -> @ast.Node[@ast.Exposing] raise SyntaxError {
  c.within(Exposing, () => exposing_list_body(c))
}

///|
fn exposing_list_body(c : Cursor) -> @ast.Node[@ast.Exposing] raise SyntaxError {
  let keyword = c.expect(Keyword(Exposing), "`exposing`")
  ignore(c.expect(LParen, "`(`"))
  if c.at_kind(DotDot) {
    let dots = c.advance()
    let close = c.expect(RParen, "`)`")
    return node(
      range_from(keyword, close),
      All({ start: location(dots.span.start), end: location(close.span.start), }),
    )
  }
  let items = [exposable(c)]
  while c.at_kind(Comma) {
    ignore(c.advance())
    items.push(exposable(c))
  }
  let close = c.expect(RParen, "`,` or `)`")
  node(range_from(keyword, close), Explicit(items))
}

///|
/// `module`, `port module` or `effect module ... where { ... }` header.
fn module_header(c : Cursor) -> @ast.Node[@ast.Module] raise SyntaxError {
  c.within(ModuleHeader, () => module_header_body(c))
}

///|
fn module_header_body(c : Cursor) -> @ast.Node[@ast.Module] raise SyntaxError {
  module_level_column(c, "module")
  guard c.peek() is Some(first) else { raise c.fail("a module header") }
  if first.kind == Keyword(Port) {
    ignore(c.advance())
    ignore(c.expect(Keyword(Module), "`module`"))
    let name = module_name(c)
    let exposing = exposing_list(c)
    return node(
      { start: location(first.span.start), end: exposing.range.end, },
      PortModule({ module_name: name, exposing_list: exposing, }),
    )
  }
  if first.kind == Identifier && first.lexeme == "effect" {
    ignore(c.advance())
    ignore(c.expect(Keyword(Module), "`module`"))
    let name = module_name(c)
    ignore(c.expect(Keyword(Where), "`where`"))
    ignore(c.expect(LBrace, "`{`"))
    let mut command : @ast.Node[String]? = None
    let mut subscription : @ast.Node[String]? = None
    while true {
      let key = c.lower("`command` or `subscription`")
      ignore(c.expect(Equals, "`=`"))
      let value = c.upper("a type name")
      match key.lexeme {
        "command" => command = Some(token_node(value, value.lexeme))
        "subscription" => subscription = Some(token_node(value, value.lexeme))
        _ => ()
      }
      if c.at_kind(Comma) {
        ignore(c.advance())
      } else {
        break
      }
    }
    ignore(c.expect(RBrace, "`}`"))
    let exposing = exposing_list(c)
    return node(
      { start: location(first.span.start), end: exposing.range.end, },
      EffectModule({
        module_name: name,
        exposing_list: exposing,
        command,
        subscription,
      }),
    )
  }
  ignore(c.expect(Keyword(Module), "`module`"))
  let name = module_name(c)
  let exposing = exposing_list(c)
  node(
    { start: location(first.span.start), end: exposing.range.end, },
    NormalModule({ module_name: name, exposing_list: exposing, }),
  )
}

///|
/// `import A.B as C exposing (...)`; the range ends at the last part.
fn import_declaration(c : Cursor) -> @ast.Node[@ast.Import] raise SyntaxError {
  c.within(Import, () => import_declaration_body(c))
}

///|
fn import_declaration_body(
  c : Cursor,
) -> @ast.Node[@ast.Import] raise SyntaxError {
  module_level_column(c, "import")
  let keyword = c.expect(Keyword(Import), "`import`")
  let name = module_name(c)
  let mut end = name.range.end
  let mut module_alias : @ast.Node[Array[String]]? = None
  if c.is_keyword(As) {
    ignore(c.advance())
    if c.at_lower() {
      raise c.fail_titled(
        "expected a module alias",
        "EXPECTING IMPORT ALIAS",
        [Plain("I was parsing an import, but I got stuck here:")],
        [
          Text([
            Plain("I was expecting an alias like "),
            @scanner.Chunk::code("D"),
            Plain(" in "),
            @scanner.Chunk::code("import Dict as D"),
            Plain(". Aliases must start with a capital letter."),
          ]),
        ],
      )
    }
    let alias_token = c.upper("a module alias")
    let alias_node = token_node(alias_token, [alias_token.lexeme])
    end = alias_node.range.end
    module_alias = Some(alias_node)
  }
  let mut exposing : @ast.Node[@ast.Exposing]? = None
  if c.is_keyword(Exposing) {
    let list = exposing_list(c)
    end = list.range.end
    exposing = Some(list)
  }
  node({ start: location(keyword.span.start), end, }, {
    module_name: name,
    module_alias,
    exposing_list: exposing,
  })
}

///|
/// A module header or import must start in column 1.
fn module_level_column(c : Cursor, keyword : String) -> Unit raise SyntaxError {
  guard c.dialect.has(ModuleLevelColumn) &&
    c.peek() is Some(t) &&
    t.span.start.column != 1 else {
    return
  }
  raise SyntaxError(
    "`\{keyword}` must start in column 1 [rule: \{@dialect.Rule::ModuleLevelColumn.name()}]",
    t.span,
    span_problem(
      "TOO MUCH INDENTATION",
      "This `\{keyword}` should not have any spaces before it:",
      point(t.span.start),
      [
        plain(
          "Delete the spaces before `\{keyword}` until there are none left!",
        ),
      ],
    ),
  )
}
