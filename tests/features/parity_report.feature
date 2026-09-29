Feature: Parity reports
  The parity check writes its results as JSON, JUnit XML, HTML and a Markdown
  summary, so CI runs can attach them as build reports.

  Background:
    Given a parity run with baseline 3 files, 2 tokenized, 1 parsed, 0 matched
    And the file "elm/core@1.0.5/src/Basics.elm" matched
    And the file "elm/core@1.0.5/src/List.elm" parsed but differs at "$.declarations[0].range[3]"
    And the file "elm/json@1.1.4/src/Json/Decode.elm" failed with "KR-SCAN-003" at "12:5" "Invalid <char> & more"

  Scenario: JSON report carries counts, baseline delta and every file
    When I render the JSON report
    Then the JSON counts are 3 files, 3 tokenized, 2 parsed, 1 matched
    And the JSON delta is 0 files, 1 tokenized, 1 parsed, 1 matched
    And the JSON report lists 3 files
    And JSON file "elm/json@1.1.4/src/Json/Decode.elm" has diagnostic "KR-SCAN-003"

  Scenario: JUnit report groups files by package and skips unmatched files
    When I render the JUnit report
    Then the JUnit report has a testsuite "elm/core@1.0.5" with 2 tests and 1 skipped
    And the JUnit report has a testsuite "elm/json@1.1.4" with 1 tests and 1 skipped
    And the JUnit report contains 'message="KR-SCAN-003 at 12:5: Invalid &lt;char&gt; &amp; more"'
    And the JUnit report contains 'message="differs from elm-syntax at $.declarations[0].range[3]"'
    And the JUnit baseline testcase passes

  Scenario: JUnit report fails the baseline testcase on a regression
    Given the baseline was 3 files, 3 tokenized, 2 parsed, 2 matched
    When I render the JUnit report
    Then the JUnit report contains '<failure message="matched: 1 &lt; baseline 2"'

  Scenario: HTML report shows count tiles and one row per file
    When I render the HTML report
    Then the HTML report contains "<title>Elm parity</title>"
    And the HTML report contains 'data-status="matched"'
    And the HTML report contains 'data-status="parsed"'
    And the HTML report contains 'data-status="failing"'
    And the HTML report contains "Invalid &lt;char&gt; &amp; more"
    And the HTML report has 3 file rows

  Scenario: Markdown summary compares counts with the baseline
    When I render the Markdown summary
    Then the summary contains "| Matched | 1 | 0 | +1 |"
    And the summary contains "| KR-SCAN-003 | 1 |"
