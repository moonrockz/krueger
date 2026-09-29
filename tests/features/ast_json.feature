Feature: elm-syntax JSON model
  krueger's syntax tree mirrors stil4m/elm-syntax 7.3.9. Decoding the
  elm-syntax JSON of a file and encoding it again gives the same bytes.

  Scenario Outline: Round-trip elm-syntax output
    Given the elm-syntax JSON fixture "<fixture>"
    When I decode and encode the fixture
    Then the encoded JSON equals the fixture byte for byte

    Examples:
      | fixture       |
      | module_normal |
      | module_port   |
      | module_effect |
      | declarations  |
      | expressions   |
      | patterns      |
