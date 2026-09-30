///|
test "a 400-level tree builds and answers without a stack overflow" {
  // 398 operators is the deepest chain the parser accepts (MAX_AST_DEPTH).
  let sb = StringBuilder()
  sb.write_string("module M exposing (..)\n\n\nf =\n    1")
  for _ in 0..<398 {
    sb.write_string(" + 1")
  }
  sb.write_string("\n")
  let tree = tree_of(sb.to_string())
  // The deepest node is the first `1` at the bottom of the left spine.
  guard tree.node_at(loc(5, 5)) is Some(deepest) else { fail("nothing at 5:5") }
  @expect.expect(deepest.kind()).to_equal("integer")
  @expect.expect(tree.ancestors(deepest).length() >= 398).to_equal(true)
  @expect.expect(tree.path(deepest).length() >= 400).to_equal(true)
}

///|
test "returned arrays are new arrays" {
  let tree = tree_of(expression_source)
  let root = tree.root()
  guard root.field("declarations") is [f, ..] else { fail("no declarations") }
  let children = root.children()
  children.clear()
  @expect.expect(root.children().length() > 0).to_equal(true)
  let declarations = root.field("declarations")
  declarations.push(root)
  @expect.expect(root.field("declarations").contains(root)).to_equal(false)
  let ancestors = tree.ancestors(f)
  ancestors.push(f)
  @expect.expect(tree.ancestors(f)).to_equal([root])
  let path = tree.path(f)
  path.clear()
  @expect.expect(tree.path(f)).to_equal([root, f])
  let tokens = tree.tokens_in(f.range())
  let count = tokens.length()
  tokens.clear()
  @expect.expect(tree.tokens_in(f.range()).length()).to_equal(count)
}
