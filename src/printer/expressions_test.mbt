///|
fn expr_of(body : String) -> @ast.Node[@ast.Expression] raise {
  let text = "module M exposing (..)\n\n\nf =\n    " + body + "\n"
  let result = @parser.parse_module(
    @scanner.SourceText::new(text),
    @scanner.DefaultScanner::new(),
  )
  guard result.diagnostics.is_empty() &&
    result.ast is Some(file) &&
    file.declarations[0].value is FunctionDeclaration(f) else {
    fail("does not parse: \{body}")
  }
  f.declaration.value.expression
}

///|
fn v(name : String) -> @ast.Node[@ast.Expression] {
  n(FunctionOrValue([][:], name))
}

///|
fn op(
  symbol : String,
  dir : @ast.InfixDirection,
  l : @ast.Node[@ast.Expression],
  r : @ast.Node[@ast.Expression],
) -> @ast.Node[@ast.Expression] {
  n(OperatorApplication(symbol, dir, l, r))
}

///|
fn app(items : Array[@ast.Node[@ast.Expression]]) -> @ast.Node[@ast.Expression] {
  n(Application(items[:]))
}

///|
fn lam(body : @ast.Node[@ast.Expression]) -> @ast.Node[@ast.Expression] {
  n(LambdaExpression({ args: [pvar("x")][:], expression: body, }))
}

///|
test "parsed one-line expressions print back unchanged" {
  @expect.expect_all(s => {
    for
      src in [
        "a + b * c", "(a + b) * c", "a ++ b ++ c |> d", "a :: b :: c", "g -x -1",
        "-(-x)", "f (g x) [ 1, 2 ] { a = 1 }", "List.map .name xs", "\\x y -> x + y",
        "f <| \\x -> x", "(\\x -> x) 1", "r.a.b", "{ r | a = 1, b = 2 }", "( 1, \"s\", 'c' )",
        "a == b", "(+) 1 2", "0xFF", "1.5e-7", "Nothing", "()", "[]", "{}", "x |> (\\y -> y) |> z",
        "f -(g x)",
      ] {
      s.expect(@printer.print_expression(expr_of(src))).to_equal(src)
    }
  })
}

///|
test "missing parentheses are added where precedence needs them" {
  @expect.expect_all(s => {
    let (a, b, c) = (v("a"), v("b"), v("c"))
    s
    .expect(@printer.print_expression(op("*", Left, op("+", Left, a, b), c)))
    .to_equal("(a + b) * c")
    s
    .expect(@printer.print_expression(op("-", Left, a, op("-", Left, b, c))))
    .to_equal("a - (b - c)")
    s
    .expect(@printer.print_expression(op("-", Left, op("-", Left, a, b), c)))
    .to_equal("a - b - c")
    s
    .expect(@printer.print_expression(op("^", Right, op("^", Right, a, b), c)))
    .to_equal("(a ^ b) ^ c")
    s
    .expect(@printer.print_expression(op("==", Non, op("==", Non, a, b), c)))
    .to_equal("(a == b) == c")
    s
    .expect(@printer.print_expression(app([v("f"), app([v("g"), a])])))
    .to_equal("f (g a)")
    s
    .expect(@printer.print_expression(app([app([v("f"), a]), b])))
    .to_equal("(f a) b")
    s
    .expect(@printer.print_expression(n(Negation(n(Negation(a))))))
    .to_equal("-(-a)")
    s
    .expect(@printer.print_expression(n(Negation(n(Integer(-1L))))))
    .to_equal("-(-1)")
    s
    .expect(
      @printer.print_expression(op("+", Left, lam(v("x")), n(Integer(1L)))),
    )
    .to_equal("(\\x -> x) + 1")
    s
    .expect(
      @printer.print_expression(op("+", Left, n(Integer(1L)), lam(v("x")))),
    )
    .to_equal("1 + \\x -> x")
    s
    .expect(@printer.print_expression(app([v("f"), lam(v("x"))])))
    .to_equal("f (\\x -> x)")
    s
    .expect(@printer.print_expression(app([v("f"), n(Integer(-3L))])))
    .to_equal("f -3")
  })
}

///|
test "record access targets get parentheses" {
  @expect.expect_all(s => {
    s
    .expect(@printer.print_expression(n(RecordAccess(n(Integer(1L)), n("a")))))
    .to_equal("(1).a")
    s
    .expect(@printer.print_expression(n(RecordAccess(v("Just"), n("a")))))
    .to_equal("(Just).a")
    s
    .expect(
      @printer.print_expression(n(RecordAccess(app([v("f"), v("x")]), n("a")))),
    )
    .to_equal("(f x).a")
    s
    .expect(@printer.print_expression(n(RecordAccess(v("r"), n("a")))))
    .to_equal("r.a")
    s
    .expect(
      @printer.print_expression(
        n(RecordAccess(n(RecordAccessFunction(".f")), n("a"))),
      ),
    )
    .to_equal("(.f).a")
    s
    .expect(
      @printer.print_expression(n(Negation(n(RecordAccessFunction(".f"))))),
    )
    .to_equal("-(.f)")
  })
}

///|
test "number edges" {
  @expect.expect_all(s => {
    s.expect(@printer.print_expression(n(Floatable(-0.0)))).to_equal("-0.0")
    s.expect(@printer.print_expression(n(Floatable(1.0e21)))).to_equal("1.0e21")
    s.expect(@printer.print_expression(n(Hex(-16L)))).to_equal("-0x10")
    s
    .expect(@printer.print_expression(n(Integer(9223372036854775807L))))
    .to_equal("9223372036854775807")
    s
    .expect(
      problem_of(() => {
        @printer.print_expression(n(Integer(-9223372036854775807L - 1L)))
      }),
    )
    .to_equal(Some((UnrepresentableInt(-9223372036854775807L - 1L), [])))
    s
    .expect(
      problem_of(() => @printer.print_expression(n(Floatable(0.0 / 0.0)))).map(p => {
        p.0 is NonFiniteFloat(_)
      }),
    )
    .to_equal(Some(true))
  })
}

///|
test "expressions that Elm cannot write raise with their path" {
  @expect.expect_all(s => {
    let x = v("x")
    s
    .expect(problem_of(() => @printer.print_expression(app([x]))))
    .to_equal(Some((ShortApplication, [])))
    s
    .expect(problem_of(() => @printer.print_expression(op("<=>", Left, x, x))))
    .to_equal(Some((UnknownOperator("<=>"), [])))
    s
    .expect(
      problem_of(() => @printer.print_expression(n(GLSLExpression("a|]b")))),
    )
    .to_equal(Some((InvalidGlsl, [])))
    s
    .expect(
      problem_of(() => @printer.print_expression(n(TupledExpression([x][:])))),
    )
    .to_equal(Some((ShortTuple, [])))
    s
    .expect(
      problem_of(() => {
        @printer.print_expression(n(RecordUpdateExpression(n("r"), [][:])))
      }),
    )
    .to_equal(Some((NoFields, [])))
    s
    .expect(
      problem_of(() => {
        @printer.print_expression(
          n(CaseExpression({ expression: x, cases: [][:], })),
        )
      }),
    )
    .to_equal(Some((EmptyCase, [])))
    s
    .expect(
      problem_of(() => {
        @printer.print_expression(
          n(LetExpression({ declarations: [][:], expression: x, })),
        )
      }),
    )
    .to_equal(Some((EmptyLet, [])))
    s
    .expect(
      problem_of(() => {
        @printer.print_expression(
          n(LambdaExpression({ args: [][:], expression: x, })),
        )
      }),
    )
    .to_equal(Some((NoLambdaArguments, [])))
    s
    .expect(
      problem_of(() => {
        @printer.print_expression(app([v("f"), n(ListExpr([x, v("if")][:]))]))
      }),
    )
    .to_equal(
      Some(
        (
          InvalidName(Lower, "if"),
          [{ field: "application", index: 1, }, { field: "list", index: 1, }],
        ),
      ),
    )
  })
}

///|
test "vertical shapes of if, case and let" {
  @expect.expect_all(s => {
    s
    .expect(@printer.print_expression(expr_of("if a then b else c")))
    .to_equal("if a then\n    b\n\nelse\n    c")
    s
    .expect(
      @printer.print_expression(expr_of("if a then b else if c then d else e")),
    )
    .to_equal("if a then\n    b\n\nelse if c then\n    d\n\nelse\n    e")
    s
    .expect(
      @printer.print_expression(
        expr_of("case x of\n        Just y -> y\n\n        Nothing -> 0"),
      ),
    )
    .to_equal(
      "case x of\n    Just y ->\n        y\n\n    Nothing ->\n        0",
    )
    s
    .expect(
      @printer.print_expression(
        expr_of("let\n        a = 1\n        b = 2\n    in\n    a + b"),
      ),
    )
    .to_equal("let\n    a =\n        1\n\n    b =\n        2\nin\na + b")
  })
}

///|
test "groups break in the elm-format shape" {
  @expect.expect_all(s => {
    s
    .expect(
      @printer.print_expression(
        expr_of("aaaaaaaa |> bbbbbbbb |> cccccccc"),
        width=20,
      ),
    )
    .to_equal("aaaaaaaa\n    |> bbbbbbbb\n    |> cccccccc")
    s
    .expect(@printer.print_expression(expr_of("f aaaaaa bbbbbb"), width=12))
    .to_equal("f\n    aaaaaa\n    bbbbbb")
    s
    .expect(@printer.print_expression(expr_of("[ aaaa, bbbb ]"), width=10))
    .to_equal("[ aaaa\n, bbbb\n]")
    s
    .expect(
      @printer.print_expression(expr_of("{ r | aaaa = 1, bbbb = 2 }"), width=20),
    )
    .to_equal("{ r\n    | aaaa = 1\n    , bbbb = 2\n}")
    s
    .expect(@printer.print_expression(expr_of("\\x -> aaaaaaaaaa"), width=10))
    .to_equal("\\x ->\n    aaaaaaaaaa")
    s
    .expect(@printer.print_expression(expr_of("( aaaa, bbbb )"), width=10))
    .to_equal("( aaaa\n, bbbb\n)")
  })
}

///|
test "a long string literal stays on one line" {
  let long = "a very long text that does not fit"
  inspect(
    @printer.print_expression(
      n(ListExpr([n(@ast.Expression::Literal(long))][:])),
      width=10,
    ),
    content="[ \"a very long text that does not fit\"\n]",
  )
}

///|
test "the first problem in print order is reported" {
  let bad = app([v("x")])
  let negative : @ast.Node[@ast.Pattern] = n(IntPattern(-1L))
  let case_ : @ast.Node[@ast.Expression] = n(
    CaseExpression({
      expression: bad,
      cases: [({ pattern: negative, expression: v("x"), } : @ast.Case)][:],
    }),
  )
  let let_ : @ast.Node[@ast.Expression] = n(
    LetExpression({
      declarations: [
        (
          n(
            LetFunction({
              documentation: Some(n("not a doc")),
              signature: None,
              declaration: n({
                name: n("f"),
                arguments: [negative][:],
                expression: bad,
              }),
            }),
          ) : @ast.Node[@ast.LetDeclaration]),
      ][:],
      expression: bad,
    }),
  )
  let access : @ast.Node[@ast.Expression] = n(RecordAccess(bad, n("X")))
  let chain = op("+", Left, bad, op("<=>", Left, v("a"), v("b")))
  let problem = (e : @ast.Node[@ast.Expression]) => {
    problem_of(() => @printer.print_expression(e)).map(p => p.0)
  }
  @expect.expect_all(s => {
    s.expect(problem(case_)).to_equal(Some(ShortApplication))
    s.expect(problem(let_)).to_equal(Some(InvalidDocumentation))
    s.expect(problem(access)).to_equal(Some(ShortApplication))
    s.expect(problem(chain)).to_equal(Some(UnknownOperator("<=>")))
  })
}

///|
test "a let destructuring pattern that is not a term gets parentheses" {
  let let_with = (p : @ast.Node[@ast.Pattern]) => {
    @printer.print_expression(
      n(
        LetExpression({
          declarations: [n(@ast.LetDeclaration::LetDestructuring(p, v("x")))][:],
          expression: v("w"),
        }),
      ),
    )
  }
  @expect.expect_all(s => {
    s
    .expect(let_with(ctor("Wrap", [pvar("w")])))
    .to_equal("let\n    (Wrap w) =\n        x\nin\nw")
    s
    .expect(let_with(n(UnConsPattern(pvar("a"), pvar("b")))))
    .to_equal("let\n    (a :: b) =\n        x\nin\nw")
    s
    .expect(let_with(n(AsPattern(pvar("a"), n("b")))))
    .to_equal("let\n    (a as b) =\n        x\nin\nw")
    s
    .expect(let_with(n(TuplePattern([pvar("a"), pvar("b")][:]))))
    .to_equal("let\n    ( a, b ) =\n        x\nin\nw")
  })
}

///|
test "a record access target that is not a name, record or parenthesized expression gets parentheses" {
  let access = (target : @ast.Expression) => {
    @printer.print_expression(n(RecordAccess(n(target), n("f"))))
  }
  @expect.expect_all(s => {
    s.expect(access(Literal("s"))).to_equal("(\"s\").f")
    s.expect(access(CharLiteral('c'))).to_equal("('c').f")
    s.expect(access(UnitExpr)).to_equal("(()).f")
    s.expect(access(ListExpr([][:]))).to_equal("([]).f")
    s.expect(access(ListExpr([v("x")][:]))).to_equal("([ x ]).f")
    s
    .expect(access(TupledExpression([v("a"), v("b")][:])))
    .to_equal("(( a, b )).f")
    s.expect(access(GLSLExpression(" a "))).to_equal("([glsl| a |]).f")
    s.expect(access(PrefixOperator("+"))).to_equal("((+)).f")
    // These parse back as a record access without parentheses.
    s.expect(access(FunctionOrValue(["List"][:], "map"))).to_equal("List.map.f")
    s.expect(access(RecordExpr([][:]))).to_equal("{}.f")
    s
    .expect(
      access(
        RecordUpdateExpression(
          n("r"),
          [n(@ast.RecordSetter::{ field: n("a"), expression: v("x"), })][:],
        ),
      ),
    )
    .to_equal("{ r | a = x }.f")
    s.expect(access(ParenthesizedExpression(v("x")))).to_equal("(x).f")
  })
}

///|
test "let, case and if after an operator indent right of their keyword" {
  // `let` is at column 9 here: its declarations must be right of it.
  @expect.expect_all(s => {
    s
    .expect(@printer.print_expression(expr_of("a </> let y = 1 in y")))
    .to_equal(
      (
        #|a
        #|    </> let
        #|            y =
        #|                1
        #|        in
        #|        y
      ),
    )
    s
    .expect(@printer.print_expression(expr_of("a </> case x of _ -> y")))
    .to_equal(
      (
        #|a
        #|    </> case x of
        #|            _ ->
        #|                y
      ),
    )
    s
    .expect(@printer.print_expression(expr_of("a </> if c then x else y")))
    .to_equal(
      (
        #|a
        #|    </> if c then
        #|            x
        #|
        #|        else
        #|            y
      ),
    )
    s
    .expect(@printer.print_expression(expr_of("a == (b && let y = 1 in y)")))
    .to_equal(
      (
        #|a
        #|    == (b
        #|            && let
        #|                y =
        #|                    1
        #|               in
        #|               y
        #|       )
      ),
    )
  })
}

///|
test "if, case and let indent to the next multiple of 4 right of their keyword" {
  // The elm-format 0.8.7 forms: `in`, `else` and the let body in the
  // keyword's column, everything inside at the next tab stop.
  @expect.expect_all(s => {
    s
    .expect(
      @printer.print_expression(
        expr_of("g (case x of A -> 1) (let y = 1 in y) (if c then x else y)"),
      ),
    )
    .to_equal(
      (
        #|g
        #|    (case x of
        #|        A ->
        #|            1
        #|    )
        #|    (let
        #|        y =
        #|            1
        #|     in
        #|     y
        #|    )
        #|    (if c then
        #|        x
        #|
        #|     else
        #|        y
        #|    )
      ),
    )
    s
    .expect(
      @printer.print_expression(
        expr_of("[ case x of A -> 1, let y = 1 in y, if c then x else y ]"),
      ),
    )
    .to_equal(
      (
        #|[ case x of
        #|    A ->
        #|        1
        #|, let
        #|    y =
        #|        1
        #|  in
        #|  y
        #|, if c then
        #|    x
        #|
        #|  else
        #|    y
        #|]
      ),
    )
    s
    .expect(@printer.print_expression(expr_of("a |> let y = 1 in y")))
    .to_equal(
      (
        #|a
        #|    |> let
        #|        y =
        #|            1
        #|       in
        #|       y
      ),
    )
  })
}

///|
test "a broken <| ends its line" {
  // elm-format 0.8.7 (`formatBinary`): `<|` ends the line, or stands on its
  // own line after other operators; the rest is a new chain one tab stop in.
  @expect.expect_all(s => {
    s
    .expect(@printer.print_expression(expr_of("f x <| g y"), width=8))
    .to_equal("f x <|\n    g y")
    s
    .expect(@printer.print_expression(expr_of("f x <| g y <| h z"), width=12))
    .to_equal("f x <|\n    g y <|\n        h z")
    s
    .expect(@printer.print_expression(expr_of("f x <| g y ++ h z"), width=14))
    .to_equal("f x <|\n    g y\n        ++ h z")
    s
    .expect(@printer.print_expression(expr_of("f x ++ g y <| h z"), width=14))
    .to_equal("f x\n    ++ g y\n<|\n    h z")
    s
    .expect(@printer.print_expression(expr_of("f x <| g y")))
    .to_equal("f x <| g y")
  })
}

///|
test "broken items indent to the next tab stop" {
  // elm-format indents to multiples of 4: inside `[ ` (2 columns) an
  // application's arguments go to column 4, not 6.
  @expect.expect_all(s => {
    s
    .expect(@printer.print_expression(expr_of("[ f aaaa bbbb, g ]"), width=12))
    .to_equal("[ f\n    aaaa\n    bbbb\n, g\n]")
    s
    .expect(
      @printer.print_expression(expr_of("[ a |> bbbb |> cccc ]"), width=12),
    )
    .to_equal("[ a\n    |> bbbb\n    |> cccc\n]")
    s
    .expect(
      @printer.print_expression(
        expr_of("( { r | aaaa = 1, bbbb = 2 }, x )"),
        width=20,
      ),
    )
    .to_equal("( { r\n    | aaaa = 1\n    , bbbb = 2\n  }\n, x\n)")
    s
    .expect(
      @printer.print_expression(
        expr_of("x |> (\\str -> if a then b else c)"),
        width=24,
      ),
    )
    .to_equal(
      (
        #|x
        #|    |> (\str ->
        #|            if a then
        #|                b
        #|
        #|            else
        #|                c
        #|       )
      ),
    )
  })
}
