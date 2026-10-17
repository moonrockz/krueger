Feature: Formatter
  krueger formats Elm source as elm-format 0.8.7 does.

  Scenario: Doc code keeps a final multiline expression with a trailing comment as written
    Given the Elm source:
      """
      module A exposing (f)

      {-| A.

          f
              [1,2] -- x
      -}

      f = 1
      """
    When I format it
    Then the output is:
      """
      module A exposing (f)

      {-| A.

          f
              [1,2] -- x

      -}


      f =
          1
      """

  Scenario: Doc code keeps a comment between its module header and imports
    Given the Elm source:
      """
      module A exposing (f)

      {-| A.

          module B exposing (x)
          -- c
          import C
          x = 1
      -}

      f = 1
      """
    When I format it
    Then the output is:
      """
      module A exposing (f)

      {-| A.

          module B exposing (x)

          -- c

          import C

          x =
              1

      -}


      f =
          1
      """

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
