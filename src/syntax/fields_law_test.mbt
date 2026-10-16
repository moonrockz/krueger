///|
/// Every (node, parent) pair under `root`, collected with an explicit stack;
/// the root has no parent.
fn nodes_with_parents(
  root : @syntax.NodeRef,
) -> Array[(@syntax.NodeRef, @syntax.NodeRef?)] {
  let found = []
  let stack : Array[(@syntax.NodeRef, @syntax.NodeRef?)] = [(root, None)]
  while stack.pop() is Some((node, parent)) {
    found.push((node, parent))
    for c in node.children() {
      stack.push((c, Some(node)))
    }
  }
  found
}

///|
test "law: children_with_fields gives children in order, each with the step that leads to it" {
  // Edges: nodes with no, one and many children; fields with several nodes
  // (arguments, declarations); children of different fields that start at
  // the same place (a doc comment and its attributes).
  @quickcheck.check(
    (m : ElmModule) => {
      nodes_with_parents(elm_root(m))
      .iter()
      .all(entry => {
        let node = entry.0
        let with_fields = node.children_with_fields()
        with_fields.map(x => x.1) == node.children() &&
        with_fields
        .iter()
        .all(x => {
          let (step, child) = x
          let in_field = node.field(step.field)
          step.index >= 0 &&
          step.index < in_field.length() &&
          in_field[step.index] == child &&
          node.field_of(child) == Some(step.field)
        })
      })
    },
    count=100,
    max_size=24,
    seed=211,
  )
}

///|
test "law: Tree::step and Tree::field_of agree with the parent's field_of and with node_path" {
  @quickcheck.check(
    (m : ElmModule) => {
      ignore(elm_root(m))
      guard @syntax.Tree::new(parse_result(m.text())) is Some(tree) else {
        return false
      }
      nodes_with_parents(tree.root())
      .iter()
      .all(entry => {
        let (node, parent) = entry
        let step = tree.step(node)
        let expected_field = parent.bind(p => p.field_of(node))
        tree.field_of(node) == expected_field &&
        step.map(s => s.field) == expected_field &&
        step == tree.node_path(node).bind(p => p.last()) &&
        (parent is None) == (step is None)
      })
    },
    count=100,
    max_size=24,
    seed=223,
  )
}

///|
test "Tree::step and Tree::field_of give None for a node of another tree" {
  let tree = @syntax.Tree::new(
    parse_result("module M exposing (..)\n\na = 1\n"),
  )
  let other = @syntax.NodeRef::of_result(
    parse_result("module M exposing (..)\n\nb = 2\n"),
  )
  guard (tree, other) is (Some(tree), Some(other)) else { fail("no AST") }
  let foreign = other.field("declarations")[0]
  @expect.expect_all(s => {
    s.expect(tree.step(foreign)).to_equal(None)
    s.expect(tree.field_of(foreign)).to_equal(None)
    s.expect(tree.step(tree.root())).to_equal(None)
  })
}

///|
/// The children of `node` by the model: every field's nodes, in field order,
/// then a stable insertion sort by start.
fn model_children(node : @syntax.NodeRef) -> Array[@syntax.NodeRef] {
  let all : Array[@syntax.NodeRef] = []
  for f in node.fields() {
    all.append(node.field(f))
  }
  let before = (a : @ast.Location, b : @ast.Location) => {
    a.row < b.row || (a.row == b.row && a.column < b.column)
  }
  for i in 1..<all.length() {
    let x = all[i]
    let mut j = i
    while j > 0 && before(x.range().start, all[j - 1].range().start) {
      all[j] = all[j - 1]
      j -= 1
    }
    all[j] = x
  }
  all
}

///|
test "law: children is the stable sort of the field lists by start, also when comments interleave with declarations" {
  // Edges: a file whose comments sit in every gap (many interleaved runs of
  // declarations and comments); children of different fields that start at
  // the same place; nodes whose fields are out of source order (`as`).
  @quickcheck.check(
    (m : @lawkit.Commented) => {
      let text = m.text()
      let result = parse_result(text)
      if !result.diagnostics.is_empty() {
        fail("generated Elm does not parse:\n\{text}")
      }
      guard @syntax.NodeRef::of_result(result) is Some(root) else {
        fail("no AST")
      }
      nodes_with_parents(root)
      .iter()
      .all(entry => {
        let node = entry.0
        let expected = model_children(node)
        node.children() == expected &&
        node.children_with_fields().map(x => x.1) == expected
      })
    },
    count=100,
    max_size=24,
    seed=239,
  )
}
