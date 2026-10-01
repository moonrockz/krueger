Feature: Release tooling
  A release is a pull request that sets the version in moon.mod and adds its
  section to CHANGELOG.md (`release prepare`). When it merges, the Release
  workflow decides to release (`release plan`), tags the commit, publishes,
  and creates the GitHub release from the section (`release notes`).

  Scenario Outline: Choose the next version from git-cliff
    Given git-cliff exits with <code> and prints "<stdout>"
    Then the printed version is "<version>"

    Examples:
      | code | stdout   | version |
      | 0    | v0.2.0   | v0.2.0  |
      | 1    | v0.2.0   | v0.1.0  |
      | 0    |          | v0.1.0  |
      | 127  |          | v0.1.0  |

  Scenario Outline: Read a version
    When I read the version "<text>"
    Then the version is "<version>"

    Examples:
      | text    | version |
      | 0.3.0   | 0.3.0   |
      | v0.3.0  | 0.3.0   |
      | 1.10.20 | 1.10.20 |
      | v10.0.0 | 10.0.0  |

  Scenario Outline: Reject what is not a version
    When I read the version "<text>"
    Then it fails with "not a version: <text>"

    Examples:
      | text        |
      | 0.3         |
      | 0.3.0.1     |
      | 0.3.x       |
      | 0.3.0-rc.1  |
      | vv0.3.0     |
      | 0..3        |

  Scenario Outline: Choose the release version
    When I choose the release version with request "<request>", computed "<computed>" and current "<current>"
    Then the version is "<version>"

    Examples:
      | request | computed | current | version |
      |         | v0.3.0   | 0.2.0   | 0.3.0   |
      |         | v0.2.1   | 0.2.0   | 0.2.1   |
      | 1.0.0   | v0.3.0   | 0.2.0   | 1.0.0   |
      | v0.2.5  | v0.3.0   | 0.2.0   | 0.2.5   |

  Scenario Outline: The release version must be above the current one
    When I choose the release version with request "<request>", computed "<computed>" and current "<current>"
    Then it fails with "<message>"

    Examples:
      | request | computed | current | message                                                                                   |
      |         | v0.2.0   | 0.2.0   | version 0.2.0 is not above the current version 0.2.0; nothing to release, or pass a higher version |
      | 0.1.9   | v0.3.0   | 0.2.0   | version 0.1.9 is not above the current version 0.2.0; nothing to release, or pass a higher version |
      | next    | v0.3.0   | 0.2.0   | not a version: next                                                                       |

  Scenario: Set the module version
    Given the text:
      """
      name = "moonrockz/krueger"

      version = "0.2.0"

      import {
        "moonrockz/expect@0.6.0",
      }
      """
    When I set the module version to "0.3.0"
    Then moon.mod becomes:
      """
      name = "moonrockz/krueger"

      version = "0.3.0"

      import {
        "moonrockz/expect@0.6.0",
      }
      """

  Scenario: A moon.mod without a version line
    Given the text:
      """
      name = "moonrockz/krueger"
      """
    When I set the module version to "0.3.0"
    Then the module has no version line

  Scenario: Tidy a changelog after git cliff --prepend
    Given the text:
      """
      # Changelog

      <!-- git-cliff: end of header -->


      ## [0.3.0] - 2026-10-02


      - Two


      ## [0.2.0] - 2026-10-01

      - One

      """
    When I tidy the changelog
    Then the result is:
      """
      # Changelog

      <!-- git-cliff: end of header -->

      ## [0.3.0] - 2026-10-02

      - Two

      ## [0.2.0] - 2026-10-01

      - One
      """

  Scenario: Take one version's section
    Given the text:
      """
      # Changelog

      ## [0.3.0] - 2026-10-02

      Highlights of 0.3.0.

      ### 🚀 Features

      - Two ([#40](https://github.com/moonrockz/krueger/pull/40))

      ## [0.2.0] - 2026-10-01

      - One
      """
    When I take the changelog section for "v0.3.0"
    Then the result is:
      """
      Highlights of 0.3.0.

      ### 🚀 Features

      - Two ([#40](https://github.com/moonrockz/krueger/pull/40))
      """

  Scenario: Take the last section
    Given the text:
      """
      ## [0.3.0] - 2026-10-02

      - Two

      ## [0.2.0] - 2026-10-01

      - One
      """
    When I take the changelog section for "0.2.0"
    Then the result is:
      """
      - One
      """

  Scenario Outline: No section for the version
    Given the text:
      """
      ## [0.3.0] - 2026-10-02

      - Two

      ## [0.2.0] - 2026-10-01
      """
    When I take the changelog section for "<version>"
    Then there is no section

    Examples:
      | version |
      | 0.4.0   |
      | 0.3.1   |
      | 0.30.0  |

  Scenario: A section with no lines is still a section
    Given the text:
      """
      ## [0.3.0] - 2026-10-02
      """
    When I take the changelog section for "0.3.0"
    Then the section is empty

  Scenario: Release notes start with the install line
    Given the text:
      """
      Highlights of 0.3.0.

      ### 🚀 Features

      - Two
      """
    When I make the release notes for "0.3.0"
    Then the result is:
      """
      **Install:** `moon add moonrockz/krueger@0.3.0` · [mooncakes.io](https://mooncakes.io/docs/moonrockz/krueger)

      Highlights of 0.3.0.

      ### 🚀 Features

      - Two
      """

  Scenario Outline: Decide whether a Release run releases
    Given the ref type is "<type>" and the ref name is "<name>"
    And the tag exists: "<tagged>"
    And the changelog has the section: "<section>"
    Then the plan for version "0.3.0" is "<plan>"

    Examples:
      | type   | name   | tagged | section | plan                                                                                      |
      | branch | main   | no     | yes     | release 0.3.0                                                                             |
      | branch | main   | yes    | yes     | skip: v0.3.0 is already tagged; nothing to release                                        |
      | branch | main   | yes    | no      | skip: v0.3.0 is already tagged; nothing to release                                        |
      | branch | main   | no     | no      | error: CHANGELOG.md has no section for 0.3.0; release with `mise run release:prepare`     |
      | tag    | v0.3.0 | yes    | yes     | release 0.3.0                                                                             |
      | tag    | v0.3.0 | yes    | no      | error: CHANGELOG.md has no section for 0.3.0; release with `mise run release:prepare`     |
      | tag    | v0.4.0 | yes    | yes     | error: tag v0.4.0 does not match moon.mod version 0.3.0 (v0.3.0)                          |
      | tag    | 0.3.0  | yes    | yes     | error: tag 0.3.0 does not match moon.mod version 0.3.0 (v0.3.0)                           |

  Scenario: Outputs for the workflow
    Then the outputs for a release of "0.3.0" are:
      """
      release=true
      version=0.3.0
      tag=v0.3.0
      """
