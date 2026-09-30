Feature: Elm parser
  The parser builds an elm-syntax AST for the syntax it supports, keeps every
  declaration in the CST, and reports syntax it cannot yet produce exactly.

  Scenario Outline: Parser output matches elm-syntax
    Given the Elm fixture "<fixture>"
    When I parse the source
    Then parsing succeeds without diagnostics
    And the AST JSON equals the elm-syntax output for "<fixture>"

    Examples:
      | fixture                  |
      | header_all               |
      | header_explicit          |
      | imports                  |
      | single_constructor       |
      | documented_type          |
      | module_documentation     |
      | second_declaration_doc   |
      | doc_across_comment       |
      | module_doc_then_type_doc |
      | comments                 |
      | spaced_exposing_all      |
      | operators                |

  Scenario Outline: Parser output matches elm-syntax for every construct
    Given the Elm fixture "<fixture>" from the AST fixtures
    When I parse the source
    Then parsing succeeds without diagnostics
    And the AST JSON equals the elm-syntax output for AST fixture "<fixture>"

    Examples:
      | fixture       |
      | module_normal |
      | module_port   |
      | module_effect |
      | declarations  |
      | expressions   |
      | patterns      |

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

  Scenario Outline: Reject syntax that elm-syntax rejects
    Given Elm source:
      """elm
      <source>
      """
    When I parse the source
    Then the diagnostics include "<code>"

    Examples:
      | source                       | code         |
      | module A exposing (..) extra | KR-PARSE-007 |
      | module a exposing (..)       | KR-PARSE-001 |

  Scenario: Reject a doc comment before the module header
    Given Elm source:
      """elm
      {-| before header -}
      module A exposing (T)
      """
    When I parse the source
    Then the diagnostics include "KR-PARSE-007"

  Scenario: Reject a stray doc comment before an import
    Given Elm source:
      """elm
      module A exposing (T)

      import B

      {-| stray -}
      import C
      """
    When I parse the source
    Then the diagnostics include "KR-PARSE-007"

  Scenario: Reject tokens the parser would otherwise skip
    Given Elm source:
      """elm
      module A exposing (T)

      import B C
      """
    When I parse the source
    Then the diagnostics include "KR-PARSE-007"

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
