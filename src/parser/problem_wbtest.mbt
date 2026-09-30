///|
fn first_title(body : String) -> String {
  let text = "module Fixture exposing (..)\n\n\nx =\n    1\n\n\n" + body
  let source = @scanner.SourceText::{ module_name: Some("Fixture"), text, }
  guard @scanner.DefaultScanner::new().tokenize(source) is Ok(tokens) else {
    return "scan error"
  }
  match parse_tokens(tokens).diagnostics.get(0) {
    Some(d) => d.title
    None => "no error"
  }
}

///|
test "syntax errors take their title from the innermost construct" {
  @expect.expect(first_title("f =\n    case x of\n")).to_equal(
    "UNFINISHED CASE",
  )
  @expect.expect(first_title("f =\n    if True then 1\n")).to_equal(
    "UNFINISHED IF",
  )
  @expect.expect(first_title("f =\n    \\a a\n")).to_equal(
    "UNFINISHED ANONYMOUS FUNCTION",
  )
  @expect.expect(first_title("f =\n    [ 1, ]\n")).to_equal("UNFINISHED LIST")
  @expect.expect(first_title("f =\n    case 1 of\n        { a = 1 } -> 1\n")).to_equal(
    "UNFINISHED RECORD PATTERN",
  )
  @expect.expect(first_title("type T\n    = A\n    | B\n    |\n")).to_equal(
    "UNFINISHED CUSTOM TYPE",
  )
}

///|
test "rules on the token found come before the construct" {
  @expect.expect(first_title("f =\n    let in 1\n")).to_equal("RESERVED WORD")
  @expect.expect(first_title("f =\n    { a = 1, }\n")).to_equal("EXTRA COMMA")
  @expect.expect(first_title("type alias R =\n    { a : Int, }\n")).to_equal(
    "EXTRA COMMA",
  )
  @expect.expect(first_title("f =\n    - x\n")).to_equal("MISSING EXPRESSION")
  @expect.expect(first_title("f =\n    ( + ) 1 2\n")).to_equal(
    "MISSING EXPRESSION",
  )
  @expect.expect(
    first_title("r =\n    { a = 1 }\n\n\nf =\n    { Fixture.r | a = 2 }\n"),
  ).to_equal("PROBLEM IN RECORD")
  @expect.expect(
    first_title("f =\n    case 1.5 of\n        1.5 -> 1\n        _ -> 2\n"),
  ).to_equal("UNEXPECTED PATTERN")
}

///|
test "specific constructs have their own titles" {
  @expect.expect(first_title("f =\n    (+ 1)\n")).to_equal(
    "UNFINISHED OPERATOR FUNCTION",
  )
  @expect.expect(first_title("type alias a =\n    Int\n")).to_equal(
    "EXPECTING TYPE ALIAS NAME",
  )
  @expect.expect(first_title("f =\n    1.\n")).to_equal("WEIRD NUMBER")
  @expect.expect(first_title("f =\n    ''\n")).to_equal("NEEDS DOUBLE QUOTES")
  @expect.expect(first_title("f =\n    \"\\q\"\n")).to_equal("UNKNOWN ESCAPE")
  @expect.expect(first_title("f =\n    \"\\u{zz}\"\n")).to_equal(
    "BAD UNICODE ESCAPE",
  )
  @expect.expect(first_title("f =\n    x <=> 1\n")).to_equal("UNKNOWN OPERATOR")
  @expect.expect(first_title("f =\n    x == 1 == True\n")).to_equal(
    "INFIX PROBLEM",
  )
  @expect.expect(first_title(" y =\n    1\n")).to_equal("UNEXPECTED EQUALS")
}

///|
test "module-level errors have titles" {
  let title = fn(text : String) {
    let source = @scanner.SourceText::{ module_name: Some("Fixture"), text, }
    guard @scanner.DefaultScanner::new().tokenize(source) is Ok(tokens) else {
      return "scan error"
    }
    match parse_tokens(tokens).diagnostics.get(0) {
      Some(d) => d.title
      None => "no error"
    }
  }
  @expect.expect(title("module Fixture exposing ()\n\n\nx =\n    1\n")).to_equal(
    "PROBLEM IN EXPOSING",
  )
  @expect.expect(
    title("module Fixture exposing (..)\n\nimport Dict as d\n\n\nx =\n    1\n"),
  ).to_equal("EXPECTING IMPORT ALIAS")
}

///|
test "an error with no construct still has a title and an excerpt" {
  let text = "module Fixture exposing (..)\n\n\n)\n"
  let source = @scanner.SourceText::{ module_name: Some("Fixture"), text, }
  guard @scanner.DefaultScanner::new().tokenize(source) is Ok(tokens) else {
    fail("scan error")
  }
  guard parse_tokens(tokens).diagnostics.get(0) is Some(d) else {
    fail("expected an error")
  }
  @expect.expect(d.title != "").to_equal(true)
  @expect.expect(d.report.iter().any(b => b is Excerpt(_))).to_equal(true)
}

///|
test "the excerpt ends where elm make marks the error" {
  let text = "module Fixture exposing (..)\n\n\nf =\n    let\n        y = 1\n"
  let source = @scanner.SourceText::{ module_name: Some("Fixture"), text, }
  guard @scanner.DefaultScanner::new().tokenize(source) is Ok(tokens) else {
    fail("scan error")
  }
  guard parse_tokens(tokens).diagnostics.get(0) is Some(d) else {
    fail("expected an error")
  }
  guard d.report.iter().find_first(b => b is Excerpt(_))
    is Some(Excerpt(context~, highlight~)) else {
    fail("expected an excerpt")
  }
  // After `1` on line 6, where the `let` stopped; the excerpt starts at `let`.
  @expect.expect((highlight.start.line, highlight.start.column)).to_equal(
    (6, 14),
  )
  @expect.expect(context.start.line).to_equal(5)
}
