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
test "a trailing comment after the last line of a multi-line child" {
  @expect.expect(
    placed_of(
      "module A exposing (a)\n\n\na =\n    case x of\n        1 ->\n            2 -- t\n\n        _ ->\n            3\n",
    ),
  ).to_equal(["-- t trailing 6:9"])
}

///|
test "a comment at the end of the file is inner to the file" {
  @expect.expect(placed_of("module A exposing (a)\n\n\na =\n    1\n\n-- end\n")).to_equal([
      "-- end inner -",
    ],
  )
}

///|
test "a comment before the first import leads it" {
  @expect.expect(
    placed_of("module A exposing (a)\n\n-- i\nimport B\n\n\na =\n    1\n"),
  ).to_equal(["-- i leading 4:1"])
}

///|
test "CRLF input places comments as LF input does" {
  let lf = "module A exposing (a)\n\n\na =\n    [ b -- x\n    , c\n    -- own\n    , d\n    -- end\n    ]\n"
  @expect.expect(placed_of(lf.replace_all(old="\n", new="\r\n"))).to_equal(
    placed_of(lf).map(s => s),
  )
  @expect.expect(placed_of(lf).length()).to_equal(3)
}

///|
test "two comments with the same owner and role keep source order" {
  @expect.expect(
    placed_of(
      "module A exposing (a)\n\n\na =\n    [ 1\n    -- p\n    -- q\n    ]\n",
    ),
  ).to_equal(["-- p inner -", "-- q inner -"])
}

///|
test "generated commented modules parse without errors" {
  let rs = @splitmix.new(seed=2027)
  let counts = [0, 0, 0]
  let mut crlf = 0
  for i in 0..<200 {
    let m : @lawkit.Commented = @quickcheck.Arbitrary::arbitrary(i % 24, rs)
    let text = m.text()
    let r = @parser.parse_module(
      @scanner.SourceText::new(text),
      @scanner.DefaultScanner::new(),
    )
    let errors = r.diagnostics.filter(d => d.severity is Error)
    @expect.expect(errors.length()).to_equal(0)
    if text.contains("\r\n") {
      crlf += 1
    }
    // Every comment that the generator added is a regular comment: the
    // marker appears once per added comment, and never in a string or in a
    // doc comment.
    let file = r.ast.unwrap()
    let marked = file.comments
      .iter()
      .filter(c => !c.value.has_prefix("{-|") && c.value.contains("\u{A7}"))
      .count()
    @expect.expect(marked).to_equal(text.split("\u{A7}").count() - 1)
    for p in place_comments(file).placed {
      let k = match p.role {
        Leading => 0
        Trailing => 1
        Inner => 2
      }
      counts[k] += 1
    }
  }
  @expect.expect_all(s => {
    s.expect(counts[0] > 50).to_be_true()
    s.expect(counts[1] > 50).to_be_true()
    s.expect(counts[2] > 50).to_be_true()
    s.expect(crlf > 30).to_be_true()
  })
}

///|
test "law: every comment has one owner, and its role fits the owner" {
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
      let root : @syntax.NodeRef = File(file, [][:])
      let nodes = []
      @syntax.walk(root, n => {
        nodes.push(n)
        Continue
      })
      let t = place_comments(file)
      let regular = file.comments
        .iter()
        .filter(c => !c.value.has_prefix("{-|"))
        .count()
      let role_fits = (p : Placed) => {
        let c = p.comment.range
        match (p.role, p.child) {
          (Trailing, Some(ch)) =>
            at_or_before(ch.end, c.start) && ch.end.row == c.start.row
          (Leading, Some(ch)) => at_or_before(c.end, ch.start)
          (Inner, None) =>
            nodes
            .iter()
            .any(n => {
              n.range() == p.owner &&
              n
              .children()
              .iter()
              .all(ch => {
                is_skipped(ch) || !at_or_before(c.end, ch.range().start)
              })
            })
          _ => false
        }
      }
      let owner_fits = (p : Placed) => {
        p.owner == root.range() ||
        range_contains(p.owner, p.comment.range.start)
      }
      t.placed.length() == regular &&
      t.placed.iter().all(p => owner_fits(p) && role_fits(p))
    },
    count=100,
    max_size=20,
    seed=2028,
  )
}
