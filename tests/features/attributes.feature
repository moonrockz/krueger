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

  Scenario: An attributes block with the marker as the fence info string
    Given Elm source:
      """elm
      module Bank exposing (..)

      {-| Bank. -}


      {-| An account.

      ```-attributes:
      @morphir { key = "account_id", note = "a*b*c" }
      @multi
          { kind = "entity"
          , key = "id"
          }
      ```

      -}
      account =
          1
      """
    When I parse the source
    Then the attributes are:
      """
      account @morphir({ key = "account_id", note = "a*b*c" }) 9:1
      account @multi({ kind = "entity"\n    , key = "id"\n    }) 10:1
      """
    And there are no warnings

  Scenario: An attributes block as elm-format leaves it
    Given Elm source:
      """elm
      module Bank exposing (..)

      {-| Bank. -}


      {-| An account.

          -attributes:
          @morphir { key = "account_id" }
          @unit "EUR"

      -}
      account =
          1
      """
    When I parse the source
    Then the attributes are:
      """
      account @morphir({ key = "account_id" }) 9:5
      account @unit("EUR") 10:5
      """

  Scenario: An attributes block with the marker on its first line
    Given Elm source:
      """elm
      module Bank exposing (..)

      {-| Bank. -}


      {-| An account.

      ```
      -attributes:
      @unit "EUR"
      ```

      -}
      account =
          1
      """
    When I parse the source
    Then the attributes are:
      """
      account @unit("EUR") 10:1
      """

  Scenario: A value in a code span
    Given Elm source:
      """elm
      module Bank exposing (..)

      {-| Bank. -}


      {-| An account.

      @morphir `{ key = "account_id" }`
      @tag `one two`

      -}
      account =
          1
      """
    When I parse the source
    Then the attributes are:
      """
      account @morphir({ key = "account_id" }) 8:1
      account @tag(one | two) 9:1
      """
    And there are no warnings

  Scenario: Prose right after a plain attribute is not read as values
    Given Elm source:
      """elm
      module Bank exposing (..)

      {-| Bank. -}


      {-| An account.

      @deprecated "x"
      This is fine now.

      -}
      account =
          1
      """
    When I parse the source
    Then the attributes are:
      """
      account @deprecated("x") 8:1
      """
    And there are no warnings

  Scenario: The compatibility example that elm make and elm-format accept
    Given the Elm file "tests/attributes/compat/Attributes.elm"
    When I parse the source
    Then the attributes are:
      """
      module @morphir({ package = "Bank" }) 5:1
      module @docs(Account, balance, rate, tag) 7:1
      Account @deprecated("Use Account.V2") 15:1
      Account @derive([ Json.encoder, Json.decoder ]) 16:1
      Account @morphir({ kind = "entity"\n    , key = "account_id"\n    , note = "a*b*c"\n    }) 17:1
      balance @pure() 32:5
      balance @morphir({ kind = "function", url = "http://x.org/a_b" }) 33:5
      rate @unit("EUR") 43:1
      rate @tag(one | two) 44:1
      tag @tag(one | two) 54:1
      """
    And there are no warnings
