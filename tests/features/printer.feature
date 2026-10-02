Feature: Elm printer
  krueger prints an AST as Elm source in the elm-format layout. Source in
  that layout prints back unchanged; a construct that does not fit the
  line width breaks in the elm-format shape.

  Scenario: A module in elm-format layout prints unchanged
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
