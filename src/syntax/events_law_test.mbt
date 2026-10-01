///|
/// What an `Enter` can show of a node: category/kind@start (no end yet).
fn start_tag(category : String, kind : String, start : @ast.Location) -> String {
  "\{category}/\{kind}@\{start.row}:\{start.column}"
}

///|
/// walk's events under `p`, with each enter shown as an `Enter` shows it.
fn walk_projection(root : @syntax.NodeRef, p : Policy) -> Array[String] {
  let events = []
  let mut k = 0
  @syntax.walk(
    root,
    n => {
      events.push("+" + start_tag(n.category(), n.kind(), n.range().start))
      k = k + 1
      decide(p, k - 1)
    },
    leave=n => events.push("-" + tag(n)),
  )
  events
}

///|
/// The events a reader gives when its caller follows `p` after each `Enter`.
fn reader_events(root : @syntax.NodeRef, p : Policy) -> Array[String] {
  let r = @syntax.EventReader::new(root)
  let events = []
  let mut k = 0
  while r.next() is Some(e) {
    match e {
      Enter(e) => {
        events.push("+" + start_tag(e.category, e.kind, e.start))
        k = k + 1
        match decide(p, k - 1) {
          Continue => ()
          SkipChildren => r.skip_children()
          Stop => break
        }
      }
      Leave(e) => events.push("-" + tag(e.node))
    }
  }
  events
}

///|
test "law: an event reader driven by a Control policy gives walk's events" {
  @quickcheck.check(
    (input : (ElmModule, Policy)) => {
      let (m, p) = input
      let root = elm_root(m)
      reader_events(root, p) == walk_projection(root, p)
    },
    count=200,
    max_size=24,
    seed=101,
  )
}

///|
test "law: each Enter's field is the parent's field_of the child" {
  @quickcheck.check(
    (m : ElmModule) => {
      let root = elm_root(m)
      let from_reader = []
      let r = @syntax.EventReader::new(root)
      while r.next() is Some(e) {
        if e is Enter({ field, .. }) {
          from_reader.push(field)
        }
      }
      let from_walk = []
      let open : Array[@syntax.NodeRef] = []
      @syntax.walk(
        root,
        n => {
          from_walk.push(open.last().bind(parent => parent.field_of(n)))
          open.push(n)
          Continue
        },
        leave=_ => ignore(open.pop()),
      )
      from_reader == from_walk
    },
    count=100,
    max_size=24,
    seed=107,
  )
}

///|
/// Reads one event from `r` under policy `p`: records it, then applies the
/// policy's decision after an `Enter`. Returns false when the reader is done
/// (no events left, or the policy said `Stop`).
fn read_one(
  r : @syntax.EventReader,
  p : Policy,
  taken : Ref[Int],
  out : Array[String],
) -> Bool {
  match r.next() {
    Some(Enter(e)) => {
      out.push("+" + start_tag(e.category, e.kind, e.start))
      taken.val = taken.val + 1
      match decide(p, taken.val - 1) {
        Continue => true
        SkipChildren => {
          r.skip_children()
          true
        }
        Stop => false
      }
    }
    Some(Leave(e)) => {
      out.push("-" + tag(e.node))
      true
    }
    None => false
  }
}

///|
test "law: two readers, each with its own policy, interleaved in any order, give their standalone events" {
  @quickcheck.check(
    (input : (ElmModule, (Policy, Policy), Array[Bool])) => {
      let (m, (p, q), schedule) = input
      let root = elm_root(m)
      let a = @syntax.EventReader::new(root)
      let b = @syntax.EventReader::new(root)
      let (from_a, from_b) = ([], [])
      let ka = Ref(0)
      let kb = Ref(0)
      let mut a_live = true
      let mut b_live = true
      let mut i = 0
      while a_live || b_live {
        let pick_a = if !b_live {
          true
        } else if !a_live {
          false
        } else if schedule.is_empty() {
          i % 2 == 0
        } else {
          schedule[i % schedule.length()]
        }
        i = i + 1
        if pick_a {
          a_live = read_one(a, p, ka, from_a)
        } else {
          b_live = read_one(b, q, kb, from_b)
        }
      }
      from_a == walk_projection(root, p) && from_b == walk_projection(root, q)
    },
    count=100,
    max_size=24,
    seed=157,
  )
}

///|
test "law: skip_children anywhere but right after an Enter changes nothing" {
  @quickcheck.check(
    (input : (ElmModule, Policy, Array[Bool])) => {
      let (m, p, extra) = input
      let root = elm_root(m)
      let r = @syntax.EventReader::new(root)
      r.skip_children()
      let events = []
      let mut k = 0
      let mut i = 0
      let mut stopped = false
      while r.next() is Some(e) {
        match e {
          Enter(e) => {
            events.push("+" + start_tag(e.category, e.kind, e.start))
            k = k + 1
            match decide(p, k - 1) {
              Continue => ()
              SkipChildren => {
                r.skip_children()
                r.skip_children()
              }
              Stop => {
                stopped = true
                break
              }
            }
          }
          Leave(e) => {
            events.push("-" + tag(e.node))
            i = i + 1
            if !extra.is_empty() && extra[i % extra.length()] {
              r.skip_children()
            }
          }
        }
      }
      if !stopped {
        r.skip_children()
        if r.next() is Some(_) || r.next() is Some(_) {
          events.push("! an event after the end")
        }
      }
      events == walk_projection(root, p)
    },
    count=200,
    max_size=24,
    seed=151,
  )
}

///|
test "law: under any Control policy, each event's depth and path lead to its node, and each Leave repeats its Enter's" {
  @quickcheck.check(
    (input : (ElmModule, Policy)) => {
      let (m, p) = input
      let root = elm_root(m)
      let r = @syntax.EventReader::new(root)
      let open : Array[@syntax.EnterEvent] = []
      let mut ok = true
      let mut k = 0
      while r.next() is Some(e) {
        match e {
          Enter(e) => {
            ok = ok &&
              e.depth == open.length() &&
              e.depth == e.path.depth() &&
              e.path.parent() == open.last().map(o => o.path) &&
              e.path.last().map(s => s.field) == e.field &&
              e.path
              .resolve(root)
              .map(n => start_tag(n.category(), n.kind(), n.range().start)) ==
              Some(start_tag(e.category, e.kind, e.start))
            open.push(e)
            k = k + 1
            match decide(p, k - 1) {
              Continue => ()
              SkipChildren => r.skip_children()
              Stop => break
            }
          }
          Leave(e) =>
            match open.pop() {
              Some(entered) =>
                ok = ok &&
                  e.depth == entered.depth &&
                  e.path == entered.path &&
                  e.path.resolve(root).map(tag) == Some(tag(e.node))
              None => ok = false
            }
        }
      }
      ok
    },
    count=200,
    max_size=24,
    seed=173,
  )
}

///|
/// The path of every Enter, in pre-order (all events read with Continue).
fn reader_paths(root : @syntax.NodeRef) -> Array[@syntax.NodePath] {
  let paths = []
  let r = @syntax.EventReader::new(root)
  while r.next() is Some(e) {
    if e is Enter(e) {
      paths.push(e.path)
    }
  }
  paths
}

///|
test "law: a tree's node_path of every node is the reader's path at that node" {
  @quickcheck.check(
    (m : ElmModule) => {
      ignore(elm_root(m))
      let ElmModule(text) = m
      guard @syntax.Tree::new(parse_result(text)) is Some(tree) else {
        return false
      }
      let nodes = []
      @syntax.walk(tree.root(), n => {
        nodes.push(n)
        Continue
      })
      let paths = reader_paths(tree.root())
      paths.length() == nodes.length() &&
      nodes
      .iter()
      .zip(paths.iter())
      .all(pair => tree.node_path(pair.0) == Some(pair.1))
    },
    count=100,
    max_size=24,
    seed=191,
  )
}

///|
test "law: a path resolves exactly the field slot it names, and nothing else" {
  @quickcheck.check(
    (m : ElmModule) => {
      let root = elm_root(m)
      let nodes = []
      @syntax.walk(root, n => {
        nodes.push(n)
        Continue
      })
      let paths = reader_paths(root)
      let mut ok = paths.length() == nodes.length()
      for k, n in nodes {
        let p = paths[k]
        ok = ok && p.resolve(root).map(tag) == Some(tag(n))
        for f in n.fields() {
          let slots = n.field(f)
          for i, child in slots {
            ok = ok && p.child(f, i).resolve(root).map(tag) == Some(tag(child))
          }
          ok = ok &&
            p.child(f, -1).resolve(root) is None &&
            p.child(f, slots.length()).resolve(root) is None
        }
        ok = ok && p.child("no such field", 0).resolve(root) is None
      }
      ok
    },
    count=100,
    max_size=24,
    seed=193,
  )
}
