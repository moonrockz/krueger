///|
test "chunk helpers style code and keywords as elm make does" {
  @expect.expect_all(s => {
    s
    .expect(Chunk::code("42"))
    .to_equal(
      Styled(text="42", color=Some(Yellow), bold=false, underline=false),
    )
    s
    .expect(Chunk::keyword("in"))
    .to_equal(
      Styled(text="in", color=Some(VividCyan), bold=false, underline=false),
    )
    s.expect(Color::json_name(VividRed)).to_equal("RED")
    s.expect(Color::json_name(Yellow)).to_equal("yellow")
  })
}

///|
test "scanner diagnostics carry a title" {
  let span : Span = {
    start: { offset: 0, line: 1, column: 1, },
    end: { offset: 1, line: 1, column: 2, },
  }
  @expect.expect(unterminated_block_comment(span).title).to_equal(
    "ENDLESS COMMENT",
  )
}
