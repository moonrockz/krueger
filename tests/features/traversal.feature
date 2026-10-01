Feature: Traversal
  walk, fold, accept, the event reader, push_events and a tree cursor visit
  the same nodes in the same order: pre-order over the node model's children,
  in source order.

  Scenario Outline: The traversals agree on <fixture>
    Given the Elm file "tests/fixtures/ast/<fixture>.elm"
    When I build the syntax tree
    Then walk, fold, accept, the event reader, push_events and a cursor visit the same nodes as the children pre-order
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

  Scenario: Reading events with their depth and path
    Given Elm source:
      """elm
      module M exposing (..)


      f =
          g 1
      """
    When I build the syntax tree
    And I read its events
    Then the events are:
      """
      + file/file 0 (start)
      + module/normal 1 moduleDefinition[0]
      + module_name/module_name 2 moduleDefinition[0].moduleName[0]
      - module_name/module_name 2 moduleDefinition[0].moduleName[0]
      + exposing/all 2 moduleDefinition[0].exposingList[0]
      - exposing/all 2 moduleDefinition[0].exposingList[0]
      - module/normal 1 moduleDefinition[0]
      + declaration/function 1 declarations[0]
      + implementation/implementation 2 declarations[0].declaration[0]
      + name/name 3 declarations[0].declaration[0].name[0]
      - name/name 3 declarations[0].declaration[0].name[0]
      + expression/application 3 declarations[0].declaration[0].expression[0]
      + expression/functionOrValue 4 declarations[0].declaration[0].expression[0].application[0]
      - expression/functionOrValue 4 declarations[0].declaration[0].expression[0].application[0]
      + expression/integer 4 declarations[0].declaration[0].expression[0].application[1]
      - expression/integer 4 declarations[0].declaration[0].expression[0].application[1]
      - expression/application 3 declarations[0].declaration[0].expression[0]
      - implementation/implementation 2 declarations[0].declaration[0]
      - declaration/function 1 declarations[0]
      - file/file 0 (start)
      """

  Scenario: A cursor moves into a module attribute inside the module doc comment
    Given Elm source:
      """elm
      module M exposing (f)

      {-| Module.

      @docs f
      -}


      {-| F.

      @deprecated "no"
      -}
      f =
          1
      """
    When I build the syntax tree
    And I move a cursor toward "5:1"
    Then the cursor passes through:
      """
      attribute/docs attributes attributes[0]
      name/name names attributes[0].names[0]
      """

  Scenario: A cursor moves into a declaration attribute inside its doc comment
    Given Elm source:
      """elm
      module M exposing (f)

      {-| Module.

      @docs f
      -}


      {-| F.

      @deprecated "no"
      -}
      f =
          1
      """
    When I build the syntax tree
    And I move a cursor toward "11:1"
    Then the cursor passes through:
      """
      declaration/function declarations declarations[0]
      attribute/attribute attributes declarations[0].attributes[0]
      name/name name declarations[0].attributes[0].name[0]
      """

  Scenario: From a blank line, a cursor moves to the next node
    Given Elm source:
      """elm
      module M exposing (f)

      {-| Module.

      @docs f
      -}


      {-| F.

      @deprecated "no"
      -}
      f =
          1
      """
    When I build the syntax tree
    And I move a cursor toward "7:1"
    Then the cursor passes through:
      """
      declaration/function declarations declarations[0]
      documentation/documentation documentation declarations[0].documentation[0]
      """
