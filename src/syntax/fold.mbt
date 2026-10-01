///|
/// Walk `root` (see `walk`) with an accumulator: `enter` and `leave` take the
/// current value and return the next one, in walk's callback order. The
/// result is the value after the last callback. The accumulator belongs to
/// the caller; fold does not copy it.
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
