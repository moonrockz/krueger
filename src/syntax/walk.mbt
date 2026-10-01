///|
/// What a traversal does after it enters a node.
pub(all) enum Control {
  /// Visit the node's children next.
  Continue
  /// Do not visit the children; the node is still left.
  SkipChildren
  /// End the traversal now; no node is left after this.
  Stop
} derive(Eq, Debug)

///|
/// One open node on the walk stack.
priv struct Frame {
  node : NodeRef
  children : Array[NodeRef]
  mut next : Int
}

///|
/// Visit `root` and every node below it in pre-order (source order). `enter`
/// runs when a node is reached and decides what happens next; `leave` runs
/// after all of a node's children, with the same node object. An explicit
/// stack, not recursion, holds the open nodes, so trees of any depth work on
/// every target. All traversal state belongs to this call.
///
/// ```mbt check
/// test {
///   let src = "module Main exposing (..)\n\nf x = x\n"
///   let result = @parser.parse_module(
///     @scanner.SourceText::new(src),
///     @scanner.DefaultScanner::new(),
///   )
///   let root = @syntax.NodeRef::of_result(result).unwrap()
///   // Log enter and leave; skip the module header.
///   let log = []
///   @syntax.walk(
///     root,
///     n => {
///       log.push("+" + n.kind())
///       if n.category() == "module" {
///         SkipChildren
///       } else {
///         Continue
///       }
///     },
///     leave=n => log.push("-" + n.kind()),
///   )
///   inspect(
///     log.join(" "),
///     content="+file +normal -normal +function +implementation +name -name +var -var +functionOrValue -functionOrValue -implementation -function -file",
///   )
///   // Stop at the first pattern: the walk ends there, with no more `leave`.
///   let seen = []
///   @syntax.walk(
///     root,
///     n => {
///       seen.push("+" + n.kind())
///       if n.category() == "pattern" {
///         Stop
///       } else {
///         Continue
///       }
///     },
///     leave=n => seen.push("-" + n.kind()),
///   )
///   inspect(
///     seen.join(" "),
///     content="+file +normal +module_name -module_name +all -all -normal +function +implementation +name -name +var",
///   )
/// }
/// ```
pub fn walk(
  root : NodeRef,
  enter : (NodeRef) -> Control,
  leave? : (NodeRef) -> Unit = _ => (),
) -> Unit {
  match enter(root) {
    Stop => return
    SkipChildren => {
      leave(root)
      return
    }
    Continue => ()
  }
  let stack = [{ node: root, children: root.children(), next: 0, }]
  while stack.last() is Some(top) {
    if top.next < top.children.length() {
      let child = top.children[top.next]
      top.next = top.next + 1
      match enter(child) {
        Stop => return
        SkipChildren => leave(child)
        Continue =>
          stack.push({ node: child, children: child.children(), next: 0, })
      }
    } else {
      ignore(stack.pop())
      leave(top.node)
    }
  }
}
