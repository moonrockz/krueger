///|
fn expect_error(f : () -> Unit raise @ast.DecodeError) -> String {
  try f() catch {
    e => e.to_string()
  } noraise {
    _ => "no error"
  }
}

///|
test "decode error names the path of an unknown tag" {
  let src =
    #|{"moduleDefinition":{"range":[1,1,1,20],"value":{"type":"normal","normal":{"moduleName":{"range":[1,8,1,9],"value":["A"]},"exposingList":{"range":[1,10,1,20],"value":{"type":"all","all":[1,19,1,21]}}}}},
    #| "imports":[],
    #| "declarations":[{"range":[3,1,3,6],"value":{"type":"function","function":{"documentation":null,"signature":null,"declaration":{"range":[3,1,3,6],"value":{"name":{"range":[3,1,3,2],"value":"f"},"arguments":[],"expression":{"range":[3,5,3,6],"value":{"type":"bogus","bogus":1}}}}}}}],
    #| "comments":[]}
  let j = @json.parse(src)
  @expect.expect(expect_error(() => ignore(@ast.decode_file(j)))).to_equal(
    "$.declarations[0].value.function.declaration.value.expression.value.type: No decoder for type: bogus",
  )
}

///|
test "decode error on missing field, bad range, non-integer int, no payload" {
  let missing =
    #|{"type":"ifBlock","ifBlock":{"clause":{"range":[1,1,1,2],"value":{"type":"unit","unit":null}}}}
  let missing_json = @json.parse(missing)
  @expect.expect(
    expect_error(() => ignore(@ast.decode_expression(missing_json))),
  ).to_equal("$.ifBlock: Expecting an OBJECT with a field named `then`")
  let short_range = @json.parse("[1,2,3]")
  @expect.expect(expect_error(() => ignore(@ast.decode_range(short_range)))).to_equal(
    "$: Invalid input list",
  )
  let not_int =
    #|{"type":"integer","integer":1.5}
  let not_int_json = @json.parse(not_int)
  @expect.expect(
    expect_error(() => ignore(@ast.decode_expression(not_int_json))),
  ).to_equal("$.integer: Expecting an INT but got 1.5")
  let no_payload =
    #|{"type":"unit"}
  let no_payload_json = @json.parse(no_payload)
  @expect.expect(
    expect_error(() => ignore(@ast.decode_expression(no_payload_json))),
  ).to_equal("$: Expecting an OBJECT with a field named `unit`")
}

///|
test "decode_node prefixes inner errors with $.value" {
  let src =
    #|{"range":[1,1,1,2],"value":{"type":"var","var":{}}}
  let j = @json.parse(src)
  @expect.expect(
    expect_error(() => ignore(@ast.decode_node(j, @ast.decode_pattern))),
  ).to_equal("$.value.var: Expecting an OBJECT with a field named `value`")
}

///|
test "hex pattern accepts the encoded shape and elm-syntax's decoder shape" {
  let encoded =
    #|{"type":"hex","hex":{"value":255}}
  let bare =
    #|{"type":"hex","hex":255}
  @expect.expect(@ast.decode_pattern(@json.parse(encoded))).to_equal(
    @ast.Pattern::HexPattern(255L),
  )
  @expect.expect(@ast.decode_pattern(@json.parse(bare))).to_equal(
    @ast.Pattern::HexPattern(255L),
  )
  @expect.expect(
    @ast.encode_pattern(@ast.Pattern::HexPattern(255L)).stringify(),
  ).to_equal(encoded)
}

///|
test "numbers: large ints, hex beyond 32 bits, floats" {
  let big =
    #|{"type":"integer","integer":31536000000}
  let e = @ast.decode_expression(@json.parse(big))
  @expect.expect(e).to_equal(@ast.Expression::Integer(31536000000L))
  @expect.expect(@ast.encode_expression(e).stringify()).to_equal(big)
  let hex =
    #|{"type":"hex","hex":4294967296}
  @expect.expect(@ast.decode_expression(@json.parse(hex))).to_equal(
    @ast.Expression::Hex(4294967296L),
  )
  let tiny =
    #|{"type":"float","float":1e-7}
  @expect.expect(@ast.decode_expression(@json.parse(tiny))).to_equal(
    @ast.Expression::Floatable(1.0e-7),
  )
  // Elm `JE.float 1.0` is written as `1` by JSON.stringify; we write the same.
  @expect.expect(
    @ast.encode_expression(@ast.Expression::Floatable(1.0)).stringify(),
  ).to_equal("{\"type\":\"float\",\"float\":1}")
  @expect.expect(
    @ast.encode_expression(@ast.Expression::Floatable(9007199254740992.0)).stringify(),
  ).to_equal("{\"type\":\"float\",\"float\":9007199254740992}")
}

///|
test "chars: non-BMP and escapes round-trip" {
  let rainbow =
    #|{"type":"charLiteral","charLiteral":"🌈"}
  @expect.expect(@ast.decode_expression(@json.parse(rainbow))).to_equal(
    @ast.Expression::CharLiteral('\u{1F308}'),
  )
  @expect.expect(
    @ast.encode_expression(@ast.Expression::CharLiteral('\u{1F308}')),
  ).to_equal(
    Json::object(
      Map([
        ("type", Json::string("charLiteral")),
        ("charLiteral", Json::string("\u{1F308}")),
      ]),
    ),
  )
  let newline =
    #|{"type":"char","char":{"value":"\n"}}
  let p = @ast.decode_pattern(@json.parse(newline))
  @expect.expect(p).to_equal(@ast.Pattern::CharPattern('\n'))
  @expect.expect(@ast.encode_pattern(p).stringify()).to_equal(newline)
  let empty =
    #|{"type":"charLiteral","charLiteral":""}
  let empty_json = @json.parse(empty)
  @expect.expect(expect_error(() => ignore(@ast.decode_expression(empty_json)))).to_equal(
    "$.charLiteral: Not a char",
  )
}

///|
test "tags absent from the oracle corpus round-trip byte-exact" {
  let src =
    #|{"moduleDefinition":{"range":[1,1,1,30],"value":{"type":"port","port":{"moduleName":{"range":[1,13,1,14],"value":["P"]},"exposingList":{"range":[1,15,1,30],"value":{"type":"explicit","explicit":[{"range":[1,25,1,29],"value":{"type":"infix","infix":{"name":"+"}}}]}}}}},"imports":[{"range":[2,1,2,20],"value":{"moduleName":{"range":[2,8,2,11],"value":["A","B"]},"moduleAlias":{"range":[2,15,2,16],"value":["C"]},"exposingList":null}}],"declarations":[{"range":[3,1,3,30],"value":{"type":"port","port":{"name":{"range":[3,6,3,9],"value":"out"},"typeAnnotation":{"range":[3,12,3,30],"value":{"type":"unit","unit":{}}}}}},{"range":[4,1,4,40],"value":{"type":"infix","infix":{"direction":{"range":[4,7,4,12],"value":"non"},"precedence":{"range":[4,13,4,14],"value":4},"operator":{"range":[4,15,4,19],"value":"(==)"},"function":{"range":[4,22,4,24],"value":"eq"}}}},{"range":[5,1,5,40],"value":{"type":"function","function":{"documentation":{"range":[5,1,5,9],"value":"{-| d -}"},"signature":null,"declaration":{"range":[6,1,6,40],"value":{"name":{"range":[6,1,6,2],"value":"f"},"arguments":[{"range":[6,3,6,6],"value":{"type":"float","float":{"value":1.5}}}],"expression":{"range":[6,9,6,40],"value":{"type":"application","application":[{"range":[6,9,6,10],"value":{"type":"operator","operator":"+"}},{"range":[6,11,6,40],"value":{"type":"glsl","glsl":"void main() {}"}}]}}}}}}}],"comments":[{"range":[7,1,7,5],"value":"-- c"}]}
  let file = @ast.decode_file(@json.parse(src))
  guard file.module_definition.value is @ast.Module::PortModule(_) else {
    fail("expected a port module")
  }
  @expect.expect(@ast.encode_file(file).stringify()).to_equal(src)
}

///|
test "a non-finite float encodes as null, as elm-syntax does" {
  let e : @ast.Expression = Floatable(1.0 / 0.0)
  @expect.expect(@ast.encode_expression(e).stringify()).to_contain(
    "\"float\":null",
  )
}
