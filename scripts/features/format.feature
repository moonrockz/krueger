Feature: Formatter oracle
  The record step hashes elm-format's output per file and builds the
  pending list; the fetch step selects the elm-format test files and
  verifies each one against its pinned hash.

  Scenario: Select the Elm files below the test-files prefix
    Given the archive entries:
      | entry                                                        |
      | elm-format-0.8.7/tests/test-files/good/Elm-0.19/A.elm        |
      | elm-format-0.8.7/tests/test-files/good/Elm-0.19/A.json       |
      | elm-format-0.8.7/src/Main.hs                                 |
      | elm-format-0.8.7/tests/test-files/transform/B.formatted.elm  |
    When I select the test files
    Then the keys are:
      | key                                       |
      | elm-format/good/Elm-0.19/A.elm            |
      | elm-format/transform/B.formatted.elm      |

  Scenario: Verify files against the pinned hashes
    Given the pinned files:
      | key   | pinned | actual |
      | a.elm | h1     | h1     |
      | b.elm | h1     | h2     |
      | c.elm | h1     | -      |
    Then the verification problems are:
      | key   | problem                |
      | b.elm | sha256 mismatch: b.elm |
      | c.elm | missing: c.elm         |

  Scenario: Build lock entries from verdicts
    Given the verdicts:
      | key   | source | krueger  | elm_format_exit | output |
      | a.elm | s1     | parsed   | 0               | x      |
      | b.elm | s2     | rejected | 0               | y      |
      | c.elm | s3     | parsed   | 1               |        |
    When I build the lock
    Then the lock is:
      """
      {
        "a.elm": {
          "source": "s1",
          "expected": "2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881"
        },
        "b.elm": {
          "source": "s2",
          "skipped": "krueger rejects the file"
        },
        "c.elm": {
          "source": "s3",
          "skipped": "elm-format exited with code 1"
        }
      }
      """

  Scenario: The pending list holds the keys whose hashes differ
    Given the expected and actual hashes:
      | key   | expected | actual |
      | a.elm | h1       | h1     |
      | b.elm | h2       | h3     |
    When I build the pending list
    Then the pending list is "b.elm"
