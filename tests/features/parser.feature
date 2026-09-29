Feature: Elm parser
  The parser builds an elm-syntax AST for the syntax it supports, keeps every
  declaration in the CST, and reports syntax it cannot yet produce exactly.

  Scenario Outline: Parser output matches elm-syntax
    Given the Elm fixture "<fixture>"
    When I parse the source
    Then parsing succeeds without diagnostics
    And the AST JSON equals the elm-syntax output for "<fixture>"

    Examples:
      | fixture                |
      | header_all             |
      | header_explicit        |
      | imports                |
      | single_constructor     |
      | documented_type        |
      | module_documentation   |
      | second_declaration_doc |

  Scenario: Attach doc comment to following declaration
    Given Elm source:
      """elm
      module Main exposing (Msg)

      import Html

      {-| A message. -}
      type Msg
          = Inc
      """
    When I parse the source
    Then parsing succeeds without diagnostics
    And declaration "Msg" has documentation "{-| A message. -}"

  Scenario: First doc comment after the header documents the module
    Given Elm source:
      """elm
      module Main exposing (Msg)

      {-| Module documentation. -}
      type Msg
          = Inc
      """
    When I parse the source
    Then parsing succeeds without diagnostics
    And declaration "Msg" has no documentation
    And the file comments are "{-| Module documentation. -}"

  Scenario: Do not attach doc comment when separated by regular comment
    Given Elm source:
      """elm
      module Main exposing (Msg)

      import Html

      {-| Candidate doc comment. -}
      -- separating regular comment
      type Msg
          = Inc
      """
    When I parse the source
    Then parsing succeeds without diagnostics
    And declaration "Msg" has no documentation
    And both comments are preserved in CST or token trivia

  Scenario: Report declarations the parser cannot produce yet
    Given Elm source:
      """elm
      module Main exposing (add)

      add x = x + 1
      """
    When I parse the source
    Then the diagnostics are "KR-PARSE-005"
    And the AST has no declarations
    And the CST has declaration "add"

  Scenario: Report a missing module header
    Given Elm source:
      """elm
      x = 1
      """
    When I parse the source
    Then the diagnostics include "KR-PARSE-006"
    And there is no AST

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
