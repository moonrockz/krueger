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
  @expect.expect(literal_titles("'ab'")).to_equal(
    ("NEEDS DOUBLE QUOTES", "NEEDS DOUBLE QUOTES"),
  )
  @expect.expect(literal_titles("'abc'")).to_equal(
    ("NEEDS DOUBLE QUOTES", "NEEDS DOUBLE QUOTES"),
  )
  @expect.expect(literal_titles("0x")).to_equal(
    ("WEIRD HEXIDECIMAL", "WEIRD HEXIDECIMAL"),
  )
  @expect.expect(literal_titles("0X1F")).to_equal(("WEIRD NUMBER", "no error"))
  @expect.expect(literal_titles("1e")).to_equal(("WEIRD NUMBER", "no error"))
  @expect.expect(literal_titles("007")).to_equal(("LEADING ZEROS", "no error"))
  @expect.expect(literal_titles("01")).to_equal(("LEADING ZEROS", "no error"))
  @expect.expect(literal_titles("'\\u{110000}'")).to_equal(
    ("BAD UNICODE ESCAPE", "no error"),
  )
  @expect.expect(literal_titles("'\\u{10FFFF}'")).to_equal(
    ("no error", "no error"),
  )
  @expect.expect(literal_titles("0x1F + 1e5 + 0")).to_equal(
    ("no error", "no error"),
  )
}

///|
test "exposed operators must be written without spaces" {
  let text = "module Fixture exposing (..)\n\nimport Basics exposing (( + ))\n\n\nx =\n    1\n"
  @expect.expect(first_in(text, @dialect.Dialect::elm_0_19_1())).to_equal(
    "PROBLEM IN EXPOSING",
  )
  @expect.expect(first_in(text, @dialect.Dialect::elm_syntax_7_3_9())).to_equal(
    "PROBLEM IN EXPOSING",
  )
}

///|
fn pattern_titles(pattern : String) -> (String, String) {
  literal_titles("case x of\n        " + pattern + " -> 1\n\n        _ -> 2")
}

///|
test "number rules also apply to patterns" {
  @expect.expect(pattern_titles("01").0).to_equal("LEADING ZEROS")
  @expect.expect(pattern_titles("007").0).to_equal("LEADING ZEROS")
  @expect.expect(pattern_titles("01").1 != "no error").to_equal(true)
  @expect.expect(pattern_titles("0x").0).to_equal("WEIRD HEXIDECIMAL")
  @expect.expect(pattern_titles("0X1F").0).to_equal("WEIRD NUMBER")
  @expect.expect(pattern_titles("0x1F")).to_equal(("no error", "no error"))
}

///|
test "zero followed by an exponent is a weird number in elm make" {
  @expect.expect(literal_titles("0e1")).to_equal(("WEIRD NUMBER", "no error"))
  @expect.expect(literal_titles("0E1")).to_equal(("WEIRD NUMBER", "no error"))
  @expect.expect(literal_titles("0.5e1")).to_equal(("no error", "no error"))
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
