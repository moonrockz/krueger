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

///|
fn first_diagnostic(text : String) -> @scanner.Diagnostic? {
  let source = @scanner.SourceText::{ module_name: Some("Fixture"), text, }
  guard @scanner.DefaultScanner::new().tokenize(source) is Ok(tokens) else {
    return None
  }
  parse_tokens(tokens).diagnostics.get(0)
}

///|
fn highlight_of(d : @scanner.Diagnostic) -> (Int, Int) {
  match d.report.iter().find_first(b => b is Excerpt(_)) {
    Some(Excerpt(highlight~, ..)) =>
      (highlight.start.line, highlight.start.column)
    _ => (0, 0)
  }
}

///|
fn report_text(d : @scanner.Diagnostic) -> String {
  let sb = StringBuilder()
  for b in d.report {
    match b {
      Text(chunks) | Hint(chunks) | Note(chunks) =>
        for c in chunks {
          match c {
            Plain(s) => sb.write_string(s)
            Styled(text~, ..) => sb.write_string(text)
          }
        }
      _ => ()
    }
  }
  sb.to_string()
}

///|
let header : String = "module Fixture exposing (..)\n\n\n"

///|
test "the caret marks a wrong token on its own line" {
  guard first_diagnostic(
      header + "f =\n    case 1.5 of\n        1.5 -> 1\n        _ -> 2\n",
    )
    is Some(d) else {
    fail("expected an error")
  }
  @expect.expect(highlight_of(d)).to_equal((6, 9))
  guard first_diagnostic(
      header +
      "f =\n    case x of\n        1 ->\n            1\n\n          _ ->\n            2\n",
    )
    is Some(m) else {
    fail("expected an error")
  }
  @expect.expect(highlight_of(m)).to_equal((9, 11))
}

///|
test "a missing expression is not a reserved word" {
  @expect.expect(first_title("f =\n    if a then else b\n")).to_equal(
    "MISSING EXPRESSION",
  )
  @expect.expect(first_title("f =\n    case of\n")).to_equal(
    "MISSING EXPRESSION",
  )
  @expect.expect(first_title("f =\n    if a then 1 else then\n")).to_equal(
    "UNFINISHED IF",
  )
  @expect.expect(first_title("f =\n    let\n        y = (\n    in\n    y\n")).to_equal(
    "UNFINISHED PARENTHESES",
  )
  @expect.expect(first_title("f =\n    let\n        y =\n    in\n    y\n")).to_equal(
    "UNFINISHED DEFINITION",
  )
}

///|
test "an expression is missing after =, -> and (" {
  @expect.expect(first_title("z = )\n")).to_equal("MISSING EXPRESSION")
  @expect.expect(
    first_title("f =\n    case x of\n        1 -> )\n        _ -> 2\n"),
  ).to_equal("MISSING EXPRESSION")
}

///|
test "every error has a report" {
  guard first_diagnostic("x = 1\n") is Some(missing) else {
    fail("expected an error")
  }
  @expect.expect(missing.title).to_equal("MODULE NAME MISSING")
  @expect.expect(missing.report.is_empty()).to_equal(false)
  guard first_diagnostic(header + "x =\n    1\n\n\n{-| stray -}\n")
    is Some(stray) else {
    fail("expected an error")
  }
  @expect.expect(stray.title).to_equal("WEIRD DECLARATION")
  @expect.expect(stray.report.is_empty()).to_equal(false)
}

///|
test "a stray token is not named as a definition" {
  guard first_diagnostic(header + "X = 1\n") is Some(upper) else {
    fail("expected an error")
  }
  @expect.expect(upper.title).to_equal("UNEXPECTED CAPITAL LETTER")
  @expect.expect(highlight_of(upper)).to_equal((4, 1))
  guard first_diagnostic(header + ")\n") is Some(paren) else {
    fail("expected an error")
  }
  @expect.expect(report_text(paren).contains("the ) definition")).to_equal(
    false,
  )
  @expect.expect(highlight_of(paren)).to_equal((4, 1))
}
