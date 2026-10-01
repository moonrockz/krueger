///|
/// The AST of `text`; fails the law on any diagnostic.
fn elm_file(text : String) -> @ast.File raise {
  let r = @parser.parse_module(
    { module_name: None, text, },
    @scanner.DefaultScanner::new(),
  )
  if !r.diagnostics.is_empty() {
    fail(
      "generated Elm does not parse:\n\{text}\n" +
      r.diagnostics.map(d => d.message).join("; "),
    )
  }
  guard r.ast is Some(file) else { fail("no AST:\n\{text}") }
  file
}

///|
/// The AST after encoding it, writing the JSON as text, reading it back and
/// decoding it.
fn round_trip(file : @ast.File) -> @ast.File raise {
  @ast.decode_file(@json.parse(@ast.encode_file(file).stringify()))
}

///|
/// Whether encoding the decoded AST gives the same JSON text again.
fn fixpoint(file : @ast.File) -> Bool raise {
  let json = @ast.encode_file(file).stringify()
  @ast.encode_file(@ast.decode_file(@json.parse(json))).stringify() == json
}

///|
test "law: decoding an encoded AST gives it back, except Int literals above 2^53 (krueger-wqh.4)" {
  // Edges: see `@lawkit.ElmModule` (every declaration form, non-ASCII names
  // and strings, the largest Int and hex a Double holds exactly, the largest
  // and smallest Float, a Float that rounds to zero, the first and last code
  // point, escapes, CRLF), through JSON text. The generator makes no Int
  // literal above 2^53: those come back as the nearest Double (krueger-wqh.4).
  @quickcheck.check(
    (m : @lawkit.ElmModule) => {
      let file = elm_file(m.text())
      round_trip(file) == file
    },
    count=100,
    max_size=24,
    seed=353,
  )
}

///|
test "law: encoding a decoded AST gives the same JSON text" {
  // Holds for every AST, Int literals above 2^53 included. Edges: as above.
  @quickcheck.check(
    (m : @lawkit.ElmModule) => fixpoint(elm_file(m.text())),
    count=100,
    max_size=24,
    seed=367,
  )
}

///|
/// A module whose one value is the expression `e`, and one whose one case
/// branch has the pattern `p`.
fn with_expression(e : String) -> String {
  "module M exposing (..)\n\n\nx =\n    " + e + "\n"
}

///|
fn with_pattern(p : String) -> String {
  "module M exposing (..)\n\n\nx =\n    case 1 of\n        " +
  p +
  " ->\n            1\n"
}

///|
test "every numeric edge literal survives the round trip" {
  // Exhaustive and independent of the generator: Ints a Double holds exactly
  // and Floats at the edges of the Double format (subnormals, the
  // subnormal/normal step, neighbours of 1, the thresholds where printers
  // switch to an exponent, a value that rounds to zero).
  let ints = ["0", "1", "9007199254740991", "0x0", "0xFF", "0x1FFFFFFFFFFFFF"]
  let floats = [
    "4.9e-324", "5e-324", "1e-323", "2.225073858507201e-308", "2.2250738585072014e-308",
    "1.7976931348623157e308", "0.1", "1.0000000000000002", "0.9999999999999999",
    "1e-7", "0.000001", "1e21", "9.999999999999999e20", "1e23", "0.30000000000000004",
    "1e-400", "123456789.125",
  ]
  @expect.expect_all(s => {
    for v in ints + floats {
      let file = elm_file(with_expression(v))
      s
      .expect((v, round_trip(file) == file, fixpoint(file)))
      .to_equal((v, true, true))
    }
    for v in ints {
      let file = elm_file(with_pattern(v))
      s
      .expect((v, round_trip(file) == file, fixpoint(file)))
      .to_equal((v, true, true))
    }
  })
}

///|
/// The expression of the module's first declaration.
fn first_expression(file : @ast.File) -> @ast.Expression raise {
  guard file.declarations is [{ value: FunctionDeclaration(f), .. }, ..] else {
    fail("no function")
  }
  f.declaration.value.expression.value
}

///|
test "an Int literal above 2^53 comes back as the nearest Double (krueger-wqh.4)" {
  // The parser keeps the exact Int64; JSON holds a Double, as elm-syntax
  // writes it. The JSON text is still a fixpoint.
  let big = ["9007199254740993", "9223372036854775806", "0x20000000000001"]
  @expect.expect_all(s => {
    for v in big {
      let file = elm_file(with_expression(v))
      s
      .expect((v, round_trip(file) == file, fixpoint(file)))
      .to_equal((v, false, true))
      let file = elm_file(with_pattern(v))
      s
      .expect((v, round_trip(file) == file, fixpoint(file)))
      .to_equal((v, false, true))
    }
    let file = elm_file(with_expression("9007199254740993"))
    s
    .expect(first_expression(round_trip(file)))
    .to_equal(Integer(9007199254740992L))
  })
}

///|
test "a Float too large for a Double encodes as null and does not decode, as in elm-syntax" {
  // JSON has no Infinity: elm-syntax writes `null` (JSON.stringify), so the
  // round trip holds only for finite floats, which is every Float the parser
  // accepts without a warning.
  let r = @parser.parse_module(
    { module_name: None, text: with_expression("1e309"), },
    @scanner.DefaultScanner::new(),
  )
  guard r.ast is Some(file) else { fail("no AST") }
  @expect.expect_all(s => {
    s.expect(r.diagnostics.map(d => d.code)).to_equal(["KR-PARSE-009"])
    s
    .expect(@ast.encode_file(file).stringify().contains("\"float\":null"))
    .to_be_true()
    let fails = try round_trip(file) catch {
      _ => true
    } noraise {
      _ => false
    }
    s.expect(fails).to_be_true()
  })
}
