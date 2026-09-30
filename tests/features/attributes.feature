Feature: Attributes in doc comments
  A doc comment line that starts with `@name` is an attribute. Its arguments are
  Elm data values. krueger reports attributes per module and declaration; their
  meaning belongs to the tools that read them.

  Scenario: Attributes on a type alias
    Given Elm source:
      """elm
      module Bank exposing (..)

      {-| Bank. -}


      {-| A customer account.

      @deprecated "Use Account.V2"
      @derive [ Json.encoder, Json.decoder ]
      @morphir { kind = "entity", key = "id" }
      @unit "EUR"
      -}
      type alias Account =
          { id : String, balance : Float }
      """
    When I parse the source
    Then the attributes are:
      """
      Account @deprecated("Use Account.V2") 8:1
      Account @derive([ Json.encoder, Json.decoder ]) 9:1
      Account @morphir({ kind = "entity", key = "id" }) 10:1
      Account @unit("EUR") 11:1
      """
    And there are no warnings

  Scenario: Module attributes and the docs list
    Given Elm source:
      """elm
      module Bank exposing (Account, balance)

      {-| Accounts.

      @morphir { package = "Bank" }

      @docs Account, balance

      -}


      type alias Account =
          { balance : Float }


      balance : Account -> Float
      balance a =
          a.balance
      """
    When I parse the source
    Then the attributes are:
      """
      module @morphir({ package = "Bank" }) 5:1
      module @docs(Account, balance) 7:1
      """

  Scenario: Continuation lines and several arguments
    Given Elm source:
      """elm
      module Bank exposing (..)

      {-| Bank. -}


      {-| Balance.

      @morphir
          { kind = "entity"
          , key = "id"
          }
      @tag one two
      -}
      balance =
          1
      """
    When I parse the source
    Then the attributes are:
      """
      balance @morphir({ kind = "entity"\n    , key = "id"\n    }) 8:1
      balance @tag(one | two) 12:1
      """

  Scenario: Continuation lines as elm-format leaves them
    Given Elm source:
      """elm
      module Bank exposing (..)

      {-| Bank. -}


      {-| The balance. Some prose first.
      @pure
      @morphir
      { kind = "function"
      , total = True
      }
      -}
      balance =
          1
      """
    When I parse the source
    Then the attributes are:
      """
      balance @pure() 7:1
      balance @morphir({ kind = "function"\n, total = True\n}) 8:1
      """
    And there are no warnings

  Scenario: Prose and code blocks are not attributes
    Given Elm source:
      """elm
      module Bank exposing (..)


      {-| Mail @someone about this.

      ```
      @x 1
      ```

          @y 2

      Done.
      -}
      balance =
          1
      """
    When I parse the source
    Then there are no attributes
    And there are no warnings

  Scenario: Malformed attributes are warnings and are skipped
    Given Elm source:
      """elm
      module Bank exposing (..)

      {-| Bank. -}


      {-| Balance.

      @bad (\x -> x)
      @Upper 1
      @ok 1
      -}
      balance =
          1
      """
    When I parse the source
    Then warning "KR-ATTR-001" is reported at "8:1"
    And warning "KR-ATTR-001" is reported at "9:1"
    And the attributes are:
      """
      balance @ok(1) 10:1
      """

  Scenario: Attributes on a port
    Given Elm source:
      """elm
      port module Bank exposing (..)

      {-| Bank. -}


      {-| Send out.

      @js "send"
      -}
      port out : String -> Cmd msg
      """
    When I parse the source
    Then the attributes are:
      """
      out @js("send") 8:1
      """

  Scenario: A dialect can switch attributes off
    Given Elm source:
      """elm
      module Bank exposing (..)


      {-| Balance.

      @unit "EUR"
      -}
      balance =
          1
      """
    And the attribute syntax is off
    When I parse the source
    Then there are no attributes
