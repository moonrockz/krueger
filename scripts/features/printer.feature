Feature: Printer elm-format lock
  The recording script writes, for each printed corpus file, its SHA-256 and
  whether elm-format 0.8.7 leaves it unchanged.

  Scenario Outline: Only an exact pinned oracle transition gets an exemption
    Given the known oracle transitions:
      """
      {
        "known.elm": { "first": "aa", "second": "bb" }
      }
      """
    And the printed candidate:
      | key   | sha256  | stable   | formatted |
      | <key> | <first> | <stable> | <second>  |
    When I classify the printed candidate
    Then the recorded verdict is "<verdict>"
    And the pending keys are "<pending>"

    Examples:
      | key         | first | stable | second | verdict            | pending     |
      | known.elm   | aa    | no     | bb     | oracle_second_pass |             |
      | known.elm   | cc    | no     | bb     | changed            | known.elm   |
      | known.elm   | aa    | no     | cc     | changed            | known.elm   |
      | known.elm   | cc    | no     | cc     | changed            | known.elm   |
      | unknown.elm | aa    | no     | bb     | changed            | unknown.elm |
      | unknown.elm | cc    | no     | bb     | changed            | unknown.elm |
      | unknown.elm | aa    | no     | cc     | changed            | unknown.elm |
      | unknown.elm | cc    | no     | cc     | changed            | unknown.elm |
      | known.elm   | aa    | yes    | bb     | stable             |             |
      | known.elm   | cc    | yes    | bb     | stable             |             |
      | known.elm   | aa    | yes    | cc     | stable             |             |
      | known.elm   | cc    | yes    | cc     | stable             |             |
      | unknown.elm | aa    | yes    | bb     | stable             |             |
      | unknown.elm | cc    | yes    | bb     | stable             |             |
      | unknown.elm | aa    | yes    | cc     | stable             |             |
      | unknown.elm | cc    | yes    | cc     | stable             |             |

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

  Scenario: A recorded oracle second pass is separate from pending differences
    Given the verdicts:
      | key               | sha256 | stable | second |
      | a/1.0.0/src/A.elm | aa     | no     | cc     |
    Then the lock is:
      """
      {
        "a/1.0.0/src/A.elm": {
          "sha256": "aa",
          "elm_format": "oracle_second_pass",
          "second": "cc"
        }
      }
      """
    And the pending list is:
      """
      []
      """
