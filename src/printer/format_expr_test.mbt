///|
fn body(lines : String) -> String {
  "module A exposing (..)\n\n\nv =\n" + lines
}

///|
test "application: break before a later argument" {
  @expect.expect(@printer.format(body("  f x\n    y\n"))).to_equal(
    body("    f x\n        y\n"),
  )
}

///|
test "application: break before the first argument" {
  @expect.expect(@printer.format(body("  f\n    x y\n"))).to_equal(
    body("    f\n        x\n        y\n"),
  )
}

///|
test "list: a break anywhere gives one item per line" {
  @expect.expect(@printer.format(body("  [ 1, 2\n    , 3 ]\n"))).to_equal(
    body("    [ 1\n    , 2\n    , 3\n    ]\n"),
  )
}

///|
test "record on one line stays on one line" {
  @expect.expect(@printer.format(body("  { a = 1, b = 2 }\n"))).to_equal(
    body("    { a = 1, b = 2 }\n"),
  )
}

///|
test "tuple with a break" {
  @expect.expect(@printer.format(body("  ( 1,\n  2 )\n"))).to_equal(
    body("    ( 1\n    , 2\n    )\n"),
  )
}

///|
test "lambda with the body on the next line" {
  @expect.expect(@printer.format(body("  \\x ->\n    x\n"))).to_equal(
    body("    \\x ->\n        x\n"),
  )
}

///|
test "pipeline on one line, and broken" {
  @expect.expect_all(s => {
    s
    .expect(@printer.format(body("  a |> f |> g\n")))
    .to_equal(body("    a |> f |> g\n"))
    s
    .expect(@printer.format(body("  a\n    |> f\n    |> g\n")))
    .to_equal(body("    a\n        |> f\n        |> g\n"))
  })
}

///|
test "operator with a trailing line comment" {
  @expect.expect(@printer.format(body("  x + -- note\n    y\n"))).to_equal(
    body("    x\n        + -- note\n          y\n"),
  )
}

///|
test "application: a multi-line later argument keeps the first argument on the line" {
  // elm-format ElmStructure.application (FAJoinFirst JoinAll): the first
  // argument stays on the line when it is on one line.
  @expect.expect(@printer.format(body("  f a (if c then 1 else 2) b\n"))).to_equal(
    body(
      "    f a\n        (if c then\n            1\n\n         else\n            2\n        )\n        b\n",
    ),
  )
}

///|
test "application: a multi-line first argument puts every argument on its own line" {
  @expect.expect(@printer.format(body("  f (if c then 1 else 2) a b\n"))).to_equal(
    body(
      "    f\n        (if c then\n            1\n\n         else\n            2\n        )\n        a\n        b\n",
    ),
  )
}

///|
test "application: a multi-line function puts every argument on its own line" {
  @expect.expect(@printer.format(body("  (\\x ->\n  x) a b\n"))).to_equal(
    body("    (\\x ->\n        x\n    )\n        a\n        b\n"),
  )
}

///|
test "application: a multi-line record after a joined argument" {
  @expect.expect(
    @printer.format(body("  State NotAnimating { a = 1\n    , b = 2 }\n")),
  ).to_equal(
    body(
      "    State NotAnimating\n        { a = 1\n        , b = 2\n        }\n",
    ),
  )
}

///|
test "operators: a multi-line operand breaks the operators up to it" {
  // elm-format Box.hs formatBinary folds from the left: an operator goes on
  // a new line when an operand before it, or its own operand, is multi-line.
  @expect.expect_all(s => {
    s
    .expect(@printer.format(body("  a + b + (if c then 1 else 2)\n")))
    .to_equal(
      body(
        "    a + b\n        + (if c then\n            1\n\n           else\n            2\n          )\n",
      ),
    )
    s
    .expect(@printer.format(body("  a + (if c then 1 else 2) + b\n")))
    .to_equal(
      body(
        "    a\n        + (if c then\n            1\n\n           else\n            2\n          )\n        + b\n",
      ),
    )
  })
}

///|
test "operators: a break in the chain puts every operator on its own line" {
  @expect.expect(@printer.format(body("  a + b + f (\\y ->\n  y)\n"))).to_equal(
    body(
      "    a\n        + b\n        + f\n            (\\y ->\n                y\n            )\n",
    ),
  )
}

///|
test "record update with a break" {
  @expect.expect(@printer.format(body("  { r | a = 1\n  , b = 2 }\n"))).to_equal(
    body("    { r\n        | a = 1\n        , b = 2\n    }\n"),
  )
}

///|
test "record field with a break after the equals sign" {
  @expect.expect(@printer.format(body("  { a =\n    1, b = 2 }\n"))).to_equal(
    body("    { a =\n        1\n    , b = 2\n    }\n"),
  )
}

///|
test "lambda on one line with a multi-line body" {
  @expect.expect(@printer.format(body("  \\x -> if x then 1 else 2\n"))).to_equal(
    body(
      "    \\x ->\n        if x then\n            1\n\n        else\n            2\n",
    ),
  )
}

///|
test "case with a break around the subject" {
  @expect.expect(@printer.format(body("  case\n    x of\n    _ -> 1\n"))).to_equal(
    body("    case\n        x\n    of\n        _ ->\n            1\n"),
  )
}

///|
test "if with a break in the condition" {
  // elm-format has no source rule for `if`: the condition joins.
  @expect.expect(@printer.format(body("  if\n    x then 1 else 2\n"))).to_equal(
    body("    if x then\n        1\n\n    else\n        2\n"),
  )
}

///|
test "comments around an operator join it as elm-format parses them" {
  // elm-format Parse/Binop.hs: the comments before an operator and after
  // it belong to that operator (`BinopsClause`), also when they are on the
  // row of the operand before it.
  @expect.expect_all(s => {
    s
    .expect(@printer.format(body("  x + {- a -}\n    y\n")))
    .to_equal(body("    x\n        + {- a -} y\n"))
    s
    .expect(@printer.format(body("  x {- b -} +\n    y\n")))
    .to_equal(body("    x\n        {- b -} + y\n"))
    s
    .expect(@printer.format(body("  x {- b -} + y\n")))
    .to_equal(body("    x {- b -} + y\n"))
    s
    .expect(@printer.format(body("  x\n    {- c -}\n    + y\n")))
    .to_equal(body("    x\n        {- c -} + y\n"))
    s
    .expect(@printer.format(body("  x {- b -} + -- note\n    y\n")))
    .to_equal(body("    x\n        {- b -}\n        + -- note\n          y\n"))
    s
    .expect(@printer.format(body("  f <| -- c\n    g\n")))
    .to_equal(body("    f <|\n        -- c\n        g\n"))
    s
    .expect(@printer.format(body("  f x <| {- c -} g\n")))
    .to_equal(body("    f x <| {- c -} g\n"))
  })
}

///|
test "comments before a <| go before it" {
  // elm-format Box.hs formatBinary: the comments before `<|` stay on its
  // side (`spaceSepOrStack left (comments ++ [op])`); those after it go
  // before the rest of the chain.
  @expect.expect_all(s => {
    s
    .expect(@printer.format(body("  f x {- c -} <| g\n")))
    .to_equal(body("    f x {- c -} <| g\n"))
    s
    .expect(@printer.format(body("  f x -- c\n    <| g\n")))
    .to_equal(body("    f x\n    -- c\n    <|\n        g\n"))
    s
    .expect(@printer.format(body("  f x\n    {- c -}\n    <| g\n")))
    .to_equal(body("    f x {- c -} <|\n        g\n"))
    s
    .expect(@printer.format(body("  f x <| {- c -} g\n")))
    .to_equal(body("    f x <| {- c -} g\n"))
    s
    .expect(@printer.format(body("  f x <| -- c\n    g\n")))
    .to_equal(body("    f x <|\n        -- c\n        g\n"))
    s
    .expect(@printer.format(body("  a + b <| -- c\n    g\n")))
    .to_equal(body("    a\n        + b\n    <|\n        -- c\n        g\n"))
    s
    .expect(@printer.format(body("  a\n    + b\n    {- c -}\n    <| g\n")))
    .to_equal(body("    a\n        + b\n    {- c -}\n    <|\n        g\n"))
  })
}

///|
test "Width layout: comments around operators" {
  // The Width layout puts the comments where elm-format puts them, and
  // breaks the chain only when it does not fit or a line comment ends a
  // line.
  let width = (s : String) => @printer.format(body(s), layout=Width(120))
  @expect.expect_all(s => {
    s
    .expect(width("  f x {- c -} <| g\n"))
    .to_equal(body("    f x {- c -} <| g\n"))
    s
    .expect(width("  f x -- c\n    <| g\n"))
    .to_equal(body("    f x\n    -- c\n    <|\n        g\n"))
    s
    .expect(width("  f x <| -- c\n    g\n"))
    .to_equal(body("    f x <|\n        -- c\n        g\n"))
    s
    .expect(width("  x\n    {- c -}\n    + y\n"))
    .to_equal(body("    x {- c -} + y\n"))
    s
    .expect(width("  x {- b -} + -- note\n    y\n"))
    .to_equal(body("    x\n        {- b -}\n        + -- note\n          y\n"))
  })
}

///|
test "comments before then and else stay with the condition and the branch" {
  // elm-format 0.8.7 output for each source (Parse/Expression.hs ifClause:
  // the comments before `then` follow the condition, and the comments
  // before `else` follow the branch before it; Box.hs If).
  let x = (body : String) => "module A exposing (..)\n\n\nx =\n" + body
  @expect.expect_all(s => {
    for
      case_ in [
        (
          "    if a then\n        b\n    -- c\n    else\n        d\n", "    if a then\n        b\n        -- c\n\n    else\n        d\n",
        ),
        (
          "    if a\n        -- c\n    then\n        b\n\n    else\n        d\n",
          "    if\n        a\n        -- c\n    then\n        b\n\n    else\n        d\n",
        ),
        (
          "    if a {- c -} then\n        b\n\n    else\n        d\n", "    if a {- c -} then\n        b\n\n    else\n        d\n",
        ),
        (
          "    if a then\n        b\n        {- c -}\n\n    else\n        d\n", "    if a then\n        b\n        {- c -}\n\n    else\n        d\n",
        ),
        (
          "    if a then\n        b\n        -- c\n\n    else if e then\n        f\n        -- g\n\n    else\n        d\n",
          "    if a then\n        b\n        -- c\n\n    else if e then\n        f\n        -- g\n\n    else\n        d\n",
        ),
        (
          "    if a then b {- c -} else d\n", "    if a then\n        b\n        {- c -}\n\n    else\n        d\n",
        ),
        (
          "    if a then\n        b\n    else -- c\n        d\n", "    if a then\n        b\n\n    else\n        -- c\n        d\n",
        ),
        (
          "    if a then\n        b\n    -- c\n    else if e then\n        f\n    else\n        d\n",
          "    if a then\n        b\n        -- c\n\n    else if e then\n        f\n\n    else\n        d\n",
        ),
      ] {
      let (source, expected) = case_
      s.expect(@printer.format(x(source))).to_equal(x(expected))
    }
  })
}

///|
test "a comment after an argument goes before the next argument" {
  // elm-format 0.8.7 output for each source (Parse/Expression.hs appExpr:
  // the comments before an argument are its own, `formatPreCommented`).
  let x = (body : String) => "module A exposing (..)\n\n\nx =\n" + body
  @expect.expect_all(s => {
    for
      case_ in [
        ("    f x -- why\n        y\n", "    f x\n        -- why\n        y\n"),
        (
          "    f\n        a -- c\n        b\n", "    f\n        a\n        -- c\n        b\n",
        ),
        ("    f x {- c -} y\n", "    f x {- c -} y\n"),
        ("    f (x) -- c\n        y\n", "    f x\n        -- c\n        y\n"),
      ] {
      let (source, expected) = case_
      s.expect(@printer.format(x(source))).to_equal(x(expected))
    }
  })
}
