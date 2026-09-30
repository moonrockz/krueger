///|
/// `Elm.Parser.Expression.expression`.
fn expression(c : Cursor) -> @ast.Node[@ast.Expression] raise SyntaxError {
  expression_above(c, 0, false)
}

///|
/// Precedence climbing as elm-syntax does it: after the left operand, take
/// operators whose precedence is above `min` (or equal when `or_equal`).
fn expression_above(
  c : Cursor,
  min : Int,
  or_equal : Bool,
) -> @ast.Node[@ast.Expression] raise SyntaxError {
  let mut left = application(c)
  while c.positively_indented() {
    guard c.peek() is Some({ kind: Operator(op), .. } as op_token) else {
      break
    }
    guard c.dialect.operator(op) is Some({ precedence, direction, .. }) else {
      raise c.error_at(
        "unknown infix operator `\{op}`",
        op_token.span,
        "UNKNOWN OPERATOR",
        "I do not recognize this operator:",
        [
          plain(
            "Elm has a fixed set of operators; this is not one of them. Is there a typo?",
          ),
        ],
      )
    }
    let accepted = if or_equal { precedence >= min } else { precedence > min }
    if !accepted {
      break
    }
    ignore(c.advance())
    let right = match direction {
      Left => expression_above(c, precedence, false)
      Right => expression_above(c, precedence, true)
      Non => non_associative_right(c, precedence)
    }
    left = node(
      combine(left.range, right.range),
      OperatorApplication(op, direction, left, right),
    )
  }
  left
}

///|
/// Right operand of a non-associative operator: higher precedence only; an
/// operator of the same precedence is an error.
fn non_associative_right(
  c : Cursor,
  precedence : Int,
) -> @ast.Node[@ast.Expression] raise SyntaxError {
  let right = expression_above(c, precedence, false)
  if c.positively_indented() &&
    c.peek() is Some({ kind: Operator(op), .. } as t) &&
    c.dialect.operator(op) is Some({ precedence: p, .. }) &&
    p == precedence {
    raise c.error_at(
      "cannot mix non-associative infix operators without parentheses",
      t.span,
      "INFIX PROBLEM",
      "You cannot mix these two operators without parentheses:",
      [
        plain(
          "They do not associate, so I cannot tell which one goes first. Add parentheses to say what you mean.",
        ),
      ],
    )
  }
  right
}

///|
/// A sub-expression followed by positively indented arguments.
fn application(c : Cursor) -> @ast.Node[@ast.Expression] raise SyntaxError {
  let head = sub_expression(c)
  let args = [head]
  while c.positively_indented() && starts_argument(c) {
    args.push(sub_expression(c))
  }
  if args.length() == 1 {
    head
  } else {
    node(combine(head.range, args.last().unwrap().range), Application(args))
  }
}

///|
/// Whether a `-` at the cursor is a negation: the character before it is a
/// space, `(`, `)`, `}` or `,` (or nothing), and the operand touches it.
fn negation_here(c : Cursor) -> Bool {
  guard c.peek() is Some({ kind: Operator("-"), .. } as minus) else {
    return false
  }
  let before = match minus.trivia_before.last() {
    Some(Whitespace(_, _)) => Some(' ')
    Some(Newline(_, _)) => Some('\n')
    Some(Comment(comment)) => comment.text.to_array().last()
    None =>
      match c.previous() {
        Some(prev) => prev.lexeme.to_array().last()
        None => None
      }
  }
  let allowed = match before {
    None | Some(' ' | '(' | ')' | '}' | ',') => true
    _ => false
  }
  allowed &&
  (match c.peek_at(1) {
    Some(next) => touching(minus, next) && next.trivia_before.is_empty()
    None => false
  })
}

///|
fn starts_argument(c : Cursor) -> Bool {
  guard c.peek() is Some(t) else { return false }
  match t.kind {
    StringLiteral
    | CharLiteral
    | IntLiteral
    | FloatLiteral
    | Glsl
    | LParen
    | LBracket
    | LBrace
    | Backslash
    | Identifier
    | Keyword(Case | Let | If) => true
    Dot => c.peek_at(1) is Some(n) && is_lower(n) && touching(t, n)
    Operator("-") => negation_here(c)
    _ => false
  }
}

///|
fn sub_expression(c : Cursor) -> @ast.Node[@ast.Expression] raise SyntaxError {
  c.nested(() => sub_expression_at_depth(c))
}

///|
fn sub_expression_at_depth(
  c : Cursor,
) -> @ast.Node[@ast.Expression] raise SyntaxError {
  guard c.peek() is Some(t) else { raise c.fail("an expression") }
  match t.kind {
    StringLiteral => {
      ignore(c.advance())
      token_node(t, Literal(string_value(t, c.dialect)))
    }
    CharLiteral => {
      ignore(c.advance())
      token_node(t, CharLiteral(char_value(t, c.dialect)))
    }
    IntLiteral => {
      ignore(c.advance())
      weird_number_check(c, t)
      match int_value(t) {
        Ok(n) => token_node(t, Integer(n))
        Err(n) => token_node(t, Hex(n))
      }
    }
    FloatLiteral => {
      ignore(c.advance())
      weird_number_check(c, t)
      token_node(t, Floatable(float_value(t)))
    }
    Glsl => {
      ignore(c.advance())
      let text = t.lexeme
      let source = text.unsafe_substring(start=6, end=text.length() - 2)
      // elm-syntax keeps an elm/parser quirk: the range ends two columns late.
      let range = range_of(t)
      node(
        { start: range.start, end: shift(range.end, 2), },
        GLSLExpression(source),
      )
    }
    LParen => c.within(Parens, () => parens_expression(c))
    LBracket => c.within(List, () => list_expression(c))
    LBrace => c.within(Record, () => record_expression(c))
    Keyword(Case) => c.within(Case, () => case_expression(c))
    Keyword(Let) => c.within(Let, () => let_expression(c))
    Keyword(If) => c.within(If, () => if_expression(c))
    Backslash => c.within(Lambda, () => lambda_expression(c))
    Dot => {
      let dot = c.advance()
      if !(c.at_lower() && c.next_touches()) {
        raise c.fail("a field name after `.`")
      }
      let field = c.advance()
      node(range_from(dot, field), RecordAccessFunction("." + field.lexeme))
    }
    Operator("-") => {
      if !negation_here(c) {
        raise c.fail("an expression")
      }
      let minus = c.advance()
      let operand = sub_expression(c)
      node(
        { start: location(minus.span.start), end: operand.range.end, },
        Negation(operand),
      )
    }
    Identifier if is_lower(t) => {
      ignore(c.advance())
      record_accesses(
        c,
        token_node(t, @ast.Expression::FunctionOrValue([], t.lexeme)),
      )
    }
    Identifier => qualified_reference(c)
    _ => raise c.fail("an expression")
  }
}

///|
/// A number followed by a touching `.` with nothing after it, like `1.`.
fn weird_number_check(
  c : Cursor,
  number : @scanner.Token,
) -> Unit raise SyntaxError {
  let text = number.lexeme
  let is_decimal = !text.has_prefix("0x")
  if c.dialect.has(LeadingZero) &&
    (text.has_prefix("0e") || text.has_prefix("0E")) {
    raise c.error_at(
      "a number cannot start with 0 before an exponent [rule: leading-zero]",
      {
        start: shift_position(number.span.start, 1),
        end: shift_position(number.span.start, 1),
      },
      "WEIRD NUMBER",
      "I thought I was reading a number, but I ran into some weird stuff here:",
      [
        plain("I recognize numbers in the following formats:"),
        Example("42\n3.14\n6.022e23\n0x002B"),
        plain("So is there a way to write it like one of those?"),
      ],
    )
  }
  if c.dialect.has(LeadingZero) &&
    is_decimal &&
    text.length() > 1 &&
    text.has_prefix("0") &&
    !text.has_prefix("0.") &&
    !text.has_prefix("0e") &&
    !text.has_prefix("0E") {
    raise c.error_at(
      "numbers cannot start with zeros [rule: leading-zero]",
      {
        start: shift_position(number.span.start, 1),
        end: shift_position(number.span.start, 1),
      },
      "LEADING ZEROS",
      "I do not accept numbers with leading zeros:",
      [plain("Just delete the leading zeros and it should work!")],
    )
  }
  if c.peek() is Some({ kind: Identifier, lexeme: name, .. } as next) &&
    touching(number, next) {
    let first = name.get_char(0).unwrap_or(' ')
    if c.dialect.has(EmptyHex) && text == "0" && first == 'x' {
      raise c.error_at(
        "expected hex digits after `0x` [rule: empty-hex]",
        { start: next.span.start, end: next.span.start, },
        "WEIRD HEXIDECIMAL",
        "I thought I was reading a hexidecimal number until I got here:",
        [
          Text([
            Plain(
              "Valid hexidecimal digits include 0123456789abcdefABCDEF, so I can only recognize things like this:",
            ),
          ]),
          Example("0x2B\n0x002B\n0x00ffb3"),
        ],
      )
    }
    let weird = (
        c.dialect.has(UppercaseHexPrefix) && text == "0" && first == 'X'
      ) ||
      (c.dialect.has(ExponentWithoutDigits) && (first == 'e' || first == 'E'))
    if weird {
      raise c.error_at(
        "unexpected characters after a number",
        { start: next.span.start, end: next.span.start, },
        "WEIRD NUMBER",
        "I thought I was reading a number, but I ran into some weird stuff here:",
        [
          plain("I recognize numbers in the following formats:"),
          Example("42\n3.14\n6.022e23\n0x002B"),
          plain("So is there a way to write it like one of those?"),
        ],
      )
    }
  }
  if c.peek() is Some({ kind: Dot, .. } as dot) &&
    touching(number, dot) &&
    !(c.peek_at(1) is Some(n) && touching(dot, n) && is_lower(n)) {
    raise c.error_at(
      "a number cannot end with a dot",
      dot.span,
      "WEIRD NUMBER",
      "I thought I was reading a number, but I ran into some weird stuff here:",
      [
        Text([
          Plain("Floats need digits after the dot, like "),
          @scanner.Chunk::code("1.0"),
          Plain("."),
        ]),
      ],
    )
  }
}

///|
/// `.field` accesses that touch the expression before them.
fn record_accesses(
  c : Cursor,
  base : @ast.Node[@ast.Expression],
) -> @ast.Node[@ast.Expression] raise SyntaxError {
  let mut left = base
  while c.at_kind(Dot) &&
        c.next_touches() &&
        (match c.peek_at(1) {
          Some(n) => is_lower(n) && touching(c.peek().unwrap(), n)
          None => false
        }) {
    ignore(c.advance())
    let field = c.advance()
    let field_node = token_node(field, field.lexeme)
    left = node(
      combine(left.range, field_node.range),
      RecordAccess(left, field_node),
    )
  }
  left
}

///|
/// `Module.Name`, `Module.value`, `Name`, then record accesses.
fn qualified_reference(
  c : Cursor,
) -> @ast.Node[@ast.Expression] raise SyntaxError {
  let first = c.upper("a name")
  let modules = [first.lexeme]
  let mut last = first
  let mut lower_name : String? = None
  while c.at_kind(Dot) && c.next_touches() {
    guard c.peek_at(1) is Some(n) && touching(c.peek().unwrap(), n) else {
      break
    }
    if is_upper(n) {
      ignore(c.advance())
      last = c.advance()
      modules.push(last.lexeme)
    } else if is_lower(n) {
      ignore(c.advance())
      last = c.advance()
      lower_name = Some(last.lexeme)
      break
    } else {
      break
    }
  }
  let reference = match lower_name {
    Some(name) =>
      node(
        range_from(first, last),
        @ast.Expression::FunctionOrValue(modules, name),
      )
    None => {
      let name = modules.pop().unwrap()
      node(
        range_from(first, last),
        @ast.Expression::FunctionOrValue(modules, name),
      )
    }
  }
  if lower_name is Some(_) {
    record_accesses(c, reference)
  } else {
    reference
  }
}

///|
fn parens_expression(
  c : Cursor,
) -> @ast.Node[@ast.Expression] raise SyntaxError {
  let open = c.advance()
  if c.at_kind(RParen) && c.next_touches() {
    let close = c.advance()
    return node(range_from(open, close), UnitExpr)
  }
  if c.peek() is Some({ kind: Operator(op), .. } as op_token) &&
    touching(open, op_token) &&
    c.peek_at(1) is Some({ kind: RParen, .. } as close) &&
    touching(op_token, close) {
    ignore(c.advance())
    ignore(c.advance())
    return node(range_from(open, close), PrefixOperator(op))
  }
  if c.peek() is Some({ kind: Operator(_), .. } as op_token) &&
    touching(open, op_token) &&
    !negation_here(c) {
    ignore(c.advance())
    raise c.fail_titled(
      "expected `)` after the operator",
      "UNFINISHED OPERATOR FUNCTION",
      [
        Plain("I was parsing an operator function like "),
        @scanner.Chunk::code("(+)"),
        Plain(", but I got stuck here:"),
      ],
      [plain("I was expecting a closing parenthesis right after the operator.")],
    )
  }
  let first = expression(c)
  if c.at_kind(RParen) {
    let close = c.advance()
    return record_accesses(
      c,
      node(range_from(open, close), ParenthesizedExpression(first)),
    )
  }
  ignore(c.expect(Comma, "`,` or `)`"))
  let parts = [first, expression(c)]
  if c.at_kind(Comma) {
    ignore(c.advance())
    parts.push(expression(c))
  }
  let close = c.expect(RParen, "`)`")
  node(range_from(open, close), TupledExpression(parts))
}

///|
fn list_expression(c : Cursor) -> @ast.Node[@ast.Expression] raise SyntaxError {
  let open = c.advance()
  let items = []
  if !c.at_kind(RBracket) {
    items.push(expression(c))
    while c.at_kind(Comma) {
      ignore(c.advance())
      items.push(expression(c))
    }
  }
  let close = c.expect(RBracket, "`,` or `]`")
  node(range_from(open, close), ListExpr(items))
}

///|
/// A record setter whose range ends where the next token starts (elm-syntax
/// includes the trailing whitespace).
fn record_setter(c : Cursor) -> @ast.Node[@ast.RecordSetter] raise SyntaxError {
  let field = c.lower("a field name")
  ignore(c.expect(Equals, "`=`"))
  let value = expression(c)
  let end = match c.peek() {
    Some(next) => location(next.span.start)
    None => value.range.end
  }
  node({ start: location(field.span.start), end, }, {
    field: token_node(field, field.lexeme),
    expression: value,
  })
}

///|
fn record_expression(
  c : Cursor,
) -> @ast.Node[@ast.Expression] raise SyntaxError {
  let open = c.advance()
  if c.at_kind(RBrace) {
    let close = c.advance()
    return record_accesses(c, node(range_from(open, close), RecordExpr([])))
  }
  if c.at_lower() && c.peek_at(1) is Some({ kind: Pipe, .. }) {
    let name = c.advance()
    ignore(c.advance())
    let setters = [record_setter(c)]
    while c.at_kind(Comma) {
      ignore(c.advance())
      setters.push(record_setter(c))
    }
    let close = c.expect(RBrace, "`,` or `}`")
    return record_accesses(
      c,
      node(
        range_from(open, close),
        RecordUpdateExpression(token_node(name, name.lexeme), setters),
      ),
    )
  }
  let first_name = c.lower("a field name")
  ignore(c.expect(Equals, "`=` or `|`"))
  let first_value = expression(c)
  let setters : Array[@ast.Node[@ast.RecordSetter]] = [
    node(combine(range_of(first_name), first_value.range), {
      field: token_node(first_name, first_name.lexeme),
      expression: first_value,
    }),
  ]
  while c.at_kind(Comma) {
    ignore(c.advance())
    setters.push(record_setter(c))
  }
  let close = c.expect(RBrace, "`,` or `}`")
  record_accesses(c, node(range_from(open, close), RecordExpr(setters)))
}

///|
fn lambda_expression(
  c : Cursor,
) -> @ast.Node[@ast.Expression] raise SyntaxError {
  let backslash = c.advance()
  let args = [argument_pattern(c)]
  while !c.at_kind(Arrow) {
    args.push(argument_pattern(c))
  }
  ignore(c.expect(Arrow, "`->`"))
  let body = expression(c)
  node(
    { start: location(backslash.span.start), end: body.range.end, },
    LambdaExpression({ args, expression: body, }),
  )
}

///|
fn if_expression(c : Cursor) -> @ast.Node[@ast.Expression] raise SyntaxError {
  let if_token = c.advance()
  let condition = expression(c)
  ignore(c.expect(Keyword(Then), "`then`"))
  let then_branch = expression(c)
  ignore(c.expect(Keyword(Else), "`else`"))
  let else_branch = expression(c)
  node(
    { start: location(if_token.span.start), end: else_branch.range.end, },
    IfBlock(condition, then_branch, else_branch),
  )
}

///|
fn case_branch(c : Cursor) -> @ast.Case raise SyntaxError {
  c.start_item()
  let pat = pattern(c)
  ignore(c.expect(Arrow, "`->`"))
  { pattern: pat, expression: expression(c), }
}

///|
fn case_expression(c : Cursor) -> @ast.Node[@ast.Expression] raise SyntaxError {
  let case_token = c.advance()
  let subject = expression(c)
  ignore(c.expect(Keyword(Of), "`of`"))
  guard c.peek() is Some(first) else { raise c.fail("a case branch") }
  let column = first.span.start.column
  if c.dialect.has(IndentedContinuation) && column <= c.indent {
    c.layout_failure = true
    let error = c.fail("a case branch indented more")
    c.layout_failure = false
    raise error
  }
  let cases = c.with_indent(column, () => {
    let cases = [case_branch(c)]
    // A token at the branch column that cannot start a pattern (for example
    // an operator) ends the branches, as in elm-syntax.
    while c.peek() is Some(t) &&
          t.span.start.column == column &&
          starts_pattern(c) {
      cases.push(case_branch(c))
    }
    cases
  })
  let end = cases.last().unwrap().expression.range.end
  node(
    { start: location(case_token.span.start), end, },
    CaseExpression({ expression: subject, cases, }),
  )
}

///|
fn let_expression(c : Cursor) -> @ast.Node[@ast.Expression] raise SyntaxError {
  let let_token = c.advance()
  guard c.peek() is Some(first) else { raise c.fail("a let declaration") }
  let column = first.span.start.column
  if c.dialect.has(LetDeclarationColumn) &&
    column <= let_token.span.start.column {
    c.layout_failure = true
    let error = c.fail("a let declaration indented more than `let`")
    c.layout_failure = false
    raise error
  }
  let declarations = c.with_indent(column, () => {
    let declarations = [let_declaration(c)]
    while !c.is_keyword(In) {
      guard c.peek() is Some(t) && t.span.start.column == column else {
        raise c.fail("`in` or a let declaration")
      }
      declarations.push(let_declaration(c))
    }
    declarations
  })
  ignore(c.expect(Keyword(In), "`in`"))
  let body = expression(c)
  node(
    { start: location(let_token.span.start), end: body.range.end, },
    LetExpression({ declarations, expression: body, }),
  )
}

///|
fn let_declaration(
  c : Cursor,
) -> @ast.Node[@ast.LetDeclaration] raise SyntaxError {
  c.start_item()
  if c.peek() is Some(t) && is_lower(t) {
    let f = c.within(Definition(t.lexeme), () => function_parts(c, None))
    node(f.range, LetFunction(f.value))
  } else {
    let pat = argument_pattern(c)
    ignore(c.expect(Equals, "`=`"))
    let value = expression(c)
    node(combine(pat.range, value.range), LetDestructuring(pat, value))
  }
}

///|
/// A function: `name : type` on its own line (optional), then
/// `name args = expression`. The range starts at `start` (the doc comment)
/// or at the first name.
fn function_parts(
  c : Cursor,
  documentation : @ast.Node[String]?,
) -> @ast.Node[@ast.Function] raise SyntaxError {
  let start_name = c.lower("a function name")
  let mut signature : @ast.Node[@ast.Signature]? = None
  let mut name = start_name
  if c.at_kind(Colon) {
    ignore(c.advance())
    let annotation = type_annotation(c)
    guard c.peek() is Some(impl_name) &&
      is_lower(impl_name) &&
      impl_name.span.start.column == c.indent else {
      raise c.fail("the implementation of `\{start_name.lexeme}`")
    }
    c.start_item()
    if impl_name.lexeme != start_name.lexeme {
      raise c.error_at(
        "expected to find the same name for declaration and signature",
        impl_name.span,
        "NAME MISMATCH",
        "I just saw a type annotation for `\{start_name.lexeme}`, but it is followed by a definition for `\{impl_name.lexeme}`:",
        [plain("These names do not match! Is there a typo?")],
      )
    }
    ignore(c.advance())
    signature = Some(
      node(combine(range_of(start_name), annotation.range), {
        name: token_node(start_name, start_name.lexeme),
        type_annotation: annotation,
      }),
    )
    name = impl_name
  }
  let arguments = []
  while !c.at_kind(Equals) {
    arguments.push(argument_pattern(c))
  }
  ignore(c.advance())
  let body = expression(c)
  let implementation : @ast.Node[@ast.FunctionImplementation] = node(
    { start: location(name.span.start), end: body.range.end, },
    { name: token_node(name, name.lexeme), arguments, expression: body, },
  )
  let start = match documentation {
    Some(doc) => doc.range.start
    None => location(start_name.span.start)
  }
  node({ start, end: body.range.end, }, {
    documentation,
    signature,
    declaration: implementation,
  })
}
