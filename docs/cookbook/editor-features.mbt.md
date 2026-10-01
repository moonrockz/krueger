# Build editor features

An editor asks questions about positions: what is under the cursor, where is
it in the tree, which function holds it, what comes next. This article
answers these questions with `Tree` and `TreeCursor`. It also shows how to
keep a stable pointer to a node with `NodePath`, and how to get the exact
tokens and comments of a node with `tokens_in`.

## Positions

A position is an `@ast.Location` with a `row` and a `column`. Both start at
1. Columns count code points, as elm-syntax does. A range (`@ast.Range`) has
a `start` and an `end`. The `end` is the position after the last character,
so a range contains `p` when `start <= p < end`.

## The module for the examples

```mbt check
///|
let ef_source : String =
  #|module Editor exposing (..)
  #|
  #|import Html exposing (text)
  #|
  #|
  #|{-| Greet a person. -}
  #|greet : String -> String
  #|greet name =
  #|    -- build the greeting
  #|    "Hello, " ++ name
  #|
  #|
  #|main =
  #|    text (greet "World")
  #|

///|
/// The tree of `text`. Fails on any diagnostic.
fn ef_tree(text : String) -> @syntax.Tree raise {
  let result = @krueger.parse_module(@krueger.SourceText::new(text))
  guard result.diagnostics.is_empty() else {
    fail("unexpected diagnostics: \{result.diagnostics.length()}")
  }
  guard @syntax.Tree::new(result) is Some(tree) else { fail("no AST") }
  tree
}

///|
fn ef_at(row : Int, column : Int) -> @ast.Location {
  { row, column, }
}

///|
/// Whether `a` comes before `b` or is equal to it.
fn ef_at_or_before(a : @ast.Location, b : @ast.Location) -> Bool {
  a.row < b.row || (a.row == b.row && a.column <= b.column)
}

///|
/// Whether `r` contains `p` (`start <= p < end`).
fn ef_contains(r : @ast.Range, p : @ast.Location) -> Bool {
  ef_at_or_before(r.start, p) && !ef_at_or_before(r.end, p)
}

///|
/// `category/kind row:column-row:column` of a node.
fn ef_label(n : @syntax.NodeRef) -> String {
  let r = n.range()
  "\{n.category()}/\{n.kind()} \{r.start.row}:\{r.start.column}-\{r.end.row}:\{r.end.column}"
}
```

`Tree::new` builds a parent index once. It returns `None` when the parse
gave no AST (for example, with no module header). Build the tree again after
each edit.

## Find the node under the cursor

`Tree::node_at(location)` returns the innermost node that contains the
location. It returns `None` outside the file.

```mbt check
///|
test "node_at finds the node under the cursor" {
  let tree = ef_tree(ef_source)
  // The cursor is on `name` in `"Hello, " ++ name`.
  debug_inspect(
    tree.node_at(ef_at(10, 19)).map(ef_label),
    content=(
      #|Some("expression/functionOrValue 10:18-10:22")
    ),
  )
  // On `++`, the innermost node is the whole operator application.
  debug_inspect(
    tree.node_at(ef_at(10, 15)).map(ef_label),
    content=(
      #|Some("expression/operatorapplication 10:5-10:22")
    ),
  )
  // After the end of the file there is no node.
  debug_inspect(tree.node_at(ef_at(99, 1)).map(ef_label), content="None")
}
```

## Show breadcrumbs

`Tree::path(node)` returns the nodes from the root down to the node, both
included. `Tree::ancestors(node)` returns the parents, nearest first, up to
the root. Use the path for breadcrumbs. Use `Tree::field_of` to name the
role of each step: it reads the tree's index, so it does not look through
the parent's fields.

```mbt check
///|
fn ef_breadcrumbs(tree : @syntax.Tree, node : @syntax.NodeRef) -> String {
  tree
  .path(node)
  .map(n => {
    // The root has no field.
    let role = tree.field_of(n).unwrap_or("file")
    "\{role}:\{n.kind()}"
  })
  .join(" > ")
}

///|
test "breadcrumbs from the root to the node under the cursor" {
  let tree = ef_tree(ef_source)
  guard tree.node_at(ef_at(10, 19)) is Some(node) else { fail("no node") }
  inspect(
    ef_breadcrumbs(tree, node),
    content="file:file > declarations:function > declaration:implementation > expression:operatorapplication > right:functionOrValue",
  )
  // The nearest ancestor is the parent.
  debug_inspect(
    tree.ancestors(node).map(n => n.kind()),
    content=(
      #|["operatorapplication", "implementation", "function", "file"]
    ),
  )
}
```

## Find the top-level function at a position

To find the function that holds a position, look at the `declarations` of
the file. Do not use the ancestors of `node_at` for this: comments are
children of the file, so a position inside a comment has only the file as an
ancestor.

```mbt check
///|
/// The name of the top-level function whose range contains `p`.
fn ef_function_at(tree : @syntax.Tree, p : @ast.Location) -> String? {
  for decl in tree.root().field("declarations") {
    if decl is Declaration({ value: FunctionDeclaration(f), range, }, _) &&
      ef_contains(range, p) {
      return Some(f.declaration.value.name.value)
    }
  }
  None
}

///|
test "the top-level function at a position" {
  let tree = ef_tree(ef_source)
  // Inside the comment `-- build the greeting`.
  let p = ef_at(9, 10)
  debug_inspect(
    tree.node_at(p).map(ef_label),
    content=(
      #|Some("comment/comment 9:5-9:26")
    ),
  )
  debug_inspect(
    tree.ancestors(tree.node_at(p).unwrap()).map(n => n.kind()),
    content=(
      #|["file"]
    ),
  )
  debug_inspect(ef_function_at(tree, p), content="Some(\"greet\")")
  // A function's range starts at its doc comment.
  debug_inspect(ef_function_at(tree, ef_at(6, 3)), content="Some(\"greet\")")
  debug_inspect(ef_function_at(tree, ef_at(14, 11)), content="Some(\"main\")")
  debug_inspect(ef_function_at(tree, ef_at(3, 1)), content="None")
}
```

## Move with a `TreeCursor`

A `TreeCursor` keeps a current node and moves on your command, like the
cursor of tree-sitter. Each `goto_*` method returns `true` when it moves.
It returns `false` and stays in place when there is nowhere to go.
`field_name()` gives the role of the current node in its parent.

```mbt check
///|
test "a cursor moves to children and siblings" {
  let tree = ef_tree(ef_source)
  let c = @syntax.TreeCursor::new(tree.root())
  let steps = []
  steps.push(c.goto_first_child()) // the module header
  steps.push(c.goto_next_sibling()) // the import
  steps.push(c.goto_next_sibling()) // the first declaration
  debug_inspect(steps, content="[true, true, true]")
  debug_inspect(c.field_name(), content="Some(\"declarations\")")
  inspect(ef_label(c.node()), content="declaration/function 6:1-10:22")
  inspect(c.depth(), content="1")
  // The cursor cannot go above the node it started at.
  debug_inspect(c.goto_parent(), content="true")
  debug_inspect(c.goto_parent(), content="false")
  debug_inspect(c.field_name(), content="None")
}
```

### Put the cursor at a position

`goto_first_child_for(location)` moves to the innermost child that contains
the location, or else to the first child after it. To reach the node of
`node_at`, descend while the new node contains the location. When a new node
does not contain it, step back with `goto_parent` and stop. A plain loop of
`goto_first_child_for` goes one node too far when that node has children
after the location.

```mbt check
///|
/// A cursor at the innermost node that contains `p`.
fn ef_cursor_at(
  root : @syntax.NodeRef,
  p : @ast.Location,
) -> @syntax.TreeCursor {
  let c = @syntax.TreeCursor::new(root)
  while c.goto_first_child_for(p) {
    if !ef_contains(c.node().range(), p) {
      ignore(c.goto_parent())
      break
    }
  }
  c
}

///|
test "the cursor recipe reaches the node of node_at" {
  @expect.expect_all(s => {
    let tree = ef_tree(ef_source)
    for
      p in [
        ef_at(1, 1),
        ef_at(3, 9),
        ef_at(8, 7),
        ef_at(9, 10),
        ef_at(10, 19),
        ef_at(14, 12),
      ] {
      let c = ef_cursor_at(tree.root(), p)
      s.expect(Some(c.node())).to_equal(tree.node_at(p))
    }
  })
}
```

### Go to the parent and to the next declaration

With the cursor at a position, the editor commands "select parent" and
"go to next declaration" are a few moves:

```mbt check
///|
/// Moves `c` up to the top-level declaration that holds it.
fn ef_up_to_declaration(c : @syntax.TreeCursor) -> Bool {
  while c.field_name() != Some("declarations") {
    if !c.goto_parent() {
      return false
    }
  }
  true
}

///|
/// Moves `c` to the next sibling that is a top-level declaration. The
/// children of the file include all comments, in source order, so a
/// comment (also one inside a declaration) can come between two
/// declarations. When there is no next declaration, `c` stays in place.
fn ef_next_declaration(c : @syntax.TreeCursor) -> Bool {
  // Look ahead with a copy, so that `c` moves only on success.
  let probe = c.copy()
  let mut steps = 0
  while probe.goto_next_sibling() {
    steps += 1
    if probe.field_name() == Some("declarations") {
      for _ in 0..<steps {
        ignore(c.goto_next_sibling())
      }
      return true
    }
  }
  false
}

///|
test "select the parent and go to the next declaration" {
  let tree = ef_tree(ef_source)
  let c = ef_cursor_at(tree.root(), ef_at(10, 19))
  inspect(ef_label(c.node()), content="expression/functionOrValue 10:18-10:22")
  // Select parent.
  ignore(c.goto_parent())
  inspect(
    ef_label(c.node()),
    content="expression/operatorapplication 10:5-10:22",
  )
  // Go to the next declaration.
  debug_inspect(ef_up_to_declaration(c), content="true")
  // The next sibling of `greet` is the comment inside it.
  let peek = c.copy()
  ignore(peek.goto_next_sibling())
  inspect(ef_label(peek.node()), content="comment/comment 9:5-9:26")
  // So skip the siblings that are not declarations.
  debug_inspect(ef_next_declaration(c), content="true")
  inspect(ef_label(c.node()), content="declaration/function 13:1-14:25")
  // There is no declaration after `main`.
  debug_inspect(ef_next_declaration(c), content="false")
  inspect(ef_label(c.node()), content="declaration/function 13:1-14:25")
}
```

## Keep a stable pointer with `NodePath`

A `NodeRef` points into one parse result. After an edit, parse again and
the old node is gone. A `NodePath` is the list of steps from the root (the
field and the index in that field), like a path into elm-syntax's JSON. Get
it with `Tree::node_path(node)` or from `TreeCursor::path()`. Print it, keep
it, and `resolve` it against the new root.

A path stays valid while the edit does not change the structure along it.
Here, a new import moves every declaration down by one row:

```mbt check
///|
test "a NodePath finds the node again after an edit" {
  let before = ef_tree(ef_source)
  guard before.node_at(ef_at(10, 19)) is Some(node) else { fail("no node") }
  guard before.node_path(node) is Some(path) else { fail("no path") }
  inspect(path, content="declarations[0].declaration[0].expression[0].right[0]")
  // The cursor gives the same path.
  inspect(
    ef_cursor_at(before.root(), ef_at(10, 19)).path() == path,
    content="true",
  )
  // Add an import and parse again.
  let after = ef_tree(
    ef_source.replace(old="import Html", new="import Dict\nimport Html"),
  )
  debug_inspect(
    path.resolve(after.root()).map(ef_label),
    content=(
      #|Some("expression/functionOrValue 11:18-11:22")
    ),
  )
  // A path that leads nowhere resolves to None.
  let gone = @syntax.NodePath::root().child("declarations", 5)
  debug_inspect(gone.resolve(after.root()).map(ef_label), content="None")
}
```

## Get the tokens and comments of a node

`Tree::tokens_in(range)` returns the tokens that lie inside the range, in
source order. A token that lies only partly inside is left out. Each token
has its `lexeme` and its trivia: the whitespace, line breaks and comments
before it (`trivia_before`) and after it (`trivia_after`). The tokens are
copies, so changing them does not change the tree.

This example lists the tokens of `greet`, and the comments inside its
range, with their kinds:

```mbt check
///|
/// The comments in the trivia of `tokens` that start inside `r`.
fn ef_comments_in(
  tokens : Array[@scanner.Token],
  r : @ast.Range,
) -> Array[String] {
  let found = []
  for t in tokens {
    for trivia in [..t.trivia_before, ..t.trivia_after] {
      if trivia is Comment(c) &&
        ef_contains(r, { row: c.span.start.line, column: c.span.start.column, }) {
        let kind = match c.kind {
          Line => "line"
          Block => "block"
          Doc => "doc"
        }
        found.push("\{kind}: \{c.text}")
      }
    }
  }
  found
}

///|
test "the tokens and comments of a function" {
  let tree = ef_tree(ef_source)
  guard tree.root().field("declarations").get(0) is Some(greet) else {
    fail("no declaration")
  }
  let tokens = tree.tokens_in(greet.range())
  inspect(
    tokens.map(t => t.lexeme).join(" "),
    content="greet : String -> String greet name = \"Hello, \" ++ name",
  )
  debug_inspect(
    ef_comments_in(tokens, greet.range()),
    content=(
      #|["doc: {-| Greet a person. -}", "line: -- build the greeting"]
    ),
  )
}
```

A doc comment is trivia, not a token, so the first token of `greet` is its
name, although the range of the function starts at the doc comment.

## See also

- [Choose a traversal](traversal.mbt.md): `walk`, `fold`, `accept`,
  `EventReader` and `push_events`.
- API: `@syntax.Tree` (`node_at`, `path`, `ancestors`, `parent`,
  `node_path`, `field_of`, `step`, `tokens_in`), `@syntax.TreeCursor`,
  `@syntax.NodePath`, `@scanner.Token`, `@scanner.Trivia`.
- The node model: `@syntax.NodeRef` and `@syntax.kind_table` (every
  category, kind and field).
