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
  @expect.expect(layout_title("f =\n    let\n        y = 1\nin\n    y\n")).to_equal(
    "UNFINISHED LET",
  )
  @expect.expect(layout_title("f =\n    if True\nthen 1 else 2\n")).to_equal(
    "UNFINISHED IF",
  )
  @expect.expect(layout_title("f =\n    if True then 1\nelse 2\n")).to_equal(
    "WEIRD ELSE BRANCH",
  )
  @expect.expect(layout_title("f =\n    [ 1\n, 2 ]\n")).to_equal(
    "UNFINISHED LIST",
  )
  @expect.expect(layout_title("f =\n    (1\n)\n")).to_equal(
    "UNFINISHED PARENTHESES",
  )
  @expect.expect(layout_title("type alias A =\nInt\n")).to_equal(
    "UNFINISHED TYPE ALIAS",
  )
  @expect.expect(
    layout_title(
      "f =\n    case x of\n        1 ->\n        2\n\n        _ ->\n            3\n",
    ),
  ).to_equal("UNFINISHED CASE")
}

///|
test "let declarations must be right of let" {
  @expect.expect(layout_title("f =\n    let\n    y = 1\n    in\n    y\n")).to_equal(
    "UNFINISHED LET",
  )
  @expect.expect(layout_title("f =\n    let\n  y = 1\n    in\n    y\n")).to_equal(
    "UNFINISHED LET",
  )
}

///|
test "module header and imports start in column 1" {
  let d = @dialect.Dialect::elm_0_19_1()
  @expect.expect(first_in(" module Fixture exposing (..)\n\n\nx =\n    1\n", d)).to_equal(
    "TOO MUCH INDENTATION",
  )
  @expect.expect(
    first_in(
      "module Fixture exposing (..)\n\n import Dict\n\n\nx =\n    1\n", d,
    ),
  ).to_equal("TOO MUCH INDENTATION")
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
