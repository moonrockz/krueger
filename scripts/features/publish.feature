Feature: Publish to mooncakes.io
  The publish script publishes the version in moon.mod. A release tag must
  name that version, so a forgotten version bump fails. A second release run
  for the same tag (GitHub can start two for one tag push) finds the version
  already published and succeeds without publishing again.

  Scenario: Read the version from moon.mod
    Given moon.mod is:
      """
      name = "moonrockz/krueger"

      version = "0.2.0"

      import {
        "moonrockz/expect@0.6.0",
      }
      """
    Then the module version is "0.2.0"

  Scenario: moon.mod without a version
    Given moon.mod is:
      """
      name = "moonrockz/krueger"
      """
    Then the module has no version

  Scenario Outline: A release tag must name the module version
    Given the ref type is "<type>" and the ref name is "<name>"
    When I check the ref against version "0.2.0"
    Then the check gives "<result>"

    Examples:
      | type   | name   | result                                                    |
      | tag    | v0.2.0 | ok                                                        |
      | tag    | v0.3.0 | tag v0.3.0 does not match moon.mod version 0.2.0 (v0.2.0) |
      | tag    | 0.2.0  | tag 0.2.0 does not match moon.mod version 0.2.0 (v0.2.0)  |
      | branch | main   | ok                                                        |
      |        |        | ok                                                        |

  Scenario Outline: Classify the result of moon publish
    Given moon publish exits with <code> and prints "<output>"
    Then the outcome is "<outcome>"

    Examples:
      | code | output                                                                                  | outcome           |
      | 0    | Server status: 200 OK                                                                   | published         |
      | 255  | Server status: 409 Conflict, detail: Version Error: The version you are attempting to upload (0.2.0) is duplicated with an existing version (0.2.0). | already published |
      | 255  | Server status: 401 Unauthorized                                                         | failed            |
      | 1    | Check failed                                                                            | failed            |
