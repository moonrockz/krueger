///|
fn render_flat(d : @pretty.Doc) -> String {
  @pretty.render(d, width=@int.MAX_VALUE)
}

///|
test "sequence: Join stays on one line, Split puts one item per line" {
  let items = [@pretty.text("1"), @pretty.text("2")]
  @expect.expect_all(s => {
    s.expect(render_flat(sequence(Join, "[", "]", items))).to_equal("[ 1, 2 ]")
    s
    .expect(render_flat(sequence(Split, "[", "]", items)))
    .to_equal("[ 1\n, 2\n]")
  })
}

///|
test "sequence: Join breaks when an item has a forced break" {
  let items = [@pretty.text("a") + @pretty.hardline() + @pretty.text("b")]
  @expect.expect(render_flat(sequence(Join, "[", "]", items))).to_equal(
    "[ a\n  b\n]",
  )
}

///|
test "spaced: Split puts each item on its own line at the next tab stop" {
  let items = [@pretty.text("x"), @pretty.text("y")]
  @expect.expect_all(s => {
    s
    .expect(render_flat(spaced(Join, @pretty.text("f"), items)))
    .to_equal("f x y")
    s
    .expect(render_flat(spaced(Split, @pretty.text("f"), items)))
    .to_equal("f\n    x\n    y")
  })
}

///|
test "split_if gives Fit for Width and Join without source" {
  let width = Ctx::new(@dialect.Dialect::elm_0_19_1(), layout=Width(80))
  let bare = Ctx::new(@dialect.Dialect::elm_0_19_1(), layout=ElmFormat)
  @expect.expect_all(s => {
    s.expect(width.split_if(() => true) is Fit).to_be_true()
    s.expect(bare.split_if(() => true) is Join).to_be_true()
  })
}
