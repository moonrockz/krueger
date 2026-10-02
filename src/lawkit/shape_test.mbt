///|
test "without_ranges ignores ranges and keeps everything else" {
  let source = "module A exposing (..)\n\n\nf x =\n    x + 1\n"
  let moved = "module A exposing (..)\n\n\n\n\nf x = x + 1\n"
  let other = "module A exposing (..)\n\n\nf x =\n    x + 2\n"
  let shape = text => {
    let r = @parser.parse_module(
      @scanner.SourceText::new(text),
      @scanner.DefaultScanner::new(),
    )
    @lawkit.without_ranges(r.ast.unwrap())
  }
  @expect.expect_all(s => {
    s.expect(shape(source) == shape(moved)).to_be_true()
    s.expect(shape(source) == shape(other)).to_be_false()
  })
}

///|
test "without_ranges tells Ints above 2^53 apart" {
  let shape = text => {
    let r = @parser.parse_module(
      @scanner.SourceText::new(text),
      @scanner.DefaultScanner::new(),
    )
    @lawkit.without_ranges(r.ast.unwrap())
  }
  // Both literals have the same nearest Double, 9007199254740992.
  let a = shape("module A exposing (..)\n\n\nf =\n    9007199254740992\n")
  let b = shape("module A exposing (..)\n\n\nf =\n    9007199254740993\n")
  let max = shape("module A exposing (..)\n\n\nf =\n    9223372036854775807\n")
  let below = shape(
    "module A exposing (..)\n\n\nf =\n    9223372036854775806\n",
  )
  @expect.expect_all(s => {
    s.expect(a == b).to_be_false()
    s.expect(a == a).to_be_true()
    s.expect(b == b).to_be_true()
    s.expect(max == below).to_be_false()
    s
    .expect(a.stringify().contains("\"integer\":9007199254740992"))
    .to_be_true()
    s
    .expect(b.stringify().contains("\"integer\":\"9007199254740993\""))
    .to_be_true()
  })
}
