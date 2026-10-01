Feature: Traversal
  walk, fold and accept visit the same nodes in the same order: pre-order over
  the node model's children, in source order. (EventReader, push_events and
  TreeCursor join this check in V3.)

  Scenario Outline: The traversals agree on <fixture>
    Given the Elm file "tests/fixtures/ast/<fixture>.elm"
    When I build the syntax tree
    Then walk, fold and accept visit the same nodes as the children pre-order
    And every entered node is left once, after its children

    Examples:
      | fixture       |
      | module_normal |
      | module_port   |
      | module_effect |
      | declarations  |
      | expressions   |
      | patterns      |

  Scenario: Skipping function bodies
    Given Elm source:
      """elm
      module M exposing (..)

      import Html


      f x =
          x + 1
      """
    When I build the syntax tree
    And I walk it and skip the children of functions
    Then the entered nodes are:
      """
      file/file
      module/normal
      module_name/module_name
      exposing/all
      import/import
      module_name/module_name
      declaration/function
      """
