///|
let port_with_attributes : String =
  #|port module M exposing (..)
  #|
  #|{-| M. -}
  #|
  #|
  #|x =
  #|    1
  #|
  #|
  #|{-| Port.
  #|
  #|@unit "EUR"
  #|-}
  #|port p : (Int -> msg) -> Sub msg
  #|

///|
test "a port's doc attributes lie inside the port declaration" {
  @expect.expect_all(s => {
    let tree = tree_of(port_with_attributes)
    guard tree.root().field("declarations") is [_, port] else {
      fail("expected two declarations")
    }
    guard port.field("attributes") is [attribute] else {
      fail("expected one attribute")
    }
    let r = port.range()
    let a = attribute.range()
    s.expect(at_or_before_loc(r.start, a.start)).to_equal(true)
    s.expect(at_or_before_loc(a.end, r.end)).to_equal(true)
    s
    .expect(tree.node_at(a.start).map(n => n.kind()))
    .to_equal(Some("attribute"))
    // The rest of the doc comment is still the comment.
    s
    .expect(tree.node_at(loc(10, 1)).map(n => n.kind()))
    .to_equal(Some("comment"))
  })
}

///|
fn at_or_before_loc(a : @ast.Location, b : @ast.Location) -> Bool {
  a.row < b.row || (a.row == b.row && a.column <= b.column)
}

///|
test "ancestors of every element of a large list take linear time" {
  @expect.expect_all(s => {
    let sb = StringBuilder()
    sb.write_string("module M exposing (..)\n\n\nf =\n    [ 1\n")
    for _ in 0..<20000 {
      sb.write_string("    , 1\n")
    }
    sb.write_string("    ]\n")
    let tree = tree_of(sb.to_string())
    guard tree.node_at(loc(5, 7)) is Some(first) &&
      tree.parent(first) is Some(list) else {
      fail("no list")
    }
    let start = @env.now()
    let mut total = 0
    for element in list.children() {
      total = total + tree.ancestors(element).length()
    }
    let elapsed = @env.now() - start
    s.expect(total).to_equal(20001 * 4)
    // Structural comparison of whole subtrees made this quadratic (seconds).
    s.expect(elapsed < 2000).to_equal(true)
  })
}

///|
test "changing the parse result does not change the tree" {
  @expect.expect_all(s => {
    let result = parse_result("module M exposing (..)\n\n\nf =\n    g 1\n")
    guard @syntax.Tree::new(result) is Some(tree) && result.cst is Some(cst) else {
      fail("no tree")
    }
    let whole = tree.root().range()
    let count = tree.tokens_in(whole).length()
    cst.tokens.clear()
    result.attributes.push({ target: Module, attributes: [], })
    s.expect(tree.tokens_in(whole).length()).to_equal(count)
    guard tree.root() is File(_, groups) else { fail("no file") }
    s.expect(groups.length()).to_equal(0)
  })
}

///|
/// The number of trivia items before and after each token in `r`.
fn trivia_counts(tree : @syntax.Tree, r : @ast.Range) -> Array[Int] {
  tree.tokens_in(r).map(t => t.trivia_before.length() + t.trivia_after.length())
}

///|
test "changing token trivia returned by tokens_in does not change the tree" {
  @expect.expect_all(s => {
    let tree = tree_of("module M exposing (..)\n\n-- hi\nx =\n    1\n")
    let whole = tree.root().range()
    let before = trivia_counts(tree, whole)
    for t in tree.tokens_in(whole) {
      t.trivia_before.clear()
      t.trivia_after.clear()
    }
    s.expect(trivia_counts(tree, whole)).to_equal(before)
    s.expect(before.any(n => n > 0)).to_equal(true)
  })
}

///|
test "changing the parse result's token trivia does not change the tree" {
  let result = parse_result("module M exposing (..)\n\n-- hi\nx =\n    1\n")
  guard @syntax.Tree::new(result) is Some(tree) && result.cst is Some(cst) else {
    fail("no tree")
  }
  let whole = tree.root().range()
  let before = trivia_counts(tree, whole)
  for t in cst.tokens {
    t.trivia_before.clear()
    t.trivia_after.clear()
  }
  @expect.expect(trivia_counts(tree, whole)).to_equal(before)
}
