///|
test "doc code accepts elm-format's tuple functions, negative list items and orphan annotations" {
  @expect.expect_all(s => {
    for
      (input, expected) in [
        ("(,)  a  b", "(,) a b\n"),
        ("List.map (,,) xs", "List.map (,,) xs\n"),
        ("[-2,-1,0]", "[ -2, -1, 0 ]\n"),
        ("compare : a -> a -> Order", "compare : a -> a -> Order\n"),
        ("f : Int\ng : Int\ng = 1", "f : Int\n\ng : Int\ng =\n    1\n"),
      ] {
      s
      .expect(
        format_code(
          input,
          @dialect.Dialect::elm_0_19_1(),
          @dialect.DEFAULT_FUEL,
          0,
        ),
      )
      .to_equal(Some(expected))
    }
  })
}

///|
test "doc code joins column-one operator lines and accepts ellipses and repeated comparisons" {
  @expect.expect_all(s => {
    for
      (input, expected) in [
        (
          "isUpper 'B' == True\n...\nisUpper 'Z' == True", "isUpper 'B'\n    == True\n    ... isUpper 'Z'\n    == True\n",
        ),
        (
          "14 / 4 == 3.5\n-1 / 4 == -0.25", "14\n    / 4\n    == 3.5\n    - 1\n    / 4\n    == -0.25\n",
        ),
        ("a\n|> f", "a\n    |> f\n"),
      ] {
      s
      .expect(
        format_code(
          input,
          @dialect.Dialect::elm_0_19_1(),
          @dialect.DEFAULT_FUEL,
          0,
        ),
      )
      .to_equal(Some(expected))
    }
  })
}

///|
test "doc code formats legacy infix functions and top-level destructuring with trailing comments" {
  @expect.expect_all(s => {
    for
      (input, expected) in [
        ("diff = x `xor` y\n\n-- why", "\ndiff =\n    x `xor` y\n\n-- why\n"),
        (
          "dict = 1\n(lower,higher) = split 2 dict\n\n-- why", "\ndict =\n    1\n\n( lower, higher ) =\n    split 2 dict\n\n-- why\n",
        ),
        ("f : Int\nf : a", "f : Int\nf : a\n"),
        ("x `foo` y `bar` z", "x `foo` y `bar` z\n"),
        ("\"(,) `foo` [-1]\"", "\"(,) `foo` [-1]\"\n"),
      ] {
      s
      .expect(
        format_code(
          input,
          @dialect.Dialect::elm_0_19_1(),
          @dialect.DEFAULT_FUEL,
          0,
        ),
      )
      .to_equal(Some(expected))
    }
  })
}
