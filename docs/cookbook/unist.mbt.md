# Build a unist tree

[unist](https://github.com/syntax-tree/unist) is the syntax tree format of
the unified ecosystem (remark, rehype, retext). This article converts a
krueger parse into a unist tree as JSON. You get one unist node for each
krueger node, with the elm-syntax kind, the role in the parent, the source
text of each leaf and a unist `position`. JavaScript tools such as
`unist-util-visit` and `unist-util-select` can then process Elm. At the end
you read a unist position back into a krueger node.

## Choose the mapping

unist defines three node shapes:

- `Node`: `type` (a string), optional `data`, optional `position`.
- `Parent`: a node with `children`, an array of nodes.
- `Literal`: a node with `value`.

A `Position` has `start` and `end` points. A `Point` has `line` (1-based),
`column` (1-based) and an optional `offset` (0-based). The end point is the
place after the last character.

krueger's node model (`@krueger.NodeRef`) has a category and a kind for
each node. `@krueger.kind_table()` lists every category, kind and field. elm-syntax uses the same kind in more than
one category (`record` is an expression, a pattern and a type), so a kind
alone does not identify a node type. This article uses this mapping:

| unist field | Value |
|---|---|
| `type` | `root` for the file node; else the krueger category: `expression`, `pattern`, `declaration`, `comment`, … |
| `kind` | the krueger kind: `application`, `record`, `functionOrValue`, … |
| `field` | the role of the node in its parent (`left`, `arguments`, …); not on the root |
| `children` | the child nodes, in source order (a node with children is a `Parent`) |
| `value` | the source text of the node (a node with no children is a `Literal`) |
| `position` | `start` and `end`, with `line`, `column` and `offset` |

The file node has the type `root`, as the root of a tree has in the unist
families (mdast, hast, xast). Its `kind` stays `file`. `type` and `kind`
together identify a node type, as `(category, kind)` does in krueger. A unist specification can add its own fields to a node, so
`kind` and `field` are node fields. The `data` field belongs to the tools
that use the tree, so the converter does not write it.

Values that are not nodes in krueger (an operator symbol, the name of a
`typed` type, a name qualifier) are not in the tree. Read them from the
source text with the `offset` of the node.

## Count columns in UTF-16 units

krueger and unist both count lines from 1. For text with LF or CRLF line
ends, the lines agree with unist tools. krueger does not end a line at a
lone CR, but some unist tools do, so a lone CR gives different lines.
Columns are different:

- krueger counts columns in code points. A surrogate pair, such as `😀`, is
  one column.
- JavaScript strings are UTF-16. unist tools that compute positions from a
  JavaScript string (`vfile-location`, the remark parsers) count columns and
  offsets in UTF-16 code units.

This article writes `column` and `offset` in UTF-16 code units, so the tree
agrees with those tools. `offset` is the index into the JavaScript string of
the whole source. `column` is the offset from the start of the line, plus
one. After a surrogate pair on the same line, the unist column is one more
than the krueger column.

MoonBit strings are also UTF-16, so the conversion needs only the start
offset of each line. Then walk the code points of the line, one krueger
column at a time:

```mbt check
///|
/// The UTF-16 offset where each line starts. Only LF ends a line.
fn un_line_starts(text : String) -> Array[Int] {
  let starts = [0]
  for i in 0..<text.length() {
    if text.code_unit_at(i) is '\n' {
      starts.push(i + 1)
    }
  }
  starts
}

///|
/// True when a surrogate pair (one code point, two units) starts at `i`.
fn un_is_pair(text : String, i : Int) -> Bool {
  i + 1 < text.length() &&
  text.code_unit_at(i).to_int() is (0xD800..=0xDBFF) &&
  text.code_unit_at(i + 1).to_int() is (0xDC00..=0xDFFF)
}

///|
/// A unist point. `column` and `offset` count UTF-16 units.
struct UnPoint {
  line : Int
  column : Int
  offset : Int
} derive(Debug)

///|
fn UnPoint::json(self : UnPoint) -> Json {
  { "line": self.line, "column": self.column, "offset": self.offset }
}

///|
/// Converts a krueger location (code-point column) to a unist point.
fn un_point(
  text : String,
  starts : Array[Int],
  location : @krueger.Location,
) -> UnPoint {
  let line_start = starts[location.row - 1]
  let mut offset = line_start
  for _ in 1..<location.column {
    guard offset < text.length() else { break }
    offset += if un_is_pair(text, offset) { 2 } else { 1 }
  }
  { line: location.row, column: offset - line_start + 1, offset, }
}

///|
test "a column after a surrogate pair" {
  let text = "x = \"😀\" ++ y\n"
  let starts = un_line_starts(text)
  // `y` is in krueger column 12: the emoji is one column.
  debug_inspect(
    un_point(text, starts, { row: 1, column: 12, }),
    content="{ line: 1, column: 13, offset: 12 }",
  )
}
```

A lone surrogate is one code point in krueger and one unit in UTF-16, so
`un_is_pair` moves one unit for it.

## Build the tree with a stack

`@krueger.walk` visits the nodes in pre-order and calls `leave` after the
children of a node. The converter keeps one frame for each open node on a
stack:

- `enter` pushes a frame with the node, its field in the parent and an empty
  list of children.
- `leave` pops the frame, makes the unist node and adds it to the children of
  the frame below. The last frame popped is the root.

The parent's frame is on top of the stack when a node is entered, so
`field_of` on the parent gives the field.

```mbt check
///|
priv struct UnFrame {
  node : @krueger.NodeRef
  field : String?
  children : Array[Json]
}

///|
/// Makes the unist node for a finished frame.
fn un_node(text : String, starts : Array[Int], frame : UnFrame) -> Json {
  let node = frame.node
  let range = node.range()
  let start = un_point(text, starts, range.start)
  let end = un_point(text, starts, range.end)
  // unist families (mdast, hast, xast) give the root node the type `root`.
  let type_ = if node.category() == "file" { "root" } else { node.category() }
  let object : Map[String, Json] = {
    "type": type_.to_json(),
    "kind": node.kind().to_json(),
  }
  if frame.field is Some(field) {
    object["field"] = field.to_json()
  }
  if frame.children.is_empty() {
    let value = text.view(start_offset=start.offset, end_offset=end.offset)
    object["value"] = value.to_owned().to_json()
  } else {
    object["children"] = Json::array(frame.children)
  }
  object["position"] = { "start": start.json(), "end": end.json() }
  Json::object(object)
}

///|
/// Converts the tree under `root` to a unist tree. `text` is the parsed
/// source.
fn un_tree(text : String, root : @krueger.NodeRef) -> Json {
  let starts = un_line_starts(text)
  let stack : Array[UnFrame] = []
  let mut result = Json::null()
  @krueger.walk(
    root,
    node => {
      let field = match stack.last() {
        Some(parent) => parent.node.field_of(node)
        None => None
      }
      stack.push({ node, field, children: [], })
      Continue
    },
    leave=_ => {
      guard stack.pop() is Some(frame) else { return }
      let json = un_node(text, starts, frame)
      match stack.last() {
        Some(parent) => parent.children.push(json)
        None => result = json
      }
    },
  )
  result
}
```

Do not write this converter as a recursive function. An Elm declaration can
be up to 400 levels deep (krueger reports deeper ones as `TOO MUCH
NESTING`). On wasm, a stack overflows at a few hundred frames. `walk` uses an
explicit stack, and so does `Json::stringify`, so the converter works for
every tree that krueger gives.

`field_of` looks at all the children of the parent. For a file with very
many declarations, use `@krueger.EventReader` instead: each `Enter` event
has the `field` already.

## Look at the JSON

Parse a small module and convert it. A node with no children is a
`Literal`, and its `value` is its source text:

```mbt check
///|
test "the unist tree of a small module" {
  let text = "module A exposing (..)\n\n-- hi\nx = 1\n"
  let result = @krueger.parse_module(@krueger.SourceText::new(text))
  guard @krueger.NodeRef::of_result(result) is Some(root) else {
    fail("no AST")
  }
  inspect(
    un_tree(text, root).stringify(indent=2),
    content=(
      #|{
      #|  "type": "root",
      #|  "kind": "file",
      #|  "children": [
      #|    {
      #|      "type": "module",
      #|      "kind": "normal",
      #|      "field": "moduleDefinition",
      #|      "children": [
      #|        {
      #|          "type": "module_name",
      #|          "kind": "module_name",
      #|          "field": "moduleName",
      #|          "value": "A",
      #|          "position": {
      #|            "start": {
      #|              "line": 1,
      #|              "column": 8,
      #|              "offset": 7
      #|            },
      #|            "end": {
      #|              "line": 1,
      #|              "column": 9,
      #|              "offset": 8
      #|            }
      #|          }
      #|        },
      #|        {
      #|          "type": "exposing",
      #|          "kind": "all",
      #|          "field": "exposingList",
      #|          "value": "exposing (..)",
      #|          "position": {
      #|            "start": {
      #|              "line": 1,
      #|              "column": 10,
      #|              "offset": 9
      #|            },
      #|            "end": {
      #|              "line": 1,
      #|              "column": 23,
      #|              "offset": 22
      #|            }
      #|          }
      #|        }
      #|      ],
      #|      "position": {
      #|        "start": {
      #|          "line": 1,
      #|          "column": 1,
      #|          "offset": 0
      #|        },
      #|        "end": {
      #|          "line": 1,
      #|          "column": 23,
      #|          "offset": 22
      #|        }
      #|      }
      #|    },
      #|    {
      #|      "type": "comment",
      #|      "kind": "comment",
      #|      "field": "comments",
      #|      "value": "-- hi",
      #|      "position": {
      #|        "start": {
      #|          "line": 3,
      #|          "column": 1,
      #|          "offset": 24
      #|        },
      #|        "end": {
      #|          "line": 3,
      #|          "column": 6,
      #|          "offset": 29
      #|        }
      #|      }
      #|    },
      #|    {
      #|      "type": "declaration",
      #|      "kind": "function",
      #|      "field": "declarations",
      #|      "children": [
      #|        {
      #|          "type": "implementation",
      #|          "kind": "implementation",
      #|          "field": "declaration",
      #|          "children": [
      #|            {
      #|              "type": "name",
      #|              "kind": "name",
      #|              "field": "name",
      #|              "value": "x",
      #|              "position": {
      #|                "start": {
      #|                  "line": 4,
      #|                  "column": 1,
      #|                  "offset": 30
      #|                },
      #|                "end": {
      #|                  "line": 4,
      #|                  "column": 2,
      #|                  "offset": 31
      #|                }
      #|              }
      #|            },
      #|            {
      #|              "type": "expression",
      #|              "kind": "integer",
      #|              "field": "expression",
      #|              "value": "1",
      #|              "position": {
      #|                "start": {
      #|                  "line": 4,
      #|                  "column": 5,
      #|                  "offset": 34
      #|                },
      #|                "end": {
      #|                  "line": 4,
      #|                  "column": 6,
      #|                  "offset": 35
      #|                }
      #|              }
      #|            }
      #|          ],
      #|          "position": {
      #|            "start": {
      #|              "line": 4,
      #|              "column": 1,
      #|              "offset": 30
      #|            },
      #|            "end": {
      #|              "line": 4,
      #|              "column": 6,
      #|              "offset": 35
      #|            }
      #|          }
      #|        }
      #|      ],
      #|      "position": {
      #|        "start": {
      #|          "line": 4,
      #|          "column": 1,
      #|          "offset": 30
      #|        },
      #|        "end": {
      #|          "line": 4,
      #|          "column": 6,
      #|          "offset": 35
      #|        }
      #|      }
      #|    }
      #|  ],
      #|  "position": {
      #|    "start": {
      #|      "line": 1,
      #|      "column": 1,
      #|      "offset": 0
      #|    },
      #|    "end": {
      #|      "line": 4,
      #|      "column": 6,
      #|      "offset": 35
      #|    }
      #|  }
      #|}
    ),
  )
}
```

Comments are children of the root node, with type `comment`. The root's
children are in source order, so the comment `-- hi` comes between the
module header and the declaration. The position of the root node is the
range that krueger gives the file: from line 1, column 1 to the end of the last
item (the module header, an import, a declaration or a comment).

The ranges are the elm-syntax ranges. For example, the range of the
exposing list starts at the keyword `exposing`. The rule "no children, so a
`Literal`" also applies to kinds that can have children: the type `String`
(kind `typed`, no arguments) and the empty record `{}` are `Literal` nodes.

## Check a non-ASCII literal

Use a string literal with an emoji to check the columns. The tree in this
test is small, so a short search function finds the nodes. It also uses a
stack, like `unist-util-select` in JavaScript does a search:

```mbt check
///|
/// The member `key` of a JSON object.
fn un_get(json : Json, key : String) -> Json? {
  if json is Object(object) {
    object.get(key)
  } else {
    None
  }
}

///|
/// The first node (in pre-order) whose `kind` is `kind`.
fn un_find(tree : Json, kind : String) -> Json? {
  let stack = [tree]
  while stack.pop() is Some(node) {
    if un_get(node, "kind") is Some(String(k)) && k == kind {
      return Some(node)
    }
    if un_get(node, "children") is Some(Array(children)) {
      for i = children.length() - 1; i >= 0; i = i - 1 {
        stack.push(children[i])
      }
    }
  }
  None
}

///|
test "positions after a surrogate pair" {
  let text = "module A exposing (..)\n\nx = \"😀\" ++ y\n"
  let result = @krueger.parse_module(@krueger.SourceText::new(text))
  guard @krueger.NodeRef::of_result(result) is Some(root) else {
    fail("no AST")
  }
  let tree = un_tree(text, root)
  guard un_find(tree, "literal") is Some(literal) &&
    un_find(tree, "functionOrValue") is Some(y) else {
    fail("node not found")
  }
  inspect(
    un_get(literal, "value").unwrap().stringify(),
    content=(
      #|"\"😀\""
    ),
  )
  inspect(
    un_get(literal, "position").unwrap().stringify(),
    content=(
      #|{"start":{"line":3,"column":5,"offset":28},"end":{"line":3,"column":9,"offset":32}}
    ),
  )
  inspect(
    un_get(y, "position").unwrap().stringify(),
    content=(
      #|{"start":{"line":3,"column":13,"offset":36},"end":{"line":3,"column":14,"offset":37}}
    ),
  )
}
```

The literal `"😀"` is 3 code points and 4 UTF-16 units long, so its unist
end column is 9, not 8. krueger gives `y` column 12. The unist tree gives
column 13 and offset 36, which is `text.indexOf("y")` in JavaScript.

## Use it from JavaScript

Write the JSON (`un_tree(text, root).stringify()`) to a file. Then load it
in JavaScript and use any unist utility. This code is not tested here:

```js
import {readFile} from 'node:fs/promises'
import {visit} from 'unist-util-visit'
import {selectAll} from 'unist-util-select'

const tree = JSON.parse(await readFile('Main.elm.json', 'utf8'))

// Every comment, with its line.
visit(tree, 'comment', (node) => {
  console.log(node.position.start.line, node.value)
})

// Every variable reference, with the kind of its parent.
visit(tree, {type: 'expression', kind: 'functionOrValue'}, (node, index, parent) => {
  console.log(node.value, 'in', parent.kind, 'as', node.field)
})

// Every string literal.
const strings = selectAll('expression[kind=literal]', tree)
```

For text with LF or CRLF line ends, the lines, columns and offsets agree
with unist tools that count in UTF-16 units. A lone CR gives different
lines.

## Read a position back

A JavaScript tool gives you a unist point, for example the start of a node
it reports. To find the krueger node at that point, convert the point to a
krueger `Location` (code-point column) and call `Tree::node_at`. It gives
the innermost node that contains the location.

```mbt check
///|
/// Converts a unist point (UTF-16 column) to a krueger location.
fn un_location(
  text : String,
  starts : Array[Int],
  line : Int,
  column : Int,
) -> @krueger.Location {
  let line_start = starts[line - 1]
  let target = line_start + column - 1
  let mut offset = line_start
  let mut code_points = 0
  while offset < target && offset < text.length() {
    offset += if un_is_pair(text, offset) { 2 } else { 1 }
    code_points += 1
  }
  { row: line, column: code_points + 1, }
}

///|
test "find the krueger node at a unist point" {
  let text = "module A exposing (..)\n\nx = \"😀\" ++ y\n"
  let result = @krueger.parse_module(@krueger.SourceText::new(text))
  guard @krueger.Tree::new(result) is Some(tree) else { fail("no AST") }
  // The unist start of `y`, as a JavaScript tool reports it.
  let location = un_location(text, un_line_starts(text), 3, 13)
  debug_inspect(
    location,
    content=(
      #|{ row: 3, column: 12 }
    ),
  )
  guard tree.node_at(location) is Some(node) else { fail("no node") }
  inspect(
    node.kind(),
    content=(
      #|functionOrValue
    ),
  )
  debug_inspect(
    node.range(),
    content=(
      #|{ start: { row: 3, column: 12 }, end: { row: 3, column: 13 } }
    ),
  )
}
```

When you have only the `offset`, find the last line start at or before it
in `un_line_starts`. Its index plus one is the line, and `offset - start + 1`
is the unist column. Then call `un_location`.

## Complete code

The complete converter is `un_line_starts`, `un_is_pair`, `UnPoint`,
`un_point`, `UnFrame`, `un_node` and `un_tree` above. It needs the root
package `moonrockz/krueger`; the JSON type is in `moonbitlang/core`.

## See also

- [Parse your first Elm module](getting-started.mbt.md)
- API: `@krueger.NodeRef`, `@krueger.kind_table`, `@krueger.walk`,
  `@krueger.EventReader`, `@krueger.Tree::node_at`
- [unist](https://github.com/syntax-tree/unist),
  [unist-util-visit](https://github.com/syntax-tree/unist-util-visit),
  [unist-util-select](https://github.com/syntax-tree/unist-util-select),
  [vfile-location](https://github.com/vfile/vfile-location)
