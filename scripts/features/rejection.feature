Feature: Rejection oracle
  The recording script reads the elm make and elm-syntax results for each
  rejection fixture.

  Scenario Outline: Syntax error titles
    Then "<title>" is a syntax error title "<syntax>"

    Examples:
      | title             | syntax |
      | UNFINISHED LET    | yes    |
      | PROBLEM IN RECORD | yes    |
      | LEADING ZEROS     | yes    |
      | NO TABS           | yes    |
      | NAMING ERROR      | no     |
      | TYPE MISMATCH     | no     |

  Scenario: An accepted fixture
    When elm make exits with 0 and stderr:
      """
      """
    Then the elm make verdict is:
      """
      {"accepted":true}
      """

  Scenario: A rejected fixture
    When elm make exits with 1 and stderr:
      """
      {"type":"compile-errors","errors":[{"path":"src/Fixture.elm","name":"Fixture","problems":[{"title":"LEADING ZEROS","region":{"start":{"line":6,"column":5},"end":{"line":6,"column":8}},"message":["Numbers cannot start with zeros."]}]}]}
      """
    Then the elm make verdict is:
      """
      {"accepted":false,"title":"LEADING ZEROS","region":[6,5,6,8],"message":["Numbers cannot start with zeros."]}
      """

  Scenario: A non-syntax error is a bad fixture
    When elm make exits with 1 and stderr:
      """
      {"type":"compile-errors","errors":[{"path":"src/Fixture.elm","name":"Fixture","problems":[{"title":"NAMING ERROR","region":{"start":{"line":6,"column":5},"end":{"line":6,"column":8}},"message":["x"]}]}]}
      """
    Then reading the verdict fails with "not a syntax error: NAMING ERROR"

  Scenario: Other elm make failures are reported
    When elm make exits with 1 and stderr:
      """
      {"type":"error","path":"elm.json","title":"BAD JSON","message":["x"]}
      """
    Then reading the verdict fails with "elm make: "

  Scenario: elm-syntax results by fixture
    Given the oracle output:
      """
      {"name":"tests/rejection/a/b.elm","ok":true,"file":{}}
      {"name":"tests/rejection/a/c.elm","ok":false,"error":"x"}
      """
    Then the oracle verdicts with prefix "tests/rejection/" are "a/b.elm=true, a/c.elm=false"
