///|
fn at(row : Int, column : Int) -> @ast.Location {
  { row, column, }
}

///|
test "edge_positions lists range edges, line starts and ends, and the text end" {
  let ranges : Array[@ast.Range] = [{ start: at(1, 3), end: at(1, 5), }]
  @expect.expect(@lawkit.edge_positions("ab cd\nxé😀\n", ranges)).to_equal([
    at(1, 1),
    at(1, 2),
    at(1, 3),
    at(1, 4),
    at(1, 5),
    at(1, 6),
    at(1, 7),
    at(2, 1),
    at(2, 4),
    at(2, 5),
    at(3, 1),
    at(3, 2),
    at(4, 1),
  ])
}

///|
test "the end of a text counts code points, CRLF and lone carriage returns" {
  @expect.expect_all(s => {
    s.expect(@lawkit.end_of_text("")).to_equal(at(1, 1))
    s.expect(@lawkit.end_of_text("é😀")).to_equal(at(1, 3))
    s.expect(@lawkit.end_of_text("ab\r")).to_equal(at(1, 4))
    s.expect(@lawkit.end_of_text("ab\r\r\n")).to_equal(at(2, 1))
    s.expect(@lawkit.end_of_text("ab\r\n")).to_equal(at(2, 1))
  })
}

///|
test "edge_positions drops only the carriage return of a CRLF" {
  @expect.expect_all(s => {
    s
    .expect(@lawkit.edge_positions("ab\r\r\n", []).contains(at(1, 4)))
    .to_be_true()
    s.expect(@lawkit.edge_positions("ab\r", []).contains(at(1, 4))).to_be_true()
    s
    .expect(@lawkit.edge_positions("", []))
    .to_equal([at(1, 1), at(1, 2), at(2, 1)])
  })
}

///|
test "offset_of counts code points and line breaks" {
  @expect.expect_all(s => {
    s.expect(@lawkit.offset_of("xé😀\r\nb", at(1, 4))).to_equal(Some(4))
    s.expect(@lawkit.offset_of("xé😀\r\nb", at(1, 5))).to_equal(None)
    s.expect(@lawkit.offset_of("xé😀\r\nb", at(2, 1))).to_equal(Some(6))
    s.expect(@lawkit.offset_of("xé😀\r\nb", at(2, 2))).to_equal(Some(7))
    s.expect(@lawkit.offset_of("a\rb", at(1, 3))).to_equal(Some(2))
    s.expect(@lawkit.offset_of("", at(1, 1))).to_equal(Some(0))
  })
}

///|
test "law: edge_positions are sorted, unique and include every range edge" {
  // Edges: equal, adjacent, empty and two-row ranges (the Ranges generator).
  @quickcheck.check(
    (input : @lawkit.Ranges) => {
      let ranges = input.ranges()
      let ps = @lawkit.edge_positions("abc\nde\n", ranges)
      let sorted = ps
        .iter()
        .zip(ps[1:].iter())
        .all(pair => @lawkit.at_or_before(pair.0, pair.1) && pair.0 != pair.1)
      sorted &&
      ranges
      .iter()
      .all(r => {
        ps.contains(r.start) &&
        ps.contains(r.end) &&
        (r.end.column == 1 || ps.contains(at(r.end.row, r.end.column - 1)))
      })
    },
    count=100,
    max_size=12,
    seed=211,
  )
}

///|
test "law: every line's end is on the text and one column past it is not" {
  // Edges: CRLF, surrogate pairs, no final newline, an empty last line.
  @quickcheck.check(
    (m : @lawkit.ElmModule) => {
      let text = m.text()
      let rows = @lawkit.end_of_text(text).row
      let ps = @lawkit.edge_positions(text, [])
      let on = (p : @ast.Location) => @lawkit.offset_of(text, p) is Some(_)
      (1)
      .until(rows, inclusive=true)
      .all(row => {
        ps.iter().any(p => p.row == row && on(p) && !on(at(row, p.column + 1)))
      }) &&
      @lawkit.offset_of(text, @lawkit.end_of_text(text)) == Some(text.length())
    },
    count=100,
    max_size=24,
    seed=251,
  )
}

///|
test "law: generated ranges never run backwards and stay on the grid" {
  // Edges: copies (equal ranges), adjacent ranges, empty ranges, two rows.
  @quickcheck.check(
    (input : @lawkit.Ranges) => {
      input
      .ranges()
      .iter()
      .all(r => {
        @lawkit.at_or_before(r.start, r.end) &&
        r.start.row >= 1 &&
        r.end.row <= 3 &&
        r.start.column >= 1
      })
    },
    count=100,
    max_size=12,
    seed=223,
  )
}

///|
/// A string made of these UTF-16 code units (string literals cannot hold a
/// lone surrogate).
fn units(xs : Array[Int]) -> String {
  let sb = StringBuilder()
  for x in xs {
    sb.write_char(Int::unsafe_to_char(x))
  }
  sb.to_string()
}

///|
test "lone surrogates count as the scanner counts them" {
  // The scanner adds a column for every UTF-16 unit except a low surrogate,
  // so a lone high surrogate is one column and a lone low surrogate none.
  let high = units(['a'.to_int(), 0xD800, '\n'.to_int(), 'b'.to_int()])
  let alone = units(['a'.to_int(), 0xD800])
  let low = units(['a'.to_int(), 0xDC00, 'b'.to_int()])
  @expect.expect_all(s => {
    s.expect(@lawkit.end_of_text(high)).to_equal(at(2, 2))
    s.expect(@lawkit.offset_of(high, at(2, 1))).to_equal(Some(3))
    s.expect(@lawkit.end_of_text(alone)).to_equal(at(1, 3))
    s
    .expect(@lawkit.offset_of(alone, @lawkit.end_of_text(alone)))
    .to_equal(Some(2))
    s.expect(@lawkit.end_of_text(low)).to_equal(at(1, 3))
    s.expect(@lawkit.offset_of(low, at(1, 2))).to_equal(Some(2))
  })
}
