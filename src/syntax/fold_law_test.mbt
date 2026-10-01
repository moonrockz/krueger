///|
/// Walk's events under `p`, collected by fold into a persistent list that
/// starts with "init": fold must hand each returned value to the next call.
fn fold_events(root : @syntax.NodeRef, p : Policy) -> Array[String] {
  let mut k = 0
  let folded : @list.List[String] = @syntax.fold(
    root,
    @list.empty().add("init"),
    (acc, n) => {
      k = k + 1
      (acc.add("+" + tag(n)), decide(p, k - 1))
    },
    leave=(acc, n) => acc.add("-" + tag(n)),
  )
  folded.rev().to_array()
}

///|
test "law: fold with a logging accumulator gives walk's events" {
  @quickcheck.check(
    (input : (ElmModule, Policy)) => {
      let (m, p) = input
      let root = elm_root(m)
      fold_events(root, p) == ["init"] + walk_events(root, p)
    },
    count=200,
    max_size=24,
    seed=17,
  )
}

///|
test "law: a fold inside a walk callback gives its standalone result" {
  @quickcheck.check(
    (input : (ElmModule, Policy, Policy)) => {
      let (m, p, q) = input
      let root = elm_root(m)
      let mut ok = true
      let mut k = 0
      let outer = []
      @syntax.walk(
        root,
        n => {
          outer.push("+" + tag(n))
          if fold_events(n, q) != ["init"] + model(n, q) {
            ok = false
          }
          k = k + 1
          decide(p, k - 1)
        },
        leave=n => {
          outer.push("-" + tag(n))
          if fold_events(n, q) != ["init"] + model(n, q) {
            ok = false
          }
        },
      )
      ok && outer == model(root, p)
    },
    count=50,
    max_size=16,
    seed=31,
  )
}
