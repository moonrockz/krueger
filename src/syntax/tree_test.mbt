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
  let tree = tree_of(expression_source)
  let root = tree.root()
  @expect.expect(tree.parent(root)).to_equal(None)
  for entry in all_nodes(root) {
    let (node, parent) = entry
    @expect.expect(tree.parent(node)).to_equal(parent)
    let ancestors = tree.ancestors(node)
    if parent is Some(_) {
      @expect.expect(ancestors.last()).to_equal(Some(root))
      @expect.expect(ancestors.get(0)).to_equal(parent)
    } else {
      @expect.expect(ancestors).to_equal([])
    }
    let path = tree.path(node)
    @expect.expect(path.get(0)).to_equal(Some(root))
    @expect.expect(path.last()).to_equal(Some(node))
    @expect.expect(path.length()).to_equal(ancestors.length() + 1)
  }
}

///|
test "nested parentheses each have the right parent" {
  let tree = tree_of("module M exposing (..)\n\n\nf =\n    ((x))\n")
  let nodes = all_nodes(tree.root()).filter(e => e.0.category() == "expression")
  // outer parenthesized, inner parenthesized, x
  @expect.expect(nodes.map(e => e.0.kind())).to_equal([
    "parenthesized", "parenthesized", "functionOrValue",
  ])
  @expect.expect(tree.parent(nodes[1].0)).to_equal(Some(nodes[0].0))
  @expect.expect(tree.parent(nodes[2].0)).to_equal(Some(nodes[1].0))
}

///|
test "no AST, no tree" {
  @expect.expect(@syntax.Tree::new(parse_result("x = 1\n")) is None).to_equal(
    true,
  )
}
