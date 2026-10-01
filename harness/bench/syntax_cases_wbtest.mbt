///|
/// One parsed source with what the queries need, built outside the
/// measured work.
priv struct Parsed {
  result : @parser.ParseResult
  tree : @syntax.Tree
  nodes : Array[@syntax.NodeRef]
  positions : Array[@ast.Location]
  declarations : Array[@syntax.NodeRef]
}

///|
fn all_nodes(root : @syntax.NodeRef) -> Array[@syntax.NodeRef] {
  let found = []
  @syntax.walk(root, n => {
    found.push(n)
    Continue
  })
  found
}

///|
/// Up to 200 expression starts, evenly spaced through the file.
fn sample_positions(nodes : Array[@syntax.NodeRef]) -> Array[@ast.Location] {
  let starts = nodes
    .filter(n => n.category() == "expression")
    .map(n => n.range().start)
  let n = starts.length()
  if n <= 200 {
    return starts
  }
  Array::makei(200, i => starts[i * n / 200])
}

///|
fn parse_all(sources : Array[Source]) -> Array[Parsed] raise {
  let parsed = []
  for s in sources {
    let result = parse_source(s)
    guard @syntax.Tree::new(result) is Some(tree) else {
      fail("syntax bench: \{s.key} has no AST")
    }
    let nodes = all_nodes(tree.root())
    parsed.push({
      result,
      tree,
      nodes,
      positions: sample_positions(nodes),
      declarations: tree.root().field("declarations"),
    })
  }
  parsed
}

///|
fn count_if(b : Bool) -> Int {
  if b {
    1
  } else {
    0
  }
}

///|
/// A check that `run` returns `expected`, or a positive count for `None`.
fn check_count(
  id : String,
  run : () -> Int,
  expected : Int?,
) -> () -> Unit raise {
  fn() raise {
    let got = run()
    match expected {
      Some(e) => if got != e { fail("\{id}: expected \{e}, got \{got}") }
      None => if got <= 0 { fail("\{id}: no result") }
    }
  }
}

///|
/// `syntax/*` cases over `sources`, named with `input` (`corpus` or
/// `large`). Each sample runs the query over every parsed source.
fn syntax_cases(input : String, sources : Array[Source]) -> Array[Case] raise {
  let parsed = parse_all(sources)
  let over = (f : (Parsed) -> Int) => {
    () => {
      let mut n = 0
      for p in parsed {
        n += f(p)
      }
      n
    }
  }
  let files = parsed.length()
  let nodes_total = parsed.fold(init=0, (a, p) => a + p.nodes.length())
  let tree_new = over(p => count_if(@syntax.Tree::new(p.result) is Some(_)))
  let walk = over(p => {
    let mut k = 0
    @syntax.walk(p.tree.root(), _ => {
      k += 1
      Continue
    })
    k
  })
  let event_reader = over(p => {
    @syntax.EventReader::new(p.tree.root()).iter().count()
  })
  let children_all = over(p => {
    p.nodes.fold(init=0, (a, n) => a + n.children().length())
  })
  let parent_all = over(p => {
    p.nodes.fold(init=0, (a, n) => a + count_if(p.tree.parent(n) is Some(_)))
  })
  // The measured work is node_path only; the check also resolves each path
  // (resolve is slow on a wide file, and is not what this case measures).
  let node_path_all = over(p => {
    p.nodes.fold(init=0, (a, n) => a + count_if(p.tree.node_path(n) is Some(_)))
  })
  let node_path_resolves = over(p => {
    p.nodes.fold(init=0, (a, n) => {
      let ok = p.tree.node_path(n) is Some(path) &&
        path.resolve(p.tree.root()) == Some(n)
      a + count_if(ok)
    })
  })
  let node_at = over(p => {
    p.positions.fold(init=0, (a, l) => {
      a + count_if(p.tree.node_at(l) is Some(_))
    })
  })
  let tokens_in = over(p => {
    p.declarations.fold(init=0, (a, d) => {
      a + p.tree.tokens_in(d.range()).length()
    })
  })
  let cursor = over(p => {
    let c = @syntax.TreeCursor::new(p.tree.root())
    let mut k = 0
    for l in p.positions {
      c.reset(p.tree.root())
      if c.goto_node_at(l) {
        k += c.depth()
      }
    }
    k
  })
  let expect_count = (name : String, run : () -> Int, expected : Int) => {
    check_count("syntax/\{name}/\{input}", run, Some(expected))
  }
  let expect_some = (name : String, run : () -> Int) => {
    check_count("syntax/\{name}/\{input}", run, None)
  }
  let case_of = (name : String, run : () -> Int, check : () -> Unit raise) => {
    suite: "syntax",
    name,
    input,
    run,
    check,
  }
  [
    case_of("tree_new", tree_new, expect_count("tree_new", tree_new, files)),
    case_of("walk", walk, expect_count("walk", walk, nodes_total)),
    case_of(
      "event_reader",
      event_reader,
      expect_count("event_reader", event_reader, 2 * nodes_total),
    ),
    case_of(
      "children_all",
      children_all,
      expect_count("children_all", children_all, nodes_total - files),
    ),
    case_of(
      "parent_all",
      parent_all,
      expect_count("parent_all", parent_all, nodes_total - files),
    ),
    case_of(
      "node_path_all",
      node_path_all,
      expect_count("node_path_all", node_path_resolves, nodes_total),
    ),
    case_of("node_at", node_at, expect_some("node_at", node_at)),
    case_of(
      "tokens_in_decls",
      tokens_in,
      expect_some("tokens_in_decls", tokens_in),
    ),
    case_of(
      "cursor_goto_node_at",
      cursor,
      expect_some("cursor_goto_node_at", cursor),
    ),
  ]
}

///|
test "syntax cases cover the tree queries and pass their checks" {
  let cases = syntax_cases("large", [{ key: "large", text: large_module(5), }])
  @expect.expect(cases.map(c => c.id())).to_equal([
    "syntax/tree_new/large", "syntax/walk/large", "syntax/event_reader/large", "syntax/children_all/large",
    "syntax/parent_all/large", "syntax/node_path_all/large", "syntax/node_at/large",
    "syntax/tokens_in_decls/large", "syntax/cursor_goto_node_at/large",
  ])
  for c in cases {
    (c.check)()
  }
}
