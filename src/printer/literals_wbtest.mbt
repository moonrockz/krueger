///|
test "string literals escape quotes, backslashes and control characters" {
  @expect.expect_all(s => {
    s.expect(string_literal("a\"b\\c")).to_equal("\"a\\\"b\\\\c\"")
    s.expect(string_literal("x\ny\tz")).to_equal("\"x\\ny\\tz\"")
    s
    .expect(string_literal("\r\u{7}\u{2028}"))
    .to_equal("\"\\u{000D}\\u{0007}\\u{2028}\"")
    s.expect(string_literal("é😀'")).to_equal("\"é😀'\"")
    s.expect(string_literal("")).to_equal("\"\"")
  })
}

///|
test "char literals escape the single quote" {
  @expect.expect_all(s => {
    s.expect(char_literal('\'')).to_equal("'\\''")
    s.expect(char_literal('"')).to_equal("'\"'")
    s.expect(char_literal('\n')).to_equal("'\\n'")
    s.expect(char_literal('\u{0}')).to_equal("'\\u{0000}'")
    s.expect(char_literal('😀')).to_equal("'😀'")
  })
}

///|
test "floats print as the shortest text with a dot" {
  @expect.expect_all(s => {
    s.expect(float_text(1.0)).to_equal("1.0")
    s.expect(float_text(0.0)).to_equal("0.0")
    s.expect(float_text(0.1)).to_equal("0.1")
    s.expect(float_text(1.5)).to_equal("1.5")
    s.expect(float_text(1.0e21)).to_equal("1.0e21")
    s.expect(float_text(1.0e-7)).to_equal("1.0e-7")
    s.expect(float_text(1.0e20)).to_equal("100000000000000000000.0")
    s.expect(float_text(5.0e-324)).to_equal("5.0e-324")
    s
    .expect(float_text(1.7976931348623157e308))
    .to_equal("1.7976931348623157e308")
  })
}

///|
test "negative zero counts as negative" {
  @expect.expect_all(s => {
    s.expect(is_negative(-0.0)).to_be_true()
    s.expect(is_negative(0.0)).to_be_false()
    s.expect(is_negative(-1.5)).to_be_true()
  })
}

///|
test "hex literals use upper-case digits padded to 2, 4, 8 or 16" {
  @expect.expect_all(s => {
    s.expect(hex_text(0L)).to_equal("0x00")
    s.expect(hex_text(15L)).to_equal("0x0F")
    s.expect(hex_text(255L)).to_equal("0xFF")
    s.expect(hex_text(256L)).to_equal("0x0100")
    s.expect(hex_text(65536L)).to_equal("0x00010000")
    s.expect(hex_text(0x100000000L)).to_equal("0x0000000100000000")
    s.expect(hex_text(9223372036854775807L)).to_equal("0x7FFFFFFFFFFFFFFF")
  })
}

///|
test "the smallest Int64 has no positive literal" {
  @expect.expect_all(s => {
    s.expect(is_min_int(-9223372036854775807L - 1L)).to_be_true()
    s.expect(is_min_int(-9223372036854775807L)).to_be_false()
    s.expect(is_min_int(0L)).to_be_false()
  })
}
