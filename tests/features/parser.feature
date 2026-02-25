Feature: Elm parser baseline
  The parser should build AST/CST for Elm core subset source and attach
  doc comments to declarations according to the design contract.

  Scenario: Attach doc comment to following declaration
    Given Elm source:
      """elm
      module Main exposing (add)

      {-| Adds one to a value. -}
      add x = x + 1
      """
    When I parse the source
    Then parsing succeeds without diagnostics
    And the AST contains function declaration "add"
    And declaration "add" has the attached doc comment "Adds one to a value."

  Scenario: Do not attach doc comment when separated by regular comment
    Given Elm source:
      """elm
      module Main exposing (add)

      {-| Candidate doc comment. -}
      -- separating regular comment
      add x = x + 1
      """
    When I parse the source
    Then parsing succeeds
    And declaration "add" has no attached doc comment in AST metadata
    And both comments are preserved in CST or token trivia

  Scenario: Surface malformed comment as diagnostic during parse
    Given Elm source:
      """elm
      module Main exposing (add)
      {-| unclosed doc
      add x = x + 1
      """
    When I parse the source
    Then parsing returns diagnostics
    And at least one diagnostic reports malformed comment with a source span
