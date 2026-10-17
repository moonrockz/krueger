Feature: Elm printer
  krueger prints an AST as Elm source in the elm-format layout. A module
  with no regular comments, in the layout that the printer chooses, prints
  back unchanged; a construct that does not fit the line width breaks in
  the elm-format shape.

  Scenario: A module in the printer's layout prints unchanged
    Given the Elm module:
      """elm
      module Main exposing (main)

      import Html exposing (text)


      main =
          text "hello"
      """
    When I print its AST
    Then the printed source equals the module

  Scenario: A long application breaks in the elm-format shape
    Given the Elm module:
      """elm
      module Main exposing (main)


      main =
          Html.div [ class "a" ] [ text "first", text "second" ]
      """
    When I print its AST with width 40
    Then the printed source is:
      """elm
      module Main exposing (main)


      main =
          Html.div
              [ class "a" ]
              [ text "first", text "second" ]
      """

  Scenario: An atomic condition keeps the if head on one line
    Given the Elm module:
      """elm
      module Main exposing (..)


      main =
          if veryLongCondition then
              1

          else
              0
      """
    When I print its AST with width 12
    Then the printed source equals the module

  Scenario: A multiline left operand puts the backward pipe on its own line
    Given the Elm module:
      """elm
      module Main exposing (..)


      main =
          longFunction argument <| value
      """
    When I print its AST with width 20
    Then the printed source is:
      """elm
      module Main exposing (..)


      main =
          longFunction
              argument
          <|
              value
      """
