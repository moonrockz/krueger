///|
test "a start node's path is empty" {
  @expect.expect_all(s => {
    let path = @syntax.NodePath::root()
    s.expect(path.depth()).to_equal(0)
    s.expect(path.steps()).to_equal([])
    s.expect(path.last()).to_equal(None)
    s.expect(path.parent()).to_equal(None)
    s.expect(path.to_string()).to_equal("")
  })
}

///|
test "a path names each field and index from the start node" {
  @expect.expect_all(s => {
    let path = @syntax.NodePath::root()
      .child("declarations", 0)
      .child("declaration", 0)
      .child("expression", 0)
      .child("application", 1)
    s.expect(path.depth()).to_equal(4)
    s
    .expect(path.to_string())
    .to_equal("declarations[0].declaration[0].expression[0].application[1]")
    s.expect(path.last()).to_equal(Some({ field: "application", index: 1, }))
    s
    .expect(path.parent().map(p => p.to_string()))
    .to_equal(Some("declarations[0].declaration[0].expression[0]"))
  })
}

///|
test "a child path does not change its parent" {
  @expect.expect_all(s => {
    let parent = @syntax.NodePath::root().child("declarations", 0)
    let a = parent.child("declaration", 0)
    let b = parent.child("signature", 0)
    let steps = parent.steps()
    steps.clear()
    s.expect(parent.to_string()).to_equal("declarations[0]")
    s.expect(a.to_string()).to_equal("declarations[0].declaration[0]")
    s.expect(b.to_string()).to_equal("declarations[0].signature[0]")
  })
}

///|
test "a path resolves to its node, or to None where a step does not exist" {
  @expect.expect_all(s => {
    let root = parse_root(small)
    let path = @syntax.NodePath::root()
      .child("declarations", 0)
      .child("declaration", 0)
      .child("expression", 0)
      .child("application", 1)
    s
    .expect(path.resolve(root).map(n => label(n)))
    .to_equal(Some("expression/integer"))
    s
    .expect(@syntax.NodePath::root().child("declarations", 1).resolve(root))
    .to_equal(None)
    s
    .expect(@syntax.NodePath::root().child("nothing", 0).resolve(root))
    .to_equal(None)
  })
}

///|
test "a tree gives the path of a node, or None for a node not in it" {
  @expect.expect_all(s => {
    let tree = tree_of(small)
    guard tree.node_at(loc(5, 7)) is Some(integer) else { fail("no node") }
    s
    .expect(tree.node_path(integer).map(p => p.to_string()))
    .to_equal(
      Some("declarations[0].declaration[0].expression[0].application[1]"),
    )
    s.expect(tree.node_path(tree.root()).map(p => p.depth())).to_equal(Some(0))
    let elsewhere = parse_root(small)
    guard elsewhere.field("declarations") is [d] else { fail("no declaration") }
    // A node of another tree: equal in value, but the tree compares by identity
    // first and then by structure, so it is found; a node that is in no tree at
    // all is not.
    s
    .expect(tree.node_path(d).map(p => p.to_string()))
    .to_equal(Some("declarations[0]"))
    let made_up = @syntax.NodeRef::Name({ range: r0, value: "nowhere", })
    s.expect(tree.node_path(made_up)).to_equal(None)
  })
}

///|
test "a path's debug form lists its steps from the start node" {
  let path = @syntax.NodePath::root()
    .child("declarations", 0)
    .child("declaration", 0)
  debug_inspect(
    path,
    content=(
      #|{
      #|  steps: [
      #|    { field: "declarations", index: 0 },
      #|    { field: "declaration", index: 0 },
      #|  ],
      #|}
    ),
  )
  debug_inspect(@syntax.NodePath::root(), content="{ steps: [] }")
}

///|
test "an appended path resolves from the node where the first part ends" {
  let src = "module Main exposing (..)\n\nadd x y =\n    x + y\n"
  let root = @syntax.NodeRef::of_result(parse_result(src)).unwrap()
  let to_expression = @syntax.NodePath::from_steps([
    { field: "declarations", index: 0, },
    { field: "declaration", index: 0, },
    { field: "expression", index: 0, },
  ])
  let to_right = @syntax.NodePath::root().child("right", 0)
  let whole = to_expression.append(to_right)
  @expect.expect_all(s => {
    s
    .expect(whole.to_string())
    .to_equal("declarations[0].declaration[0].expression[0].right[0]")
    s
    .expect(whole.resolve(root))
    .to_equal(to_expression.resolve(root).bind(n => to_right.resolve(n)))
    s
    .expect(whole.resolve(root).map(n => n.kind()))
    .to_equal(Some("functionOrValue"))
  })
}
