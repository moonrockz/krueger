///|
fn file_of(
  text : String,
  dialect? : @dialect.Dialect = @dialect.Dialect::elm_0_19_1(),
) -> @ast.File raise {
  let result = @parser.parse_module(
    @scanner.SourceText::new(text),
    @scanner.DefaultScanner::new(dialect~),
    dialect~,
  )
  guard !result.diagnostics.iter().any(d => d.severity is Error) &&
    result.ast is Some(file) else {
    fail("does not parse:\n\{text}")
  }
  file
}

///|
fn core_dialect() -> @dialect.Dialect {
  { ..@dialect.Dialect::elm_0_19_1(), core_package: true, }
}

///|
test "a file in the elm-format layout prints unchanged" {
  let text =
    #|module Main exposing (Model, Msg(..), main)
    #|
    #|{-| The app.
    #|-}
    #|
    #|import Dict as D
    #|import Html exposing (Html, text)
    #|
    #|
    #|{-| The model. -}
    #|type alias Model =
    #|    { count : Int, names : D.Dict String Int }
    #|
    #|
    #|type Msg
    #|    = Increment
    #|    | Set Int
    #|
    #|
    #|main : Html msg
    #|main =
    #|    text "hi"
    #|
  inspect(@printer.print_file(file_of(text)) == text, content="true")
}

///|
test "module documentation without imports" {
  let text = "module A exposing (f)\n\n{-| Doc.\n-}\n\n\nf =\n    1\n"
  inspect(@printer.print_file(file_of(text)), content=text)
}

///|
test "port doc comments go above their port" {
  let text = "port module Ports exposing (..)\n\n\n{-| Send. -}\nport send : String -> Cmd msg\n"
  inspect(@printer.print_file(file_of(text)), content=text)
}

///|
test "doc comments print unchanged" {
  let text = "module A exposing (f)\n\n{-| Mod.\n-}\n\n\n{-| Hard break  \nnext\n\n    indented code\n\n-}\nf =\n    1\n"
  inspect(@printer.print_file(file_of(text)) == text, content="true")
}

///|
test "infix declarations stay on consecutive lines" {
  let text =
    #|module Basics exposing (..)
    #|
    #|
    #|infix right 0 (<|) = apL
    #|infix left  0 (|>) = apR
    #|infix non   4 (==) = eq
    #|
    #|
    #|apL f x =
    #|    f x
    #|
  let d = core_dialect()
  inspect(
    @printer.print_file(file_of(text, dialect=d), dialect=d) == text,
    content="true",
  )
}

///|
test "effect module header" {
  let text =
    #|effect module Task where { command = MyCmd } exposing (Task, perform)
    #|
    #|
    #|type MyCmd msg
    #|    = Perform (Task Never msg)
    #|
  let d = core_dialect()
  inspect(
    @printer.print_file(file_of(text, dialect=d), dialect=d) == text,
    content="true",
  )
}

///|
test "a long exposing list and a long signature break" {
  @expect.expect_all(s => {
    let file = file_of(
      "module A exposing (aaaa, bbbb, cccc)\n\n\naaaa =\n    1\n",
    )
    s
    .expect(@printer.print_file(file, width=20))
    .to_equal(
      "module A exposing\n    ( aaaa\n    , bbbb\n    , cccc\n    )\n\n\naaaa =\n    1\n",
    )
    let g = file_of(
      "module A exposing (..)\n\n\nf : Int -> Int\nf x =\n    x\n",
    )
    s
    .expect(@printer.print_declaration(g.declarations[0], width=10))
    .to_equal("f :\n    Int\n    -> Int\nf x =\n    x")
  })
}

///|
test "declarations that Elm cannot write raise" {
  @expect.expect_all(s => {
    let no_ctors : @ast.Node[@ast.Declaration] = n(
      CustomTypeDeclaration({
        documentation: None,
        name: n("T"),
        generics: [][:],
        constructors: [][:],
      }),
    )
    s
    .expect(problem_of(() => @printer.print_declaration(no_ctors)))
    .to_equal(Some((NoConstructors, [])))
    let bad_doc : @ast.Node[@ast.Declaration] = n(
      AliasDeclaration({
        documentation: Some(n("-- not a doc comment")),
        name: n("A"),
        generics: [][:],
        type_annotation: n(Unit),
      }),
    )
    s
    .expect(problem_of(() => @printer.print_declaration(bad_doc)))
    .to_equal(
      Some((InvalidDocumentation, [{ field: "documentation", index: 0, }])),
    )
    let file = file_of("module A exposing (f)\n\n\nf =\n    1\n")
    let empty_exposing = {
      ..file,
      module_definition: n(
        NormalModule({
          module_name: n(["A"][:]),
          exposing_list: n(Explicit([][:])),
        }),
      ),
    }
    s
    .expect(problem_of(() => @printer.print_file(empty_exposing)))
    .to_equal(
      Some(
        (
          EmptyExposing,
          [
            { field: "moduleDefinition", index: 0, },
            { field: "exposingList", index: 0, },
          ],
        ),
      ),
    )
  })
}

///|
test "a long import exposing list breaks in the elm-format import form" {
  // elm-format 0.8.7 puts `exposing` of an import on its own line.
  let file = file_of(
    "module A exposing (..)\n\nimport Dict exposing (Dict, empty, insert)\n\n\nf =\n    1\n",
  )
  inspect(
    @printer.print_file(file, width=30),
    content=(
      #|module A exposing (..)
      #|
      #|import Dict
      #|    exposing
      #|        ( Dict
      #|        , empty
      #|        , insert
      #|        )
      #|
      #|
      #|f =
      #|    1
      #|
    ),
  )
}
