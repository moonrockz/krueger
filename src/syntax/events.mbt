///|
/// What an `Enter` event tells: only what a streaming parser knows when a node
/// starts. `field` is the node's field in its parent and `path` the steps from
/// the start node (`None` and the empty path for the start node); `depth` is
/// `path.depth()`.
pub struct EnterEvent {
  category : String
  kind : String
  field : String?
  start : @ast.Location
  depth : Int
  path : NodePath
} derive(Eq, Debug)

///|
/// What a `Leave` event tells: the finished node, with the depth and path of
/// its `Enter`.
pub struct LeaveEvent {
  node : NodeRef
  depth : Int
  path : NodePath
} derive(Eq, Debug)

///|
/// An `EnterEvent`; its `depth` is `path.depth()`. Event sources outside this
/// package build events with `new`, so fields added later need not break
/// them.
pub fn EnterEvent::new(
  category~ : String,
  kind~ : String,
  field~ : String?,
  start~ : @ast.Location,
  path~ : NodePath,
) -> EnterEvent {
  { category, kind, field, start, depth: path.depth(), path, }
}

///|
/// A `LeaveEvent`; its `depth` is `path.depth()`.
pub fn LeaveEvent::new(node~ : NodeRef, path~ : NodePath) -> LeaveEvent {
  { node, depth: path.depth(), path, }
}

///|
/// A traversal event, in walk order.
pub(all) enum Event {
  Enter(EnterEvent)
  Leave(LeaveEvent)
} derive(Eq, Debug)

///|
/// A pull source of events in walk order. `skip_children` is valid right
/// after an `Enter`: the next event is then that node's `Leave`. Elsewhere it
/// does nothing.
pub(open) trait EventSource {
  fn next(Self) -> Event?
  fn skip_children(Self) -> Unit
}

///|
/// One open node of a reader: its children with their fields.
priv struct ReaderFrame {
  entered : NodeRef
  path : NodePath
  fields : Array[(String, Int, NodeRef)]
  mut at : Int
}

///|
/// Reads the events of a tree one at a time (the walk engine, paused between
/// `next` calls). Each reader owns its state; readers over one tree do not
/// affect each other.
pub struct EventReader {
  priv stack : Array[ReaderFrame]
  /// The node whose `Enter` was returned last (with its path), until its
  /// children are read.
  priv mut pending : (NodeRef, NodePath)?
  /// The root, until its `Enter` is returned.
  priv mut root : NodeRef?
}

///|
/// A reader positioned before `root`'s `Enter`.
pub fn EventReader::new(root : NodeRef) -> EventReader {
  { stack: [], pending: None, root: Some(root), }
}

///|
fn enter_event(n : NodeRef, field : String?, path : NodePath) -> Event {
  Enter(
    EnterEvent::new(
      category=n.category(),
      kind=n.kind(),
      field~,
      start=n.range().start,
      path~,
    ),
  )
}

///|
pub impl EventSource for EventReader with fn next(self) {
  if self.pending is Some((n, path)) {
    self.pending = None
    self.stack.push({
      entered: n,
      path,
      fields: n.children_with_fields(),
      at: 0,
    })
  }
  if self.root is Some(r) {
    self.root = None
    let path = NodePath::root()
    self.pending = Some((r, path))
    return Some(enter_event(r, None, path))
  }
  guard self.stack.last() is Some(top) else { return None }
  if top.at < top.fields.length() {
    let (field, index, child) = top.fields[top.at]
    top.at = top.at + 1
    let path = top.path.child(field, index)
    self.pending = Some((child, path))
    Some(enter_event(child, Some(field), path))
  } else {
    ignore(self.stack.pop())
    Some(Leave(LeaveEvent::new(node=top.entered, path=top.path)))
  }
}

///|
pub impl EventSource for EventReader with fn skip_children(self) {
  if self.pending is Some((n, path)) {
    self.pending = None
    self.stack.push({ entered: n, path, fields: [], at: 0, })
  }
}
