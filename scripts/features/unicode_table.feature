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
