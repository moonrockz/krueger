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
test "law: format prints every regular comment once, in source order" {
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
          c.value.replace_all(old="\r\n", new="\n").trim_end().to_owned()
        })
        .collect()
      }
      regular(parse(text)) == regular(parse(out))
    },
    count=100,
    max_size=20,
    seed=2029,
  )
}
