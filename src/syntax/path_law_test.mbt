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

///|
fn steps_of(xs : ArrayView[(Bool, UInt)]) -> Array[@syntax.PathStep] {
  xs.map(x => {
    field: if x.0 {
      "a"
    } else {
      "b"
    },
    index: x.1.reinterpret_as_int(),
  })
}

///|
test "law: from_steps builds the path whose steps it gets" {
  // Edges: no step, one step, many steps.
  @quickcheck.check(
    (s : Steps) => {
      let Steps(xs) = s
      let steps = steps_of(xs)
      let mut built = @syntax.NodePath::root()
      for step in steps {
        built = built.child(step.field, step.index)
      }
      let path = @syntax.NodePath::from_steps(steps)
      path.steps() == steps && path == built && path.depth() == steps.length()
    },
    count=100,
    max_size=24,
    seed=229,
  )
}

///|
test "law: append puts the steps of its argument after its own" {
  // Edges: either part empty (root is the identity on both sides), one step,
  // many steps; three parts for associativity.
  @quickcheck.check(
    (s : Steps) => {
      let Steps(xs) = s
      let third = xs.length() / 3
      let a = steps_of(xs[:third])
      let b = steps_of(xs[third:2 * third])
      let c = steps_of(xs[2 * third:])
      let pa = @syntax.NodePath::from_steps(a)
      let pb = @syntax.NodePath::from_steps(b)
      let pc = @syntax.NodePath::from_steps(c)
      let root = @syntax.NodePath::root()
      pa.append(pb).steps() == [..a, ..b] &&
      pa.append(pb).depth() == a.length() + b.length() &&
      pa.append(root) == pa &&
      root.append(pa) == pa &&
      pa.append(pb).append(pc) == pa.append(pb.append(pc)) &&
      pa.append(root.child("a", 1)) == pa.child("a", 1)
    },
    count=100,
    max_size=24,
    seed=233,
  )
}
