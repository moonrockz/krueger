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

///|
/// A string of up to `size` pieces of `@lawkit.literal_edge_chars()`.
struct LiteralValue(String) derive(Debug)

///|
impl @quickcheck.Arbitrary for LiteralValue with fn arbitrary(size, rs) {
  let edges = @lawkit.literal_edge_chars()
  let sb = StringBuilder()
  let count = rs
    .next_uint(limit=(size + 1).reinterpret_as_uint())
    .reinterpret_as_int()
  for _ in 0..<count {
    let i = rs
      .next_uint(limit=edges.length().reinterpret_as_uint())
      .reinterpret_as_int()
    sb.write_string(edges[i])
  }
  LiteralValue(sb.to_string())
}

///|
impl @quickcheck.Shrink for LiteralValue

///|
/// The value of the expression `text` in a module, or `None` when the
/// module has a diagnostic or the body is not a literal.
fn literal_value(text : String) -> @ast.Expression? {
  let result = @parser.parse_module(
    @scanner.SourceText::new(
      "module A exposing (..)\n\n\nx =\n    " + text + "\n",
    ),
    @scanner.DefaultScanner::new(),
  )
  guard result.diagnostics.is_empty() &&
    result.ast is Some(file) &&
    file.declarations[0].value is FunctionDeclaration(f) else {
    return None
  }
  Some(f.declaration.value.expression.value)
}

///|
test "law: a printed string or char literal parses back to its value" {
  @quickcheck.check(
    (v : LiteralValue) => {
      let LiteralValue(s) = v
      let chars = s.iter().collect()
      literal_value(string_literal(s)) == Some(Literal(s)) &&
      literal_value(triple_literal(s)) == Some(Literal(s)) &&
      (
        chars.length() != 1 ||
        literal_value(char_literal(chars[0])) == Some(CharLiteral(chars[0]))
      )
    },
    count=300,
    max_size=6,
    seed=2040,
  )
}

///|
test "law: a printed literal writes only plain characters as they are" {
  // A character outside `literal_plain_ranges` is escaped; so formatting
  // the printed text again gives the same text.
  @quickcheck.check(
    (v : LiteralValue) => {
      let LiteralValue(s) = v
      [string_literal(s), triple_literal(s)].all(text => {
        text.iter().all(c => c == '\n' || is_plain(c.to_int()))
      })
    },
    count=300,
    max_size=6,
    seed=2041,
  )
}

///|
test "every pair of literal edge characters reads back from both quotes" {
  let edges = @lawkit.literal_edge_chars()
  let failures = []
  for a in edges {
    for b in edges {
      let s = a + b
      if literal_value(string_literal(s)) != Some(Literal(s)) ||
        literal_value(triple_literal(s)) != Some(Literal(s)) {
        failures.push(s)
      }
    }
  }
  @expect.expect(failures).to_equal([])
}

///|
/// A finite Double that is not negative: an edge value or random bits.
struct PlainDouble(Double) derive(Debug)

///|
impl @quickcheck.Arbitrary for PlainDouble with fn arbitrary(_, rs) {
  let edges = [
    0.0, 5.0e-324, 2.2250738585072014e-308, 1.0e-7, 1.0e-6, 0.1, 0.5, 1.0, 9.5, 1.0e20,
    1.0e21, 9007199254740992.0, 9007199254740993.0, 1.2345678901234569e23, 1.7976931348623157e308,
  ]
  if rs.next_uint(limit=2U) == 0U {
    let i = rs
      .next_uint(limit=edges.length().reinterpret_as_uint())
      .reinterpret_as_int()
    return PlainDouble(edges[i])
  }
  // Random bits with the sign bit clear; the largest exponent (infinity,
  // NaN) is left out.
  let bits = rs.next_uint64() & 0x7FEFFFFFFFFFFFFFUL
  PlainDouble(bits.reinterpret_as_int64().reinterpret_as_double())
}

///|
impl @quickcheck.Shrink for PlainDouble

///|
test "law: elm-format's float forms read back as the value" {
  @quickcheck.check(
    (v : PlainDouble) => {
      let PlainDouble(x) = v
      let reads = (text : String) => {
        try @string.parse_double(text) catch {
          _ => false
        } noraise {
          y => y == x
        }
      }
      reads(exponent_float_text(x)) && reads(decimal_float_text(x))
    },
    count=500,
    seed=2042,
  )
}

///|
test "float forms as Haskell's showEFloat and showFFloat write them" {
  @expect.expect_all(s => {
    s.expect(exponent_float_text(0.0)).to_equal("0.0e0")
    s.expect(exponent_float_text(1000.0)).to_equal("1.0e3")
    s.expect(exponent_float_text(1.5e-7)).to_equal("1.5e-7")
    s.expect(exponent_float_text(5.0e-324)).to_equal("5.0e-324")
    s.expect(decimal_float_text(0.0)).to_equal("0.0")
    s.expect(decimal_float_text(1.0e-6)).to_equal("0.000001")
    s.expect(decimal_float_text(1.0e21)).to_equal("1000000000000000000000.0")
    s.expect(decimal_float_text(2.5)).to_equal("2.5")
  })
}
