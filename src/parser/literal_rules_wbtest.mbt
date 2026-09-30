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
