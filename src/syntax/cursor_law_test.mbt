///|
fn range_contains(r : @ast.Range, p : @ast.Location) -> Bool {
  @lawkit.contains(r, p)
}

///|
fn range_within(a : @ast.Range, b : @ast.Range) -> Bool {
  @lawkit.within(a, b)
}

///|
/// Positions around and inside `n` (edges: the start and end of every node in
/// it and one column before each; the row after `n`).
fn node_positions(n : @syntax.NodeRef) -> Array[@ast.Location] {
  let ranges = []
  @syntax.walk(n, k => {
    ranges.push(k.range())
    Continue
  })
  let out = @lawkit.range_edges(ranges)
  out.push({ row: n.range().end.row + 1, column: 1, })
  out
}

///|
/// The child goto_first_child_for(p) must pick: the innermost child that
/// contains `p` (the first among equals), or else the first child that
/// starts after `p`.
fn child_for(kids : Array[@syntax.NodeRef], p : @ast.Location) -> Int? {
  let mut best : Int? = None
  for i, k in kids {
    let r = k.range()
    if range_contains(r, p) {
      match best {
        None => best = Some(i)
        Some(b) =>
          if range_within(r, kids[b].range()) && r != kids[b].range() {
            best = Some(i)
          }
      }
    }
  }
  match best {
    Some(_) => best
    None => kids.search_by(k => !before_or_at(k.range().start, p))
  }
}

///|
/// The node at `path` (child indices from `base`) and its field in its parent.
fn node_at_path(
  base : @syntax.NodeRef,
  path : Array[Int],
) -> (@syntax.NodeRef, String?) {
  let mut n = base
  let mut field = None
  for i in path {
    let parent = n
    n = parent.children()[i]
    field = parent.field_of(n)
  }
  (n, field)
}

///|
fn pick_position(n : @syntax.NodeRef, m : UInt) -> @ast.Location {
  let ps = node_positions(n)
  ps[(m / 7 % ps.length().reinterpret_as_uint()).reinterpret_as_int()]
}

///|
/// Move `m` (not a reset), applied to a model cursor: a path of child indices
/// from `base`.
fn model_move(base : @syntax.NodeRef, path : Array[Int], m : UInt) -> Bool {
  let (n, _) = node_at_path(base, path)
  let siblings = if path.is_empty() {
    1
  } else {
    node_at_path(base, path[:path.length() - 1].to_owned()).0
    .children()
    .length()
  }
  match m % 6 {
    0 =>
      if n.children().is_empty() {
        false
      } else {
        path.push(0)
        true
      }
    1 => {
      let kids = n.children()
      if kids.is_empty() {
        false
      } else {
        path.push(kids.length() - 1)
        true
      }
    }
    2 =>
      if path.is_empty() || path[path.length() - 1] + 1 >= siblings {
        false
      } else {
        path[path.length() - 1] = path[path.length() - 1] + 1
        true
      }
    3 =>
      if path.is_empty() || path[path.length() - 1] == 0 {
        false
      } else {
        path[path.length() - 1] = path[path.length() - 1] - 1
        true
      }
    4 =>
      if path.is_empty() {
        false
      } else {
        ignore(path.pop())
        true
      }
    _ =>
      match child_for(n.children(), pick_position(n, m)) {
        Some(i) => {
          path.push(i)
          true
        }
        None => false
      }
  }
}

///|
/// Move `m` (not a reset), applied to a real cursor.
fn cursor_move(c : @syntax.TreeCursor, m : UInt) -> Bool {
  match m % 6 {
    0 => c.goto_first_child()
    1 => c.goto_last_child()
    2 => c.goto_next_sibling()
    3 => c.goto_previous_sibling()
    4 => c.goto_parent()
    _ => c.goto_first_child_for(pick_position(c.node(), m))
  }
}

///|
/// The children of `n` as (field, index in field, node), sorted by start and
/// then by field order: computed apart from `children()`.
fn slot_order(n : @syntax.NodeRef) -> Array[(String, Int, @syntax.NodeRef)] {
  let slots : Array[(Int, String, Int, @syntax.NodeRef)] = []
  for f in n.fields() {
    for i, c in n.field(f) {
      slots.push((slots.length(), f, i, c))
    }
  }
  slots.sort_by((a, b) => {
    let x = a.3.range().start
    let y = b.3.range().start
    if x.row != y.row {
      x.row.compare(y.row)
    } else if x.column != y.column {
      x.column.compare(y.column)
    } else {
      a.0.compare(b.0)
    }
  })
  slots.map(s => (s.1, s.2, s.3))
}

///|
/// The path steps a model path (child indices from `base`) names.
fn model_steps(
  base : @syntax.NodeRef,
  path : Array[Int],
) -> Array[@syntax.PathStep] {
  let mut n = base
  let steps = []
  for k in path {
    let (field, index, child) = slot_order(n)[k]
    let step : @syntax.PathStep = { field, index, }
    steps.push(step)
    n = child
  }
  steps
}

///|
/// Whether the cursor is where the model path from `base` says.
fn agrees(
  c : @syntax.TreeCursor,
  base : @syntax.NodeRef,
  path : Array[Int],
) -> Bool {
  let (n, field) = node_at_path(base, path)
  tag(c.node()) == tag(n) &&
  c.field_name() == field &&
  c.depth() == path.length() &&
  c.path().depth() == path.length() &&
  c.path().last().map(s => s.field) == field &&
  c.path().resolve(base).map(tag) == Some(tag(n)) &&
  c.path().steps() == model_steps(base, path)
}

///|
test "law: every cursor move agrees with a path model, resets included" {
  @quickcheck.check(
    (input : (ElmModule, Array[UInt])) => {
      let (m, moves) = input
      let root = elm_root(m)
      let nodes = []
      @syntax.walk(root, n => {
        nodes.push(n)
        Continue
      })
      let c = @syntax.TreeCursor::new(root)
      let mut base = root
      let path = []
      moves
      .iter()
      .all(mv => {
        let same = if mv % 8 == 7 {
          // Reset to any node; the model is then based there.
          base = nodes[(mv / 8 % nodes.length().reinterpret_as_uint()).reinterpret_as_int()]
          c.reset(base)
          path.clear()
          true
        } else {
          cursor_move(c, mv) == model_move(base, path, mv)
        }
        same && agrees(c, base, path)
      })
    },
    count=200,
    max_size=24,
    seed=127,
  )
}

///|
test "law: a cursor's copy moves independently" {
  @quickcheck.check(
    (input : (ElmModule, Array[UInt], Array[UInt])) => {
      let (m, first, second) = input
      let root = elm_root(m)
      let c = @syntax.TreeCursor::new(root)
      let path = []
      for mv in first {
        ignore(cursor_move(c, mv))
        ignore(model_move(root, path, mv))
      }
      let d = c.copy()
      let copy_path = path.copy()
      for mv in second {
        ignore(cursor_move(d, mv))
        ignore(model_move(root, copy_path, mv))
      }
      let c_unchanged = agrees(c, root, path)
      for mv in first {
        ignore(cursor_move(c, mv))
        ignore(model_move(root, path, mv))
      }
      c_unchanged && agrees(c, root, path) && agrees(d, root, copy_path)
    },
    count=100,
    max_size=24,
    seed=131,
  )
}

///|
test "law: a full cursor navigation enters children() pre-order and ends at the start" {
  @quickcheck.check(
    (m : ElmModule) => {
      let root = elm_root(m)
      navigate(root) == tag_preorder(root)
    },
    count=100,
    max_size=24,
    seed=137,
  )
}

///|
test "law: at every node, goto_first_child_for(p) moves to the innermost child that contains p, or the first that follows it" {
  @quickcheck.check(
    (m : ElmModule) => {
      let root = elm_root(m)
      let c = @syntax.TreeCursor::new(root)
      let mut ok = true
      @syntax.walk(root, n => {
        let kids = n.children()
        for p in node_positions(n) {
          c.reset(n)
          let moved = c.goto_first_child_for(p)
          ok = ok &&
            (match child_for(kids, p) {
              None => !moved && c.depth() == 0
              Some(i) =>
                moved &&
                c.depth() == 1 &&
                tag(c.node()) == tag(kids[i]) &&
                c.field_name() == n.field_of(kids[i])
            })
        }
        Continue
      })
      ok
    },
    count=100,
    max_size=24,
    seed=149,
  )
}

///|
/// Whether the descent stopped at the documented port exception: a file
/// comment (a port's doc comment) that contains `found`, while `found` lies in
/// a declaration that the comment overlaps only in part.
fn port_exception(
  tree : @syntax.Tree,
  stopped : @syntax.NodeRef,
  found : @syntax.NodeRef,
) -> Bool {
  let c = stopped.range()
  stopped.category() == "comment" &&
  range_within(found.range(), c) &&
  tree
  .ancestors(found)
  .iter()
  .any(a => {
    let d = a.range()
    a.category() == "declaration" &&
    !range_within(d, c) &&
    !range_within(c, d) &&
    before_or_at(d.start, c.end) &&
    before_or_at(c.start, d.end)
  })
}

///|
test "law: descending with goto_first_child_for ends at node_at, except at a port's doc comment" {
  // Edges: every node's start and end, one column before each, every line's
  // start and end and one past it, the end of the file and (1,1); every
  // position inside the file is checked. The port exception is documented on
  // goto_first_child_for.
  @quickcheck.check(
    (m : ElmModule) => {
      ignore(elm_root(m))
      let text = m.text()
      guard @syntax.Tree::new(parse_result(text)) is Some(tree) else {
        return false
      }
      let root = tree.root()
      let ranges = []
      @syntax.walk(root, n => {
        ranges.push(n.range())
        Continue
      })
      @lawkit.edge_positions(text, ranges)
      .iter()
      .filter(p => range_contains(root.range(), p))
      .all(p => {
        let c = @syntax.TreeCursor::new(root)
        while c.goto_first_child_for(p) {
          if !range_contains(c.node().range(), p) {
            ignore(c.goto_parent())
            break
          }
        }
        guard tree.node_at(p) is Some(found) else { return false }
        range_contains(c.node().range(), p) &&
        !c.node().children().iter().any(k => range_contains(k.range(), p)) &&
        (tag(c.node()) == tag(found) || port_exception(tree, c.node(), found))
      })
    },
    count=100,
    max_size=24,
    seed=139,
  )
}
