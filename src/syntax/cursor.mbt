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
  let kids = self
    .node()
    .children_with_fields()
    .map(x => (Some({ field: x.0, index: x.1, }), x.2))
  guard choose(kids) is Some(i) else { return false }
  let parent_path = self.path()
  self.frames.push({ siblings: kids, parent_path, index: i, })
  true
}

///|
pub fn TreeCursor::goto_first_child(self : TreeCursor) -> Bool {
  self.descend(kids => if kids.is_empty() { None } else { Some(0) })
}

///|
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
/// source order among equals, so a descent ends at `Tree::node_at(p)`. (A
/// port's doc comment overlaps its declaration only in part; there the
/// descent stops at the comment, which contains `node_at(p)`.)
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
