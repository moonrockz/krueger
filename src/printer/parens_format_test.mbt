///|
/// A module with the declarations `decls`.
fn parens_module(decls : String) -> String {
  "module A exposing (..)\n\n\n" + decls
}

///|
test "parentheses that the parse does not need go" {
  // elm-format Box.hs formatExpression `Parens`: parentheses with no
  // comments inside go; `syntaxParens` adds the ones the context needs.
  @expect.expect(
    @printer.format(
      parens_module(
        "a =\n    case (f x) of\n        _ ->\n            if (Bitwise.and a b) == 0 then\n                a - (f b) - c\n\n            else\n                [ (f x), (a + b), ((g y)), (-x), ((1)), (a.b) ]\n",
      ),
    ),
  ).to_equal(
    parens_module(
      "a =\n    case f x of\n        _ ->\n            if Bitwise.and a b == 0 then\n                a - f b - c\n\n            else\n                [ f x, a + b, g y, -x, 1, a.b ]\n",
    ),
  )
}

///|
test "record values, tuple items, lambda bodies, heads and operands lose them" {
  @expect.expect(
    @printer.format(
      parens_module(
        "b =\n    { a = (f x), b = ( (f x), 1 ), c = \\x -> (f x), d = (f) x, e = (SubTree node) :: acc }\n",
      ),
    ),
  ).to_equal(
    parens_module(
      "b =\n    { a = f x, b = ( f x, 1 ), c = \\x -> f x, d = f x, e = SubTree node :: acc }\n",
    ),
  )
}

///|
test "arguments keep only the parentheses that they need" {
  @expect.expect_all(s => {
    s
    .expect(
      @printer.format(
        parens_module("c =\n    x |> (&&) (signed) |> (f x) |> (\\y -> y)\n"),
      ),
    )
    .to_equal(parens_module("c =\n    x |> (&&) signed |> f x |> (\\y -> y)\n"))
    s
    .expect(
      @printer.format(
        parens_module("d =\n    a + (-x) + (f (-x)) + (-(f x))\n"),
      ),
    )
    .to_equal(parens_module("d =\n    a + -x + f -x + -(f x)\n"))
    s
    .expect(@printer.format(parens_module("e =\n    f (a.b) (A.b) ((x))\n")))
    .to_equal(parens_module("e =\n    f a.b A.b x\n"))
  })
}

///|
test "parentheses with a comment inside stay" {
  @expect.expect_all(s => {
    s
    .expect(
      @printer.format(
        parens_module(
          "e =\n    [ (f x {- c -}), ({- c -} f x), {- e -} (f x) ]\n",
        ),
      ),
    )
    .to_equal(
      parens_module("e =\n    [ (f x {- c -}), ({- c -} f x), {- e -} f x ]\n"),
    )
    s
    .expect(
      @printer.format(
        parens_module("j =\n    [ (-- c\n       f x\n      )\n    ]\n"),
      ),
    )
    .to_equal(parens_module("j =\n    [ (-- c\n       f x\n      )\n    ]\n"))
  })
}

///|
test "a lambda, if or case at the end of a chain gets parentheses, except after <|" {
  // elm-format Box.hs formatBinops: the last operand is `AmbiguousEnd`
  // only after `<|`.
  @expect.expect_all(s => {
    s
    .expect(
      @printer.format(
        parens_module(
          "h =\n    (\\x -> x) <| (\\y -> y)\n\n\nk =\n    f <| a + \\x -> x\n\n\nl =\n    (f <| \\x -> x) |> g\n",
        ),
      ),
    )
    .to_equal(
      parens_module(
        "h =\n    (\\x -> x) <| \\y -> y\n\n\nk =\n    f <| a + (\\x -> x)\n\n\nl =\n    (f <| \\x -> x) |> g\n",
      ),
    )
    s
    .expect(
      @printer.format(
        parens_module("i =\n    x ++ case y of\n        _ ->\n            z\n"),
      ),
    )
    .to_equal(
      parens_module(
        "i =\n    x\n        ++ (case y of\n                _ ->\n                    z\n           )\n",
      ),
    )
    s
    .expect(@printer.format(parens_module("g =\n    a + if c then x else y\n")))
    .to_equal(
      parens_module(
        "g =\n    a\n        + (if c then\n            x\n\n           else\n            y\n          )\n",
      ),
    )
    s
    .expect(
      @printer.format(
        parens_module("c =\n    x\n        |> \\y ->\n            y\n"),
      ),
    )
    .to_equal(
      parens_module(
        "c =\n    x\n        |> (\\y ->\n                y\n           )\n",
      ),
    )
  })
}

///|
test "parentheses that group operators stay" {
  @expect.expect(
    @printer.format(
      parens_module(
        "j =\n    a |> (f <| x) |> (g <| y)\n\n\nk =\n    (f x).y\n\n\nm =\n    (a + b) + (c * d) + ((f x)) + (f x)\n",
      ),
    ),
  ).to_equal(
    parens_module(
      "j =\n    a |> (f <| x) |> (g <| y)\n\n\nk =\n    (f x).y\n\n\nm =\n    (a + b) + (c * d) + f x + f x\n",
    ),
  )
}

///|
test "krueger keeps the parentheses that the parser needs where elm-format does not" {
  // elm-format writes `--x` (a comment) and `"s".length` (a syntax
  // error); krueger keeps the parentheses.
  @expect.expect(
    @printer.format(
      parens_module("l =\n    -(-x)\n\n\nd =\n    (\"s\").length\n"),
    ),
  ).to_equal(parens_module("l =\n    -(-x)\n\n\nd =\n    (\"s\").length\n"))
}

///|
test "a chain of |> and <| stays flat, as the source has it" {
  @expect.expect(
    @printer.format(
      parens_module(
        "a =\n    a {- c -} |> f <| g\n\n\nb =\n    a |> f <| g |> h\n",
      ),
    ),
  ).to_equal(
    parens_module(
      "a =\n    a {- c -} |> f <| g\n\n\nb =\n    a |> f <| g |> h\n",
    ),
  )
}

///|
test "constructor patterns get parentheses before :: and in as" {
  // elm-format Box.hs formatPattern: the operands of `::` and the pattern
  // of `as` are `SpaceSeparated`.
  @expect.expect(
    @printer.format(
      parens_module(
        "g x =\n    case x of\n        Parser parse :: rest ->\n            1\n\n        Good _ _ _ as step ->\n            2\n\n        x :: Foo y ->\n            3\n\n        (Just a) :: (Just b) :: ((Just c) as d) ->\n            4\n\n\nh (Token oStr oX as open) =\n    let\n        (Wrap w) =\n            w\n    in\n    w\n",
      ),
    ),
  ).to_equal(
    parens_module(
      "g x =\n    case x of\n        (Parser parse) :: rest ->\n            1\n\n        (Good _ _ _) as step ->\n            2\n\n        x :: (Foo y) ->\n            3\n\n        (Just a) :: (Just b) :: ((Just c) as d) ->\n            4\n\n\nh ((Token oStr oX) as open) =\n    let\n        (Wrap w) =\n            w\n    in\n    w\n",
    ),
  )
}

///|
test "print_file and normalize_file apply the same parentheses" {
  let source = parens_module(
    "a =\n    case (f x) of\n        Just y :: z ->\n            [ (g y), x |> \\v -> v ]\n",
  )
  let expected = parens_module(
    "a =\n    case f x of\n        (Just y) :: z ->\n            [ g y, x |> (\\v -> v) ]\n",
  )
  let parse = (text : String) => {
    @parser.parse_module(
      @scanner.SourceText::new(text),
      @scanner.DefaultScanner::new(),
    ).ast.unwrap()
  }
  let file = parse(source)
  @expect.expect_all(s => {
    s.expect(@printer.print_file(file)).to_equal(expected)
    s
    .expect(@lawkit.without_ranges(@printer.normalize_file(file)))
    .to_equal(@lawkit.without_ranges(parse(expected)))
  })
}
