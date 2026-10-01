///|
fn first_in(text : String, dialect : @dialect.Dialect) -> String {
  let source = @scanner.SourceText::{ module_name: Some("Fixture"), text, }
  guard @scanner.DefaultScanner::new(dialect~).tokenize(source) is Ok(tokens) else {
    return "scan error"
  }
  match parse_tokens(tokens, dialect~).diagnostics.get(0) {
    Some(d) => d.title
    None => "no error"
  }
}

///|
fn layout_title(body : String) -> String {
  first_in(
    "module Fixture exposing (..)\n\n\nx =\n    1\n\n\n" + body,
    @dialect.Dialect::elm_0_19_1(),
  )
}

///|
test "continuation lines must be indented" {
  @expect.expect_all(s => {
    s
    .expect(layout_title("f =\n    let\n        y = 1\nin\n    y\n"))
    .to_equal("UNFINISHED LET")
    s
    .expect(layout_title("f =\n    if True\nthen 1 else 2\n"))
    .to_equal("UNFINISHED IF")
    s
    .expect(layout_title("f =\n    if True then 1\nelse 2\n"))
    .to_equal("WEIRD ELSE BRANCH")
    s.expect(layout_title("f =\n    [ 1\n, 2 ]\n")).to_equal("UNFINISHED LIST")
    s
    .expect(layout_title("f =\n    (1\n)\n"))
    .to_equal("UNFINISHED PARENTHESES")
    s
    .expect(layout_title("type alias A =\nInt\n"))
    .to_equal("UNFINISHED TYPE ALIAS")
    s
    .expect(
      layout_title(
        "f =\n    case x of\n        1 ->\n        2\n\n        _ ->\n            3\n",
      ),
    )
    .to_equal("UNFINISHED CASE")
  })
}

///|
test "let declarations must be right of let" {
  @expect.expect_all(s => {
    s
    .expect(layout_title("f =\n    let\n    y = 1\n    in\n    y\n"))
    .to_equal("UNFINISHED LET")
    s
    .expect(layout_title("f =\n    let\n  y = 1\n    in\n    y\n"))
    .to_equal("UNFINISHED LET")
  })
}

///|
test "module header and imports start in column 1" {
  @expect.expect_all(s => {
    let d = @dialect.Dialect::elm_0_19_1()
    s
    .expect(first_in(" module Fixture exposing (..)\n\n\nx =\n    1\n", d))
    .to_equal("TOO MUCH INDENTATION")
    s
    .expect(
      first_in(
        "module Fixture exposing (..)\n\n import Dict\n\n\nx =\n    1\n", d,
      ),
    )
    .to_equal("TOO MUCH INDENTATION")
  })
}

///|
test "valid nested layouts still parse" {
  @expect.expect(
    layout_title(
      "f : Int\nf =\n    case x of\n        1 ->\n            let\n                y =\n                    if True then\n                        1\n\n                    else\n                        2\n            in\n            y\n\n        _ ->\n            0\n",
    ),
  ).to_equal("no error")
}

///|
test "layout rules can be switched off" {
  let d = @dialect.Dialect::elm_0_19_1()
  d.rules.remove(IndentedContinuation)
  @expect.expect(
    first_in("module Fixture exposing (..)\n\n\nf =\n    [ 1\n, 2 ]\n", d),
  ).to_equal("no error")
}

///|
test "layout failures are marked right after the previous token" {
  let text = "module Fixture exposing (..)\n\n\nf =\n    let\n    y = 1\n    in\n    y\n"
  let source = @scanner.SourceText::{ module_name: Some("Fixture"), text, }
  guard @scanner.DefaultScanner::new().tokenize(source) is Ok(tokens) else {
    fail("scan error")
  }
  guard parse_tokens(tokens).diagnostics.get(0) is Some(d) else {
    fail("expected an error")
  }
  guard d.report.iter().find_first(b => b is Excerpt(_))
    is Some(Excerpt(highlight~, ..)) else {
    fail("expected an excerpt")
  }
  // After `let` (line 5, columns 5-7), as elm make marks it.
  @expect.expect((highlight.start.line, highlight.start.column)).to_equal(
    (5, 8),
  )
}

///|
test "the first case branch must be indented" {
  @expect.expect_all(s => {
    s
    .expect(layout_title("f y =\n    case y of\n1 -> 2\n"))
    .to_equal("UNFINISHED CASE")
    s
    .expect(
      first_in(
        "module Fixture exposing (..)\n\n\nf y =\n    case y of\n1 -> 2\n",
        @dialect.Dialect::elm_syntax_7_3_9(),
      ),
    )
    .to_equal("UNFINISHED CASE")
  })
}

///|
test "a layout failure gives one error, not a second one for the same token" {
  for
    body in [
      "f =\n    if True then 1\nelse 2\n", "f =\n    [ 1\n, 2 ]\n", "type alias A =\nInt\n",
      "f =\n    \\a ->\na\n",
    ] {
    let text = "module Fixture exposing (..)\n\n\nx =\n    1\n\n\n" + body
    let source = @scanner.SourceText::{ module_name: Some("Fixture"), text, }
    guard @scanner.DefaultScanner::new().tokenize(source) is Ok(tokens) else {
      fail("scan error")
    }
    @expect.expect(parse_tokens(tokens).diagnostics.length()).to_equal(1)
  }
}

///|
test "a declaration after a failing one is still parsed" {
  let text = "module Fixture exposing (..)\n\n\nf =\ng =\n    1\n"
  let source = @scanner.SourceText::{ module_name: Some("Fixture"), text, }
  guard @scanner.DefaultScanner::new().tokenize(source) is Ok(tokens) else {
    fail("scan error")
  }
  let result = parse_tokens(tokens)
  guard result.ast is Some(file) else { fail("expected an AST") }
  @expect.expect(file.declarations.length()).to_equal(1)
}

///|
test "only the first import must be in column 1 for elm-syntax" {
  @expect.expect_all(s => {
    let text = "module Fixture exposing (..)\n\nimport Dict\n  import Set\n\n\nx =\n    1\n"
    s
    .expect(first_in(text, @dialect.Dialect::elm_syntax_7_3_9()))
    .to_equal("no error")
    s
    .expect(first_in(text, @dialect.Dialect::elm_0_19_1()))
    .to_equal("UNFINISHED IMPORT")
  })
}
