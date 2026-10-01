///|
fn parse_result(text : String) -> @parser.ParseResult raise {
  let source = @scanner.SourceText::{ module_name: Some("M"), text, }
  guard @scanner.DefaultScanner::new().tokenize(source) is Ok(tokens) else {
    fail("scan error")
  }
  @parser.parse_tokens(tokens)
}

///|
fn tree_of(text : String) -> @syntax.Tree raise {
  guard @syntax.Tree::new(parse_result(text)) is Some(tree) else {
    fail("no tree")
  }
  tree
}

///|
test "every node knows its parent" {
  @expect.expect_all(s => {
    let tree = tree_of(expression_source)
    let root = tree.root()
    s.expect(tree.parent(root)).to_equal(None)
    for entry in all_nodes(root) {
      let (node, parent) = entry
      s.expect(tree.parent(node)).to_equal(parent)
      let ancestors = tree.ancestors(node)
      if parent is Some(_) {
        s.expect(ancestors.last()).to_equal(Some(root))
        s.expect(ancestors.get(0)).to_equal(parent)
      } else {
        s.expect(ancestors).to_equal([])
      }
      let path = tree.path(node)
      s.expect(path.get(0)).to_equal(Some(root))
      s.expect(path.last()).to_equal(Some(node))
      s.expect(path.length()).to_equal(ancestors.length() + 1)
    }
  })
}

///|
test "nested parentheses each have the right parent" {
  @expect.expect_all(s => {
    let tree = tree_of("module M exposing (..)\n\n\nf =\n    ((x))\n")
    let nodes = all_nodes(tree.root()).filter(e => {
      e.0.category() == "expression"
    })
    // outer parenthesized, inner parenthesized, x
    s
    .expect(nodes.map(e => e.0.kind()))
    .to_equal(["parenthesized", "parenthesized", "functionOrValue"])
    s.expect(tree.parent(nodes[1].0)).to_equal(Some(nodes[0].0))
    s.expect(tree.parent(nodes[2].0)).to_equal(Some(nodes[1].0))
  })
}

///|
test "no AST, no tree" {
  @expect.expect(@syntax.Tree::new(parse_result("x = 1\n")) is None).to_equal(
    true,
  )
}

///|
fn loc(row : Int, column : Int) -> @ast.Location {
  { row, column, }
}

///|
test "node_at finds the node that starts at a position, or a descendant" {
  let tree = tree_of(expression_source)
  for entry in all_nodes(tree.root()) {
    let (node, _) = entry
    let r = node.range()
    if r.start == r.end {
      continue
    }
    guard tree.node_at(r.start) is Some(found) else {
      fail("nothing at the start of \{node.kind()}")
    }
    if found != node && !tree.ancestors(found).contains(node) {
      fail(
        "node_at(start of \{node.category()}/\{node.kind()}) gave \{found.category()}/\{found.kind()}",
      )
    }
  }
}

///|
test "node_at on blank lines, comments and outside the file" {
  @expect.expect_all(s => {
    let tree = tree_of(expression_source)
    // Line 17 is the blank line between the first two case branches.
    guard tree.node_at(loc(17, 5)) is Some(blank) else { fail("nothing") }
    s
    .expect(tree.path(blank).any(n => n.category() == "implementation"))
    .to_equal(true)
    // Line 38 is `-- a comment`.
    guard tree.node_at(loc(38, 4)) is Some(comment) else { fail("nothing") }
    s.expect(comment.category()).to_equal("comment")
    s.expect(tree.node_at(loc(90, 1))).to_equal(None)
  })
}

///|
test "node_at between record setters returns the record" {
  @expect.expect_all(s => {
    let tree = tree_of(
      "module M exposing (..)\n\n\nf =\n    { a = 1, b = 2 }\n",
    )
    guard tree.node_at(loc(5, 12)) is Some(comma) else { fail("nothing") }
    s
    .expect((comma.category(), comma.kind()))
    .to_equal(("expression", "record"))
    guard tree.node_at(loc(5, 7)) is Some(a) else { fail("nothing") }
    s
    .expect(tree.path(a).any(n => n.category() == "record_setter"))
    .to_equal(true)
  })
}

///|
test "tokens_in returns the tokens of a range" {
  let tree = tree_of(
    "module M exposing (..)\n\n\nf =\n    g 1\n\n\nh =\n    2\n",
  )
  guard tree.root().field("declarations") is [f, _] else {
    fail("expected two declarations")
  }
  @expect.expect(tree.tokens_in(f.range()).map(t => t.lexeme)).to_equal([
    "f", "=", "g", "1",
  ])
}
