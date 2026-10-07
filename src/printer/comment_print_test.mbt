///|
test "a comment on its own line before an expression stays above it" {
  let source = "module A exposing (g)\n\n\ng =\n    -- lead\n    1 {- inline -} + 2\n"
  @expect.expect(@printer.format(source)).to_equal(source)
}

///|
test "a comment after a list item stays after it, and the list breaks" {
  let source = "module A exposing (r)\n\n\nr =\n    [ a -- x\n    ]\n"
  @expect.expect(@printer.format(source)).to_equal(source)
}

///|
test "comments between top-level items keep elm-format's blank lines" {
  let source =
    #|module A exposing (a)
    #|
    #|-- top comment
    #|
    #|import Html
    #|
    #|
    #|a =
    #|    1
    #|
    #|
    #|
    #|-- end
    #|
  @expect.expect(@printer.format(source)).to_equal(source)
}

///|
test "a trailing comment after a case branch moves before the next branch" {
  let source =
    #|module A exposing (f)
    #|
    #|
    #|f x =
    #|  case x of
    #|    -- c1
    #|    1 -> a -- c2
    #|    _ -> b
    #|
  let expected =
    #|module A exposing (f)
    #|
    #|
    #|f x =
    #|    case x of
    #|        -- c1
    #|        1 ->
    #|            a
    #|
    #|        -- c2
    #|        _ ->
    #|            b
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "Width layout keeps comments too" {
  let source = "module A exposing (g)\n\n\ng =\n    -- lead\n    1\n"
  @expect.expect(@printer.format(source, layout=Width(120))).to_equal(source)
}

///|
test "CRLF source gives the same output as LF" {
  let lf = "module A exposing (g)\n\n\ng =\n    -- lead\n    1\n"
  @expect.expect(@printer.format(lf.replace_all(old="\n", new="\r\n"))).to_equal(
    lf,
  )
}

///|
test "elm-format: imports gather their comments above them, and body comments form blocks" {
  let source =
    #|module A exposing (a)
    #|
    #|import B -- ib
    #|import C
    #|-- before d
    #|import D
    #|
    #|-- x
    #|
    #|
    #|-- y
    #|a =
    #|    1
    #|-- after a
    #|
    #|
    #|{- block -}
    #|b = 2
    #|
    #|
    #|
    #|-- before c
    #|
    #|-- before c2
    #|c = 3
    #|-- end1
    #|
    #|-- end2
    #|
  let expected =
    #|module A exposing (a)
    #|
    #|-- ib
    #|-- before d
    #|
    #|import B
    #|import C
    #|import D
    #|
    #|
    #|
    #|-- x
    #|-- y
    #|
    #|
    #|a =
    #|    1
    #|
    #|
    #|
    #|-- after a
    #|{- block -}
    #|
    #|
    #|b =
    #|    2
    #|
    #|
    #|
    #|-- before c
    #|-- before c2
    #|
    #|
    #|c =
    #|    3
    #|
    #|
    #|
    #|-- end1
    #|-- end2
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "elm-format: comments before the header, after it, and after declarations" {
  let source =
    #|-- initial
    #|module A exposing (a) -- mod trailing
    #|
    #|-- before a
    #|a = 1 -- t
    #|b : Int -- sig
    #|b = 2
    #|
  let expected =
    #|-- initial
    #|
    #|
    #|module A exposing (a)
    #|
    #|-- mod trailing
    #|-- before a
    #|
    #|
    #|a =
    #|    1
    #|
    #|
    #|
    #|-- t
    #|
    #|
    #|b : Int
    #|
    #|
    #|
    #|-- sig
    #|
    #|
    #|b =
    #|    2
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "elm-format: comments in a let move before the next declaration or before in" {
  let source =
    #|module A exposing (a)
    #|
    #|
    #|a =
    #|    let
    #|        -- c
    #|        x = 1 -- t
    #|
    #|        -- d
    #|        y = 2
    #|        -- before in
    #|    in
    #|    -- body
    #|    x
    #|
  let expected =
    #|module A exposing (a)
    #|
    #|
    #|a =
    #|    let
    #|        -- c
    #|        x =
    #|            1
    #|
    #|        -- t
    #|        -- d
    #|        y =
    #|            2
    #|
    #|        -- before in
    #|    in
    #|    -- body
    #|    x
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "elm-format: comments in a record stay after a field or go before its comma" {
  let source =
    #|module A exposing (a)
    #|
    #|
    #|a =
    #|    { a = 1 -- c
    #|    , b = 2
    #|    -- own
    #|    , c = 3
    #|    }
    #|
  let expected =
    #|module A exposing (a)
    #|
    #|
    #|a =
    #|    { a = 1 -- c
    #|    , b = 2
    #|
    #|    -- own
    #|    , c = 3
    #|    }
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "elm-format: comments of constructors and record type fields" {
  let source =
    #|module A exposing (a)
    #|
    #|
    #|type T
    #|    = A -- ca
    #|    -- own
    #|    | B Int
    #|
    #|
    #|type alias R =
    #|    { a : Int -- c
    #|    , b : Int
    #|    }
    #|
  let expected =
    #|module A exposing (a)
    #|
    #|
    #|type T
    #|    = A -- ca
    #|      -- own
    #|    | B Int
    #|
    #|
    #|type alias R =
    #|    { a : Int -- c
    #|    , b : Int
    #|    }
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "elm-format: comments before a closing bracket follow a blank line" {
  let source =
    #|module A exposing (r)
    #|
    #|
    #|r =
    #|    [ 1
    #|    -- p
    #|    -- q
    #|    ]
    #|
  let expected =
    #|module A exposing (r)
    #|
    #|
    #|r =
    #|    [ 1
    #|
    #|    -- p
    #|    -- q
    #|    ]
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "elm-format: a comment after a comma stays after it" {
  let source =
    #|module A exposing (a)
    #|
    #|
    #|a =
    #|    [ a, -- c
    #|      b
    #|    ]
    #|
  let expected =
    #|module A exposing (a)
    #|
    #|
    #|a =
    #|    [ a
    #|    , -- c
    #|      b
    #|    ]
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "elm-format: comments before an operator, and after it" {
  let source =
    #|module A exposing (a)
    #|
    #|
    #|a =
    #|    b
    #|        |> f
    #|        -- |> g
    #|        |> h
    #|        || -- c
    #|           (d == 1)
    #|
  @expect.expect(@printer.format(source)).to_equal(source)
}

///|
test "elm-format: a line comment in an empty record or list" {
  let source =
    #|module A exposing (a)
    #|
    #|
    #|f : { --M
    #|    } -> ()
    #|f _ =
    #|    ()
    #|
    #|
    #|g =
    #|    [ -- p
    #|    ]
    #|
  let expected =
    #|module A exposing (a)
    #|
    #|
    #|f :
    #|    { --M
    #|    }
    #|    -> ()
    #|f _ =
    #|    ()
    #|
    #|
    #|g =
    #|    [-- p
    #|    ]
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "elm-format: effect module: a line comment after a where field" {
  let dialect = @dialect.Dialect::elm_syntax_7_3_9()
  let source =
    #|effect module Task where { command = MyCmd -- c
    #| , subscription = MySub } exposing (..)
    #|
    #|
    #|a =
    #|    1
    #|
  let expected =
    #|effect module Task
    #|    where
    #|        { command =
    #|            MyCmd
    #|            -- c
    #|        , subscription = MySub
    #|        }
    #|    exposing
    #|    (..)
    #|
    #|
    #|a =
    #|    1
    #|
  @expect.expect(@printer.format(source, dialect~)).to_equal(expected)
}

///|
test "elm-format: effect module: a line comment before a where field" {
  let dialect = @dialect.Dialect::elm_syntax_7_3_9()
  let source =
    #|effect module Task where { -- c
    #| command = MyCmd } exposing (..)
    #|
    #|
    #|a =
    #|    1
    #|
  let expected =
    #|effect module Task
    #|    where
    #|        { -- c
    #|          command = MyCmd
    #|        }
    #|    exposing
    #|    (..)
    #|
    #|
    #|a =
    #|    1
    #|
  @expect.expect(@printer.format(source, dialect~)).to_equal(expected)
}

///|
test "elm-format: effect module: comments break the header before an exposing list" {
  let dialect = @dialect.Dialect::elm_syntax_7_3_9()
  let source =
    #|effect module Task where { -- c
    #| command = MyCmd } exposing (a, b)
    #|
    #|
    #|a =
    #|    1
    #|
  let expected =
    #|effect module Task
    #|    where
    #|        { -- c
    #|          command = MyCmd
    #|        }
    #|    exposing
    #|    (a, b)
    #|
    #|
    #|a =
    #|    1
    #|
  @expect.expect(@printer.format(source, dialect~)).to_equal(expected)
}

///|
test "elm-format: effect module: a line comment after the name" {
  let dialect = @dialect.Dialect::elm_syntax_7_3_9()
  let source =
    #|effect module Task -- n
    #| where { command = MyCmd, subscription = MySub } exposing (a, b)
    #|
    #|
    #|a =
    #|    1
    #|
  let expected =
    #|effect module Task
    #|    -- n
    #|    where
    #|        { command = MyCmd, subscription = MySub }
    #|    exposing
    #|    (a, b)
    #|
    #|
    #|a =
    #|    1
    #|
  @expect.expect(@printer.format(source, dialect~)).to_equal(expected)
}

///|
test "elm-format: effect module: a line comment before exposing" {
  let dialect = @dialect.Dialect::elm_syntax_7_3_9()
  let source =
    #|effect module Task where { command = MyCmd } -- e
    #| exposing (..)
    #|
    #|
    #|a =
    #|    1
    #|
  let expected =
    #|effect module Task
    #|    where { command = MyCmd }
    #|    -- e
    #|    exposing
    #|    (..)
    #|
    #|
    #|a =
    #|    1
    #|
  @expect.expect(@printer.format(source, dialect~)).to_equal(expected)
}

///|
test "elm-format: effect module: block comments stay on the line" {
  let dialect = @dialect.Dialect::elm_syntax_7_3_9()
  let source =
    #|effect module Task where { command = MyCmd {- c -}, subscription = MySub {- d -} } exposing (..)
    #|
    #|
    #|a =
    #|    1
    #|
  @expect.expect(@printer.format(source, dialect~)).to_equal(source)
}

///|
test "elm-format: infix declaration with comments" {
  let dialect = @dialect.Dialect::elm_syntax_7_3_9()
  let source =
    #|module Basics exposing ((|>))
    #|
    #|
    #|infix left  0 -- a
    #|    (|>) = -- b
    #|    apR
    #|
    #|
    #|apR x f =
    #|    f x
    #|
  let expected =
    #|module Basics exposing ((|>))
    #|
    #|
    #|infix
    #|    left
    #|    0
    #|    -- a
    #|    (|>)
    #|    =
    #|    -- b
    #|    apR
    #|
    #|
    #|apR x f =
    #|    f x
    #|
  @expect.expect(@printer.format(source, dialect~)).to_equal(expected)
}

///|
test "elm-format output is stable: effect module: a comment on its own line after a where field" {
  let dialect = @dialect.Dialect::elm_syntax_7_3_9()
  let formatted =
    #|effect module Task
    #|    where
    #|        { command =
    #|            MyCmd
    #|            -- c
    #|        , subscription = MySub
    #|        }
    #|    exposing
    #|    (..)
    #|
    #|
    #|a =
    #|    1
    #|
  @expect.expect(@printer.format(formatted, dialect~)).to_equal(formatted)
}

///|
test "elm-format output is stable: effect module: a line comment after the last where field" {
  let dialect = @dialect.Dialect::elm_syntax_7_3_9()
  let source =
    #|effect module Time where { subscription = MySub -- c
    #| } exposing (..)
    #|
    #|
    #|a =
    #|    1
    #|
  let formatted =
    #|effect module Time
    #|    where
    #|        { subscription =
    #|            MySub
    #|            -- c
    #|        }
    #|    exposing
    #|    (..)
    #|
    #|
    #|a =
    #|    1
    #|
  @expect.expect_all(s => {
    s.expect(@printer.format(source, dialect~)).to_equal(formatted)
    s.expect(@printer.format(formatted, dialect~)).to_equal(formatted)
  })
}

///|
test "elm-format output is stable: effect module: a comment in the record with a long exposing list" {
  let dialect = @dialect.Dialect::elm_syntax_7_3_9()
  let formatted =
    #|effect module Task
    #|    where
    #|        { command =
    #|            MyCmd
    #|            -- c
    #|        }
    #|    exposing
    #|    (Task, andThen, attempt, fail, map, map2, map3, map4, map5, mapError, onError, perform, sequence, succeed)
    #|
    #|
    #|a =
    #|    1
    #|
  @expect.expect(@printer.format(formatted, dialect~)).to_equal(formatted)
}

///|
test "elm-format output is stable: infix: a line comment after the operator" {
  let dialect = @dialect.Dialect::elm_syntax_7_3_9()
  let source =
    #|module Basics exposing ((|>))
    #|
    #|
    #|infix left 0 (|>) -- a
    #| = apR
    #|
  let formatted =
    #|module Basics exposing ((|>))
    #|
    #|
    #|infix
    #|    left
    #|    0
    #|    (|>)
    #|    -- a
    #|    =
    #|    apR
    #|
  @expect.expect_all(s => {
    s.expect(@printer.format(source, dialect~)).to_equal(formatted)
    s.expect(@printer.format(formatted, dialect~)).to_equal(formatted)
  })
}

///|
test "elm-format output is stable: infix: block comments stay on one line" {
  let dialect = @dialect.Dialect::elm_syntax_7_3_9()
  let formatted =
    #|module Basics exposing ((|>))
    #|
    #|
    #|infix left  0 {- a -} (|>) {- b -} = {- c -} apR
    #|
  @expect.expect(@printer.format(formatted, dialect~)).to_equal(formatted)
}

///|
test "elm-format output is stable: a block comment after a separator stays after it" {
  let formatted =
    #|port module A exposing (..)
    #|
    #|import B.C {- c1 -} as {- c2 -} D exposing (x, y)
    #|
    #|
    #|port p {- c3 -} : {- c4 -} Int {- c5 -} -> {- c6 -} Cmd msg
    #|
    #|
    #|type alias T a b =
    #|    { x {- c7 -} : {- c8 -} a, y : b }
    #|
    #|
    #|f ( a {- c9 -} :: {- c10 -} b, c {- c11 -} as {- c12 -} d ) =
    #|    a
    #|
  @expect.expect(@printer.format(formatted)).to_equal(formatted)
}

///|
test "law: format prints every regular comment once, in source order, and doc comments as format_doc writes them" {
  // Doc comments (spec 8.2) are compared after `@markdown.format_doc`:
  // `normalize_file` writes them as `format` does.
  @quickcheck.check(
    (m : @lawkit.Commented) => {
      let text = m.text()
      let out = try @printer.format(text) catch {
        _ => return false
      } noraise {
        t => t
      }
      let parse = (t : String) => {
        @parser.parse_module(
          @scanner.SourceText::new(t),
          @scanner.DefaultScanner::new(),
        ).ast.unwrap()
      }
      let regular = (f : @ast.File) => {
        f.comments
        .iter()
        .filter(c => !c.value.has_prefix("{-|"))
        .map(c => {
          // elm-format changes the spaces and line breaks in a comment
          // (see "block comments are written as elm-format writes them"),
          // nothing else.
          c.value.iter().filter(ch => !ch.is_whitespace()).collect()
          |> String::from_array
        })
        .collect()
      }
      let docs = (f : @ast.File) => {
        let found : Array[String] = f.comments
          .iter()
          .filter(c => c.value.has_prefix("{-|"))
          .map(c => c.value)
          .collect()
        for d in f.declarations {
          let doc = match d.value {
            FunctionDeclaration(x) => x.documentation
            AliasDeclaration(x) => x.documentation
            CustomTypeDeclaration(x) => x.documentation
            _ => None
          }
          if doc is Some(doc) {
            found.push(doc.value)
          }
        }
        found
      }
      let before = parse(text)
      let after = parse(out)
      regular(before) == regular(after) &&
      docs(@printer.normalize_file(before)) == docs(after)
    },
    count=100,
    max_size=20,
    seed=2029,
  )
}

///|
test "a comment before ) in parentheses and tuples has no blank line before it" {
  // elm-format 0.8.7 output for each source.
  let module_of = (body : String) => "module A exposing (..)\n\n\n" + body
  @expect.expect_all(s => {
    for
      body in [
        "x =\n    f\n        (\\children ->\n            -- a\n            Html.button\n         -- b\n        )\n",
        "x =\n    f\n        (g\n         -- b\n        )\n", "x =\n    f\n        (\\c -> g\n         -- b\n        )\n",
        "x =\n    ( a\n    , b\n      -- c\n    )\n", "type alias T =\n    ( Int\n    , Int\n      -- c\n    )\n",
      ] {
      s.expect(@printer.format(module_of(body))).to_equal(module_of(body))
    }
    s
    .expect(@printer.format(module_of("x =\n    ( a, b\n    -- c\n    )\n")))
    .to_equal(module_of("x =\n    ( a\n    , b\n      -- c\n    )\n"))
  })
}

///|
test "block comments are written as elm-format writes them" {
  // elm-format 0.8.7 output for each comment between two declarations
  // (Parse/Whitespace.hs multiComment: the spaces after `{-` and before
  // `-}` go, and the common indentation of the lines after the first;
  // Box.hs formatComment).
  let module_of = (comment : String) => {
    "module A exposing (..)\n\n\na =\n    1\n\n\n\n" +
    comment +
    "\n\n\nx =\n    1\n"
  }
  @expect.expect_all(s => {
    for
      case_ in [
        ("{- Internals of the model.\n-}", "{- Internals of the model. -}"),
        ("{-a-}", "{- a -}"),
        ("{-   -}", "{- -}"),
        ("{-\n-}", "{-  -}"),
        (
          "{- Explanation\n\n    This is   \n      nested\n    end\n-}", "{- Explanation\n\n   This is\n     nested\n   end\n-}",
        ),
        ("{--TODO: maybe\nx = 2\n  -}", "{--TODO: maybe\nx = 2\n-}"),
        ("{-- TODO: maybe -}", "{--TODO: maybe-}"),
        ("{-\n   a\n     b\n   -}", "{-\n   a\n     b\n-}"),
        ("{- a {- b\n  c -} d\n-}", "{- a {- b\n   c -} d\n-}"),
        ("{-\ta -}", "{- \ta -}"),
      ] {
      let (source, expected) = case_
      s.expect(@printer.format(module_of(source))).to_equal(module_of(expected))
    }
    // An indented comment: the lines after the first go 3 columns right of
    // the `{-`, and `-}` goes in its column.
    s
    .expect(
      @printer.format(
        "module A exposing (..)\n\n\nx =\n    {- a\n            b -}\n    1\n",
      ),
    )
    .to_equal(
      "module A exposing (..)\n\n\nx =\n    {- a\n       b\n    -}\n    1\n",
    )
  })
}

///|
test "a comment before a , in a tuple follows the item before it" {
  // elm-format 0.8.7 output for each source (Box.hs TupleType and Tuple:
  // `formatC2Eol`, the comments after an item stack under it). In a list
  // the comment goes after a blank line, in the column of the `[`.
  let module_of = (body : String) => "module A exposing (..)\n\n\n" + body
  @expect.expect_all(s => {
    for
      body in [
        "type alias Acc =\n    ( -- hash state\n      State\n      -- splitting into words\n    , ( Int, Array Int )\n      -- total byte count\n    , Int\n    )\n",
        "x =\n    ( a\n      -- c\n    , b\n    )\n", "y =\n    [ a\n\n    -- c\n    , b\n    ]\n",
        "type alias Acc =\n    ( State -- a\n    , Int\n    )\n", "type alias Acc =\n    ( State {- a -}\n    , Int\n    )\n",
      ] {
      s.expect(@printer.format(module_of(body))).to_equal(module_of(body))
    }
    s
    .expect(
      @printer.format(
        module_of(
          "type alias Acc =\n    ( State\n    -- splitting into words\n    , Int\n    )\n",
        ),
      ),
    )
    .to_equal(
      module_of(
        "type alias Acc =\n    ( State\n      -- splitting into words\n    , Int\n    )\n",
      ),
    )
  })
}

///|
test "comment tricks keep the declaration between them" {
  // elm-format 0.8.7 output for each source (Box.hs formatModuleBody
  // `spacer`: no blank line after `{--}` and before `--}`).
  let module_of = (body : String) => "module A exposing (..)\n\n\n" + body
  @expect.expect_all(s => {
    for
      case_ in [
        (
          "a =\n    ()\n{--}\nb =\n    ()\n--}\n{--\nc =\n  ()\n--}\nd =\n    1\n",
          "a =\n    ()\n\n\n{--}\nb =\n    ()\n--}\n\n\n\n{--\nc =\n  ()\n--}\n\n\nd =\n    1\n",
        ),
        (
          "a =\n    1\n-- x\n{--}\nb =\n    ()\n--}\n-- y\nc =\n    1\n", "a =\n    1\n\n\n\n-- x\n\n\n{--}\nb =\n    ()\n--}\n\n\n\n-- y\n\n\nc =\n    1\n",
        ),
      ] {
      let (source, expected) = case_
      s.expect(@printer.format(module_of(source))).to_equal(module_of(expected))
    }
  })
}
