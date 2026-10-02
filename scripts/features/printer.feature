Feature: Printer elm-format lock
  The recording script writes, for each printed corpus file, its SHA-256 and
  whether elm-format 0.8.7 leaves it unchanged.

  Scenario: Lock and pending list
    Given the verdicts:
      | key               | sha256 | stable |
      | a/1.0.0/src/A.elm | aa     | yes    |
      | b/1.0.0/src/B.elm | bb     | no     |
    Then the lock is:
      """
      {
        "a/1.0.0/src/A.elm": {
          "sha256": "aa",
          "elm_format": "stable"
        },
        "b/1.0.0/src/B.elm": {
          "sha256": "bb",
          "elm_format": "changed"
        }
      }
      """
    And the pending list is:
      """
      [
        "b/1.0.0/src/B.elm"
      ]
      """

  Scenario: Only exit codes 0 and 1 are verdicts
    elm-format --validate exits with 1 when it would change the file. Any
    other non-zero code means that elm-format did not run or failed.

    Then the elm-format exit codes give:
      | code | verdict |
      | 0    | stable  |
      | 1    | changed |
      | 2    | error   |
      | 127  | error   |
      | -1   | error   |
