///|
/// One step of a node path: a field of the parent and the node's index in
/// that field (0 for a field that holds one node).
pub(all) struct PathStep {
  field : String
  index : Int
} derive(Eq, Hash, Debug)

///|
/// Where a node sits below a start node: the steps from the start node, each
/// a field and an index, like a path into elm-syntax's JSON. A path is
/// immutable; a child's path shares its parent's steps.
pub struct NodePath {
  /// The steps, innermost first.
  priv reversed : @list.List[PathStep]
  priv length : Int
} derive(Eq, Hash, Debug)

///|
/// The path of the start node: no steps, depth 0.
pub fn NodePath::root() -> NodePath {
  { reversed: @list.empty(), length: 0, }
}

///|
/// The path of the node at `index` in this node's `field`.
pub fn NodePath::child(
  self : NodePath,
  field : String,
  index : Int,
) -> NodePath {
  { reversed: self.reversed.add({ field, index, }), length: self.length + 1, }
}

///|
/// The number of steps (0 for the start node).
pub fn NodePath::depth(self : NodePath) -> Int {
  self.length
}

///|
/// The steps, from the start node down (a new array).
pub fn NodePath::steps(self : NodePath) -> Array[PathStep] {
  let steps = self.reversed.to_array()
  steps.rev_in_place()
  steps
}

///|
/// The last step: the node's field and index in its parent.
pub fn NodePath::last(self : NodePath) -> PathStep? {
  self.reversed.head()
}

///|
/// The parent's path, or `None` for the start node.
pub fn NodePath::parent(self : NodePath) -> NodePath? {
  match self.reversed {
    More(_, tail~) => Some({ reversed: tail, length: self.length - 1, })
    Empty => None
  }
}

///|
/// The node this path leads to from `start`, or `None` when a step does not
/// exist there.
pub fn NodePath::resolve(self : NodePath, start : NodeRef) -> NodeRef? {
  let mut n = start
  for step in self.steps() {
    guard n.field(step.field).get(step.index) is Some(c) else { return None }
    n = c
  }
  Some(n)
}

///|
/// `declarations[0].declaration[0].expression[0]`; empty for the start node.
pub impl Show for NodePath with fn output(self, logger) {
  logger.write_string(self.steps().map(s => "\{s.field}[\{s.index}]").join("."))
}
