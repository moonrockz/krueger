# Choose a traversal

krueger gives you six ways to go through a syntax tree. They differ in who
drives the loop and in what you get at each node. `walk`, `fold`, `accept`,
`EventReader` and `push_events` visit the same nodes in the same order. This
article helps you choose a style. Then it shows one task for each of these
five styles, with tested code. [Build editor features](editor-features.mbt.md)
shows `TreeCursor`.

## The decision table

| Style | Who drives | Use it to | Control |
|---|---|---|---|
| `walk(root, enter, leave?)` | krueger, callbacks | do work at each node, stop early, skip subtrees | `enter` returns a `Control` |
| `fold(root, init, enter, leave?)` | krueger, callbacks | compute one value (a count, a depth, a set) | `enter` returns `(acc, Control)` |
| `accept(root, visitor)` + `Visitor` | krueger, one method per node family | write lint rules and analyses by node family | each `visit_*` returns a `Control` |
| `EventReader::new(root)` | you, pull | write streaming output, stop when you want, skip subtrees | call `skip_children()` after an `Enter`; stop calling `next()` |
| `push_events(source, handler)` + `Handler` | krueger, push | keep one handler for any `EventSource`, also a future streaming parser | `on_enter` returns a `Control` |
| `TreeCursor::new(node)` | you, step by step | move to parent, child and sibling, as an editor does | each `goto_*` returns `false` when there is nowhere to go |

`Control` has three values:

- `Continue` visits the children of the node.
- `SkipChildren` does not visit the children. The node is still left.
- `Stop` ends the traversal. No more `leave` calls occur.

## The module for the examples

All examples use this module. It has a `Debug.log` call, a `Debug.todo`
call, and one function with no type signature.

```mbt check
///|
let tr_source : String =
  #|module Shop exposing (Item, total, view)
  #|
  #|import Dict
  #|import Html exposing (Html, text)
  #|
  #|
  #|type alias Item =
  #|    { name : String, price : Int }
  #|
  #|
  #|total : List Item -> Int
  #|total items =
  #|    List.foldl (\i acc -> i.price + acc) 0 items
  #|
  #|
  #|view items =
  #|    Debug.log "items" (text (String.fromInt (total items)))
  #|
  #|
  #|discount : Int -> Int
  #|discount p =
  #|    Debug.todo "later"
  #|

///|
/// The root node of `text`. Fails on any diagnostic.
fn tr_root(text : String) -> @syntax.NodeRef raise {
  let result = @krueger.parse_module(@krueger.SourceText::new(text))
  guard result.diagnostics.is_empty() else {
    fail("unexpected diagnostics: \{result.diagnostics.length()}")
  }
  guard @syntax.NodeRef::of_result(result) is Some(root) else { fail("no AST") }
  root
}

///|
/// `row:column` of a location.
fn tr_loc(l : @ast.Location) -> String {
  "\{l.row}:\{l.column}"
}

///|
/// `row:column-row:column` of a range.
fn tr_range(r : @ast.Range) -> String {
  "\{tr_loc(r.start)}-\{tr_loc(r.end)}"
}
```

## Find the first `Debug.todo` with `walk`

Use `walk` when you do work at each node and want to stop early. This
example looks for the first `Debug.todo` reference. It returns `Stop` when it
finds one, so the walk does not visit the rest of the file. A type annotation
cannot hold an expression, so the walk returns `SkipChildren` for each
annotation.

```mbt check
///|
/// The range of the first `Debug.todo` reference, and the number of nodes
/// that the walk entered.
fn tr_first_todo(root : @syntax.NodeRef) -> (@ast.Range?, Int) {
  let mut found = None
  let mut entered = 0
  @syntax.walk(root, node => {
    entered += 1
    match node {
      TypeAnnotation(_) => SkipChildren
      Expression({ value: FunctionOrValue(["Debug"], "todo"), range, }) => {
        found = Some(range)
        Stop
      }
      _ => Continue
    }
  })
  (found, entered)
}

///|
test "walk stops at the first Debug.todo" {
  let root = tr_root(tr_source)
  let (found, entered) = tr_first_todo(root)
  debug_inspect(found.map(tr_range), content="Some(\"22:5-22:15\")")
  inspect(entered, content="63")
  // A walk with no SkipChildren and no Stop enters every node.
  let mut all = 0
  @syntax.walk(root, _ => {
    all += 1
    Continue
  })
  inspect(all, content="75")
}
```

`SkipChildren` still calls `leave` for the node. `Stop` calls no more
`leave`. This test counts the calls:

```mbt check
///|
test "Stop ends the walk without leave calls" {
  let root = tr_root(tr_source)
  let mut enters = 0
  let mut leaves = 0
  @syntax.walk(
    root,
    node => {
      enters += 1
      if node.kind() == "import" {
        Stop
      } else {
        Continue
      }
    },
    leave=_ => leaves += 1,
  )
  // file, module, module name, exposing list, 3 exposes, import
  inspect(enters, content="8")
  // module name, 3 exposes, exposing list, module
  inspect(leaves, content="6")
}
```

## Count nodes and measure depth with `fold`

Use `fold` when the result is one value. `fold` threads an accumulator
through the walk. `enter` returns the new accumulator and a `Control`.

This example counts the nodes per category:

```mbt check
///|
fn tr_count_categories(root : @syntax.NodeRef) -> Map[String, Int] {
  @syntax.fold(root, ({} : Map[String, Int]), (counts, node) => {
    let key = node.category()
    counts.set(key, counts.get(key).unwrap_or(0) + 1)
    (counts, Continue)
  })
}

///|
test "fold counts the nodes per category" {
  let counts = tr_count_categories(tr_root(tr_source))
  debug_inspect(counts.get("declaration"), content="Some(4)")
  debug_inspect(counts.get("import"), content="Some(2)")
  debug_inspect(counts.get("signature"), content="Some(2)")
}
```

With a `leave` function, the accumulator can track the current depth.
`enter` goes one level down, `leave` goes one level up, and the accumulator
keeps the maximum:

```mbt check
///|
/// The maximum nesting depth of expressions (an expression inside no other
/// expression has depth 1).
fn tr_expression_depth(root : @syntax.NodeRef) -> Int {
  let (_, max) = @syntax.fold(
    root,
    (0, 0),
    (acc, node) => {
      let (depth, max) = acc
      if node.category() == "expression" {
        let d = depth + 1
        ((d, if d > max { d } else { max }), Continue)
      } else {
        (acc, Continue)
      }
    },
    leave=(acc, node) => {
      let (depth, max) = acc
      if node.category() == "expression" {
        (depth - 1, max)
      } else {
        acc
      }
    },
  )
  max
}

///|
test "fold with leave measures the expression depth" {
  // view: application > parenthesized > application > parenthesized >
  // application > parenthesized > application > functionOrValue
  inspect(tr_expression_depth(tr_root(tr_source)), content="8")
}
```

## Write a lint rule with a `Visitor`

Use `accept` and a `Visitor` when your code treats node families in
different ways. Each `visit_*` method gets the nodes of one family. Every
method has a default that returns `Continue`, so you implement only the
methods you need.

This lint rule reports every `Debug.log` call and every top-level function
that has no type signature. `visit_function` gets top-level functions and
`let` functions; the rule checks only the top-level ones.

```mbt check
///|
struct TrLint {
  problems : Array[String]
}

///|
impl @syntax.Visitor for TrLint with fn visit_expression(self, node) {
  if node
    is Expression(
      {
        value: Application(
          [{ value: FunctionOrValue(["Debug"], "log"), .. }, ..]
        ),
        range,
      }
    ) {
    self.problems.push("\{tr_range(range)} remove the Debug.log call")
  }
  Continue
}

///|
impl @syntax.Visitor for TrLint with fn visit_function(self, node) {
  // A top-level function is a Declaration node; a let function is a
  // LetDeclaration node.
  if node is Declaration({ value: FunctionDeclaration(f), .. }, _) &&
    f.signature is None {
    let name = f.declaration.value.name
    self.problems.push(
      "\{tr_range(name.range)} add a type signature to \{name.value}",
    )
  }
  Continue
}

///|
test "the lint rule reports Debug.log and missing signatures" {
  let lint = TrLint::{ problems: [], }
  @syntax.accept(tr_root(tr_source), lint)
  debug_inspect(
    lint.problems,
    content=(
      #|[
      #|  "16:1-16:5 add a type signature to view",
      #|  "17:5-17:60 remove the Debug.log call",
      #|]
    ),
  )
}
```

## Print an outline with an `EventReader`

Use an `EventReader` when your code drives the loop. Each call to `next()`
returns the next event: `Enter`, `Leave`, or `None` at the end. This suits
streaming output, because you can write each line as the event comes.

An `EnterEvent` has only what a streaming parser knows when a node starts:
`category`, `kind`, `field` (the role in the parent), `start`, `depth` and
`path`. It has no end position. So decide what to skip by category or kind.
This outline skips the children of imports, signatures and type aliases:

```mbt check
///|
fn tr_outline(root : @syntax.NodeRef, max_depth : Int) -> String {
  let lines = []
  let reader = @syntax.EventReader::new(root)
  while reader.next() is Some(event) {
    guard event is Enter(e) else { continue }
    let indent = "  ".repeat(e.depth)
    let field = e.field.map(f => " (\{f})").unwrap_or("")
    lines.push("\{indent}\{e.category}/\{e.kind}\{field} @\{tr_loc(e.start)}")
    let large = e.category is ("import" | "signature") || e.kind == "typeAlias"
    if large || e.depth >= max_depth {
      reader.skip_children()
    }
  }
  lines.join("\n")
}

///|
test "an EventReader prints an outline" {
  inspect(
    tr_outline(tr_root(tr_source), 2),
    content=(
      #|file/file @1:1
      #|  module/normal (moduleDefinition) @1:1
      #|    module_name/module_name (moduleName) @1:8
      #|    exposing/explicit (exposingList) @1:13
      #|  import/import (imports) @3:1
      #|  import/import (imports) @4:1
      #|  declaration/typeAlias (declarations) @7:1
      #|  declaration/function (declarations) @11:1
      #|    signature/signature (signature) @11:1
      #|    implementation/implementation (declaration) @12:1
      #|  declaration/function (declarations) @16:1
      #|    implementation/implementation (declaration) @16:1
      #|  declaration/function (declarations) @20:1
      #|    signature/signature (signature) @20:1
      #|    implementation/implementation (declaration) @21:1
    ),
  )
}
```

Every event carries a `NodePath`: the steps from the root, like a path into
elm-syntax's JSON. Print it, or keep it to find the node again later (see
[Build editor features](editor-features.mbt.md)):

```mbt check
///|
test "events carry the path from the root" {
  let reader = @syntax.EventReader::new(tr_root(tr_source))
  let mut path = None
  while reader.next() is Some(event) {
    if event is Enter(e) && e.kind == "literal" {
      path = Some(e.path.to_string())
      break
    }
  }
  inspect(
    path.unwrap_or("none"),
    content="declarations[2].declaration[0].expression[0].application[1]",
  )
}
```

To stop early, stop calling `next()`.

## Collect names with `push_events` and a `Handler`

Use `push_events` with a `Handler` when you want a push style, but the
source of events can change. `push_events` takes any `EventSource`. Today
that is an `EventReader`. A future streaming parser can also be an
`EventSource`, and your handler stays the same.

A `LeaveEvent` carries the finished `node`, so read values from the node in
`on_leave`. This handler collects the imported module names and the names
that the module exposes. The path tells where an expose belongs: under
`moduleDefinition` or under an import. The handler skips the declarations,
because they hold no imports or exposes.

```mbt check
///|
struct TrNames {
  imported : Array[String]
  exposed : Array[String]
}

///|
impl @syntax.Handler for TrNames with fn on_enter(_, e) {
  if e.category == "declaration" {
    SkipChildren
  } else {
    Continue
  }
}

///|
impl @syntax.Handler for TrNames with fn on_leave(self, e) {
  match e.node {
    Import({ value: { module_name, .. }, .. }) =>
      self.imported.push(module_name.value.to_owned().join("."))
    Expose({ value: expose, .. }) => {
      let in_module = e.path.steps()[0].field == "moduleDefinition"
      if in_module {
        self.exposed.push(
          match expose {
            InfixExpose(name)
            | FunctionExpose(name)
            | TypeOrAliasExpose(name) => name
            TypeExpose({ name, .. }) => name
          },
        )
      }
    }
    _ => ()
  }
}

///|
test "a handler collects imports and exposed names" {
  let names = TrNames::{ imported: [], exposed: [], }
  @syntax.push_events(@syntax.EventReader::new(tr_root(tr_source)), names)
  debug_inspect(
    names.imported,
    content=(
      #|["Dict", "Html"]
    ),
  )
  debug_inspect(
    names.exposed,
    content=(
      #|["Item", "total", "view"]
    ),
  )
}
```

## All styles give the same sequence

With the same `Control` decisions, `walk`, `fold`, `accept`, an
`EventReader` and `push_events` give the same enter and leave sequence. With
`Continue` at every node, the enters follow `children()` in pre-order. So you
can change the style later and keep the result.

This test records the sequence with `walk` and with an `EventReader`, both
skipping signatures, and compares them:

```mbt check
///|
fn tr_walk_trace(root : @syntax.NodeRef) -> Array[String] {
  let trace = []
  @syntax.walk(
    root,
    node => {
      trace.push("+\{node.category()}/\{node.kind()}")
      if node.category() == "signature" {
        SkipChildren
      } else {
        Continue
      }
    },
    leave=node => trace.push("-\{node.category()}/\{node.kind()}"),
  )
  trace
}

///|
fn tr_reader_trace(root : @syntax.NodeRef) -> Array[String] {
  let trace = []
  let reader = @syntax.EventReader::new(root)
  while reader.next() is Some(event) {
    match event {
      Enter(e) => {
        trace.push("+\{e.category}/\{e.kind}")
        if e.category == "signature" {
          reader.skip_children()
        }
      }
      Leave(e) => trace.push("-\{e.node.category()}/\{e.node.kind()}")
    }
  }
  trace
}

///|
test "walk and an EventReader give the same sequence" {
  let root = tr_root(tr_source)
  let walked = tr_walk_trace(root)
  @expect.expect(tr_reader_trace(root)).to_equal(walked)
  inspect(walked.length(), content="132")
}
```

## See also

- [Build editor features](editor-features.mbt.md): `Tree`, `TreeCursor`,
  `NodePath` and `tokens_in`.
- API: `@syntax.walk`, `@syntax.fold`, `@syntax.accept`, `@syntax.Visitor`,
  `@syntax.EventReader`, `@syntax.push_events`, `@syntax.Handler`,
  `@syntax.EventSource`, `@syntax.TreeCursor`, `@syntax.Control`,
  `@syntax.NodePath`.
- [AGENTS.md](../../AGENTS.md), sections "Syntax Tree" and "Traversal": the
  node model and the rules that every traversal style follows.
