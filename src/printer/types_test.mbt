///|
test "type applications and arrows get the parentheses they need" {
  @expect.expect_all(s => {
    let a = tvar("a")
    let b = tvar("b")
    s
    .expect(
      @printer.print_type_annotation(typed("List", [typed("Maybe", [a])])),
    )
    .to_equal("List (Maybe a)")
    s
    .expect(@printer.print_type_annotation(arrow(arrow(a, b), tvar("c"))))
    .to_equal("(a -> b) -> c")
    s
    .expect(@printer.print_type_annotation(arrow(a, arrow(b, tvar("c")))))
    .to_equal("a -> b -> c")
    s
    .expect(@printer.print_type_annotation(typed("List", [arrow(a, b)])))
    .to_equal("List (a -> b)")
    s
    .expect(@printer.print_type_annotation(arrow(typed("Maybe", [a]), b)))
    .to_equal("Maybe a -> b")
  })
}

///|
test "tuples, unit and records" {
  @expect.expect_all(s => {
    let int = typed("Int", [])
    s.expect(@printer.print_type_annotation(n(Unit))).to_equal("()")
    s
    .expect(@printer.print_type_annotation(n(Tupled([int, tvar("a")][:]))))
    .to_equal("( Int, a )")
    let fields : Array[@ast.Node[@ast.RecordField]] = [
      n({ name: n("a"), type_annotation: int, }),
      n({ name: n("b"), type_annotation: tvar("b"), }),
    ]
    s
    .expect(@printer.print_type_annotation(n(Record(fields[:]))))
    .to_equal("{ a : Int, b : b }")
    s.expect(@printer.print_type_annotation(n(Record([][:])))).to_equal("{}")
    s
    .expect(
      @printer.print_type_annotation(n(GenericRecord(n("r"), n(fields[:])))),
    )
    .to_equal("{ r | a : Int, b : b }")
    s.expect(@printer.print_type_annotation(typed("Dict", []))).to_equal("Dict")
  })
}

///|
test "long types break in the elm-format shape" {
  @expect.expect_all(s => {
    let long = typed("SomeLongTypeName", [])
    s
    .expect(
      @printer.print_type_annotation(arrow(long, arrow(long, long)), width=30),
    )
    .to_equal("SomeLongTypeName\n-> SomeLongTypeName\n-> SomeLongTypeName")
    let fields : Array[@ast.Node[@ast.RecordField]] = [
      n({ name: n("first"), type_annotation: long, }),
      n({ name: n("second"), type_annotation: long, }),
    ]
    s
    .expect(@printer.print_type_annotation(n(Record(fields[:])), width=30))
    .to_equal("{ first : SomeLongTypeName\n, second : SomeLongTypeName\n}")
    s
    .expect(
      @printer.print_type_annotation(
        n(GenericRecord(n("r"), n(fields[:]))),
        width=40,
      ),
    )
    .to_equal(
      "{ r\n    | first : SomeLongTypeName\n    , second : SomeLongTypeName\n}",
    )
  })
}

///|
test "bad types raise with the path of the bad node" {
  @expect.expect_all(s => {
    s
    .expect(
      problem_of(() => {
        @printer.print_type_annotation(typed("List", [tvar("Bad")]))
      }),
    )
    .to_equal(Some((InvalidName(Lower, "Bad"), [{ field: "args", index: 0, }])))
    s
    .expect(
      problem_of(() => @printer.print_type_annotation(n(Tupled([tvar("a")][:])))),
    )
    .to_equal(Some((ShortTuple, [])))
    s
    .expect(
      problem_of(() => {
        @printer.print_type_annotation(n(GenericRecord(n("r"), n([][:]))))
      }),
    )
    .to_equal(Some((NoFields, [])))
    s
    .expect(
      problem_of(() => {
        @printer.print_type_annotation(n(Typed(n((["bad"][:], "T")), [][:])))
      }),
    )
    .to_equal(Some((InvalidName(Upper, "bad"), [])))
  })
}
