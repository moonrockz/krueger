///|
fn parse_fuel(text : String) -> @parser.ParseResult {
  @parser.parse_module(
    @scanner.SourceText::new(text),
    @scanner.DefaultScanner::new(),
  )
}

///|
test "each nesting refusal has code KR-PARSE-010, its title and its walk" {
  let cases : Array[(@lawkit.Construct, Int32, @scanner.Walk)] = [
    (Parens, 150, Nesting),
    (CtorPattern, 75, Nesting),
    (TypeApp, 75, Nesting),
    (Cons, 399, Chain),
    (Arrow, 399, Chain),
  ]
  @expect.expect_all(s => {
    for c in cases {
      let (construct, depth, walk) = c
      let errs = parse_fuel(@lawkit.nested(construct, depth)).diagnostics.filter(d => {
          d.severity is Error
        },
      )
      s
      .expect((construct, errs.map(d => d.code)))
      .to_equal((construct, ["KR-PARSE-010"]))
      s
      .expect((construct, errs.map(d => d.title)))
      .to_equal((construct, ["TOO MUCH NESTING"]))
      s
      .expect((construct, errs.map(d => d.detail)))
      .to_equal((construct, [Some(OutOfFuel(fuel=1200, walk~))]))
    }
  })
}

///|
test "the report of a nesting refusal names the fuel" {
  let errs = parse_fuel(@lawkit.nested(Parens, 150)).diagnostics
  let names_fuel = errs[0].report
    .iter()
    .any(b => {
      b is Text(chunks) &&
      chunks.iter().any(c => c is Plain(s) && s.contains("fuel"))
    })
  @expect.expect(names_fuel).to_be_true()
}

///|
test "a malformed declaration keeps its code and has no detail" {
  let errs = parse_fuel("module M exposing (..)\n\n\nf =\n    (1\n").diagnostics
  @expect.expect(errs.map(d => (d.code, d.detail))).to_equal([
    ("KR-PARSE-004", None),
  ])
}
