Feature: Formatter
  krueger formats Elm source as elm-format 0.8.7 does.

  Scenario: An application keeps its first argument on the line
    Given the Elm source:
      """
      module A exposing (..)

      a = f x
        y
      """
    When I format it
    Then the output is:
      """
      module A exposing (..)


      a =
          f x
              y
      """

  Scenario: A comment stays above its expression
    Given the Elm source:
      """
      module A exposing (..)

      g =
          -- lead
          1
      """
    When I format it
    Then the output is:
      """
      module A exposing (..)


      g =
          -- lead
          1
      """
