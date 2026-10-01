///|
fn literal_titles(body : String) -> (String, String) {
  let text = "module Fixture exposing (..)\n\n\nx =\n    1\n\n\nf =\n    " +
    body +
    "\n"
  (
    first_in(text, @dialect.Dialect::elm_0_19_1()),
    first_in(text, @dialect.Dialect::elm_syntax_7_3_9()),
  )
}

///|
test "literal rules follow each oracle" {
  @expect.expect_all(s => {
    s
    .expect(literal_titles("'ab'"))
    .to_equal(("NEEDS DOUBLE QUOTES", "NEEDS DOUBLE QUOTES"))
    s
    .expect(literal_titles("'abc'"))
    .to_equal(("NEEDS DOUBLE QUOTES", "NEEDS DOUBLE QUOTES"))
    s
    .expect(literal_titles("0x"))
    .to_equal(("WEIRD HEXIDECIMAL", "WEIRD HEXIDECIMAL"))
    s.expect(literal_titles("0X1F")).to_equal(("WEIRD NUMBER", "no error"))
    s.expect(literal_titles("1e")).to_equal(("WEIRD NUMBER", "no error"))
    s.expect(literal_titles("007")).to_equal(("LEADING ZEROS", "no error"))
    s.expect(literal_titles("01")).to_equal(("LEADING ZEROS", "no error"))
    s
    .expect(literal_titles("'\\u{110000}'"))
    .to_equal(("BAD UNICODE ESCAPE", "no error"))
    s.expect(literal_titles("'\\u{10FFFF}'")).to_equal(("no error", "no error"))
    s
    .expect(literal_titles("0x1F + 1e5 + 0"))
    .to_equal(("no error", "no error"))
  })
}

///|
test "exposed operators must be written without spaces" {
  @expect.expect_all(s => {
    let text = "module Fixture exposing (..)\n\nimport Basics exposing (( + ))\n\n\nx =\n    1\n"
    s
    .expect(first_in(text, @dialect.Dialect::elm_0_19_1()))
    .to_equal("PROBLEM IN EXPOSING")
    s
    .expect(first_in(text, @dialect.Dialect::elm_syntax_7_3_9()))
    .to_equal("PROBLEM IN EXPOSING")
  })
}

///|
fn pattern_titles(pattern : String) -> (String, String) {
  literal_titles("case x of\n        " + pattern + " -> 1\n\n        _ -> 2")
}

///|
test "number rules also apply to patterns" {
  @expect.expect_all(s => {
    s.expect(pattern_titles("01").0).to_equal("LEADING ZEROS")
    s.expect(pattern_titles("007").0).to_equal("LEADING ZEROS")
    s.expect(pattern_titles("01").1 != "no error").to_equal(true)
    s.expect(pattern_titles("0x").0).to_equal("WEIRD HEXIDECIMAL")
    s.expect(pattern_titles("0X1F").0).to_equal("WEIRD NUMBER")
    s.expect(pattern_titles("0x1F")).to_equal(("no error", "no error"))
  })
}

///|
test "zero followed by an exponent is a weird number in elm make" {
  @expect.expect_all(s => {
    s.expect(literal_titles("0e1")).to_equal(("WEIRD NUMBER", "no error"))
    s.expect(literal_titles("0E1")).to_equal(("WEIRD NUMBER", "no error"))
    s.expect(literal_titles("0.5e1")).to_equal(("no error", "no error"))
  })
}

///|
test "a code point above 10FFFF has its own report" {
  let text = "module Fixture exposing (..)\n\n\nf =\n    '\\u{110000}'\n"
  let source = @scanner.SourceText::{ module_name: Some("Fixture"), text, }
  guard @scanner.DefaultScanner::new().tokenize(source) is Ok(tokens) else {
    fail("scan error")
  }
  guard parse_tokens(tokens).diagnostics.get(0) is Some(d) else {
    fail("expected an error")
  }
  let words = d.report
    .filter_map(b => if b is Text([Plain(s)]) { Some(s) } else { None })
    .join(" ")
  @expect.expect(words).to_contain("between 0 and 10FFFF")
}

///|
fn parse_number(body : String) -> (Array[String], @ast.Expression?) {
  let text = "module Fixture exposing (..)\n\n\nf =\n    " + body + "\n"
  let source = @scanner.SourceText::{ module_name: Some("Fixture"), text, }
  guard @scanner.DefaultScanner::new().tokenize(source) is Ok(tokens) else {
    return (["scan error"], None)
  }
  let result = parse_tokens(tokens)
  let value = match result.ast {
    Some(file) =>
      match file.declarations.get(0) {
        Some({ value: FunctionDeclaration(f), .. }) =>
          Some(f.declaration.value.expression.value)
        _ => None
      }
    None => None
  }
  (result.diagnostics.map(d => "\{d.code} \{severity_word(d.severity)}"), value)
}

///|
test "out-of-range numbers are accepted with a warning" {
  @expect.expect_all(s => {
    s
    .expect(parse_number("99999999999999999999"))
    .to_equal((["KR-PARSE-009 Warning"], Some(Integer(9223372036854775807L))))
    s
    .expect(parse_number("0xFFFFFFFFFFFFFFFFFF"))
    .to_equal((["KR-PARSE-009 Warning"], Some(Hex(9223372036854775807L))))
    let (codes, value) = parse_number("1.0e400")
    s.expect(codes).to_equal(["KR-PARSE-009 Warning"])
    guard value is Some(Floatable(x)) else { fail("expected a float") }
    s.expect(x > 1.0e308).to_equal(true)
  })
}

///|
fn severity_word(s : @scanner.Severity) -> String {
  match s {
    Error => "Error"
    Warning => "Warning"
    Info => "Info"
  }
}
