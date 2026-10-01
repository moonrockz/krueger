///|
fn attributes_of(text : String) -> ParseResult {
  let source = @scanner.SourceText::{ module_name: Some("Bank"), text, }
  guard @scanner.DefaultScanner::new().tokenize(source) is Ok(tokens) else {
    abort("scan error")
  }
  parse_tokens(tokens)
}

///|
let bank : String = "module Bank exposing (..)\n\n{-| Bank. -}\n\n\n"

///|
test "attribute ranges are file positions in code points" {
  @expect.expect_all(s => {
    let result = attributes_of(
      bank + "{-| Account.\n\n@x \"😀😀\" 1\n-}\naccount =\n    1\n",
    )
    guard result.attributes
      is [{ attributes: [Attribute(name~, arguments~, range~)], .. }] else {
      fail("expected one attribute")
    }
    s
    .expect(name.range)
    .to_equal({ start: { row: 8, column: 2, }, end: { row: 8, column: 3, }, })
    // `@x "😀😀" 1` is 9 code points long.
    s.expect(range.end).to_equal({ row: 8, column: 10, })
    s
    .expect(arguments.map(a => a.range.start))
    .to_equal([{ row: 8, column: 4, }, { row: 8, column: 9, }])
  })
}

///|
test "docs names have their own ranges" {
  let result = attributes_of(
    "module Bank exposing (a, b)\n\n{-| Bank.\n\n@docs a, b\n\n-}\n\n\na =\n    1\n\n\nb =\n    2\n",
  )
  guard result.attributes
    is [{ target: Module, attributes: [Docs(names~, ..)], }] else {
    fail("expected the docs list")
  }
  @expect.expect(names.map(n => (n.value, n.range.start.column))).to_equal([
    ("a", 7),
    ("b", 10),
  ])
}

///|
test "encode_attributes gives the target, name, range and values" {
  @expect.expect_all(s => {
    let result = attributes_of(
      bank + "{-| Account.\n\n@unit \"EUR\"\n-}\naccount =\n    1\n",
    )
    let json = encode_attributes(result.attributes).stringify()
    s.expect(json).to_contain("\"declaration\":\"account\"")
    s.expect(json).to_contain("\"value\":\"unit\"")
    s.expect(json).to_contain("\"literal\":\"EUR\"")
    s.expect(json).to_contain("\"range\":[8,1,8,12]")
  })
}

///|
test "warnings inside values are kept" {
  let result = attributes_of(
    bank + "{-| Account.\n\n@big 99999999999999999999\n-}\naccount =\n    1\n",
  )
  @expect.expect(result.diagnostics.map(d => d.code)).to_equal(["KR-PARSE-009"])
}

///|
test "other fences and a fence on the first line hold no attributes" {
  @expect.expect_all(s => {
    for
      doc in [
        "{-| ```\n@x 1\n``` Done.\n\n@ok 1\n-}", "{-| Account.\n\n~~~\n@x 1\n~~~\n\n@ok 1\n-}",
        "{-| Account.\n\n  ```\n@x 1\n  ```\n\n@ok 1\n-}",
      ] {
      let result = attributes_of(bank + doc + "\naccount =\n    1\n")
      guard result.attributes is [{ attributes: [Attribute(name~, ..)], .. }] else {
        fail("expected only @ok in \{doc}")
      }
      s.expect(name.value).to_equal("ok")
      s.expect(result.diagnostics).to_equal([])
    }
  })
}
