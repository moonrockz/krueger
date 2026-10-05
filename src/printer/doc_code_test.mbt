///|
/// `module A exposing (f)` with the doc comment `{-|<doc>-}` before `f`.
fn doc_module(doc : String) -> String {
  "module A exposing (f)\n\n{-|" + doc + "-}\n\n\nf =\n    1\n"
}

///|
test "code in a doc comment is formatted; indented code too" {
  let source =
    #|module A exposing (f)
    #|
    #|{-| Doc.
    #|
    #|```elm
    #|f   x =   x
    #|```
    #|
    #|    g =  1
    #|
    #|-}
    #|
    #|
    #|f x =
    #|    x
    #|
  let expected =
    #|module A exposing (f)
    #|
    #|{-| Doc.
    #|
    #|    f x =
    #|        x
    #|
    #|    g =
    #|        1
    #|
    #|-}
    #|
    #|
    #|f x =
    #|    x
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "code that does not parse stays as written" {
  let source = "module A exposing (f)\n\n{-| Doc.\n\n```elm\nf = (\n```\n\n-}\n\n\nf =\n    1\n"
  @expect.expect(@printer.format(source)).to_equal(
    "module A exposing (f)\n\n{-| Doc.\n\n    f = (\n\n-}\n\n\nf =\n    1\n",
  )
}

///|
/// Recorded with elm-format 0.8.7: the doc comment of `doc_module(input)`
/// becomes the doc comment of `doc_module(output)`.
let code_recordings : Array[(String, String)] = [
  // Declarations: one blank line between them, none after a comment.
  (
    " A.\n\n    f : Int\n    f = 1\n    g = 2\n    -- c\n    h = 3\n", " A.\n\n    f : Int\n    f =\n        1\n\n    g =\n        2\n\n    -- c\n    h =\n        3\n\n",
  ),
  (
    " A.\n\n    type alias A = Int\n    type B = B\n    {-| d -}\n    port p : Int -> Cmd msg\n",
    " A.\n\n    type alias A =\n        Int\n\n    type B\n        = B\n\n    {-| d\n    -}\n    port p : Int -> Cmd msg\n\n",
  ),
  // Expressions: each one that starts in column 1.
  (
    " A.\n\n    toString [1,2]\n    toString 3 -- n\n\n    -- c\n    x\n", " A.\n\n    toString [ 1, 2 ]\n\n    toString 3 -- n\n\n    -- c\n    x\n\n",
  ),
  // A module, with or without its header.
  (
    " A.\n\n    import Html exposing (text)\n    import Array\n\n    main =\n      text \"hi\"\n    foo = 1\n",
    " A.\n\n    import Array\n    import Html exposing (text)\n\n    main =\n        text \"hi\"\n\n    foo =\n        1\n\n",
  ),
  (
    " A.\n\n    module B exposing (x)\n    x = 1\n    y = 2\n", " A.\n\n    module B exposing (x)\n\n    x =\n        1\n\n    y =\n        2\n\n",
  ),
  (
    " Doc.\n\n    module B exposing (x)\n    import C\n    import B\n    x = 1\n\n",
    " Doc.\n\n    module B exposing (x)\n\n    import B\n    import C\n\n    x =\n        1\n\n",
  ),
  // elm-format reads no comment after the last expression: the code stays.
  (" A.\n\n    f [1,2]\n    --> x\n", " A.\n\n    f [1,2]\n    --> x\n\n"),
  (" A.\n\n    f [1,2]\n        -- x\n", " A.\n\n    f [1,2]\n        -- x\n\n"),
  (
    " A.\n\n    f [1,2]\n\n    {-\n\n    [ 1 ]\n    ╷\n    -}\n", " A.\n\n    f [1,2]\n\n    {-\n\n    [ 1 ]\n    ╷\n    -}\n\n",
  ),
  (
    " A.\n\n    f [1,2]\n    -- x\n    g [1,2]\n", " A.\n\n    f [ 1, 2 ]\n\n    -- x\n    g [ 1, 2 ]\n\n",
  ),
  (" A.\n\n    f [1,2] -- x\n", " A.\n\n    f [ 1, 2 ] -- x\n\n"),
  // Declarations that end with a comment get a blank line before them;
  // code with only comments gets two blank lines after it.
  (
    " A.\n\n    f = 1\n    -- x\n", " A.\n\n\n    f =\n        1\n\n    -- x\n\n",
  ),
  (" A.\n\n    -- x\n", " A.\n\n    -- x\n\n\n\n"),
  (
    " A.\n\n    import B\n    f = 1\n    -- x\n", " A.\n\n    import B\n\n    f =\n        1\n\n    -- x\n\n",
  ),
  // Two definitions of one name: no blank line between them.
  (
    " A.\n\n    isEmpty graph =\n        graph == empty\n    isEmpty graph =\n        size graph == 0\n",
    " A.\n\n    isEmpty graph =\n        graph == empty\n    isEmpty graph =\n        size graph == 0\n\n",
  ),
  // A module in a doc comment (elm-format `formatModule`): comments at the
  // start, then two blank lines; a body that starts with a comment gets two
  // blank lines before it.
  (
    " A.\n\n    import B\n    -- c\n    f = 1\n", " A.\n\n    import B\n\n\n    -- c\n    f =\n        1\n\n",
  ),
  (" A.\n\n    -- a\n\n    -- b\n", " A.\n\n    -- a\n    -- b\n\n\n\n"),
  (" A.\n\n    -- a\n    {- b -}\n", " A.\n\n    -- a\n\n\n\n\n    {- b -}\n\n"),
  (" A.\n\n    {- a -}\n\n    -- b\n", " A.\n\n    {- a -}\n    -- b\n\n\n\n"),
  (
    " A.\n\n    -- a\n\n    f = 1\n    -- y\n", " A.\n\n    -- a\n\n\n\n    f =\n        1\n\n    -- y\n\n",
  ),
  (
    " A.\n\n    f = 1\n\n    -- x\n\n    -- y\n", " A.\n\n\n    f =\n        1\n\n    -- x\n    -- y\n\n",
  ),
  (
    " A.\n\n    f [1,2]\n    -- x\n    f = 2\n", " A.\n\n    f [1,2]\n    -- x\n    f = 2\n\n",
  ),
  (
    " A.\n\n    module Main exposing (x)\n\n    {-|\n\n    @docs x\n\n    -}\n\n    import String\n\n    x =\n        ()\n",
    " A.\n\n    module Main exposing (x)\n\n    {-|\n\n    @docs x\n\n    -}\n\n    import String\n\n    x =\n        ()\n\n",
  ),
  // Code after a list stays fenced.
  (
    " A.\n\n  - a\n\n```\nx = 1\n```\n", " A.\n\n  - a\n\n```\nx =\n    1\n```\n\n",
  ),
]

///|
test "code in doc comments is formatted as elm-format does" {
  @expect.expect_all(s => {
    for r in code_recordings {
      let (input, output) = r
      s.expect(@printer.format(doc_module(input))).to_equal(doc_module(output))
    }
  })
}

///|
test "attributes blocks stay and doc attributes survive formatting" {
  let doc = " A.\n\n```attributes\n@derive [ Json.encoder ]\n@morphir\n    { kind = \"entity\"\n    }\n```\n\n"
  let formatted = @printer.format(doc_module(doc))
  let parsed = @parser.parse_module(
    @scanner.SourceText::new(formatted),
    @scanner.DefaultScanner::new(),
  )
  @expect.expect_all(s => {
    s.expect(formatted).to_equal(doc_module(doc))
    s.expect(parsed.attributes.length()).to_equal(1)
  })
}

///|
test "print_file formats doc comments too" {
  let source = doc_module(" A *b* and snake_case.\n\n    f x = x\n")
  let file = @parser.parse_module(
    @scanner.SourceText::new(source),
    @scanner.DefaultScanner::new(),
  ).ast.unwrap()
  @expect.expect(@printer.print_file(file)).to_equal(
    doc_module(" A _b_ and snake\\_case.\n\n    f x =\n        x\n\n"),
  )
}

///|
test "normalize_file formats doc comments" {
  let source = doc_module(" A *b*.\n")
  let file = @parser.parse_module(
    @scanner.SourceText::new(source),
    @scanner.DefaultScanner::new(),
  ).ast.unwrap()
  // The first doc comment after the header is the module documentation.
  let normalized = @printer.normalize_file(file)
  @expect.expect(normalized.comments.map(c => c.value)).to_equal([
    "{-| A _b_.\n-}",
  ])
}

///|
test "a doc comment that formatting would not close at its end stays as written" {
  // Markdown reads `{\-` and `-\}` as `{-` and `-}`, which would open or
  // close a comment: the doc comment stays exactly as written (also the
  // `*b*` that elm-format writes `_b_`).
  @expect.expect_all(s => {
    for doc in [" A *b* {\\- c.\n", " A *b* -\\} c.\n"] {
      let source = doc_module(doc)
      s.expect(@printer.format(source)).to_equal(source)
    }
  })
}
