///|
test "law: generated Elm parses without errors" {
  @quickcheck.check(
    (m : ElmModule) => {
      ignore(elm_root(m))
      true
    },
    count=200,
    max_size=24,
    seed=2026,
  )
}

///|
test "law: walk agrees with the recursive model for every Control policy" {
  @quickcheck.check(
    (input : (ElmModule, Policy)) => {
      let (m, p) = input
      let root = elm_root(m)
      walk_events(root, p) == model(root, p)
    },
    count=200,
    max_size=24,
    seed=2026,
  )
}

///|
test "law: with Continue, walk enters in children() pre-order" {
  @quickcheck.check(
    (m : ElmModule) => {
      let root = elm_root(m)
      let seen = []
      @syntax.walk(root, n => {
        seen.push(label(n))
        Continue
      })
      seen == preorder(root)
    },
    count=100,
    max_size=24,
    seed=7,
  )
}

///|
test "law: leave gets the node its enter got, innermost first" {
  @quickcheck.check(
    (input : (ElmModule, Policy)) => {
      let (m, p) = input
      let root = elm_root(m)
      let open : Array[@syntax.NodeRef] = []
      let mut ok = true
      let mut k = 0
      let mut stopped = false
      @syntax.walk(
        root,
        n => {
          open.push(n)
          k = k + 1
          let c = decide(p, k - 1)
          if c == Stop {
            stopped = true
          }
          c
        },
        leave=n => {
          match open.pop() {
            Some(o) if physical_equal(o, n) => ()
            _ => ok = false
          }
        },
      )
      // After Stop, the open nodes are the path to the stopping node.
      ok && (stopped || open.is_empty())
    },
    count=200,
    max_size=24,
    seed=11,
  )
}

///|
/// Subtree sizes in pre-order (test-only recursion over a shallow tree).
fn subtree_sizes(root : @syntax.NodeRef) -> Array[Int] {
  let sizes = []
  fn go(n : @syntax.NodeRef) -> Int {
    let at = sizes.length()
    sizes.push(1)
    let mut total = 1
    for c in n.children() {
      total = total + go(c)
    }
    sizes[at] = total
    total
  }
  ignore(go(root))
  sizes
}

///|
test "law: Stop at the k-th node enters the pre-order prefix and leaves only closed nodes" {
  @quickcheck.check(
    (input : (ElmModule, UInt)) => {
      let (m, raw) = input
      let root = elm_root(m)
      let pre = preorder(root)
      let k = (raw % pre.length().reinterpret_as_uint()).reinterpret_as_int()
      let sizes = subtree_sizes(root)
      let entered = []
      let left = []
      let mut i = 0
      @syntax.walk(
        root,
        n => {
          entered.push(label(n))
          i = i + 1
          if i - 1 == k {
            Stop
          } else {
            Continue
          }
        },
        leave=n => left.push(label(n)),
      )
      let closed = []
      for j in 0..<k {
        if j + sizes[j] <= k {
          closed.push(pre[j])
        }
      }
      left.sort()
      closed.sort()
      entered == pre[0:k + 1].to_owned() && left == closed
    },
    count=200,
    max_size=24,
    seed=13,
  )
}

///|
test "law: a walk inside a callback neither sees nor changes the outer walk" {
  @quickcheck.check(
    (input : (ElmModule, Policy, Policy)) => {
      let (m, p, q) = input
      let root = elm_root(m)
      let outer = []
      let mut ok = true
      let mut k = 0
      @syntax.walk(
        root,
        n => {
          outer.push("+" + tag(n))
          if walk_events(n, q) != model(n, q) {
            ok = false
          }
          // Returned arrays are the caller's: changing one changes nothing.
          n.children().clear()
          k = k + 1
          decide(p, k - 1)
        },
        leave=n => {
          outer.push("-" + tag(n))
          if walk_events(n, q) != model(n, q) {
            ok = false
          }
        },
      )
      ok && outer == model(root, p)
    },
    count=50,
    max_size=16,
    seed=19,
  )
}
