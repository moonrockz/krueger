Feature: Elm tokenizer baseline
  The scanner should tokenize Elm core subset source while preserving
  comments/doc comments and emitting diagnostics for malformed comments.

  Scenario: Tokenize module with comments and doc comment
    Given Elm source:
      """elm
      module Main exposing (add)

      -- plain line comment
      {- plain block comment -}
      {-| Adds one to a value. -}
      add x = x + 1
      """
    When I tokenize the source
    Then tokenization succeeds
    And the token stream contains a module declaration and function declaration
    And regular comments are preserved in trivia
    And the doc comment is preserved and identified as a doc comment

  Scenario: Report malformed block comment
    Given Elm source:
      """elm
      module Main exposing (..)
      {- missing close
      add x = x + 1
      """
    When I tokenize the source
    Then tokenization fails with at least one diagnostic
    And a diagnostic indicates malformed block comment with a source span
