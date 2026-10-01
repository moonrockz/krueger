///|
/// Records pushed events and returns the policy's k-th decision.
struct PolicyHandler {
  policy : Policy
  log : Array[String]
  mut taken : Int
}

///|
impl @syntax.Handler for PolicyHandler with fn on_enter(self, e) {
  self.log.push("+" + start_tag(e.category, e.kind, e.start))
  self.taken = self.taken + 1
  decide(self.policy, self.taken - 1)
}

///|
impl @syntax.Handler for PolicyHandler with fn on_leave(self, e) {
  self.log.push("-" + tag(e.node))
}

///|
fn pushed_events(root : @syntax.NodeRef, p : Policy) -> Array[String] {
  let h : PolicyHandler = { policy: p, log: [], taken: 0, }
  @syntax.push_events(@syntax.EventReader::new(root), h)
  h.log
}

///|
test "law: push_events over a reader gives walk's events" {
  @quickcheck.check(
    (input : (ElmModule, Policy)) => {
      let (m, p) = input
      let root = elm_root(m)
      pushed_events(root, p) == walk_projection(root, p)
    },
    count=200,
    max_size=24,
    seed=103,
  )
}

///|
/// An event source that logs every call push_events makes to it.
struct LoggedSource {
  inner : @syntax.EventReader
  calls : Array[String]
}

///|
impl @syntax.EventSource for LoggedSource with fn next(self) {
  let e = self.inner.next()
  self.calls.push(
    match e {
      Some(Enter(e)) => "next +" + start_tag(e.category, e.kind, e.start)
      Some(Leave(e)) => "next -" + tag(e.node)
      None => "next end"
    },
  )
  e
}

///|
impl @syntax.EventSource for LoggedSource with fn skip_children(self) {
  self.calls.push("skip")
  self.inner.skip_children()
}

///|
test "law: push_events reads one event at a time, skips only on SkipChildren and reads nothing after Stop" {
  @quickcheck.check(
    (input : (ElmModule, Policy)) => {
      let (m, p) = input
      let root = elm_root(m)
      let source = { inner: @syntax.EventReader::new(root), calls: [], }
      let h : PolicyHandler = { policy: p, log: [], taken: 0, }
      @syntax.push_events(source, h)
      // The calls a correct push_events makes, from a plain reader.
      let expected = []
      let r = @syntax.EventReader::new(root)
      let mut k = 0
      let mut stopped = false
      while r.next() is Some(e) {
        match e {
          Enter(e) => {
            expected.push("next +" + start_tag(e.category, e.kind, e.start))
            k = k + 1
            match decide(p, k - 1) {
              Continue => ()
              SkipChildren => {
                expected.push("skip")
                r.skip_children()
              }
              Stop => {
                stopped = true
                break
              }
            }
          }
          Leave(e) => expected.push("next -" + tag(e.node))
        }
      }
      if !stopped {
        expected.push("next end")
      }
      source.calls == expected
    },
    count=200,
    max_size=24,
    seed=167,
  )
}

///|
/// An event as one line with every field, so records compare in full.
fn record_line(e : @syntax.Event) -> String {
  match e {
    Enter(e) =>
      "+\{e.category}/\{e.kind} field=\{e.field.unwrap_or("-")} at=\{e.start.row}:\{e.start.column} depth=\{e.depth} path=\{e.path}"
    Leave(e) => "-\{tag(e.node)} depth=\{e.depth} path=\{e.path}"
  }
}

///|
/// Records the full events pushed to it and follows a policy.
struct RecordHandler {
  policy : Policy
  lines : Array[String]
  mut taken : Int
}

///|
impl @syntax.Handler for RecordHandler with fn on_enter(self, e) {
  self.lines.push(record_line(Enter(e)))
  self.taken = self.taken + 1
  decide(self.policy, self.taken - 1)
}

///|
impl @syntax.Handler for RecordHandler with fn on_leave(self, e) {
  self.lines.push(record_line(Leave(e)))
}

///|
test "law: push_events hands the handler exactly the reader's event records" {
  @quickcheck.check(
    (input : (ElmModule, Policy)) => {
      let (m, p) = input
      let root = elm_root(m)
      let h : RecordHandler = { policy: p, lines: [], taken: 0, }
      @syntax.push_events(@syntax.EventReader::new(root), h)
      let expected = []
      let r = @syntax.EventReader::new(root)
      let mut k = 0
      while r.next() is Some(e) {
        expected.push(record_line(e))
        if e is Enter(_) {
          k = k + 1
          match decide(p, k - 1) {
            Continue => ()
            SkipChildren => r.skip_children()
            Stop => break
          }
        }
      }
      h.lines == expected
    },
    count=200,
    max_size=24,
    seed=197,
  )
}
