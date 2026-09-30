Feature: Syntax tree
  The node model gives every AST node a category, a kind, a range, named fields
  and a parent. These scenarios check its invariants on the AST fixtures, and
  check that the kind table in AGENTS.md matches the code.

  Scenario Outline: The tree invariants hold for <fixture>
    Given the Elm file "tests/fixtures/ast/<fixture>.elm"
    When I build the syntax tree
    Then every child lies inside its parent, in source order
    And every child's parent is the node it came from
    And every node's fields match the kind table
    And node_at at the start of every node finds that node or a descendant

    Examples:
      | fixture       |
      | module_normal |
      | module_port   |
      | module_effect |
      | declarations  |
      | expressions   |
      | patterns      |

  Scenario: The kind table in AGENTS.md matches the node model
    Given the file "AGENTS.md"
    Then the kind table between the markers matches the node model
