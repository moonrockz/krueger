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
  let x = f.break_before(loc(4, 7))
  let y = f.break_before(loc(5, 5))
  let a = f.break_before(loc(4, 1))
  @expect.expect_all(s => {
    s.expect(x).to_equal(false) // token x
    s.expect(y).to_equal(true) // token y
    s
    .expect(a)
    .to_equal(true) // token a
  })
}

///|
test "a block comment on one line makes no break" {
  let f = facts_of("module A exposing (a)\n\n\na = x {- c -} + y -- d\n")
  let plus = f.break_before(loc(4, 15))
  let inner = f.break_within({ start: loc(4, 5), end: loc(4, 18), })
  @expect.expect_all(s => {
    s.expect(plus).to_equal(false) // token +
    s
    .expect(inner)
    .to_equal(false) // x to y
  })
}

///|
test "a line comment makes a break" {
  // The scanner puts the line end into the trivia after a line comment, so
  // the Newline branch also fires here; a gap with only a line comment and no
  // Newline cannot occur (a line comment at the end of the file has no token
  // after it).
  let f = facts_of("module A exposing (a)\n\n\na = x -- c\n    + y\n")
  let plus = f.break_before(loc(5, 5))
  let inner = f.break_within({ start: loc(4, 5), end: loc(5, 8), })
  @expect.expect_all(s => {
    s.expect(plus).to_equal(true) // token +
    s
    .expect(inner)
    .to_equal(true) // x to the end of y
  })
}

///|
test "break_before at the first token" {
  let plain = facts_of("module A exposing (a)\n")
  let blank = facts_of("\n\nmodule A exposing (a)\n")
  let comment = facts_of("-- c\nmodule A exposing (a)\n")
  let block = facts_of("{- c -}module A exposing (a)\n")
  @expect.expect_all(s => {
    s.expect(plain.break_before(loc(1, 1))).to_equal(false)
    s.expect(blank.break_before(loc(3, 1))).to_equal(true)
    s.expect(comment.break_before(loc(2, 1))).to_equal(true)
    s.expect(block.break_before(loc(1, 8))).to_equal(false)
  })
}

///|
test "queries at and after the end of the file" {
  let f = facts_of("module A exposing (a)\n\n\na = x\n")
  let past = f.break_before(loc(9, 1))
  let to_end = f.break_within({ start: loc(4, 1), end: loc(9, 1), })
  let after_last = f.break_within({ start: loc(9, 1), end: loc(9, 5), })
  @expect.expect_all(s => {
    s.expect(past).to_equal(false)
    s.expect(to_end).to_equal(false) // no break between a, = and x
    s.expect(after_last).to_equal(false)
  })
}

///|
test "break_before at a location that is not a token start uses the next token" {
  let f = facts_of("module A exposing (a)\n\n\na = f x\n    y\n")
  let inside_x = f.break_before(loc(4, 8)) // next token is y, on a new line
  let inside_f = f.break_before(loc(4, 6)) // next token is x, same line
  @expect.expect_all(s => {
    s.expect(inside_x).to_equal(true)
    s.expect(inside_f).to_equal(false)
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
