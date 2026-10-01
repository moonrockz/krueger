///|
test "excerpt_lines reads gutters, negative labels included, and skips other lines" {
  let rendered = "-- TITLE ---- src/M.elm\n\nI found:\n\n 9| x =\n10|>    1\n-1| y\n   ^\nsee a | b\n"
  @expect.expect(@lawkit.excerpt_lines(rendered)).to_equal([
    (9, " x ="),
    (10, ">    1"),
    (-1, " y"),
  ])
}

///|
test "shows_source checks the numbers, the bounds and the shown text" {
  let text = "a\r\n  b\nc"
  @expect.expect_all(s => {
    s.expect(@lawkit.shows_source(text, "1| a\n2|   b\n", [1, 2])).to_be_true()
    s
    .expect(@lawkit.shows_source(text, "2|>   b\n3|  c\n", [2, 3]))
    .to_be_true()
    // A line end shown, the wrong line, a missing excerpt, past the end.
    s.expect(@lawkit.shows_source(text, "1| a\r\n", [1])).to_be_false()
    s.expect(@lawkit.shows_source(text, "1| c\n", [1])).to_be_false()
    s.expect(@lawkit.shows_source(text, "", [1])).to_be_false()
    s.expect(@lawkit.shows_source(text, "4| \n", [4])).to_be_false()
    s.expect(@lawkit.shows_source(text, "0| \n", [0])).to_be_false()
  })
}

///|
test "source_lines and line_count count the empty line after a final line break" {
  @expect.expect_all(s => {
    s.expect(@lawkit.source_lines("a\r\nb\n")).to_equal(["a", "b", ""])
    s
    .expect([
      @lawkit.line_count(""),
      @lawkit.line_count("a"),
      @lawkit.line_count("a\n"),
      @lawkit.line_count("a\r\nb"),
    ])
    .to_equal([1, 1, 2, 2])
  })
}

///|
test "strip_ansi removes style sequences only" {
  @expect.expect(
    @lawkit.strip_ansi("\u{1b}[36m-- T\u{1b}[0m 9| \u{1b}[1;4;91m^\u{1b}[0m é"),
  ).to_equal("-- T 9| ^ é")
}

///|
test "range_in_source accepts ranges on the text and rejects others" {
  let r = (sl : Int, sc : Int, el : Int, ec : Int) => {
    (
      { start: { row: sl, column: sc, }, end: { row: el, column: ec, }, } :
      @ast.Range)
  }
  let text = "ab\nc"
  @expect.expect_all(s => {
    s.expect(@lawkit.range_in_source(text, r(1, 1, 2, 2))).to_be_true()
    s.expect(@lawkit.range_in_source(text, r(1, 3, 1, 3))).to_be_true()
    // Past the line end, past the last line, backwards, column 0.
    s.expect(@lawkit.range_in_source(text, r(1, 4, 1, 4))).to_be_false()
    s.expect(@lawkit.range_in_source(text, r(3, 1, 3, 1))).to_be_false()
    s.expect(@lawkit.range_in_source(text, r(2, 1, 1, 1))).to_be_false()
    s.expect(@lawkit.range_in_source(text, r(1, 0, 1, 1))).to_be_false()
  })
}

///|
test "elm_json_problems reads regions and messages, and rejects fractional coordinates" {
  let at = (line : Double, column : Double) => {
    let j : Json = {
      "line": Json::number(line),
      "column": Json::number(column),
    }
    j
  }
  let report : Json = {
    "type": "compile-errors",
    "errors": [
      {
        "path": "src/M.elm",
        "problems": [
          {
            "title": "T",
            "region": { "start": at(1, 1), "end": at(1, 2) },
            "message": [
              "a\n1| x\n",
              {
                "bold": false,
                "underline": false,
                "color": "RED",
                "string": "^",
              },
            ],
          },
          {
            "title": "U",
            "region": { "start": at(1.9, 1), "end": at(1, 1) },
            "message": [],
          },
        ],
      },
    ],
  }
  @expect.expect_all(s => {
    s
    .expect(@lawkit.elm_json_problems(report))
    .to_equal(
      Some([
        (
          Some({ start: { row: 1, column: 1, }, end: { row: 1, column: 2, }, }),
          "a\n1| x\n^",
        ),
        (None, ""),
      ]),
    )
    s
    .expect(
      @lawkit.elm_json_problems({ "type": "compile-errors", "errors": [] }),
    )
    .to_equal(Some([]))
    s.expect(@lawkit.elm_json_problems(Json::null())).to_equal(None)
  })
}
