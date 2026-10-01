///|
test "fold counts the nodes walk visits" {
  let root = parse_root(expression_source)
  let count = @syntax.fold(root, 0, (n, _) => (n + 1, Continue))
  @expect.expect(count).to_equal(preorder(root).length())
}

///|
test "fold threads the accumulator through enter and leave" {
  @expect.expect_all(s => {
    // (depth, deepest): enter goes one level down, leave one level up.
    let (depth, deepest) = @syntax.fold(
      parse_root(small),
      (0, 0),
      (acc, _) => {
        let (d, m) = acc
        ((d + 1, if d + 1 > m { d + 1 } else { m }), Continue)
      },
      leave=(acc, _) => (acc.0 - 1, acc.1),
    )
    s.expect(depth).to_equal(0)
    // file > declaration > implementation > application > integer
    s.expect(deepest).to_equal(5)
  })
}

///|
test "fold runs leave after SkipChildren" {
  let events = @syntax.fold(
    parse_root(small),
    [],
    (acc : Array[String], n) => {
      acc.push("+" + label(n))
      (acc, if n.category() == "declaration" { SkipChildren } else { Continue })
    },
    leave=(acc, n) => {
      acc.push("-" + label(n))
      acc
    },
  )
  let i = events.search("+declaration/function").unwrap()
  @expect.expect(events[i + 1]).to_equal("-declaration/function")
}

///|
test "fold after Stop returns the accumulator from the stopping enter" {
  let result = @syntax.fold(
    parse_root(small),
    "",
    (acc, n) => {
      let next = acc + "+" + n.kind()
      (next, if n.kind() == "name" { Stop } else { Continue })
    },
    leave=(acc, n) => acc + "-" + n.kind(),
  )
  @expect.expect(result).to_equal(
    "+file+normal+module_name-module_name+all-all-normal+function+implementation+name",
  )
}

///|
test "a fold inside a walk callback counts exactly its subtree" {
  let root = parse_root(expression_source)
  let mut sizes = 0
  @syntax.walk(root, n => {
    sizes = sizes + @syntax.fold(n, 0, (k, _) => (k + 1, Continue))
    Continue
  })
  // Each node is counted once per ancestor-or-self: the sum of depth + 1.
  let expected = @syntax.fold(
      root,
      (0, 0),
      (acc, _) => ((acc.0 + 1, acc.1 + acc.0 + 1), Continue),
      leave=(acc, _) => (acc.0 - 1, acc.1),
    ).1
  @expect.expect(sizes).to_equal(expected)
}

///|
test "fold handles a 398-level tree" {
  let root = tree_of(deep_source()).root()
  @expect.expect(@syntax.fold(root, 0, (n, _) => (n + 1, Continue))).to_equal(
    399 + 398 + 7,
  )
}
