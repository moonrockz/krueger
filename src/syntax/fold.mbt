///|
/// Walk `root` (see `walk`) with an accumulator: `enter` and `leave` take the
/// current value and return the next one, in walk's callback order. The
/// result is the value after the last callback. The accumulator belongs to
/// the caller; fold does not copy it.
///
/// ```mbt check
/// test {
///   let src = "module Main exposing (..)\n\nadd x y =\n    x + y\n"
///   let result = @parser.parse_module(
///     @scanner.SourceText::new(src),
///     @scanner.DefaultScanner::new(),
///   )
///   let root = @syntax.NodeRef::of_result(result).unwrap()
///   // Count the expressions and find the deepest nesting.
///   let (count, _, deepest) = @syntax.fold(
///     root,
///     (0, 0, 0),
///     (acc, n) => {
///       let (count, depth, deepest) = acc
///       let count = count + (if n.category() == "expression" { 1 } else { 0 })
///       let depth = depth + 1
///       let deepest = if depth > deepest { depth } else { deepest }
///       ((count, depth, deepest), Continue)
///     },
///     leave=(acc, _) => (acc.0, acc.1 - 1, acc.2),
///   )
///   inspect(count, content="3")
///   inspect(deepest, content="5")
/// }
/// ```
pub fn[A] fold(
  root : NodeRef,
  init : A,
  enter : (A, NodeRef) -> (A, Control),
  leave? : (A, NodeRef) -> A = (a, _) => a,
) -> A {
  let mut acc = init
  walk(
    root,
    n => {
      let (next, control) = enter(acc, n)
      acc = next
      control
    },
    leave=n => acc = leave(acc, n),
  )
  acc
}
