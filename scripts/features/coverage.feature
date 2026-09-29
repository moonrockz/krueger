Feature: Coverage report
  The coverage script merges the coverage artifacts of several test runs
  and prints one summary for the non-test modules.

  Scenario: Merge artifacts from several test runs
    Given a coverage artifact:
      """
      moon test output that is not coverage
      ----- BEGIN MOONBIT COVERAGE -----
      { "m$lib": [1, 0, 0], "m$lib_test": [5] }
      ----- END MOONBIT COVERAGE -----
      """
    And a coverage artifact:
      """
      ----- BEGIN MOONBIT COVERAGE -----
      { "m$lib": [0, 3], "m$types": [] }
      ----- END MOONBIT COVERAGE -----
      """
    When I build the coverage report
    Then the report is:
      """
      Coverage summary: 66.67% (2/3 covered branch points)
       - m$lib: 66.67% (2/3)
       - m$types: 100% (0/0)
      """

  Scenario: Artifacts without coverage payloads
    Given a coverage artifact:
      """
      no coverage markers here
      """
    When I build the coverage report
    Then there is no report

  Scenario: Truncated payload
    Given a coverage artifact:
      """
      ----- BEGIN MOONBIT COVERAGE -----
      { "m$lib": [3, 0,
      ----- END MOONBIT COVERAGE -----
      """
    When I build the coverage report
    Then building the report fails

  Scenario: Payload cut off before the end marker
    Given a coverage artifact:
      """
      ----- BEGIN MOONBIT COVERAGE -----
      { "m$lib": [1, 1] }
      ----- END MOONBIT COVERAGE -----
      """
    And a coverage artifact:
      """
      ----- BEGIN MOONBIT COVERAGE -----
      { "m$other": [0, 0, 0, 0,
      """
    When I build the coverage report
    Then building the report fails

  Scenario Outline: Threshold outcome
    Given the total coverage is <total>%
    When I check it against <threshold>% in <mode> mode
    Then the outcome is "<outcome>"

    Examples:
      | total | threshold | mode | outcome |
      | 80.0  | 80        | gate | pass    |
      | 79.5  | 80        | gate | failure |
      | 79.5  | 80        | warn | warning |
      | 91.56 | 80        | warn | pass    |
