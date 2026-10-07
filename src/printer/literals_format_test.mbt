///|
/// A module with the declarations `decls`.
fn literal_module(decls : String) -> String {
  "module A exposing (..)\n\n\n" + decls
}

///|
test "hex digits are upper case, strings keep their escapes" {
  let source = "module A exposing (..)\n\n\nh = 0xff\ns = \"a\\tb\"\nfl = 1.0e3\n"
  @expect.expect(@printer.format(source)).to_equal(
    "module A exposing (..)\n\n\nh =\n    0xFF\n\n\ns =\n    \"a\\tb\"\n\n\nfl =\n    1.0e3\n",
  )
}

///|
test "a triple-quoted string stays triple-quoted" {
  let source = "module A exposing (..)\n\n\ns =\n    \"\"\"a\nb\"\"\"\n"
  @expect.expect(@printer.format(source)).to_equal(source)
}

///|
test "hex literals: upper-case digits, padded to 2, 4, 8 or 16 digits" {
  // elm-format Box.hs formatLiteral: printf "0x%02X", "0x%04X", ...
  @expect.expect(
    @printer.format(literal_module("h = [ 0x1ff, 0xabcde, 0x0, 0x00000001 ]\n")),
  ).to_equal(literal_module("h =\n    [ 0x01FF, 0x000ABCDE, 0x00, 0x01 ]\n"))
}

///|
test "float literals keep their form: decimal or exponent" {
  // elm-format Box.hs formatLiteral: printf "%f" (showFFloat Nothing) for
  // a decimal float, printf "%e" (showEFloat Nothing) for an exponent.
  @expect.expect_all(s => {
    for
      case_ in [
        ("1E3", "1.0e3"),
        ("12e2", "1.2e3"),
        ("0.1e1", "1.0e0"),
        ("1.5e-7", "1.5e-7"),
        ("1.0e21", "1.0e21"),
        ("0.000001", "0.000001"),
        ("123456789012345678901234.5", "123456789012345690000000.0"),
        ("2.50", "2.5"),
      ] {
      let (source, expected) = case_
      s
      .expect(@printer.format(literal_module("f = \{source}\n")))
      .to_equal(literal_module("f =\n    \{expected}\n"))
    }
  })
}

///|
test "an integer too big for Int64 keeps its digits" {
  // elm-format writes -9223372036854775808; krueger clamps the value
  // (KR-PARSE-009), so the digits come from the source.
  @expect.expect(
    @printer.format(
      literal_module("i = [ 9223372036854775807, -9223372036854775808 ]\n"),
    ),
  ).to_equal(
    literal_module("i =\n    [ 9223372036854775807, -9223372036854775808 ]\n"),
  )
}

///|
test "characters that are not printable, or are spaces, are escaped" {
  // elm-format Box.hs formatString: hex when not isPrint, and when
  // isSpace (except ' ').
  @expect.expect_all(s => {
    s
    .expect(
      @printer.format(
        literal_module("s = \"\u{06DD}\u{FFFB}\u{110BD}\u{E007F}\"\n"),
      ),
    )
    .to_equal(
      literal_module("s =\n    \"\\u{06DD}\\u{FFFB}\\u{110BD}\\u{E007F}\"\n"),
    )
    s
    .expect(
      @printer.format(literal_module("s = \" \u{00A0}\u{2000}\u{205F}\"\n")),
    )
    .to_equal(literal_module("s =\n    \" \\u{00A0}\\u{2000}\\u{205F}\"\n"))
    s
    .expect(
      @printer.format(
        literal_module(
          "c = [ ' ', '\u{00A0}', '\u{06DD}', '\u{E007F}', '\\u{0041}' ]\n",
        ),
      ),
    )
    .to_equal(
      literal_module(
        "c =\n    [ ' ', '\\u{00A0}', '\\u{06DD}', '\\u{E007F}', 'A' ]\n",
      ),
    )
    s
    .expect(@printer.format(literal_module("s = \"\\u{202F}\\r\\u{007F}\"\n")))
    .to_equal(literal_module("s =\n    \"\\u{202F}\\u{000D}\\u{007F}\"\n"))
  })
}

///|
test "elm-format's Unicode version: 14.0 characters print, 15.0 ones are escaped" {
  // U+0870 is new in Unicode 14.0, U+1F6DC in 15.0.
  @expect.expect(@printer.format(literal_module("s = \"\u{0870}\u{1F6DC}\"\n"))).to_equal(
    literal_module("s =\n    \"\u{0870}\\u{1F6DC}\"\n"),
  )
}

///|
test "a triple-quoted string keeps its line breaks and escapes the rest" {
  @expect.expect_all(s => {
    s
    .expect(
      @printer.format(
        literal_module("s =\n    \"\"\"a \"b\"\n\t\\\\\n\\r\u{00A0}\n\"\"\"\n"),
      ),
    )
    .to_equal(
      literal_module(
        "s =\n    \"\"\"a \"b\"\n\\t\\\\\n\\u{000D}\\u{00A0}\n\"\"\"\n",
      ),
    )
    // Trailing spaces on a line stay.
    s
    .expect(
      @printer.format(literal_module("s =\n    \"\"\"   3   \n 1 \n\"\"\"\n")),
    )
    .to_equal(literal_module("s =\n    \"\"\"   3   \n 1 \n\"\"\"\n"))
  })
}

///|
test "a triple-quoted string escapes three quotes in a row and quotes at its end" {
  // elm-format Box.hs escapeMultiQuote.
  @expect.expect_all(s => {
    for
      case_ in [
        ("\"\"\"q\\\"\"\"\"", "\"\"\"q\\\"\"\"\""),
        ("\"\"\"q\\\"\\\"\"\"\"", "\"\"\"q\\\"\\\"\"\"\""),
        ("\"\"\"(\\\"\\\"\\\")\"\"\"", "\"\"\"(\\\"\\\"\\\")\"\"\""),
        ("\"\"\"\"\"q\"\"\"", "\"\"\"\"\"q\"\"\""),
        ("\"\"\"\\\"\\\"\\\" q\"\"\"", "\"\"\"\\\"\\\"\\\" q\"\"\""),
      ] {
      let (source, expected) = case_
      s
      .expect(@printer.format(literal_module("s =\n    \{source}\n")))
      .to_equal(literal_module("s =\n    \{expected}\n"))
    }
  })
}

///|
test "patterns print their literals as expressions do" {
  @expect.expect(
    @printer.format(
      literal_module(
        "f x =\n    case x of\n        0xff ->\n            \"\"\"a\nb\"\"\"\n\n        \"\u{00A0}\" ->\n            '\u{00A0}'\n\n        _ ->\n            \"\"\n",
      ),
    ),
  ).to_equal(
    literal_module(
      "f x =\n    case x of\n        0xFF ->\n            \"\"\"a\nb\"\"\"\n\n        \"\\u{00A0}\" ->\n            '\\u{00A0}'\n\n        _ ->\n            \"\"\n",
    ),
  )
}

///|
test "without source, and in the Width layout, literals print from their value" {
  let source = literal_module(
    "s =\n    \"\"\"a\nb\u{00A0}\"\"\"\n\n\nh =\n    0xff\n\n\nf =\n    1E3\n",
  )
  let expected = literal_module(
    "s =\n    \"a\\nb\\u{00A0}\"\n\n\nh =\n    0xFF\n\n\nf =\n    1000.0\n",
  )
  let file = @parser.parse_module(
    @scanner.SourceText::new(source),
    @scanner.DefaultScanner::new(),
  ).ast.unwrap()
  @expect.expect_all(s => {
    s.expect(@printer.print_file(file)).to_equal(expected)
    s.expect(@printer.format(source, layout=Width(120))).to_equal(expected)
  })
}
