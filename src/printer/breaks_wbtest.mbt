///|
fn facts_of(text : String) -> SourceFacts {
  let r = @parser.parse_module(
    @scanner.SourceText::new(text),
    @scanner.DefaultScanner::new(),
  )
  SourceFacts::from_tokens(r.cst.unwrap().tokens)
}

///|
fn loc(row : Int, column : Int) -> @ast.Location {
  { row, column, }
}

///|
test "break_before sees a line break in the gap before a token" {
  let f = facts_of("module A exposing (a)\n\n\na = f x\n    y\n")
  @expect.expect_all(s => {
    s.expect(f.break_before(loc(4, 7))).to_equal(false) // x
    s.expect(f.break_before(loc(5, 5))).to_equal(true) // y
    s
    .expect(f.break_before(loc(4, 1)))
    .to_equal(true) // a
  })
}

///|
test "a line comment makes a break, a block comment on one line does not" {
  let f = facts_of("module A exposing (a)\n\n\na = x {- c -} + y -- d\n")
  @expect.expect_all(s => {
    s.expect(f.break_before(loc(4, 15))).to_equal(false) // +
    s
    .expect(f.break_within({ start: loc(4, 5), end: loc(4, 18), }))
    .to_equal(false)
  })
}

///|
test "break_within looks only at gaps inside the range" {
  let f = facts_of("module A exposing (a)\n\n\na =\n    [ 1, 2\n    , 3 ]\n")
  @expect.expect_all(s => {
    s
    .expect(f.break_within({ start: loc(5, 5), end: loc(6, 10), }))
    .to_equal(true)
    s
    .expect(f.break_within({ start: loc(5, 5), end: loc(5, 11), }))
    .to_equal(false)
  })
}

///|
test "no token at a location gives no lexeme" {
  let f = facts_of("module A exposing (a)\n\n\na = 0xff\n")
  @expect.expect_all(s => {
    s.expect(f.lexeme_at(loc(4, 5))).to_equal(Some("0xff"))
    s.expect(f.lexeme_at(loc(4, 6))).to_equal(None)
  })
}

///|
test "law: break_within agrees with a scan of the source text" {
  @quickcheck.check(
    (m : @lawkit.ElmModule) => {
      let text = m.text()
      let r = @parser.parse_module(
        @scanner.SourceText::new(text),
        @scanner.DefaultScanner::new(),
      )
      guard r.diagnostics.iter().all(d => !(d.severity is Error)) else {
        return false
      }
      let tokens = r.cst.unwrap().tokens
      let f = SourceFacts::from_tokens(tokens)
      // Edges: every pair of token starts up to 6 tokens apart, including
      // the same token (empty range) and adjacent tokens (no gap inside).
      let mut ok = true
      for i in 0..<tokens.length() {
        for j = i; j < tokens.length() && j < i + 6; j = j + 1 {
          // Gaps inside [start of token i, start of token j) are the gaps
          // before tokens i+1 ..< j.
          let mut expected = false
          for k in (i + 1)..<j {
            let gap = text.view(
              start_offset=tokens[k - 1].span.end.offset,
              end_offset=tokens[k].span.start.offset,
            )
            expected = expected || gap.contains("\n") || gap.contains("--")
          }
          ok = ok &&
            f.break_within({ start: f.starts[i], end: f.starts[j], }) ==
            expected
        }
      }
      ok
    },
    count=60,
    max_size=16,
    seed=2027,
  )
}
