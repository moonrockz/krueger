Feature: Next release version
  The version script prints the next version that git-cliff computes from
  conventional commits, or the initial version when git-cliff cannot.

  Scenario Outline: Choose the version to print
    Given git-cliff exits with <code> and prints "<stdout>"
    Then the printed version is "<version>"

    Examples:
      | code | stdout   | version |
      | 0    | v0.2.0   | v0.2.0  |
      | 1    | v0.2.0   | v0.1.0  |
      | 0    |          | v0.1.0  |
      | 127  |          | v0.1.0  |
