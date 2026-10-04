Feature: Unicode identifier table
  The generator reads UnicodeData.txt and writes the code point ranges the
  lexer uses for identifiers.

  Scenario: Classes from general categories, merged into ranges
    Given the Unicode data:
      """
      0041;LATIN CAPITAL LETTER A;Lu;0;L;;;;;N;;;;0061;
      0042;LATIN CAPITAL LETTER B;Lu;0;L;;;;;N;;;;0062;
      0061;LATIN SMALL LETTER A;Ll;0;L;;;;;N;;;0041;;0041
      0062;LATIN SMALL LETTER B;Ll;0;L;;;;;N;;;0042;;0042
      01C5;LATIN CAPITAL LETTER D WITH SMALL LETTER Z WITH CARON;Lt;0;L;<compat> 0044 017E;;;;N;;;01C4;01C6;01C5
      0660;ARABIC-INDIC DIGIT ZERO;Nd;0;AN;;0;0;0;N;;;;;
      2081;SUBSCRIPT ONE;No;0;EN;<sub> 0031;;1;1;N;SUBSCRIPT DIGIT ONE;;;;
      3400;<CJK Ideograph Extension A, First>;Lo;0;L;;;;;N;;;;;
      4DBF;<CJK Ideograph Extension A, Last>;Lo;0;L;;;;;N;;;;;
      """
    Then the lower-start ranges are "0061-0062"
    And the upper-start ranges are "0041-0042, 01C5-01C5"
    And the inner ranges are "0041-0042, 0061-0062, 01C5-01C5, 0660-0660, 2081-2081, 3400-4DBF"
    And the title-case ranges are "01C5-01C5"
    And the non-ASCII number ranges are "0660-0660, 2081-2081"

  Scenario: Characters that a printed literal writes as they are
    elm-format 0.8.7 escapes a character when Haskell's isPrint is false
    (Cc, Cf, Cs, Co, Zl, Zp and unassigned code points) or isSpace is true
    (Zs), except the space U+0020.
    Given the Unicode data:
      """
      0009;<control>;Cc;0;S;;;;;N;CHARACTER TABULATION;;;;
      0020;SPACE;Zs;0;WS;;;;;N;;;;;
      0021;EXCLAMATION MARK;Po;0;ON;;;;;N;;;;;
      0041;LATIN CAPITAL LETTER A;Lu;0;L;;;;;N;;;;0061;
      00A0;NO-BREAK SPACE;Zs;0;CS;<noBreak> 0020;;;;N;NON-BREAKING SPACE;;;;
      00A1;INVERTED EXCLAMATION MARK;Po;0;ON;;;;;N;;;;;
      06DD;ARABIC END OF AYAH;Cf;0;AN;;;;;N;;;;;
      2028;LINE SEPARATOR;Zl;0;WS;;;;;N;;;;;
      3400;<CJK Ideograph Extension A, First>;Lo;0;L;;;;;N;;;;;
      4DBF;<CJK Ideograph Extension A, Last>;Lo;0;L;;;;;N;;;;;
      E000;<Private Use, First>;Co;0;L;;;;;N;;;;;
      F8FF;<Private Use, Last>;Co;0;L;;;;;N;;;;;
      """
    Then the literal plain ranges are "0020-0021, 0041-0041, 00A1-00A1, 3400-4DBF"

  Scenario: Markdown character classes
    elm-format's Markdown parser uses Haskell's isLetter (L*), isAlphaNum
    (L* and N*) and isSpace (Zs and U+0009 to U+000D).
    Given the Unicode data:
      """
      0009;<control>;Cc;0;S;;;;;N;CHARACTER TABULATION;;;;
      000A;<control>;Cc;0;B;;;;;N;LINE FEED (LF);;;;
      000B;<control>;Cc;0;S;;;;;N;LINE TABULATION;;;;
      000C;<control>;Cc;0;WS;;;;;N;FORM FEED (FF);;;;
      000D;<control>;Cc;0;B;;;;;N;CARRIAGE RETURN (CR);;;;
      0020;SPACE;Zs;0;WS;;;;;N;;;;;
      0030;DIGIT ZERO;Nd;0;EN;;0;0;0;N;;;;;
      0041;LATIN CAPITAL LETTER A;Lu;0;L;;;;;N;;;;0061;
      005F;LOW LINE;Pc;0;ON;;;;;N;SPACING UNDERSCORE;;;;
      00A0;NO-BREAK SPACE;Zs;0;CS;<noBreak> 0020;;;;N;NON-BREAKING SPACE;;;;
      00AA;FEMININE ORDINAL INDICATOR;Lo;0;L;<super> 0061;;;;N;;;;;
      2028;LINE SEPARATOR;Zl;0;WS;;;;;N;;;;;
      """
    Then the letter ranges are "0041-0041, 00AA-00AA"
    And the inner ranges are "0030-0030, 0041-0041, 00AA-00AA"
    And the space ranges are "0009-000D, 0020-0020, 00A0-00A0"
