///|
test "400 nested levels print on every target" {
  // `-(-(...-x))`: the parentheses stay (a negation in a negation needs
  // them), except around `x`.
  let mut e : @ast.Node[@ast.Expression] = n(FunctionOrValue([][:], "x"))
  for _ in 0..<200 {
    e = n(Negation(n(ParenthesizedExpression(e))))
  }
  inspect(@printer.print_expression(e, width=1_000_000).length(), content="599")
}

///|
test "400 nested parentheses that go print on every target" {
  let mut e : @ast.Node[@ast.Expression] = n(FunctionOrValue([][:], "x"))
  for _ in 0..<400 {
    e = n(ParenthesizedExpression(e))
  }
  inspect(@printer.print_expression(e, width=1_000_000), content="x")
}

///|
test "401 nested levels raise TooDeep" {
  let mut e : @ast.Node[@ast.Expression] = n(FunctionOrValue([][:], "x"))
  for _ in 0..<401 {
    e = n(ParenthesizedExpression(e))
  }
  let p = problem_of(() => @printer.print_expression(e))
  @expect.expect(p.map(x => x.0)).to_equal(Some(TooDeep))
  @expect.expect(p.map(x => x.1.length())).to_equal(Some(401))
}

///|
test "nested lets, cases and lists at 130 levels print on every target" {
  let mut e : @ast.Node[@ast.Expression] = n(FunctionOrValue([][:], "x"))
  for i in 0..<130 {
    e = match i % 3 {
      0 =>
        n(
          LetExpression({
            declarations: [
              (
                n(LetDestructuring(pvar("y"), e)) :
                @ast.Node[@ast.LetDeclaration]),
            ][:],
            expression: n(FunctionOrValue([][:], "y")),
          }),
        )
      1 =>
        n(
          CaseExpression({
            expression: e,
            cases: [({ pattern: pvar("y"), expression: v("y"), } : @ast.Case)][:],
          }),
        )
      _ => n(ListExpr([e][:]))
    }
  }
  ignore(@printer.print_expression(e))
}

///|
test "long chains print without nesting" {
  let mut e : @ast.Node[@ast.Expression] = n(FunctionOrValue([][:], "x"))
  let mut access : @ast.Node[@ast.Expression] = n(FunctionOrValue([][:], "r"))
  let mut t : @ast.Node[@ast.TypeAnnotation] = n(GenericType("a"))
  for _ in 0..<10_000 {
    e = n(OperatorApplication("+", Left, e, n(Integer(1L))))
    access = n(RecordAccess(access, n("f")))
    t = n(FunctionTypeAnnotation(n(GenericType("a")), t))
  }
  @expect.expect_all(s => {
    s
    .expect(
      @printer.print_expression(e, width=1_000_000).has_prefix("x + 1 + 1"),
    )
    .to_be_true()
    s
    .expect(
      @printer.print_expression(access, width=1_000_000).has_prefix("r.f.f"),
    )
    .to_be_true()
    s
    .expect(
      @printer.print_type_annotation(t, width=1_000_000).has_prefix("a -> a"),
    )
    .to_be_true()
  })
}

///|
test "400 nested patterns print on every target" {
  let mut p : @ast.Node[@ast.Pattern] = pvar("x")
  for _ in 0..<400 {
    p = n(ParenthesizedPattern(p))
  }
  inspect(@printer.print_pattern(p, width=1_000_000).length(), content="801")
}

///|
test "401 nested patterns raise TooDeep" {
  let mut p : @ast.Node[@ast.Pattern] = pvar("x")
  for _ in 0..<401 {
    p = n(ParenthesizedPattern(p))
  }
  let e = problem_of(() => @printer.print_pattern(p))
  @expect.expect(e.map(x => x.0)).to_equal(Some(TooDeep))
  @expect.expect(e.map(x => x.1.length())).to_equal(Some(401))
}

///|
test "400 nested types print on every target" {
  let mut t : @ast.Node[@ast.TypeAnnotation] = tvar("a")
  let mut u : @ast.Node[@ast.TypeAnnotation] = tvar("a")
  for _ in 0..<400 {
    t = typed("List", [t])
    u = n(Tupled([u, tvar("b")][:]))
  }
  @expect.expect_all(s => {
    s
    .expect(@printer.print_type_annotation(t, width=1_000_000).length())
    .to_equal(2799)
    s
    .expect(@printer.print_type_annotation(u, width=1_000_000).length())
    .to_equal(2801)
  })
}

///|
test "401 nested types raise TooDeep" {
  let mut t : @ast.Node[@ast.TypeAnnotation] = tvar("a")
  for _ in 0..<401 {
    t = typed("List", [t])
  }
  let e = problem_of(() => @printer.print_type_annotation(t))
  @expect.expect(e.map(x => x.0)).to_equal(Some(TooDeep))
  @expect.expect(e.map(x => x.1.length())).to_equal(Some(401))
}

///|
/// One of each nested expression construct, at the next printer level.
fn wrap_expr(
  i : Int,
  e : @ast.Node[@ast.Expression],
) -> @ast.Node[@ast.Expression] {
  let y : @ast.Node[@ast.Expression] = n(FunctionOrValue([][:], "y"))
  match i % 12 {
    0 => n(ListExpr([y, e][:]))
    1 => n(TupledExpression([e, y][:]))
    2 =>
      n(
        RecordExpr(
          [
            (n({ field: n("a"), expression: e, }) : @ast.Node[@ast.RecordSetter]),
          ][:],
        ),
      )
    3 =>
      n(
        RecordUpdateExpression(
          n("r"),
          [
            (n({ field: n("a"), expression: e, }) : @ast.Node[@ast.RecordSetter]),
          ][:],
        ),
      )
    4 => n(Negation(n(ParenthesizedExpression(e))))
    5 => n(IfBlock(e, y, y))
    6 => n(IfBlock(y, y, e))
    7 =>
      n(
        CaseExpression({
          expression: y,
          cases: [({ pattern: pvar("z"), expression: e, } : @ast.Case)][:],
        }),
      )
    8 => n(LambdaExpression({ args: [pvar("z")][:], expression: e, }))
    9 =>
      n(
        LetExpression({
          declarations: [
            (
              n(
                LetFunction({
                  documentation: None,
                  signature: None,
                  declaration: n({
                    name: n("g"),
                    arguments: [pvar("z")][:],
                    expression: e,
                  }),
                }),
              ) : @ast.Node[@ast.LetDeclaration]),
          ][:],
          expression: y,
        }),
      )
    10 => n(Application([y, n(ParenthesizedExpression(e))][:]))
    _ => n(RecordAccess(n(ParenthesizedExpression(e)), n("f")))
  }
}

///|
test "every nested expression construct at 400 levels prints on every target" {
  // A let function adds two levels (the function and its body), a negation
  // or an access of a parenthesized expression two, an else-if none.
  let mut e : @ast.Node[@ast.Expression] = n(FunctionOrValue([][:], "x"))
  let mut level = 0
  let mut i = 0
  while level < 398 {
    e = wrap_expr(i, e)
    level = level +
      (match i % 12 {
        4 | 9 | 10 | 11 => 2
        _ => 1
      })
    i = i + 1
  }
  let printed = @printer.print_expression(e, width=1_000_000)
  @expect.expect(printed.contains("x")).to_be_true()
}

///|
/// A file with one declaration `x <arg> = <body>`.
fn depth_file(
  arg : @ast.Node[@ast.Pattern],
  body : @ast.Node[@ast.Expression],
) -> @ast.File {
  {
    module_definition: n(
      NormalModule({ module_name: n(["A"][:]), exposing_list: n(All(r0)), }),
    ),
    imports: [][:],
    declarations: [
      n(
        @ast.Declaration::FunctionDeclaration({
          documentation: None,
          signature: None,
          declaration: n({
            name: n("x"),
            arguments: [arg][:],
            expression: body,
          }),
        }),
      ),
    ][:],
    comments: [][:],
  }
}

///|
test "normalize_file handles 2000 nested patterns and expressions on every target" {
  // A built AST has no nesting limit; normalize_file uses explicit stacks.
  let mut p : @ast.Node[@ast.Pattern] = pvar("y")
  let mut cons : @ast.Node[@ast.Pattern] = pvar("t")
  let mut e : @ast.Node[@ast.Expression] = n(FunctionOrValue([][:], "y"))
  for _ in 0..<2000 {
    p = n(ParenthesizedPattern(n(TuplePattern([p, pvar("z")][:]))))
    cons = n(UnConsPattern(ctor("Just", [pvar("h")]), cons))
    e = n(ListExpr([n(@ast.Expression::ParenthesizedExpression(e))][:]))
  }
  let normalized = @printer.normalize_file(
    depth_file(n(TuplePattern([p, cons][:])), e),
  )
  guard normalized.declarations[0].value is FunctionDeclaration(f) else {
    fail("not a function")
  }
  guard f.declaration.value.arguments[0].value is TuplePattern(items) else {
    fail("not a tuple")
  }
  // Count the levels with loops (no recursion).
  let mut depth = 0
  let mut q = items[0]
  while q.value is ParenthesizedPattern({ value: TuplePattern(xs), .. }) {
    depth += 1
    q = xs[0]
  }
  let mut wrapped = 0
  let mut c = items[1]
  while c.value is UnConsPattern(left, right) {
    if left.value is ParenthesizedPattern(_) {
      wrapped += 1
    }
    c = right
  }
  let mut lists = 0
  let mut x = f.declaration.value.expression
  while x.value is ListExpr(ys) {
    lists += 1
    x = ys[0]
  }
  @expect.expect_all(s => {
    s.expect(depth).to_equal(2000)
    s.expect(wrapped).to_equal(2000)
    // The parentheses in the lists go.
    s.expect(lists).to_equal(2000)
    s.expect(x.value is FunctionOrValue(_, "y")).to_be_true()
  })
}
