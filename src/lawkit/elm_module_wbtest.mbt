///|
test "is_parenthesized_if finds an if in one or more parentheses" {
  @expect.expect_all(s => {
    s.expect(is_parenthesized_if("(if x then 1 else 2)")).to_be_true()
    s.expect(is_parenthesized_if("((if x then 1 else 2))")).to_be_true()
    s.expect(is_parenthesized_if("(\n  if\r\n x then 1 else 2)")).to_be_true()
    s.expect(is_parenthesized_if("if x then 1 else 2")).to_be_false()
    s.expect(is_parenthesized_if("(iffy)")).to_be_false()
    s.expect(is_parenthesized_if("(f x)")).to_be_false()
    s.expect(is_parenthesized_if("(if")).to_be_false()
    s.expect(is_parenthesized_if("")).to_be_false()
  })
}
