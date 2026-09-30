Feature: Elm lexer
  The scanner turns Elm 0.19.1 source into tokens, following the lexical rules
  of elm-syntax 7.3.9. Tokens are rendered as kind:lexeme, or as the lexeme for
  punctuation.

  Scenario: Module header and keywords
    Given Elm source:
      """elm
      port module Main exposing (Msg(..), view)
      import Html as H
      """
    When I tokenize the source
    Then the tokens are:
      """
      kw:port kw:module upper:Main kw:exposing ( upper:Msg ( .. ) , lower:view ) kw:import upper:Html kw:as upper:H
      """

  Scenario: Words that are not reserved in elm-syntax
    Given Elm source:
      """elm
      type alias Model = infix effect
      """
    When I tokenize the source
    Then the tokens are:
      """
      kw:type lower:alias upper:Model = lower:infix lower:effect
      """

  Scenario: Every operator elm-syntax allows
    Given Elm source:
      """elm
      == /= :: ++ + * <| |> || <= >= |= |. // </> <?> ^ << >> < > / && -
      """
    When I tokenize the source
    Then the tokens are:
      """
      op:== op:/= op::: op:++ op:+ op:* op:<| op:|> op:|| op:<= op:>= op:|= op:|. op:// op:</> op:<?> op:^ op:<< op:>> op:< op:> op:/ op:&& op:-
      """

  Scenario: Punctuation
    Given Elm source:
      """elm
      ( ) [ ] { } , = . .. : | -> \ _
      """
    When I tokenize the source
    Then the tokens are:
      """
      ( ) [ ] { } , = . .. : | -> \ _
      """

  Scenario: Symbol runs split by the longest known token
    Given Elm source:
      """elm
      x =-1
      f :: xs
      a|>b
      """
    When I tokenize the source
    Then the tokens are:
      """
      lower:x = op:- int:1 lower:f op::: lower:xs lower:a op:|> lower:b
      """

  Scenario: Qualified names, record access and access functions
    Given Elm source:
      """elm
      List.map .name r.field Html.Attributes.class
      """
    When I tokenize the source
    Then the tokens are:
      """
      upper:List . lower:map . lower:name lower:r . lower:field upper:Html . upper:Attributes . lower:class
      """

  Scenario: Numbers
    Given Elm source:
      """elm
      0 42 0xFF 0x1a 3.14 1e10 2.5e-3 6E+2
      """
    When I tokenize the source
    Then the tokens are:
      """
      int:0 int:42 int:0xFF int:0x1a float:3.14 float:1e10 float:2.5e-3 float:6E+2
      """

  Scenario: Strings and chars
    Given Elm source:
      """elm
      "plain" "esc \" \n \\ \u{1F308}" 'a' '\'' '\u{41}' "" 
      """
    When I tokenize the source
    Then the tokens are:
      """
      str:"plain" str:"esc \" \n \\ \u{1F308}" char:'a' char:'\'' char:'\u{41}' str:""
      """

  Scenario: Triple-quoted strings span lines
    Given Elm source:
      ```elm
      s = """line one
      "quoted" line two"""
      t = 1
      ```
    When I tokenize the source
    Then the tokens are:
      ```
      lower:s = str:"""line one
      "quoted" line two""" lower:t = int:1
      ```
    And token 4 starts at "3:1"

  Scenario: GLSL block
    Given Elm source:
      """elm
      shader = [glsl| void main() { gl_FragColor = vec4(1.0); } |]
      """
    When I tokenize the source
    Then the tokens are:
      """
      lower:shader = glsl:[glsl| void main() { gl_FragColor = vec4(1.0); } |]
      """

  Scenario: Nested block comments are trivia
    Given Elm source:
      """elm
      a {- outer {- inner -} still outer -} b {-| doc {- nested -} -} c
      """
    When I tokenize the source
    Then the tokens are:
      """
      lower:a lower:b lower:c
      """

  Scenario: Columns after a character outside the BMP count UTF-16 code units
    Given Elm source:
      """elm
      x = "🌈" y
      """
    When I tokenize the source
    Then token 4 starts at "1:10"

  Scenario Outline: Reject characters Elm does not allow
    Given Elm source:
      """elm
      <source>
      """
    When I tokenize the source
    Then tokenization fails with code "<code>"

    Examples:
      | source           | code        |
      | x = @            | KR-SCAN-003 |
      | naïve = 1        | KR-SCAN-003 |
      | s = "unfinished  | KR-SCAN-004 |
      | c = 'x           | KR-SCAN-004 |

  Scenario: Reject a tab
    Given Elm source with a tab
    When I tokenize the source
    Then tokenization fails with code "KR-SCAN-003"
