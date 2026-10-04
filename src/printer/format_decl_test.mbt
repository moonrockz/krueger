///|
test "type alias record on one line, and broken" {
  @expect.expect_all(s => {
    s
    .expect(
      @printer.format(
        "module A exposing (..)\n\n\ntype alias R = { a : Int, b : Int }\n",
      ),
    )
    .to_equal(
      "module A exposing (..)\n\n\ntype alias R =\n    { a : Int, b : Int }\n",
    )
    s
    .expect(
      @printer.format(
        "module A exposing (..)\n\n\ntype alias R2 = { a : Int\n  , b : Int }\n",
      ),
    )
    .to_equal(
      "module A exposing (..)\n\n\ntype alias R2 =\n    { a : Int\n    , b : Int\n    }\n",
    )
  })
}

///|
test "a broken signature puts each arrow on its own line" {
  @expect.expect(
    @printer.format(
      "module A exposing (..)\n\n\nf : Int -> Int\n  -> Int\nf a b = a\n",
    ),
  ).to_equal(
    "module A exposing (..)\n\n\nf :\n    Int\n    -> Int\n    -> Int\nf a b =\n    a\n",
  )
}

///|
fn decl(lines : String) -> String {
  "module A exposing (..)\n\n\n" + lines
}

///|
test "a multi-line record before an arrow breaks the signature" {
  @expect.expect(
    @printer.format(decl("g : { a : Int\n  , b : Int } -> Int\ng x = 1\n")),
  ).to_equal(
    decl("g :\n    { a : Int\n    , b : Int\n    }\n    -> Int\ng x =\n    1\n"),
  )
}

///|
test "a multi-line type after an arrow goes on the next line" {
  // elm-format ElmStructure.prefixOrIndented: `->` alone, then the type at
  // the next tab stop.
  @expect.expect(
    @printer.format(decl("h : Int -> { a : Int\n  , b : Int }\nh x = 1\n")),
  ).to_equal(
    decl(
      "h :\n    Int\n    ->\n        { a : Int\n        , b : Int\n        }\nh x =\n    1\n",
    ),
  )
}

///|
test "a broken type application puts each argument on its own line" {
  @expect.expect(@printer.format(decl("i : Maybe\n  Int\ni = 1\n"))).to_equal(
    decl("i :\n    Maybe\n        Int\ni =\n    1\n"),
  )
}

///|
test "a broken tuple type" {
  @expect.expect(@printer.format(decl("j : ( Int,\n  Int ) -> Int\nj = 1\n"))).to_equal(
    decl("j :\n    ( Int\n    , Int\n    )\n    -> Int\nj =\n    1\n"),
  )
}

///|
test "a broken function type in parentheses" {
  @expect.expect(@printer.format(decl("o : (Int\n  -> Int) -> Int\no = 1\n"))).to_equal(
    decl("o :\n    (Int\n     -> Int\n    )\n    -> Int\no =\n    1\n"),
  )
}

///|
test "constructors with multi-line arguments" {
  @expect.expect(
    @printer.format(
      decl("type T = A { a : Int\n  , b : Int } Int | B (Maybe\n  Int)\n"),
    ),
  ).to_equal(
    decl(
      "type T\n    = A\n        { a : Int\n        , b : Int\n        }\n        Int\n    | B\n        (Maybe\n            Int\n        )\n",
    ),
  )
}

///|
test "a broken port signature" {
  @expect.expect(
    @printer.format(
      "port module A exposing (..)\n\n\nport n : Int\n  -> Cmd msg\n",
    ),
  ).to_equal(
    "port module A exposing (..)\n\n\nport n :\n    Int\n    -> Cmd msg\n",
  )
}

///|
test "a broken record type field" {
  @expect.expect(
    @printer.format(decl("type alias R =\n    { a :\n        Int, b : Int }\n")),
  ).to_equal(
    decl("type alias R =\n    { a :\n        Int\n    , b : Int\n    }\n"),
  )
}

///|
test "an extensible record type with a break" {
  @expect.expect(
    @printer.format(decl("type alias R a = { a | b : Int\n  , c : Int }\n")),
  ).to_equal(
    decl(
      "type alias R a =\n    { a\n        | b : Int\n        , c : Int\n    }\n",
    ),
  )
}

///|
test "patterns stay on one line" {
  // elm-format Box.hs formatPattern: tuple, list and record patterns have
  // no source rule.
  @expect.expect(
    @printer.format(
      decl(
        "k x =\n  case x of\n    ( a,\n      b ) -> 1\n    [ a,\n      b ] -> 1\n",
      ),
    ),
  ).to_equal(
    decl(
      "k x =\n    case x of\n        ( a, b ) ->\n            1\n\n        [ a, b ] ->\n            1\n",
    ),
  )
}

///|
test "import exposing list with a break" {
  @expect.expect_all(s => {
    s
    .expect(
      @printer.format(
        "module A exposing (..)\n\nimport B exposing (a, b,\n  c)\n\n\nx =\n    1\n",
      ),
    )
    .to_equal(
      "module A exposing (..)\n\nimport B\n    exposing\n        ( a\n        , b\n        , c\n        )\n\n\nx =\n    1\n",
    )
    s
    .expect(
      @printer.format(
        "module A exposing (..)\n\nimport C exposing (a, b, c)\nimport D as E exposing (a,\n  b)\n\n\nx =\n    1\n",
      ),
    )
    .to_equal(
      "module A exposing (..)\n\nimport C exposing (a, b, c)\nimport D as E\n    exposing\n        ( a\n        , b\n        )\n\n\nx =\n    1\n",
    )
  })
}
