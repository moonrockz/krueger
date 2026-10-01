///|
/// Where a cursor is: label, field and depth.
fn at(c : @syntax.TreeCursor) -> String {
  let f = match c.field_name() {
    Some(f) => f
    None => "-"
  }
  "\{label(c.node())} \{f} \{c.depth()}"
}

///|
test "a cursor starts at its node with depth 0 and no field" {
  let c = @syntax.TreeCursor::new(parse_root(small))
  @expect.expect(at(c)).to_equal("file/file - 0")
}

///|
test "goto_first_child, goto_next_sibling and goto_parent move and report fields" {
  @expect.expect_all(s => {
    let c = @syntax.TreeCursor::new(parse_root(small))
    let seen = []
    s.expect(c.goto_first_child()).to_equal(true)
    seen.push(at(c))
    s.expect(c.goto_first_child()).to_equal(true)
    seen.push(at(c))
    s.expect(c.goto_next_sibling()).to_equal(true)
    seen.push(at(c))
    s.expect(c.goto_parent()).to_equal(true)
    seen.push(at(c))
    s.expect(c.goto_next_sibling()).to_equal(true)
    seen.push(at(c))
    s
    .expect(seen)
    .to_equal([
      "module/normal moduleDefinition 1", "module_name/module_name moduleName 2",
      "exposing/all exposingList 2", "module/normal moduleDefinition 1", "declaration/function declarations 1",
    ])
  })
}

///|
test "goto_last_child and goto_previous_sibling" {
  @expect.expect_all(s => {
    let c = @syntax.TreeCursor::new(parse_root(small))
    s.expect(c.goto_last_child()).to_equal(true)
    s.expect(at(c)).to_equal("declaration/function declarations 1")
    s.expect(c.goto_previous_sibling()).to_equal(true)
    s.expect(at(c)).to_equal("module/normal moduleDefinition 1")
  })
}

///|
test "a move that has nowhere to go returns false and leaves the cursor in place" {
  @expect.expect_all(s => {
    let c = @syntax.TreeCursor::new(parse_root(small))
    s.expect(c.goto_parent()).to_equal(false)
    s.expect(c.goto_next_sibling()).to_equal(false)
    s.expect(c.goto_previous_sibling()).to_equal(false)
    s.expect(at(c)).to_equal("file/file - 0")
    ignore(c.goto_first_child())
    s.expect(c.goto_previous_sibling()).to_equal(false)
    ignore(c.goto_first_child())
    // module_name is a leaf.
    s.expect(c.goto_first_child()).to_equal(false)
    s.expect(c.goto_last_child()).to_equal(false)
    s.expect(c.goto_first_child_for(loc(1, 8))).to_equal(false)
    s.expect(at(c)).to_equal("module_name/module_name moduleName 2")
  })
}

///|
test "goto_first_child_for picks the first child that contains or follows the position" {
  @expect.expect_all(s => {
    let c = @syntax.TreeCursor::new(parse_root(small))
    // Inside the module header.
    s.expect(c.goto_first_child_for(loc(1, 3))).to_equal(true)
    s.expect(at(c)).to_equal("module/normal moduleDefinition 1")
    ignore(c.goto_parent())
    // On a blank line between the header and the declaration.
    s.expect(c.goto_first_child_for(loc(2, 1))).to_equal(true)
    s.expect(at(c)).to_equal("declaration/function declarations 1")
    ignore(c.goto_parent())
    // After the last child.
    s.expect(c.goto_first_child_for(loc(9, 1))).to_equal(false)
    s.expect(at(c)).to_equal("file/file - 0")
  })
}

///|
test "reset moves the cursor to a new start node" {
  @expect.expect_all(s => {
    let root = parse_root(small)
    let c = @syntax.TreeCursor::new(root)
    ignore(c.goto_last_child())
    let declaration = c.node()
    ignore(c.goto_first_child())
    c.reset(declaration)
    s.expect(at(c)).to_equal("declaration/function - 0")
    s.expect(c.goto_parent()).to_equal(false)
  })
}

///|
test "a copy moves independently of its cursor" {
  @expect.expect_all(s => {
    let c = @syntax.TreeCursor::new(parse_root(small))
    ignore(c.goto_first_child())
    let d = c.copy()
    ignore(d.goto_next_sibling())
    ignore(d.goto_first_child())
    s.expect(at(c)).to_equal("module/normal moduleDefinition 1")
    s.expect(at(d)).to_equal("implementation/implementation declaration 2")
    ignore(c.goto_parent())
    s.expect(at(d)).to_equal("implementation/implementation declaration 2")
  })
}

///|
/// The tags a full navigation (first child, next sibling, parent) enters. It
/// fails unless the navigation ends back at the start node.
fn navigate(root : @syntax.NodeRef) -> Array[String] raise {
  let c = @syntax.TreeCursor::new(root)
  let out = [tag(c.node())]
  while true {
    if c.goto_first_child() {
      out.push(tag(c.node()))
      continue
    }
    while !c.goto_next_sibling() {
      if !c.goto_parent() {
        if c.depth() != 0 || tag(c.node()) != tag(root) {
          fail("the navigation did not end at its start node")
        }
        return out
      }
    }
    out.push(tag(c.node()))
  }
  out
}

///|
/// Pre-order tags over children(), independent of the cursor.
fn tag_preorder(root : @syntax.NodeRef) -> Array[String] {
  let out = []
  let stack = [root]
  while stack.pop() is Some(n) {
    out.push(tag(n))
    n.children().rev_each(c => stack.push(c))
  }
  out
}

///|
test "a full cursor navigation enters children() pre-order" {
  let root = parse_root(expression_source)
  @expect.expect(navigate(root)).to_equal(tag_preorder(root))
}

///|
test "a cursor handles a 398-level tree" {
  @expect.expect_all(s => {
    let root = tree_of(deep_source()).root()
    let c = @syntax.TreeCursor::new(root)
    // declaration > implementation > the outermost operator application
    for _ in 0..<3 {
      ignore(c.goto_last_child())
    }
    // The left operands lead down to the first integer.
    while c.goto_first_child() {

    }
    s.expect(at(c)).to_equal("expression/integer left 401")
    while c.goto_parent() {

    }
    s.expect(c.depth()).to_equal(0)
    s.expect(navigate(root).length()).to_equal(399 + 398 + 7)
  })
}

///|
test "a cursor reports the path of its node" {
  @expect.expect_all(s => {
    let c = @syntax.TreeCursor::new(parse_root(small))
    s.expect(c.path().to_string()).to_equal("")
    ignore(c.goto_last_child())
    ignore(c.goto_first_child())
    ignore(c.goto_last_child())
    ignore(c.goto_last_child())
    s
    .expect(c.path().to_string())
    .to_equal("declarations[0].declaration[0].expression[0].application[1]")
    s.expect(c.path().depth()).to_equal(c.depth())
  })
}

///|
let docs_source : String =
  #|module M exposing (f)
  #|
  #|{-| Module.
  #|
  #|@docs f
  #|-}
  #|
  #|
  #|f =
  #|    1
  #|

///|
/// The nodes `goto_first_child_for(p)` moves through from the start node.
fn descent(root : @syntax.NodeRef, p : @ast.Location) -> Array[String] {
  let c = @syntax.TreeCursor::new(root)
  let seen = []
  while c.goto_first_child_for(p) {
    seen.push(tag(c.node()))
  }
  seen
}

///|
test "goto_first_child_for takes the innermost of overlapping children" {
  @expect.expect_all(s => {
    // A declaration's doc comment and its attributes are both its children.
    s
    .expect(descent(parse_root(expression_source), loc(10, 1)))
    .to_equal([
      "declaration/function@8:1-35:50", "attribute/attribute@10:1-10:9", "name/name@10:2-10:5",
    ])
    // Module attributes lie inside the module doc comment; both are children
    // of the file.
    s
    .expect(descent(parse_root(docs_source), loc(5, 1)).get(0))
    .to_equal(Some("attribute/docs@5:1-5:8"))
  })
}
