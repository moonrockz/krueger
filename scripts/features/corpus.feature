Feature: Elm parity corpus manifest
  The corpus script reads a list of pinned packages and keeps a manifest with
  the package zip hash and the hash of every Elm source file.

  Scenario: Read the package list
    Given the package list:
      """
      # core packages
      elm/core@1.0.5

      elm/json@1.1.4
      """
    When I read the package list
    Then the packages are "elm/core@1.0.5, elm/json@1.1.4"

  Scenario: Reject a malformed package line
    Given the package list:
      """
      elm/core
      """
    When I read the package list
    Then reading fails with "invalid package line: elm/core"

  Scenario: Manifest survives a write and read
    Given a manifest entry for "elm/json@1.1.4" with file "src/Json/Decode.elm" hashed "ab12"
    When I write and read the manifest
    Then the manifest entry is unchanged
