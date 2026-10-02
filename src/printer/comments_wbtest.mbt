///|
fn placed_of(text : String) -> Array[String] {
  let r = @parser.parse_module(
    @scanner.SourceText::new(text),
    @scanner.DefaultScanner::new(),
  )
  let t = place_comments(r.ast.unwrap())
  t.placed.map(p => {
    let role = match p.role {
      Leading => "leading"
      Trailing => "trailing"
      Inner => "inner"
    }
    let child = match p.child {
      Some(c) => "\{c.start.row}:\{c.start.column}"
      None => "-"
    }
    "\{p.comment.value} \{role} \{child}"
  })
}

///|
test "a comment at the end of a line trails the item before it" {
  @expect.expect(
    placed_of("module A exposing (a)\n\n\na =\n    [ b -- x\n    , c\n    ]\n"),
  ).to_equal(["-- x trailing 5:7"])
}

///|
test "a comment on its own line leads the next item" {
  @expect.expect(
    placed_of("module A exposing (a)\n\n\na =\n    -- lead\n    1\n"),
  ).to_equal(["-- lead leading 6:5"])
}

///|
test "a comment before a closing bracket is inner" {
  @expect.expect(
    placed_of("module A exposing (a)\n\n\na =\n    [ b\n    -- end\n    ]\n"),
  ).to_equal(["-- end inner -"])
}

///|
test "a comment between top-level declarations leads the next one" {
  @expect.expect(
    placed_of(
      "module A exposing (a)\n\n\na =\n    1\n\n\n\n-- b\n\n\nb =\n    2\n",
    ),
  ).to_equal(["-- b leading 12:1"])
}

///|
test "doc comments are not placed" {
  @expect.expect(
    placed_of("module A exposing (a)\n\n{-| d -}\n\n\na =\n    1\n"),
  ).to_equal([])
}

///|
test "the table finds comments by role and range, once" {
  let r = @parser.parse_module(
    @scanner.SourceText::new(
      "module A exposing (a)\n\n\na =\n    -- one\n    -- two\n    1\n",
    ),
    @scanner.DefaultScanner::new(),
  )
  let t = place_comments(r.ast.unwrap())
  let child = t.placed[0].child.unwrap()
  @expect.expect(t.matching(Leading, child)).to_equal([0, 1])
  @expect.expect(t.matching(Trailing, child)).to_equal([])
  t.printed[0] = true
  @expect.expect(t.matching(Leading, child)).to_equal([1])
}

///|
test "generated commented modules parse without errors" {
  let rs = @splitmix.new(seed=2027)
  let mut with_comments = 0
  for i in 0..<200 {
    let m : @lawkit.Commented = @quickcheck.Arbitrary::arbitrary(i % 24, rs)
    let r = @parser.parse_module(
      @scanner.SourceText::new(m.text()),
      @scanner.DefaultScanner::new(),
    )
    let errors = r.diagnostics.filter(d => d.severity is Error)
    @expect.expect(errors.length()).to_equal(0)
    if r.ast.unwrap().comments.length() > 0 {
      with_comments += 1
    }
  }
  @expect.expect(with_comments > 100).to_be_true()
}

///|
test "law: every comment has one owner, and the owner contains it" {
  @quickcheck.check(
    (m : @lawkit.Commented) => {
      let r = @parser.parse_module(
        @scanner.SourceText::new(m.text()),
        @scanner.DefaultScanner::new(),
      )
      guard r.diagnostics.iter().all(d => !(d.severity is Error)) else {
        return false
      }
      let file = r.ast.unwrap()
      let t = place_comments(file)
      let regular = file.comments
        .iter()
        .filter(c => !c.value.has_prefix("{-|"))
        .count()
      t.placed.length() == regular &&
      t.placed
      .iter()
      .all(p => {
        let file_range = p.owner.start.row == 1 && p.owner.start.column == 1
        file_range || range_contains(p.owner, p.comment.range.start)
      })
    },
    count=100,
    max_size=20,
    seed=2028,
  )
}
