///|
test "patterns print with the parentheses elm-syntax needs" {
  @expect.expect_all(s => {
    let x = pvar("x")
    let xs = pvar("xs")
    s
    .expect(@printer.print_pattern(n(UnConsPattern(ctor("Just", [x]), xs))))
    .to_equal("Just x :: xs")
    s
    .expect(
      @printer.print_pattern(
        n(UnConsPattern(n(UnConsPattern(x, pvar("y"))), xs)),
      ),
    )
    .to_equal("(x :: y) :: xs")
    s
    .expect(
      @printer.print_pattern(
        n(UnConsPattern(x, n(UnConsPattern(pvar("y"), xs)))),
      ),
    )
    .to_equal("x :: y :: xs")
    s
    .expect(
      @printer.print_pattern(n(UnConsPattern(x, n(AsPattern(xs, n("all")))))),
    )
    .to_equal("x :: xs as all")
    s
    .expect(
      @printer.print_pattern(n(AsPattern(n(UnConsPattern(x, xs)), n("all")))),
    )
    .to_equal("(x :: xs) as all")
    s
    .expect(@printer.print_pattern(ctor("Just", [ctor("Just", [x])])))
    .to_equal("Just (Just x)")
    s
    .expect(@printer.print_pattern(ctor("Just", [n(AsPattern(x, n("y")))])))
    .to_equal("Just (x as y)")
    s.expect(@printer.print_pattern(n(ParenthesizedPattern(x)))).to_equal("(x)")
  })
}

///|
test "literal, collection and wildcard patterns" {
  @expect.expect_all(s => {
    s.expect(@printer.print_pattern(n(AllPattern))).to_equal("_")
    s.expect(@printer.print_pattern(n(UnitPattern))).to_equal("()")
    s.expect(@printer.print_pattern(n(CharPattern('\'')))).to_equal("'\\''")
    s
    .expect(@printer.print_pattern(n(StringPattern("a\"b"))))
    .to_equal("\"a\\\"b\"")
    s.expect(@printer.print_pattern(n(IntPattern(42L)))).to_equal("42")
    s.expect(@printer.print_pattern(n(HexPattern(255L)))).to_equal("0xFF")
    s.expect(@printer.print_pattern(n(FloatPattern(1.5)))).to_equal("1.5")
    s
    .expect(
      @printer.print_pattern(n(TuplePattern([pvar("a"), n(AllPattern)][:]))),
    )
    .to_equal("( a, _ )")
    s
    .expect(@printer.print_pattern(n(RecordPattern([n("a"), n("b")][:]))))
    .to_equal("{ a, b }")
    s.expect(@printer.print_pattern(n(ListPattern([][:])))).to_equal("[]")
    s
    .expect(@printer.print_pattern(n(ListPattern([pvar("a")][:]))))
    .to_equal("[ a ]")
    s
    .expect(
      @printer.print_pattern(
        n(
          NamedPattern(
            { module_name: ["Maybe"][:], name: "Just", },
            [pvar("v")][:],
          ),
        ),
      ),
    )
    .to_equal("Maybe.Just v")
  })
}

///|
test "patterns that Elm cannot write raise" {
  @expect.expect_all(s => {
    s
    .expect(problem_of(() => @printer.print_pattern(n(IntPattern(-1L)))))
    .to_equal(Some((NegativePattern, [])))
    s
    .expect(problem_of(() => @printer.print_pattern(n(FloatPattern(-0.0)))))
    .to_equal(Some((NegativePattern, [])))
    s
    .expect(problem_of(() => @printer.print_pattern(n(HexPattern(-16L)))))
    .to_equal(Some((NegativePattern, [])))
    s
    .expect(
      problem_of(() => @printer.print_pattern(n(FloatPattern(1.0 / 0.0)))),
    )
    .to_equal(Some((NonFiniteFloat(1.0 / 0.0), [])))
    s
    .expect(
      problem_of(() => {
        @printer.print_pattern(n(TuplePattern([pvar("type"), pvar("b")][:])))
      }),
    )
    .to_equal(
      Some((InvalidName(Lower, "type"), [{ field: "value", index: 0, }])),
    )
    s
    .expect(
      problem_of(() => {
        @printer.print_pattern(n(RecordPattern([n("ok"), n("X")][:])))
      }),
    )
    .to_equal(Some((InvalidName(Lower, "X"), [{ field: "value", index: 1, }])))
  })
}
