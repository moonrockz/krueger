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
/// The AST after a round trip through JSON text with exact Ints.
fn exact_round_trip(file : @ast.File) -> @ast.File raise {
  @ast.decode_file(
    @json.parse(@ast.encode_file_with(file, exact_ints=true).stringify()),
  )
}

///|
/// Whether, with exact Ints, encoding the decoded AST gives the same JSON
/// text again.
fn exact_fixpoint(file : @ast.File) -> Bool raise {
  let json = @ast.encode_file_with(file, exact_ints=true).stringify()
  @ast.encode_file_with(@ast.decode_file(@json.parse(json)), exact_ints=true).stringify() ==
  json
}

///|
/// Whether encoding the decoded AST gives the same JSON text again.
fn fixpoint(file : @ast.File) -> Bool raise {
  let json = @ast.encode_file(file).stringify()
  @ast.encode_file(@ast.decode_file(@json.parse(json))).stringify() == json
}

///|
test "law: by default, decoding an encoded AST gives it back for Int literals up to 2^53" {
  // Edges: see `@lawkit.ElmModule` (every declaration form, non-ASCII names
  // and strings, the largest Int and hex a Double holds exactly, the largest
  // and smallest Float, a Float that rounds to zero, the first and last code
  // point, escapes, CRLF), through JSON text. The generator makes no Int
  // literal above 2^53: by default those come back as the nearest Double, as
  // elm-syntax writes them (see the exact-Int laws).
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
test "by default, an Int literal above 2^53 comes back as the nearest Double" {
  // The parser keeps the exact Int64; the default JSON holds a Double, as
  // elm-syntax writes it. The JSON text is still a fixpoint.
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

///|
test "law: with exact Ints, decoding an encoded AST gives it back" {
  // Edges: see `@lawkit.ElmModule`.
  @quickcheck.check(
    (m : @lawkit.ElmModule) => {
      let file = elm_file(m.text())
      exact_round_trip(file) == file && exact_fixpoint(file)
    },
    count=100,
    max_size=24,
    seed=373,
  )
}

///|
test "law: with no Int literal above 2^53, exact Ints change no byte" {
  // So elm-syntax parity holds in both modes for such files. Edges: see
  // `@lawkit.ElmModule`.
  @quickcheck.check(
    (m : @lawkit.ElmModule) => {
      let file = elm_file(m.text())
      @ast.encode_file_with(file, exact_ints=true).stringify() ==
      @ast.encode_file(file).stringify()
    },
    count=100,
    max_size=24,
    seed=379,
  )
}

///|
test "law: with exact Ints, every Int literal survives the round trip" {
  // Edges: see `@lawkit.IntLiteral` (2^53 +- 2, the largest Int64, decimal
  // and hex), in an expression and in a pattern.
  @quickcheck.check(
    (lit : @lawkit.IntLiteral) => {
      let mut ok = true
      for text in [with_expression(lit.text()), with_pattern(lit.text())] {
        let file = elm_file(text)
        ok = ok &&
          exact_round_trip(file) == file &&
          exact_fixpoint(file) &&
          fixpoint(file)
      }
      ok
    },
    count=200,
    max_size=24,
    seed=383,
  )
}

///|
test "exact Ints write the literal's digits; the default writes the nearest Double" {
  let file = elm_file(with_expression("9007199254740993"))
  @expect.expect_all(s => {
    s
    .expect(
      @ast.encode_file_with(file, exact_ints=true)
      .stringify()
      .contains("9007199254740993"),
    )
    .to_be_true()
    s
    .expect(@ast.encode_file(file).stringify().contains("9007199254740992"))
    .to_be_true()
    s
    .expect(first_expression(exact_round_trip(file)))
    .to_equal(Integer(9007199254740993L))
  })
}

///|
test "the decoder reads an Int's digits, and falls back to its Double" {
  let int_json = (digits : String) => {
    @json.parse("{\"type\":\"integer\",\"integer\":" + digits + "}")
  }
  // A number built in memory has no digits: its Double is read.
  let built : Json = { "type": "integer", "integer": Json::number(5.0) }
  @expect.expect_all(s => {
    s
    .expect(@ast.decode_expression(int_json("9223372036854775806")))
    .to_equal(Integer(9223372036854775806L))
    s.expect(@ast.decode_expression(int_json("1e3"))).to_equal(Integer(1000L))
    s.expect(@ast.decode_expression(built)).to_equal(Integer(5L))
  })
}

///|
test "by default, Ints above 2^56 that a Double holds exactly round-trip" {
  // elm-syntax writes a Double's shortest digits (`1152921504606847000` for
  // 2^60); the decoder must read them as that Double, not as the digits.
  @expect.expect_all(s => {
    for v in ["0x1000000000000000", "0x4000000000000000", "1152921504606846976"] {
      let file = elm_file(with_expression(v))
      s.expect((v, round_trip(file) == file)).to_equal((v, true))
      let file = elm_file(with_pattern(v))
      s.expect((v, round_trip(file) == file)).to_equal((v, true))
    }
  })
}

///|
test "with exact Ints, digits that are a Double's shortest form read as that Double" {
  // The one ambiguous text: `1152921504606847000` is both the exact form of
  // that literal and elm-syntax's form of 2^60. It is read as elm-syntax
  // means it.
  let file = elm_file(with_expression("1152921504606847000"))
  @expect.expect(first_expression(exact_round_trip(file))).to_equal(
    Integer(1152921504606846976L),
  )
}

///|
test "with exact Ints, a big literal survives in every expression and pattern context" {
  let l = "9007199254740993"
  let expressions = [
    "\\_ -> " + l,
    "\\" + l + " -> 0",
    "let\n        y =\n            0\n    in\n    " + l,
    "let\n        ( " + l + ", b ) =\n            r\n    in\n    b",
    "1 + " + l,
    "if " + l + " == 0 then 0 else " + l,
    "case 0 of\n        _ ->\n            " + l,
    "let\n        y =\n            " + l + "\n    in\n    y",
    "let\n        ( a, _ ) =\n            ( " + l + ", 0 )\n    in\n    a",
    "{ a = " + l + " }",
    "{ r | a = " + l + " }",
    "f " + l,
    l + " + 1",
    "if True then " + l + " else 0",
    "-" + l,
    "( " + l + ", 0 )",
    "[ " + l + " ]",
    "(" + l + ")",
    "{ a = " + l + " }.a",
    "case " + l + " of\n        _ ->\n            0",
  ]
  let patterns = [
    "( " + l + ", _ )",
    "[ " + l + " ]",
    l + " :: _",
    "_ :: " + l,
    "Just " + l,
    "(" + l + " as y)",
    "(" + l + ")",
  ]
  let modules = expressions.map(with_expression) +
    patterns.map(with_pattern) +
    ["module M exposing (..)\n\n\nf " + l + " =\n    1\n"]
  // The parser makes no top-level destructuring, so build one from JSON
  // text with exact digits.
  let top = @ast.decode_file(
    @json.parse(
      (
        #|{"moduleDefinition":{"range":[1,1,1,23],"value":{"type":"normal","normal":{"moduleName":{"range":[1,8,1,9],"value":["M"]},"exposingList":{"range":[1,10,1,23],"value":{"type":"all","all":[1,20,1,22]}}}}},
        #| "imports":[],
        #| "declarations":[{"range":[4,1,5,21],"value":{"type":"destructuring","destructuring":{
        #|   "pattern":{"range":[4,1,4,17],"value":{"type":"int","int":{"value":9007199254740993}}},
        #|   "expression":{"range":[5,5,5,21],"value":{"type":"integer","integer":9007199254740993}}}}}],
        #| "comments":[]}
      ),
    ),
  )
  @expect.expect_all(s => {
    for text in modules {
      let file = elm_file(text)
      s.expect((text, exact_round_trip(file) == file)).to_equal((text, true))
    }
    s.expect(exact_round_trip(top) == top).to_be_true()
  })
}
