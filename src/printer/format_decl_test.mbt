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

///|
test "comments in the parentheses of a type keep the parentheses" {
  // elm-format 0.8.7 output for each source (Parse/Type.hs tuple:
  // `TypeParens` when the parentheses hold comments). elm-syntax keeps no
  // node for these parentheses (krueger-zm5).
  @expect.expect_all(s => {
    for
      case_ in [
        (
          "type alias T =\n    (Int\n    -- c\n    )\n", "type alias T =\n    (Int\n     -- c\n    )\n",
        ),
        (
          "type alias T =\n    ( {- c -} Int)\n", "type alias T =\n    ({- c -} Int)\n",
        ),
        (
          "type alias T =\n    (Int {- c -})\n", "type alias T =\n    (Int {- c -})\n",
        ),
        (
          "type alias T =\n    (a -- c\n    )\n", "type alias T =\n    (a\n     -- c\n    )\n",
        ),
        (
          "type alias T =\n    List (Int -- c\n    )\n", "type alias T =\n    List\n        (Int\n         -- c\n        )\n",
        ),
        (
          "type alias T =\n    ({- c -} List Int)\n", "type alias T =\n    ({- c -} List Int)\n",
        ),
      ] {
      let (source, expected) = case_
      s.expect(@printer.format(decl(source))).to_equal(decl(expected))
      s.expect(@printer.format(decl(expected))).to_equal(decl(expected))
    }
  })
}

///|
test "parentheses around a function type right of an arrow stay" {
  // elm-format 0.8.7 output for each source (Box.hs FunctionType: each
  // term after `->` gets `typeParens ForLambda`). elm-syntax reads
  // `Int -> (a -> b)` as `Int -> a -> b`; the source tokens keep them
  // (krueger-05f).
  @expect.expect_all(s => {
    for
      case_ in [
        (
          "x : Int -> (Int -> Int)\nx = f\n", "x : Int -> (Int -> Int)\nx =\n    f\n",
        ),
        (
          "x : (Int -> Int) -> (Int -> Int) -> (Int -> Int)\nx = f\n", "x : (Int -> Int) -> (Int -> Int) -> (Int -> Int)\nx =\n    f\n",
        ),
        (
          "x : (Int -> (Int -> Int))\nx = f\n", "x : Int -> (Int -> Int)\nx =\n    f\n",
        ),
        ("x : Int -> (Int)\nx = f\n", "x : Int -> Int\nx =\n    f\n"),
        (
          "x : Int\n    -> (Int -> Int)\nx = f\n", "x :\n    Int\n    -> (Int -> Int)\nx =\n    f\n",
        ),
        (
          "x : Int -> ((Int -> Int))\nx = f\n", "x : Int -> (Int -> Int)\nx =\n    f\n",
        ),
        (
          "type T = C (Int -> (Int -> Int))\n", "type T\n    = C (Int -> (Int -> Int))\n",
        ),
      ] {
      let (source, expected) = case_
      s.expect(@printer.format(decl(source))).to_equal(decl(expected))
    }
  })
}

///|
test "a line comment after a function type in a signature stays on its line" {
  // elm-format 0.8.7 output for each source (Parse/Helpers.hs separated:
  // the last term of a function type takes the comment at the end of its
  // line). After another type, the comment goes after the signature.
  @expect.expect_all(s => {
    for
      case_ in [
        (
          "f :\n    State\n    -> Parser State --Result\nf state =\n    1\n", "f :\n    State\n    -> Parser State --Result\nf state =\n    1\n",
        ),
        (
          "f : Int -> Int -- c\nf = 1\n", "f :\n    Int\n    -> Int -- c\nf =\n    1\n",
        ),
        ("f : Int -- c\nf = 1\n", "f : Int\n\n\n\n-- c\n\n\nf =\n    1\n"),
        (
          "f :\n    State\n    -> Parser State {- c -}\nf state =\n    1\n", "f :\n    State\n    -> Parser State\n\n\n\n{- c -}\n\n\nf state =\n    1\n",
        ),
      ] {
      let (source, expected) = case_
      s.expect(@printer.format(decl(source))).to_equal(decl(expected))
    }
  })
}

///|
test "comments in the head of a type alias" {
  // elm-format 0.8.7 output for each source (Box.hs TypeAlias:
  // `ElmStructure.definition "=" True` of `type`, the comments and `alias`,
  // and the commented name with its arguments).
  @expect.expect_all(s => {
    for
      case_ in [
        (
          "type alias TypeAliasMultiline\n    -- A\n    a b =\n    ()\n", "type alias\n    TypeAliasMultiline\n        -- A\n        a\n        b\n    =\n    ()\n",
        ),
        (
          "type {- P -} alias {- Q -} TypeAlias2 {- R -} a {- S -} b {- T -} =\n    {- U -}\n    { x : Int, y : Int, z : ( a, b ) }\n",
          "type {- P -} alias {- Q -} TypeAlias2 {- R -} a {- S -} b {- T -} =\n    {- U -}\n    { x : Int, y : Int, z : ( a, b ) }\n",
        ),
        (
          "type\n    --P\n    alias\n    --Q\n    TypeAlias3\n        --R\n        a\n        --S\n        b\n    --T\n    =\n    --U\n    { x : Int, y : Int, z : ( a, b ) }\n",
          "type\n    --P\n    alias\n    --Q\n    TypeAlias3\n        --R\n        a\n        --S\n        b\n    --T\n    =\n    --U\n    { x : Int, y : Int, z : ( a, b ) }\n",
        ),
        (
          "type alias A -- c\n    = Int\n", "type alias\n    A\n    -- c\n    =\n    Int\n",
        ),
        (
          "type alias A a -- c\n    = Int\n", "type alias\n    A a\n    -- c\n    =\n    Int\n",
        ),
        (
          "type alias A a = {- c -} Int\n", "type alias A a =\n    {- c -}\n    Int\n",
        ),
        (
          "type alias A a {- c -} = Int\n", "type alias A a {- c -} =\n    Int\n",
        ),
        (
          "type alias A\n    -- c\n    = Int\n", "type alias\n    A\n    -- c\n    =\n    Int\n",
        ),
      ] {
      let (source, expected) = case_
      s.expect(@printer.format(decl(source))).to_equal(decl(expected))
    }
  })
}

///|
test "comments between the name of a signature and its colon" {
  // elm-format 0.8.7 output for each source (Box.hs formatTypeAnnotation:
  // `ElmStructure.definition ":" False` of the name with the comments
  // after it).
  @expect.expect_all(s => {
    for
      case_ in [
        (
          "x\n--V\n    :\n    --W\n    ()\nx =\n    ()\n", "x\n--V\n    :\n    --W\n    ()\nx =\n    ()\n",
        ),
        (
          "x\n    {- V -}\n    : ()\nx =\n    ()\n", "x {- V -} : ()\nx =\n    ()\n",
        ),
        (
          "x -- V\n    : ()\nx =\n    ()\n", "x\n-- V\n    :\n    ()\nx =\n    ()\n",
        ),
        (
          "f x =\n    let\n        y\n        -- c\n            : Int\n        y =\n            1\n    in\n    y\n",
          "f x =\n    let\n        y\n        -- c\n            :\n            Int\n        y =\n            1\n    in\n    y\n",
        ),
      ] {
      let (source, expected) = case_
      s.expect(@printer.format(decl(source))).to_equal(decl(expected))
    }
  })
}

///|
test "comments between a record type field and its colon, and around a record base" {
  // elm-format's own test file AllSyntax/LineComments/Types.elm (elm-format
  // 0.8.7 leaves it as it is; Box.hs formatPair and formatRecordLike).
  let source =
    #|record :
    #|    { --N
    #|      x :
    #|        --P
    #|        Int
    #|
    #|    --Q
    #|    , --R
    #|      y
    #|      --S
    #|        :
    #|        --T
    #|        ()
    #|
    #|    --U
    #|    }
    #|    -> ()
    #|record _ =
    #|    ()
    #|
    #|
    #|recordExtension :
    #|    { --V
    #|      a
    #|      --W
    #|        | --X
    #|          x
    #|          --Y
    #|            :
    #|            --Z
    #|            Int
    #|
    #|        --AA
    #|        , --AB
    #|          y
    #|          --AC
    #|            :
    #|            --AD
    #|            Int
    #|
    #|        --AE
    #|    }
    #|    -> ()
    #|recordExtension _ =
    #|    ()
    #|
  @expect.expect(@printer.format(decl(source))).to_equal(decl(source))
}
