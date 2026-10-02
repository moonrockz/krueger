///|
test "400 nested levels print on every target" {
  let mut e : @ast.Node[@ast.Expression] = n(FunctionOrValue([][:], "x"))
  for _ in 0..<400 {
    e = n(ParenthesizedExpression(e))
  }
  inspect(@printer.print_expression(e, width=1_000_000).length(), content="801")
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
