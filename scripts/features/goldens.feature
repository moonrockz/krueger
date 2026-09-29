Feature: Oracle output for the parity corpus
  The goldens script runs the elm-syntax oracle over the corpus and maps each
  oracle result back to its corpus key.

  Scenario: List corpus keys from a manifest
    Given the manifest:
      """
      {"packages": [{"name": "elm/json", "version": "1.1.4", "files": [{"path": "src/Json/Decode.elm", "sha256": "ab"}, {"path": "src/Json/Encode.elm", "sha256": "cd"}]}]}
      """
    Then the corpus keys are "elm/json@1.1.4/src/Json/Decode.elm, elm/json@1.1.4/src/Json/Encode.elm"

  Scenario: Map a parsed result to its corpus key
    Given the oracle line:
      """
      {"name": ".corpus/elm/json@1.1.4/src/Json/Decode.elm", "ok": true, "file": {"imports": []}}
      """
    When I read the oracle line with corpus ".corpus"
    Then the result is parsed for "elm/json@1.1.4/src/Json/Decode.elm"

  Scenario: Map a rejected result to its corpus key
    Given the oracle line:
      """
      {"name": ".corpus/a/b@1.0.0/src/A.elm", "ok": false, "error": "expecting symbol ="}
      """
    When I read the oracle line with corpus ".corpus"
    Then the result is rejected for "a/b@1.0.0/src/A.elm" with "expecting symbol ="
