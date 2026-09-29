Feature: Elm parity scoreboard
  The parity check hashes krueger's AST JSON and compares it with the golden
  lock made from elm-syntax output. Counts must never drop below the baseline.

  Scenario: Canonical JSON ignores key order and number spelling
    Given the JSON '{"b": 1.0, "a": [2, {"d": null, "c": "x"}]}'
    Then the canonical form is '{"a":[2,{"c":"x","d":null}],"b":1}'

  Scenario: Lock lines survive a write and read
    Given the lock text:
      """
      # comment
      pkg/b@1.0.0/src/B.elm 22 PARSE_ERROR
      pkg/a@1.0.0/src/Long/Name.elm 33 cc
      pkg/a@1.0.0/src/A.elm 11 aa
      """
    When I read and write the lock
    Then the lock text is:
      """
      # <corpus key> <source sha256> <canonical elm-syntax JSON sha256 | PARSE_ERROR>
      pkg/a@1.0.0/src/A.elm 11 aa
      pkg/a@1.0.0/src/Long/Name.elm 33 cc
      pkg/b@1.0.0/src/B.elm 22 PARSE_ERROR
      """

  Scenario: Reject a malformed lock line
    Given the lock text:
      """
      pkg/a@1.0.0/src/A.elm 11
      """
    When I read and write the lock
    Then reading the lock fails

  Scenario Outline: Counts below the baseline are regressions
    Given the counts <files> files, <tokenized> tokenized, <parsed> parsed, <matched> matched
    And the baseline 363 files, 10 tokenized, 5 parsed, 0 matched
    Then the regressions are "<regressions>"

    Examples:
      | files | tokenized | parsed | matched | regressions                     |
      | 363   | 10        | 5      | 0       |                                 |
      | 363   | 12        | 6      | 1       |                                 |
      | 363   | 9         | 5      | 0       | tokenized: 9 < baseline 10      |
      | 362   | 10        | 4      | 0       | files: 362 < baseline 363; parsed: 4 < baseline 5 |

  Scenario: S-expression view of an elm-syntax node
    Given the JSON '{"range": [3, 5, 3, 6], "value": {"type": "integer", "integer": 1}}'
    Then the S-expression is "(integer 1) @3:5-3:6"

  Scenario: First difference between golden and krueger output
    Given the golden JSON '{"declarations": [{"range": [3, 1, 3, 6], "value": {"type": "integer", "integer": 1}}]}'
    And the krueger JSON '{"declarations": [{"range": [3, 1, 3, 7], "value": {"type": "integer", "integer": 1}}]}'
    Then the first difference is at "$.declarations[0].range[3]"
