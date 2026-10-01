///|
/// Random path steps: a field ("a" or "b") and an index below 4.
struct Steps(Array[(Bool, UInt)]) derive(Debug)

///|
impl @quickcheck.Arbitrary for Steps with fn arbitrary(size, rs) {
  Steps(Array::makei(size, _ => (rs.next_uint() % 2 == 0, rs.next_uint() % 4)))
}

///|
impl @quickcheck.Shrink for Steps

///|
test "law: a child path's parent is the path, and its steps grow by the new step" {
  @quickcheck.check(
    (s : Steps) => {
      let Steps(xs) = s
      let mut path = @syntax.NodePath::root()
      let built : Array[@syntax.PathStep] = []
      xs
      .iter()
      .all(x => {
        let step : @syntax.PathStep = {
          field: if x.0 {
            "a"
          } else {
            "b"
          },
          index: x.1.reinterpret_as_int(),
        }
        let next = path.child(step.field, step.index)
        built.push(step)
        let ok = next.parent() == Some(path) &&
          next.last() == Some(step) &&
          next.depth() == path.depth() + 1 &&
          next.steps() == built &&
          next.to_string() == built.map(t => "\{t.field}[\{t.index}]").join(".")
        path = next
        ok
      })
    },
    count=100,
    max_size=24,
    seed=179,
  )
}
