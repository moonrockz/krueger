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
