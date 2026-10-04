// Every expected text in this file is the output of elm-format 0.8.7 for
// the source (`elm-format --stdin --elm-version=0.19`), unless a comment
// says otherwise.

///|
test "exposing without @docs is sorted: operators, types, values" {
  @expect.expect(
    @printer.format(
      "module A exposing (b, a, C)\n\nimport Z\nimport B exposing (z, y)\n\n\na =\n    1\n\n\nb =\n    2\n",
    ),
  ).to_equal(
    "module A exposing (C, a, b)\n\nimport B exposing (y, z)\nimport Z\n\n\na =\n    1\n\n\nb =\n    2\n",
  )
}

///|
test "exposing is grouped by @docs lines" {
  let source =
    #|module A exposing (z, y, x, T, (</>))
    #|
    #|{-| Module doc.
    #|
    #|@docs x, z
    #|@docs T
    #|
    #|-}
    #|
    #|
    #|x =
    #|    1
    #|
  let expected =
    #|module A exposing
    #|    ( x, z
    #|    , T
    #|    , (</>), y
    #|    )
    #|
    #|{-| Module doc.
    #|
    #|@docs x, z
    #|@docs T
    #|
    #|-}
    #|
    #|
    #|x =
    #|    1
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "@docs: a name keeps its first group; operators of one or two characters match" {
  let source =
    #|module A exposing (z, y, x, T(..), (+), (</>), (<?>), x, T)
    #|
    #|{-| Module doc.
    #|
    #|@docs x, z, (+), (</>), (<?>)
    #|@docs T, y
    #|@docs y
    #|
    #|-}
    #|
    #|
    #|x =
    #|    1
    #|
  let expected =
    #|module A exposing
    #|    ( x, z, (+)
    #|    , T(..), y
    #|    , (</>), (<?>)
    #|    )
    #|
    #|{-| Module doc.
    #|
    #|@docs x, z, (+), (</>), (<?>)
    #|@docs T, y
    #|@docs y
    #|
    #|-}
    #|
    #|
    #|x =
    #|    1
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "@docs: `T(..)` names no exposed item" {
  let source =
    #|module A exposing (z, y, x, T(..))
    #|
    #|{-| Module doc.
    #|
    #|@docs x, z
    #|@docs T(..), y
    #|
    #|-}
    #|
    #|
    #|x =
    #|    1
    #|
  // elm-format also rewrites the doc line to `@docs T, y`; krueger keeps
  // the documentation text as it is (bd krueger-3u6).
  let expected =
    #|module A exposing
    #|    ( x, z
    #|    , y
    #|    , T(..)
    #|    )
    #|
    #|{-| Module doc.
    #|
    #|@docs x, z
    #|@docs T(..), y
    #|
    #|-}
    #|
    #|
    #|x =
    #|    1
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "@docs lines in code blocks, lists, quotes and headers do not group" {
  let source =
    #|module A exposing (a, b, c, d, e, f, g, h, i)
    #|
    #|{-| Module doc.
    #|Some text
    #|
    #|@docs i
    #|@docs h
    #|@docs b, c
    #|
    #|    @docs a
    #|
    #|    @docs d
    #|
    #|  - @docs e
    #|
    #|> @docs f
    #|
    #|@docs g
    #|
    #|-}
    #|
    #|
    #|x =
    #|    1
    #|
  let expected =
    #|module A exposing
    #|    ( i
    #|    , h
    #|    , b, c
    #|    , g
    #|    , a, d, e, f
    #|    )
    #|
    #|{-| Module doc.
    #|Some text
    #|
    #|@docs i
    #|@docs h
    #|@docs b, c
    #|
    #|    @docs a
    #|
    #|    @docs d
    #|
    #|  - @docs e
    #|
    #|> @docs f
    #|
    #|@docs g
    #|
    #|-}
    #|
    #|
    #|x =
    #|    1
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "@docs: indented lines, continuation lines and fenced code" {
  let source =
    #|module A exposing (a, b, c, d, e, f, g)
    #|
    #|{-| Doc
    #|
    #|@docs a
    #|  @docs b
    #|
    #|  @docs c
    #|
    #|@docs d
    #|    e
    #|
    #|```
    #|@docs f
    #|```
    #|
    #|# @docs g
    #|
    #|-}
    #|
    #|
    #|a =
    #|    1
    #|
  // elm-format output for this source, without its changes to the
  // documentation text (krueger keeps it as it is).
  let expected =
    #|module A exposing
    #|    ( a
    #|    , b
    #|    , c
    #|    , d
    #|    , e
    #|    , f, g
    #|    )
    #|
    #|{-| Doc
    #|
    #|@docs a
    #|  @docs b
    #|
    #|  @docs c
    #|
    #|@docs d
    #|    e
    #|
    #|```
    #|@docs f
    #|```
    #|
    #|# @docs g
    #|
    #|-}
    #|
    #|
    #|a =
    #|    1
    #|
  // Fences with an info string after a space, and a closing fence with
  // text after it: elm-format (Cheapskate) closes a fence with any line
  // that starts with it. The headers are elm-format's output; the doc
  // text stays as it is.
  let fenced = (doc : String) => {
    "module A exposing (a, b, c, x, y, z)\n\n{-| Doc\n\n\{doc}\n-}\n\n\na =\n    1\n"
  }
  let header = "module A exposing\n    ( b\n    , c\n    , a, x, y, z\n    )\n\n"
  @expect.expect_all(s => {
    s.expect(@printer.format(source)).to_equal(expected)
    for
      doc in [
        "~~~ elm\n@docs x\n~~~\n\n@docs b\n@docs c\n", "``` elm\n@docs x\n```\n\n@docs b\n@docs c\n",
      ] {
      let text = fenced(doc)
      let rest = text.view(start_offset=text.find("{-|").unwrap()).to_owned()
      s.expect(@printer.format(text)).to_equal(header + rest)
    }
    let text = "module A exposing (a, b, c)\n\n{-| Doc\n\n```\n@docs a\n```x\n@docs b\n```\n\n@docs c\n\n-}\n\n\na =\n    1\n"
    let rest = text.view(start_offset=text.find("{-|").unwrap()).to_owned()
    s
    .expect(@printer.format(text))
    .to_equal("module A exposing\n    ( b\n    , a, c\n    )\n\n" + rest)
  })
}

///|
test "exposing without @docs: a multi-line list puts each item on its own line" {
  @expect.expect_all(s => {
    s
    .expect(@printer.format("module A exposing (b,\n  a, C)\n\n\na =\n    1\n"))
    .to_equal(
      "module A exposing\n    ( C\n    , a\n    , b\n    )\n\n\na =\n    1\n",
    )
    s
    .expect(@printer.format("module A exposing (b\n  )\n\n\nb =\n    1\n"))
    .to_equal("module A exposing (b)\n\n\nb =\n    1\n")
  })
}

///|
test "exposing: duplicates are removed and `T` joins `T(..)`" {
  @expect.expect(
    @printer.format("module A exposing (a, T, a, T(..), b)\n\n\na =\n    1\n"),
  ).to_equal("module A exposing (T(..), a, b)\n\n\na =\n    1\n")
}

///|
test "effect module: exposing is grouped by @docs lines" {
  let dialect = @dialect.Dialect::elm_syntax_7_3_9()
  let source =
    #|effect module Task where { command = MyCmd } exposing (b, a, c)
    #|
    #|{-| Module doc.
    #|
    #|@docs a, b
    #|@docs c
    #|
    #|-}
    #|
    #|
    #|a =
    #|    1
    #|
  let expected =
    #|effect module Task where { command = MyCmd } exposing
    #|    ( a, b
    #|    , c
    #|    )
    #|
    #|{-| Module doc.
    #|
    #|@docs a, b
    #|@docs c
    #|
    #|-}
    #|
    #|
    #|a =
    #|    1
    #|
  @expect.expect(@printer.format(source, dialect~)).to_equal(expected)
}

///|
test "effect module: a multi-line exposing list puts each item on its own line" {
  let dialect = @dialect.Dialect::elm_syntax_7_3_9()
  let source =
    #|effect module Task where { command = MyCmd } exposing (b, a,
    #|  c)
    #|
    #|
    #|a =
    #|    1
    #|
  let expected =
    #|effect module Task where { command = MyCmd } exposing
    #|    ( a
    #|    , b
    #|    , c
    #|    )
    #|
    #|
    #|a =
    #|    1
    #|
  @expect.expect(@printer.format(source, dialect~)).to_equal(expected)
}

///|
test "exposing: comments of items in a @docs group go after the list" {
  let source =
    #|module A exposing
    #|    ( a -- ca
    #|    , b {- cb -}
    #|    , {- cc -} c
    #|    , d
    #|    -- cd
    #|    , e
    #|    )
    #|
    #|{-| Module doc.
    #|
    #|@docs a, b, c
    #|
    #|-}
    #|
    #|
    #|x =
    #|    1
    #|
  let expected =
    #|module A exposing
    #|    ( a, b, c
    #|    , d, e
    #|      -- cd
    #|    -- ca
    #|    {- cb -}
    #|    {- cc -}
    #|    )
    #|
    #|{-| Module doc.
    #|
    #|@docs a, b, c
    #|
    #|-}
    #|
    #|
    #|x =
    #|    1
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "exposing: comments of other items stay with their group" {
  let source =
    #|module A exposing (c, {- x -} b, a {- y -})
    #|
    #|{-| Module doc.
    #|
    #|@docs a
    #|
    #|-}
    #|
    #|
    #|x =
    #|    1
    #|
  let expected =
    #|module A exposing
    #|    ( a
    #|    , {- x -} b, c
    #|    {- y -}
    #|    )
    #|
    #|{-| Module doc.
    #|
    #|@docs a
    #|
    #|-}
    #|
    #|
    #|x =
    #|    1
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "exposing: comments move with their item" {
  @expect.expect_all(s => {
    s
    .expect(
      @printer.format(
        "module A exposing (c, {- x -} b, a {- y -})\n\n\nx =\n    1\n",
      ),
    )
    .to_equal("module A exposing (a {- y -}, {- x -} b, c)\n\n\nx =\n    1\n")
    s
    .expect(
      @printer.format("module A exposing (b -- x\n  , a)\n\n\na =\n    1\n"),
    )
    .to_equal(
      "module A exposing\n    ( a\n    , b\n      -- x\n    )\n\n\na =\n    1\n",
    )
    s
    .expect(
      @printer.format(
        "module A exposing ( {- p -} b, a {- q -}\n  -- r\n  )\n\n\na =\n    1\n",
      ),
    )
    .to_equal(
      "module A exposing\n    ( a\n      {- q -}\n      -- r\n    , {- p -} b\n    )\n\n\na =\n    1\n",
    )
  })
}

///|
test "exposing: a comment after the list with every item in one @docs group" {
  // elm-format writes `module A exposing (a, b, {- y -})` for the first
  // source, which is not valid Elm. krueger uses the multi-line form that
  // elm-format gives for a line comment (the second source).
  let doc = "{-| Module doc.\n\n@docs a, b\n\n-}\n\n\na =\n    1\n"
  @expect.expect_all(s => {
    s
    .expect(@printer.format("module A exposing (b {- y -}, a)\n\n\{doc}"))
    .to_equal(
      "module A exposing\n    ( a\n    , b\n    {- y -}\n    )\n\n\{doc}",
    )
    s
    .expect(@printer.format("module A exposing (b, a -- y\n  )\n\n\{doc}"))
    .to_equal("module A exposing\n    ( a\n    , b\n    -- y\n    )\n\n\{doc}")
  })
}

///|
test "imports: exposing lists sorted, comments move with their item" {
  let source =
    #|module A exposing (a)
    #|
    #|import B exposing (b {- x -}, a)
    #|import C exposing (c -- y
    #|  , {- z -} a)
    #|import D exposing (b,
    #|  a)
    #|import E exposing ((+), T, a, U(..))
    #|
    #|
    #|a =
    #|    1
    #|
  let expected =
    #|module A exposing (a)
    #|
    #|import B exposing (a, b {- x -})
    #|import C
    #|    exposing
    #|        ( {- z -} a
    #|        , c
    #|          -- y
    #|        )
    #|import D
    #|    exposing
    #|        ( a
    #|        , b
    #|        )
    #|import E exposing ((+), T, U(..), a)
    #|
    #|
    #|a =
    #|    1
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "imports: duplicates merge; a later alias wins; an alias equal to the name goes" {
  let source =
    #|module A exposing (a)
    #|
    #|import B as C
    #|import B as D
    #|import X exposing (a)
    #|import X as Y exposing (b, T)
    #|import X exposing (T(..))
    #|import Z exposing (..)
    #|import Z exposing (z)
    #|import Fifo as Fifo exposing (Fifo)
    #|
    #|
    #|a =
    #|    1
    #|
  let expected =
    #|module A exposing (a)
    #|
    #|import B as D
    #|import Fifo exposing (Fifo)
    #|import X as Y exposing (T(..), a, b)
    #|import Z exposing (..)
    #|
    #|
    #|a =
    #|    1
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "imports: comments in merged imports are kept" {
  @expect.expect_all(s => {
    s
    .expect(
      @printer.format(
        "module A exposing (a)\n\nimport B as C\nimport B {- c -} as D\n\n\na =\n    1\n",
      ),
    )
    .to_equal(
      "module A exposing (a)\n\nimport B {- c -} as D\n\n\na =\n    1\n",
    )
    s
    .expect(
      @printer.format(
        "module A exposing (a)\n\nimport B exposing (x)\nimport B exposing (y {- c -})\n\n\na =\n    1\n",
      ),
    )
    .to_equal(
      "module A exposing (a)\n\nimport B exposing (x, y {- c -})\n\n\na =\n    1\n",
    )
    s
    .expect(
      @printer.format(
        "module A exposing (a)\n\nimport B exposing (x)\nimport B {- c -} exposing (y)\n\n\na =\n    1\n",
      ),
    )
    .to_equal(
      "module A exposing (a)\n\nimport B {- c -} exposing (x, y)\n\n\na =\n    1\n",
    )
  })
}

///|
test "imports: other comments of merged imports are kept" {
  // Not elm-format output: elm-format writes
  // `import\n    B\n        -- c\n        as\n            D` for the first
  // source and drops the comment of the second. krueger never drops a
  // comment: one of a removed node goes before the imports.
  @expect.expect_all(s => {
    s
    .expect(
      @printer.format(
        "module A exposing (a)\n\nimport B as C\nimport B -- c\n    as D\n\n\na =\n    1\n",
      ),
    )
    .to_equal(
      "module A exposing (a)\n\n-- c\n\nimport B as D\n\n\na =\n    1\n",
    )
    s
    .expect(
      @printer.format(
        "module A exposing (a)\n\nimport B as {- c -}\n    C\nimport B as D\n\n\na =\n    1\n",
      ),
    )
    .to_equal(
      "module A exposing (a)\n\n{- c -}\n\nimport B as D\n\n\na =\n    1\n",
    )
    // elm-format drops `{- c -}` with the replaced alias `C`.
    s
    .expect(
      @printer.format(
        "module A exposing (a)\n\nimport B as {- c -} C exposing (x)\nimport B as D\n\n\na =\n    1\n",
      ),
    )
    .to_equal(
      "module A exposing (a)\n\n{- c -}\n\nimport B as D exposing (x)\n\n\na =\n    1\n",
    )
    // elm-format output: the alias stays, and so does its comment.
    s
    .expect(
      @printer.format(
        "module A exposing (a)\n\nimport B as {- c -} C\nimport B exposing (x)\n\n\na =\n    1\n",
      ),
    )
    .to_equal(
      "module A exposing (a)\n\nimport B as {- c -} C exposing (x)\n\n\na =\n    1\n",
    )
  })
}

///|
test "Width layout and print_file sort the exposing list and the imports" {
  let source =
    #|module A exposing (z, y, x)
    #|
    #|{-| Module doc.
    #|
    #|@docs x, z
    #|
    #|-}
    #|
    #|import Z
    #|import B exposing (z, y)
    #|
    #|
    #|x =
    #|    1
    #|
  let expected =
    #|module A exposing
    #|    ( x, z
    #|    , y
    #|    )
    #|
    #|{-| Module doc.
    #|
    #|@docs x, z
    #|
    #|-}
    #|
    #|import B exposing (y, z)
    #|import Z
    #|
    #|
    #|x =
    #|    1
    #|
  let file = @parser.parse_module(
    @scanner.SourceText::new(source),
    @scanner.DefaultScanner::new(),
  ).ast.unwrap()
  @expect.expect_all(s => {
    s.expect(@printer.format(source, layout=Width(120))).to_equal(expected)
    s.expect(@printer.print_file(file)).to_equal(expected)
  })
}

///|
test "Width layout: a group from a @docs line stays on one line" {
  // elm-format output for this source: it never breaks a `@docs` group.
  let source =
    #|module A exposing (beta, alpha, gamma)
    #|
    #|{-| Module doc.
    #|
    #|@docs gamma, beta, alpha
    #|
    #|-}
    #|
    #|
    #|alpha =
    #|    1
    #|
  let expected =
    #|module A exposing (gamma, beta, alpha)
    #|
    #|{-| Module doc.
    #|
    #|@docs gamma, beta, alpha
    #|
    #|-}
    #|
    #|
    #|alpha =
    #|    1
    #|
  @expect.expect_all(s => {
    s.expect(@printer.format(source)).to_equal(expected)
    s.expect(@printer.format(source, layout=Width(20))).to_equal(expected)
  })
}

///|
test "imports: comments of a list that `(..)` replaces are kept" {
  // Not elm-format output: elm-format drops `{- c -}`. krueger never drops
  // a comment: one of a removed node goes before the imports.
  @expect.expect(
    @printer.format(
      "module A exposing (a)\n\nimport B exposing (x {- c -})\nimport B exposing (..)\n\n\na =\n    1\n",
    ),
  ).to_equal(
    "module A exposing (a)\n\n{- c -}\n\nimport B exposing (..)\n\n\na =\n    1\n",
  )
}

///|
test "effect module: a comment before the list stays on the line" {
  let dialect = @dialect.Dialect::elm_syntax_7_3_9()
  @expect.expect(
    @printer.format(
      "effect module Task where { command = MyCmd } exposing {- e -} (b, a)\n\n\na =\n    1\n",
      dialect~,
    ),
  ).to_equal(
    "effect module Task where { command = MyCmd } exposing {- e -} (a, b)\n\n\na =\n    1\n",
  )
}

///|
/// The AST of `text`, or `None` when it has a diagnostic with severity
/// `Error`.
fn header_ast(text : String) -> @ast.File? {
  let result = @parser.parse_module(
    @scanner.SourceText::new(text),
    @scanner.DefaultScanner::new(),
  )
  if result.diagnostics.iter().any(d => d.severity is Error) {
    None
  } else {
    result.ast
  }
}

///|
test "law: normalize_file is idempotent" {
  @quickcheck.check(
    (m : @lawkit.ElmHeader) => {
      guard header_ast(m.text()) is Some(file) else { return false }
      let once = @printer.normalize_file(file)
      @printer.normalize_file(once) == once
    },
    count=200,
    max_size=20,
    seed=2031,
  )
}

///|
test "law: format and print_file give the text of normalize_file" {
  @quickcheck.check(
    (m : @lawkit.ElmHeader) => {
      guard header_ast(m.text()) is Some(file) else { return false }
      let expected = @lawkit.without_ranges(@printer.normalize_file(file))
      let formatted = try @printer.format(m.text()) catch {
        _ => return false
      } noraise {
        t => t
      }
      let printed = try @printer.print_file(file) catch {
        _ => return false
      } noraise {
        t => t
      }
      guard header_ast(formatted) is Some(a) else { return false }
      guard header_ast(printed) is Some(b) else { return false }
      @lawkit.without_ranges(a) == expected &&
      @lawkit.without_ranges(b) == expected
    },
    count=200,
    max_size=20,
    seed=2032,
  )
}

///|
test "law: format is idempotent on headers and imports" {
  @quickcheck.check(
    (m : @lawkit.ElmHeader) => {
      let once = try @printer.format(m.text()) catch {
        _ => return false
      } noraise {
        t => t
      }
      let twice = try @printer.format(once) catch {
        _ => return false
      } noraise {
        t => t
      }
      once == twice
    },
    count=200,
    max_size=20,
    seed=2033,
  )
}
