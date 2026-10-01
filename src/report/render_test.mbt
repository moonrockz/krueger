///|
fn sp(l1 : Int, c1 : Int, l2 : Int, c2 : Int) -> @scanner.Span {
  {
    start: { offset: 0, line: l1, column: c1, },
    end: { offset: 0, line: l2, column: c2, },
  }
}

///|
fn let_source() -> @scanner.SourceText {
  {
    module_name: Some("Main"),
    text: "module Main exposing (..)\n\n\nf =\n    let\n        y = 1\nin\n    y\n",
  }
}

///|
fn let_diagnostic() -> @scanner.Diagnostic {
  {
    code: "KR-PARSE-004",
    severity: Error,
    message: "expected `in`",
    span: sp(6, 14, 6, 14),
    title: "UNFINISHED LET",
    report: [
      Text([
        Plain(
          "I was partway through parsing a `let` expression, but I got stuck here:",
        ),
      ]),
      Excerpt(context=sp(5, 1, 6, 14), highlight=sp(6, 14, 6, 14)),
      Text([
        Plain("I was expecting to see the "),
        @scanner.Chunk::keyword("in"),
        Plain(" keyword next."),
      ]),
    ],
  }
}

///|
test "plain rendering has an Elm header, an excerpt and a caret" {
  let expected = "-- UNFINISHED LET " +
    "-".repeat(49) +
    " src/Main.elm\n\n" +
    "I was partway through parsing a `let` expression, but I got stuck here:\n\n" +
    "5|     let\n" +
    "6|         y = 1\n" +
    " ".repeat(16) +
    "^\n" +
    "I was expecting to see the in keyword next.\n"
  @expect.expect(
    @report.render_plain(let_diagnostic(), let_source(), "src/Main.elm"),
  ).to_equal(expected)
}

///|
test "a caret at the end of the input or on an empty line is one ^" {
  let d = {
    ..let_diagnostic(),
    report: [Excerpt(context=sp(9, 1, 9, 1), highlight=sp(9, 1, 9, 1))],
  }
  @expect.expect(@report.render_plain(d, let_source(), "x.elm")).to_contain(
    "9| \n   ^",
  )
}

///|
test "columns count code points" {
  let s : @scanner.SourceText = {
    module_name: None,
    text: "a = \"\u{1F308}\" +\n",
  }
  let d = {
    ..let_diagnostic(),
    report: [Excerpt(context=sp(1, 1, 1, 9), highlight=sp(1, 9, 1, 9))],
  }
  @expect.expect(@report.render_plain(d, s, "x.elm")).to_contain(
    "1| a = \"\u{1F308}\" +\n" + " ".repeat(11) + "^",
  )
}

///|
test "a wide gutter right-aligns line numbers" {
  let lines = Array::make(12, "x")
  let s : @scanner.SourceText = { module_name: None, text: lines.join("\n"), }
  let d = {
    ..let_diagnostic(),
    report: [Excerpt(context=sp(9, 1, 10, 2), highlight=sp(10, 2, 10, 2))],
  }
  @expect.expect(@report.render_plain(d, s, "x.elm")).to_contain(
    " 9| x\n10| x\n" + " ".repeat(5) + "^",
  )
}

///|
test "a multi-line highlight marks the gutter" {
  let d = {
    ..let_diagnostic(),
    report: [Excerpt(context=sp(4, 1, 6, 14), highlight=sp(5, 5, 6, 14))],
  }
  @expect.expect(@report.render_plain(d, let_source(), "x.elm")).to_contain(
    "4|  f =\n5|>     let\n6|>         y = 1\n",
  )
}

///|
test "reflow keeps styled chunks whole and lines within 80 columns" {
  @expect.expect_all(s => {
    let long = "word ".repeat(15)
    let d = {
      ..let_diagnostic(),
      report: [
        Text([Plain(long), @scanner.Chunk::code("List.map"), Plain(". end")]),
      ],
    }
    let text = @report.render_plain(d, let_source(), "x.elm")
    s.expect(text).to_contain("List.map. end")
    s
    .expect(text.split("\n").all(l => l.to_owned().length() <= 80))
    .to_equal(true)
  })
}

///|
test "hints, notes and examples" {
  let d = {
    ..let_diagnostic(),
    report: [
      Hint([Plain("Try this.")]),
      Note([Plain("Here is an example:")]),
      Example("f =\n  1"),
    ],
  }
  @expect.expect(@report.render_plain(d, let_source(), "x.elm")).to_contain(
    "Hint: Try this.\n\nNote: Here is an example:\n\n    f =\n      1\n",
  )
}

///|
test "terminal rendering colors the caret and keywords" {
  @expect.expect_all(s => {
    let text = @report.render_terminal(
      let_diagnostic(),
      let_source(),
      "src/Main.elm",
    )
    s.expect(text).to_contain("\u{1b}[91m^\u{1b}[0m")
    s.expect(text).to_contain("\u{1b}[96min\u{1b}[0m")
  })
}

///|
test "elm json has the elm make shape" {
  @expect.expect_all(s => {
    let json = @report.render_elm_json(
      [let_diagnostic()],
      let_source(),
      "src/Main.elm",
    )
    guard json is Object(o) &&
      o.get("type") is Some(String("compile-errors")) &&
      o.get("errors") is Some(Array([Object(e)])) &&
      e.get("name") is Some(String("Main")) &&
      e.get("problems") is Some(Array([Object(p)])) else {
      fail("bad shape: \{json.stringify()}")
    }
    s.expect(p.get("title")).to_equal(Some("UNFINISHED LET".to_json()))
    s
    .expect(p.get("region"))
    .to_equal(
      Some({
        "start": { "line": 6, "column": 14 },
        "end": { "line": 6, "column": 14 },
      }),
    )
    guard p.get("message") is Some(Array(parts)) else { fail("no message") }
    s
    .expect(parts)
    .to_contain_element({
      "bold": false,
      "underline": false,
      "color": "RED",
      "string": "^",
    })
    s
    .expect(parts[0])
    .to_equal(
      ("I was partway through parsing a `let` expression, but I got stuck here:\n\n5|     let\n6|         y = 1\n" +
      " ".repeat(16)).to_json(),
    )
  })
}

///|
test "warnings are left out of the elm json" {
  let warning = { ..let_diagnostic(), severity: Warning, }
  guard @report.render_elm_json([warning], let_source(), "x.elm") is Object(o) &&
    o.get("errors") is Some(Array(errors)) else {
    fail("bad shape")
  }
  @expect.expect(errors.length()).to_equal(0)
}

///|
test "encode_diagnostics keeps codes, severities and titles" {
  @expect.expect_all(s => {
    let json = @report.encode_diagnostics([let_diagnostic()])
    s.expect(json.stringify()).to_contain("\"title\":\"UNFINISHED LET\"")
    s.expect(json.stringify()).to_contain("\"severity\":\"error\"")
  })
}

///|
test "blank lines in examples have no trailing spaces" {
  let d = { ..let_diagnostic(), report: [Example("a\n\nb")], }
  @expect.expect(@report.render_plain(d, let_source(), "x.elm")).to_contain(
    "    a\n\n    b\n",
  )
}

///|
test "the elm json region is where the excerpt marks the problem" {
  let d = { ..let_diagnostic(), span: sp(7, 1, 7, 3), }
  guard @report.render_elm_json([d], let_source(), "x.elm") is Object(o) &&
    o.get("errors") is Some(Array([Object(e)])) &&
    e.get("problems") is Some(Array([Object(p)])) else {
    fail("bad shape")
  }
  @expect.expect(p.get("region")).to_equal(
    Some({
      "start": { "line": 6, "column": 14 },
      "end": { "line": 6, "column": 14 },
    }),
  )
}
