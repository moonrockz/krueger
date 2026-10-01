///|
let expression_source : String =
  #|module M exposing (..)
  #|
  #|{-| M. -}
  #|
  #|import Dict as D exposing (Dict, empty)
  #|
  #|
  #|{-| F.
  #|
  #|@tag one
  #|-}
  #|f : Int -> Int
  #|f x =
  #|    case x of
  #|        ( a, _ ) ->
  #|            [ -1, 0x1F, 1.5, 'c' ]
  #|
  #|        { r } ->
  #|            (\y -> y) r.a .b
  #|
  #|        c :: d ->
  #|            let
  #|                z =
  #|                    if True then () else ()
  #|
  #|                ( p, q ) =
  #|                    ( 1, 2 )
  #|            in
  #|            z
  #|
  #|        Just (e as g) ->
  #|            { h | i = "s" }
  #|
  #|        _ ->
  #|            ( (+) 1 2, x |> identity, { j = 1 } )
  #|
  #|
  #|-- a comment
  #|type alias T a =
  #|    { a | b : Int } -> ( Int, () ) -> List a -> { c : a }
  #|
  #|
  #|type U
  #|    = V Int
  #|    | W
  #|

///|
/// Every node under `root`, collected with an explicit stack.
fn all_nodes(
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
fn before_or_at(a : @ast.Location, b : @ast.Location) -> Bool {
  @lawkit.at_or_before(a, b)
}

///|
fn table_fields(category : String, kind : String) -> Array[String]? {
  for row in @syntax.kind_table() {
    if row.0 == category && row.1 == kind {
      return Some(row.2)
    }
  }
  None
}

///|
test "children lie in their parent, in source order, and match the kind table" {
  @expect.expect_all(s => {
    let root = parse_root(expression_source)
    let nodes = all_nodes(root)
    s.expect(nodes.length() > 100).to_equal(true)
    for entry in nodes {
      let (node, _) = entry
      guard table_fields(node.category(), node.kind()) is Some(fields) else {
        fail("\{node.category()}/\{node.kind()} is not in the kind table")
      }
      s.expect(node.fields()).to_equal(fields)
      let children = node.children()
      let mut previous : @ast.Location? = None
      for c in children {
        if !(before_or_at(node.range().start, c.range().start) &&
          before_or_at(c.range().end, node.range().end)) {
          fail(
            "\{c.category()}/\{c.kind()} is outside \{node.category()}/\{node.kind()}",
          )
        }
        if previous is Some(p) && !before_or_at(p, c.range().start) {
          fail("children of \{node.kind()} are out of order")
        }
        previous = Some(c.range().start)
        guard node.field_of(c) is Some(field) else {
          fail("no field holds a child of \{node.kind()}")
        }
        s.expect(node.field(field).contains(c)).to_equal(true)
      }
      let by_field = []
      for f in node.fields() {
        by_field.append(node.field(f))
      }
      s.expect(by_field.length()).to_equal(children.length())
      for c in by_field {
        s.expect(children.contains(c)).to_equal(true)
      }
    }
  })
}

///|
test "the kind table has one row per kind" {
  @expect.expect_all(s => {
    let table = @syntax.kind_table()
    s.expect(table.length()).to_equal(77)
    let seen : Array[String] = []
    for row in table {
      let key = "\{row.0}/\{row.1}"
      s.expect(seen.contains(key)).to_equal(false)
      seen.push(key)
    }
  })
}

///|
test "doc attributes are children of their declaration and of the file" {
  @expect.expect_all(s => {
    let root = parse_root(expression_source)
    guard root.field("declarations") is [f, ..] else { fail("no declarations") }
    s.expect(f.field("attributes").map(a => a.kind())).to_equal(["attribute"])
    s.expect(root.field("attributes")).to_equal([])
    let with_module = parse_root(
      "module M exposing (..)\n\n{-| M.\n\n@owner \"bank\"\n\n-}\n\n\nx =\n    1\n",
    )
    s
    .expect(with_module.field("attributes").map(a => a.kind()))
    .to_equal(["attribute"])
  })
}

///|
test "case children are in source order although the JSON puts cases first" {
  @expect.expect_all(s => {
    let root = parse_root(expression_source)
    guard all_nodes(root).search_by(e => e.0.kind() == "case") is Some(i) else {
      fail("no case")
    }
    let case_node = all_nodes(root)[i].0
    s.expect(case_node.fields()).to_equal(["cases", "expression"])
    let children = case_node.children()
    s.expect(children[0].category()).to_equal("expression")
    s.expect(children[1].category()).to_equal("case_branch")
  })
}

///|
test "an absent or unknown field is empty" {
  @expect.expect_all(s => {
    let root = parse_root(expression_source)
    s.expect(root.field("nope")).to_equal([])
    guard root.field("imports") is [import_node] else { fail("no import") }
    s
    .expect(import_node.field("moduleAlias").map(n => n.kind()))
    .to_equal(["module_name"])
  })
}

///|
test "children that start at the same place keep their field order" {
  let one : @ast.Node[@ast.Expression] = n(Integer(1L))
  let two : @ast.Node[@ast.Expression] = n(Integer(2L))
  let three : @ast.Node[@ast.Expression] = n(Integer(3L))
  // All three have the same range; the fields are clause, then, else.
  let node = e(IfBlock(one, two, three))
  @expect.expect(node.children()).to_equal([
    Expression(one),
    Expression(two),
    Expression(three),
  ])
}

///|
test "law: children are in start order, and in list order among equal starts" {
  @quickcheck.check(
    (rows : Array[UInt]) => {
      let elements : Array[@ast.Node[@ast.Expression]] = rows.mapi((i, r) => {
        let row = (r % 3).reinterpret_as_int() + 1
        {
          range: { start: { row, column: 1, }, end: { row, column: 2, }, },
          value: Integer(i.to_int64()),
        }
      })
      let kids = e(ListExpr(elements))
        .children()
        .map(k => {
          match k {
            Expression({ value: Integer(v), .. }) => v.to_int()
            _ => -1
          }
        })
      let expected = rows.mapi((i, r) => (r % 3, i))
      expected.sort()
      kids == expected.map(x => x.1)
    },
    count=100,
    max_size=64,
    seed=199,
  )
}

///|
test "law: children_with_fields sorts like children, and each step keeps its list index" {
  // Edges: no, one and many elements; already in order (no sort needed),
  // reversed, and equal starts.
  @quickcheck.check(
    (rows : Array[UInt]) => {
      let elements : Array[@ast.Node[@ast.Expression]] = rows.mapi((i, r) => {
        let row = (r % 3).reinterpret_as_int() + 1
        {
          range: { start: { row, column: 1, }, end: { row, column: 2, }, },
          value: Integer(i.to_int64()),
        }
      })
      let node = e(ListExpr(elements))
      let with_fields = node.children_with_fields()
      with_fields.map(x => x.1) == node.children() &&
      with_fields
      .iter()
      .all(x => x.0.field == "list" && x.1 == Expression(elements[x.0.index]))
    },
    count=100,
    max_size=64,
    seed=227,
  )
}

///|
test "declaration attributes come from the first group for the range, in any group order" {
  let src =
    #|module M exposing (..)
    #|
    #|{-| M. -}
    #|
    #|
    #|{-| A.
    #|
    #|@a one
    #|-}
    #|a =
    #|    1
    #|
    #|
    #|{-| B.
    #|
    #|@b two
    #|-}
    #|b =
    #|    2
    #|
  let result = @parser.parse_module(
    @scanner.SourceText::new(src),
    @scanner.DefaultScanner::new(),
  )
  guard result.ast is Some(file) else { fail("no AST") }
  let groups = result.attributes
  // One group each for `a` and `b` (the module doc has no attributes).
  @expect.expect(groups.length()).to_equal(2)
  // Reverse the groups and add a later group for `a` that must not win.
  let extra : @parser.AttributeGroup = {
    target: groups[0].target,
    attributes: [],
  }
  let shuffled = [groups[1], groups[0], extra]
  let root = @syntax.NodeRef::File(file, shuffled)
  let names = root
    .field("declarations")
    .map(d => d.field("attributes").map(x => x.field("name")[0]))
  let text = names.map(ns => {
    ns.map(n => {
      guard n is Name(node) else { "?" }
      node.value
    })
  })
  @expect.expect(text).to_equal([["a"], ["b"]])
}
