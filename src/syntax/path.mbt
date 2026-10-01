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
/// immutable; a child's path shares its parent's steps. Get one from
/// `Tree::node_path`, an `EnterEvent` or `TreeCursor::path`.
///
/// ```mbt check
/// test {
///   let src = "module Main exposing (..)\n\nadd x y =\n    x + y\n"
///   let result = @parser.parse_module(
///     @scanner.SourceText::new(src),
///     @scanner.DefaultScanner::new(),
///   )
///   let root = @syntax.NodeRef::of_result(result).unwrap()
///   let tree = @syntax.Tree::new(result).unwrap()
///   let x = tree.node_at({ row: 4, column: 5, }).unwrap()
///   let path = tree.node_path(x).unwrap()
///   inspect(path, content="declarations[0].declaration[0].expression[0].left[0]")
///   inspect(path.depth(), content="4")
///   debug_inspect(path.last(), content="Some({ field: \"left\", index: 0 })")
///   debug_inspect(
///     path.steps().map(s => s.field),
///     content="[\"declarations\", \"declaration\", \"expression\", \"left\"]",
///   )
///   // `resolve` follows the steps from a start node.
///   inspect(path.resolve(root) == Some(x), content="true")
///   let up = path.parent().unwrap()
///   inspect(up, content="declarations[0].declaration[0].expression[0]")
///   inspect(up.resolve(root).unwrap().kind(), content="operatorapplication")
///   let missing = @syntax.NodePath::root().child("declarations", 5)
///   inspect(missing.resolve(root) is None, content="true")
/// }
/// ```
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
