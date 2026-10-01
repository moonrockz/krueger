///|
fn label(n : @syntax.NodeRef) -> String {
  "\{n.category()}/\{n.kind()}"
}

///|
/// Pre-order over children(), computed independently of walk.
fn preorder(root : @syntax.NodeRef) -> Array[String] {
  let out = []
  let stack = [root]
  while stack.pop() is Some(n) {
    out.push(label(n))
    n.children().rev_each(c => stack.push(c))
  }
  out
}

///|
let small : String = "module M exposing (..)\n\n\nf =\n    g 1\n"

///|
/// `f = 1 + 1 + …` with 398 operators: the deepest chain the parser accepts.
fn deep_source() -> String {
  let sb = StringBuilder()
  sb.write_string("module M exposing (..)\n\n\nf =\n    1")
  for _ in 0..<398 {
    sb.write_string(" + 1")
  }
  sb.write_string("\n")
  sb.to_string()
}

///|
/// Enter and leave events of a walk whose enter returns `decide(n)`.
fn events_with(
  root : @syntax.NodeRef,
  decide : (@syntax.NodeRef) -> @syntax.Control,
) -> Array[String] {
  let events = []
  @syntax.walk(
    root,
    n => {
      events.push("+" + label(n))
      decide(n)
    },
    leave=n => events.push("-" + label(n)),
  )
  events
}

///|
test "walk enters in pre-order and leaves in post-order" {
  @expect.expect(events_with(parse_root(small), _ => Continue).join(" ")).to_equal(
    "+file/file +module/normal +module_name/module_name -module_name/module_name " +
    "+exposing/all -exposing/all -module/normal +declaration/function " +
    "+implementation/implementation +name/name -name/name +expression/application " +
    "+expression/functionOrValue -expression/functionOrValue +expression/integer " +
    "-expression/integer -expression/application -implementation/implementation " +
    "-declaration/function -file/file",
  )
}

///|
test "walk visits every node once, in children() pre-order" {
  let root = parse_root(expression_source)
  let seen = []
  @syntax.walk(root, n => {
    seen.push(label(n))
    Continue
  })
  @expect.expect(seen).to_equal(preorder(root))
}

///|
test "SkipChildren skips the subtree but still leaves the node" {
  @expect.expect_all(s => {
    let events = events_with(parse_root(small), n => {
      if n.category() == "declaration" {
        SkipChildren
      } else {
        Continue
      }
    })
    s
    .expect(events.filter(e => e.has_prefix("+implementation")).length())
    .to_equal(0)
    s
    .expect(events[events.length() - 2:].to_owned())
    .to_equal(["-declaration/function", "-file/file"])
  })
}

///|
test "SkipChildren on the root enters and leaves only the root" {
  @expect.expect(events_with(parse_root(small), _ => SkipChildren)).to_equal([
    "+file/file", "-file/file",
  ])
}

///|
test "SkipChildren on a leaf is the same as Continue" {
  let root = parse_root(small)
  @expect.expect(
    events_with(root, n => {
      if n.children().is_empty() {
        SkipChildren
      } else {
        Continue
      }
    }),
  ).to_equal(events_with(root, _ => Continue))
}

///|
test "Stop on the root enters only the root" {
  @expect.expect(events_with(parse_root(small), _ => Stop)).to_equal([
    "+file/file",
  ])
}

///|
test "Stop keeps finished siblings' leaves and ends the walk" {
  @expect.expect_all(s => {
    let events = events_with(parse_root(small), n => {
      if n.kind() == "integer" {
        Stop
      } else {
        Continue
      }
    })
    s
    .expect(events[events.length() - 3:].to_owned())
    .to_equal([
      "+expression/functionOrValue", "-expression/functionOrValue", "+expression/integer",
    ])
    s
    .expect(
      events.filter(e => e.has_prefix("-expression/application")).length(),
    )
    .to_equal(0)
  })
}

///|
test "Stop deep in a 398-level tree leaves no open ancestor" {
  let left = []
  @syntax.walk(
    tree_of(deep_source()).root(),
    n => if n.kind() == "integer" { Stop } else { Continue },
    leave=n => left.push(n.kind()),
  )
  // Only the nodes finished before the first (deepest) integer.
  @expect.expect(left).to_equal(["module_name", "all", "normal", "name"])
}

///|
test "changing children() inside a callback does not change the walk" {
  let root = parse_root(expression_source)
  let seen = []
  @syntax.walk(
    root,
    n => {
      seen.push(label(n))
      n.children().clear()
      Continue
    },
    leave=n => n.children().clear(),
  )
  @expect.expect(seen).to_equal(preorder(root))
}

///|
test "a walk inside a callback gets its standalone result" {
  @expect.expect_all(s => {
    let root = parse_root(expression_source)
    let outer = []
    let mut wrong = 0
    @syntax.walk(
      root,
      n => {
        outer.push(label(n))
        let inner = []
        @syntax.walk(n, m => {
          inner.push(label(m))
          Continue
        })
        if inner != preorder(n) {
          wrong = wrong + 1
        }
        // An inner walk that stops at once changes nothing outside it.
        @syntax.walk(n, _ => Stop)
        Continue
      },
      leave=n => {
        let inner = []
        @syntax.walk(n, m => {
          inner.push(label(m))
          Continue
        })
        if inner != preorder(n) {
          wrong = wrong + 1
        }
      },
    )
    s.expect(wrong).to_equal(0)
    s.expect(outer).to_equal(preorder(root))
  })
}

///|
test "walk handles a 398-level tree" {
  @expect.expect_all(s => {
    let mut count = 0
    let mut left = 0
    @syntax.walk(
      tree_of(deep_source()).root(),
      _ => {
        count = count + 1
        Continue
      },
      leave=_ => left = left + 1,
    )
    // 399 integers + 398 operator applications + file, module, module_name,
    // exposing, declaration, implementation, name.
    s.expect(count).to_equal(399 + 398 + 7)
    s.expect(left).to_equal(count)
  })
}
