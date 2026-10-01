///|
/// One level of a cursor: the siblings (with their fields) and the current
/// position among them.
priv struct CursorFrame {
  /// Never changed after the frame is made, so copies share it.
  siblings : Array[(PathStep?, NodeRef)]
  /// The parent's path (the start node's frame has the empty path).
  parent_path : NodePath
  mut index : Int
}

///|
/// A tree-sitter-style cursor: the caller moves it with the `goto_*` methods.
/// Each `goto_*` returns `false` and leaves the cursor in place when there is
/// nowhere to go. Its state is a stack of frames, not recursion. A cursor
/// belongs to its caller; `copy` gives an independent cursor.
///
/// ```mbt check
/// test {
///   let src = "module Main exposing (..)\n\nadd x y =\n    x + y\n"
///   let result = @parser.parse_module(
///     @scanner.SourceText::new(src),
///     @scanner.DefaultScanner::new(),
///   )
///   let root = @syntax.NodeRef::of_result(result).unwrap()
///   let cursor = @syntax.TreeCursor::new(root)
///   // To the module header, back to the file, then to the function.
///   inspect(cursor.goto_first_child(), content="true")
///   inspect(cursor.node().kind(), content="normal")
///   inspect(cursor.goto_previous_sibling(), content="false")
///   inspect(cursor.goto_parent(), content="true")
///   inspect(cursor.goto_last_child(), content="true")
///   inspect(cursor.node().kind(), content="function")
///   // Down to the arguments of `add`.
///   ignore(cursor.goto_first_child()) // implementation
///   ignore(cursor.goto_first_child()) // name `add`
///   inspect(cursor.goto_next_sibling(), content="true")
///   debug_inspect(cursor.field_name(), content="Some(\"arguments\")")
///   inspect(cursor.depth(), content="3")
///   inspect(cursor.path(), content="declarations[0].declaration[0].arguments[0]")
///   // A copy moves on its own.
///   let other = cursor.copy()
///   ignore(other.goto_parent())
///   inspect(cursor.node().kind(), content="var")
/// }
/// ```
pub struct TreeCursor {
  priv frames : Array[CursorFrame]
}

///|
/// A cursor at `root` (depth 0, no field).
pub fn TreeCursor::new(root : NodeRef) -> TreeCursor {
  {
    frames: [
      { siblings: [(None, root)], parent_path: NodePath::root(), index: 0, },
    ],
  }
}

///|
fn TreeCursor::top(self : TreeCursor) -> CursorFrame {
  self.frames[self.frames.length() - 1]
}

///|
/// The node at the cursor.
pub fn TreeCursor::node(self : TreeCursor) -> NodeRef {
  let f = self.top()
  f.siblings[f.index].1
}

///|
/// The node's field in its parent (`"arguments"`, …); `None` at the start
/// node.
pub fn TreeCursor::field_name(self : TreeCursor) -> String? {
  let f = self.top()
  f.siblings[f.index].0.map(step => step.field)
}

///|
/// The steps from the start node to the node (each frame keeps its parent's
/// path, so this is O(1)).
pub fn TreeCursor::path(self : TreeCursor) -> NodePath {
  let f = self.top()
  match f.siblings[f.index].0 {
    Some(step) => f.parent_path.child(step.field, step.index)
    None => f.parent_path
  }
}

///|
/// The number of `goto_*` steps below the start node (0 at the start node).
pub fn TreeCursor::depth(self : TreeCursor) -> Int {
  self.frames.length() - 1
}

///|
/// Move to the child that `choose` picks among the node's children.
fn TreeCursor::descend(
  self : TreeCursor,
  choose : (Array[(PathStep?, NodeRef)]) -> Int?,
) -> Bool {
  let kids = self.node().children_with_fields().map(x => (Some(x.0), x.1))
  guard choose(kids) is Some(i) else { return false }
  let parent_path = self.path()
  self.frames.push({ siblings: kids, parent_path, index: i, })
  true
}

///|
/// Move to the node's first child in source order. Return `false` and stay
/// when the node has no children.
pub fn TreeCursor::goto_first_child(self : TreeCursor) -> Bool {
  self.descend(kids => if kids.is_empty() { None } else { Some(0) })
}

///|
/// Move to the node's last child in source order. Return `false` and stay
/// when the node has no children.
pub fn TreeCursor::goto_last_child(self : TreeCursor) -> Bool {
  self.descend(kids => {
    if kids.is_empty() {
      None
    } else {
      Some(kids.length() - 1)
    }
  })
}

///|
/// Move to the next child of the same parent, in source order. Return
/// `false` and stay at the last child and at the start node.
pub fn TreeCursor::goto_next_sibling(self : TreeCursor) -> Bool {
  let f = self.top()
  if f.index + 1 < f.siblings.length() {
    f.index = f.index + 1
    true
  } else {
    false
  }
}

///|
/// Move to the previous child of the same parent, in source order. Return
/// `false` and stay at the first child and at the start node.
pub fn TreeCursor::goto_previous_sibling(self : TreeCursor) -> Bool {
  let f = self.top()
  if f.index > 0 {
    f.index = f.index - 1
    true
  } else {
    false
  }
}

///|
/// Move to the parent. Return `false` and stay at the start node: the
/// cursor never goes above the node it started at.
pub fn TreeCursor::goto_parent(self : TreeCursor) -> Bool {
  if self.frames.length() > 1 {
    ignore(self.frames.pop())
    true
  } else {
    false
  }
}

///|
/// Move to the child whose range contains `p`, or else to the first child
/// that starts after `p`. Where children overlap (a doc comment and its
/// attributes), the innermost one that contains `p` wins, and the first in
/// source order among equals.
///
/// To reach `Tree::node_at(p)`, descend while the new node contains `p`, and
/// step back with `goto_parent` from the first one that does not: a loop that
/// only calls `goto_first_child_for` goes one node too far whenever
/// `node_at(p)` has children after `p`. (Where a port's doc comment with
/// attributes overlaps the port declaration only in part, the descent stops
/// at the comment, which contains `node_at(p)`.)
///
/// ```mbt check
/// test {
///   let src = "module Main exposing (..)\n\nadd x y =\n    x + y\n"
///   let result = @parser.parse_module(
///     @scanner.SourceText::new(src),
///     @scanner.DefaultScanner::new(),
///   )
///   let tree = @syntax.Tree::new(result).unwrap()
///   let p : @ast.Location = { row: 4, column: 7, } // the `+` in `x + y`
///   let contains = (r : @ast.Range) => {
///     let after_start = r.start.row < p.row ||
///       (r.start.row == p.row && r.start.column <= p.column)
///     let before_end = p.row < r.end.row ||
///       (p.row == r.end.row && p.column < r.end.column)
///     after_start && before_end
///   }
///   // The recipe: descend while the new node contains `p`.
///   let cursor = @syntax.TreeCursor::new(tree.root())
///   while cursor.goto_first_child_for(p) {
///     if !contains(cursor.node().range()) {
///       ignore(cursor.goto_parent())
///       break
///     }
///   }
///   inspect(cursor.node().kind(), content="operatorapplication")
///   inspect(tree.node_at(p) == Some(cursor.node()), content="true")
///   // A plain loop goes one node too far, to `y` after the `+`.
///   let naive = @syntax.TreeCursor::new(tree.root())
///   while naive.goto_first_child_for(p) {
///
///   }
///   inspect(
///     naive.path(),
///     content="declarations[0].declaration[0].expression[0].right[0]",
///   )
/// }
/// ```
pub fn TreeCursor::goto_first_child_for(
  self : TreeCursor,
  p : @ast.Location,
) -> Bool {
  self.descend(kids => {
    let mut best : Int? = None
    for i, x in kids {
      let r = x.1.range()
      if contains(r, p) {
        match best {
          None => best = Some(i)
          Some(b) => {
            let br = kids[b].1.range()
            if within(r, br) && r != br {
              best = Some(i)
            }
          }
        }
      }
    }
    match best {
      Some(_) => best
      None => kids.search_by(x => !at_or_before(x.1.range().start, p))
    }
  })
}

///|
/// Move the cursor to a new start node (depth 0).
pub fn TreeCursor::reset(self : TreeCursor, node : NodeRef) -> Unit {
  self.frames.clear()
  self.frames.push({
    siblings: [(None, node)],
    parent_path: NodePath::root(),
    index: 0,
  })
}

///|
/// An independent cursor at the same place.
pub fn TreeCursor::copy(self : TreeCursor) -> TreeCursor {
  {
    frames: self.frames.map(f => {
      siblings: f.siblings,
      parent_path: f.parent_path,
      index: f.index,
    }),
  }
}
