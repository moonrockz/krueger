# Build an AST explorer

This article shows how to turn Elm source into the data that an AST explorer
(such as [astexplorer.net](https://astexplorer.net)) needs. First you build a
JSON tree from the `@syntax` node model: one object per node, with its type,
its role in the parent, its elm-syntax range, its UTF-16 offsets into the
source and its children. Then you put the source and the tree into one HTML
page. In the page, you hover or click a tree node to mark its text in the
source, and you click in the source to select the innermost node.

## Decide the JSON shape

Each node becomes one JSON object:

| Key | Value |
|-----|-------|
| `type` | `category.kind`, for example `expression.application` |
| `field` | The role of the node in its parent (`NodeRef::field_of`). The root has no `field`. |
| `range` | The elm-syntax range `[startRow, startColumn, endRow, endColumn]`, 1-based |
| `start`, `end` | The same range as UTF-16 offsets into the source text |
| `value` | Leaf nodes only: the source text from `start` to `end` |
| `children` | The child nodes in source order (`NodeRef::children`) |

The `type` uses the category and the kind together. The kind alone is not
enough, because elm-syntax uses the same tags for different node types:
`record` is an expression, a pattern and a type, and `function` is a
top-level declaration, a `let` declaration and a type. The pair
`(category, kind)` identifies a node type. `@krueger.kind_table()` lists every
pair with its fields.

The `range` has the same shape as a range in elm-syntax's JSON, so a tool that
reads elm-syntax output reads it too.

## Convert rows and columns to offsets

A browser marks text by UTF-16 offset (`String.prototype.slice` counts UTF-16
units). krueger's rows and columns do not count UTF-16 units:

- A row ends at LF or CRLF. A lone CR does not end a row.
- A column counts code points. A surrogate pair (for example an emoji) is one
  column but two UTF-16 units. A lone surrogate is one column and one unit.

So you cannot add the column to the start of the row. Find the start of the
row, then step over the row one code point at a time. Keep the start of each
row in an array, so that each conversion reads only one row.

```mbt check
///|
/// The rows of a source text: the UTF-16 offset where each row starts.
struct AxRows {
  text : String
  starts : Array[Int]
}

///|
fn AxRows::new(text : String) -> AxRows {
  let starts = [0]
  for i in 0..<text.length() {
    // CRLF ends a row at its LF too, so this finds both line breaks.
    if text.code_unit_at(i).to_int() == '\n'.to_int() {
      starts.push(i + 1)
    }
  }
  { text, starts, }
}

///|
/// The UTF-16 offset where row `row` (0-based) ends, before its line break.
fn AxRows::row_end(self : AxRows, row : Int) -> Int {
  if row + 1 >= self.starts.length() {
    return self.text.length()
  }
  let lf = self.starts[row + 1] - 1
  let crlf = lf > self.starts[row] &&
    self.text.code_unit_at(lf - 1).to_int() == '\r'.to_int()
  if crlf {
    lf - 1
  } else {
    lf
  }
}

///|
/// The UTF-16 offset of an elm-syntax location. A location after the end of
/// its row (or of the text) gives the end of that row (or of the text).
fn AxRows::offset(self : AxRows, at : @ast.Location) -> Int {
  if at.row < 1 {
    return 0
  }
  if at.row > self.starts.length() {
    return self.text.length()
  }
  let row = at.row - 1
  let end = self.row_end(row)
  let mut i = self.starts[row]
  let mut column = 1
  while column < at.column && i < end {
    i = i + (if ax_is_pair(self.text, i, end) { 2 } else { 1 })
    column = column + 1
  }
  i
}

///|
/// Whether a surrogate pair (one code point, two UTF-16 units) starts at `i`.
fn ax_is_pair(text : String, i : Int, end : Int) -> Bool {
  let high = text.code_unit_at(i).to_int()
  i + 1 < end &&
  high >= 0xD800 &&
  high <= 0xDBFF &&
  text.code_unit_at(i + 1).to_int() >= 0xDC00 &&
  text.code_unit_at(i + 1).to_int() <= 0xDFFF
}

///|
test "a column after an emoji is one UTF-16 unit further than it looks" {
  // "😀" is one column and two UTF-16 units.
  let rows = AxRows::new("a = \"😀\"\r\nb = 1\n")
  @expect.expect_all(s => {
    // Column 7 on row 1 is the closing quote, after the emoji.
    s.expect(rows.offset({ row: 1, column: 7, })).to_equal(7)
    // Column 9 is past the end of row 1: it stops before the CRLF.
    s.expect(rows.offset({ row: 1, column: 9, })).to_equal(8)
    // Row 2 starts after the CRLF.
    s.expect(rows.offset({ row: 2, column: 1, })).to_equal(10)
  })
}
```

## Build the tree without recursion

A recursive function that calls itself for each child is the usual way to
build a nested tree. Do not use it here. A declaration can be up to 400 levels
deep (krueger reports deeper ones as `TOO MUCH NESTING`), and on wasm the
stack overflows after a few hundred frames.

Use `@syntax.walk` instead. It walks the tree with its own explicit stack and
calls `enter` before a node's children and `leave` after them. Keep your own
stack of open nodes next to it:

1. `enter` pushes a frame for the node. The frame on top of the stack before
   the push is the parent, so `parent.field_of(node)` gives the `field`.
2. `leave` pops the frame and makes the JSON object. Then it adds the object
   to the children of the new top frame. When the stack is empty, the object
   is the root.

`walk` gives `leave` the same node as `enter`, and the calls are always in
pairs, so the two stacks stay in step.

```mbt check
///|
/// A node that is open: `enter` has run, `leave` has not.
struct AxFrame {
  node : @syntax.NodeRef
  start : Int
  end : Int
  fields : Map[String, Json]
  children : Array[Json]
}

///|
fn ax_location_json(at : @ast.Location) -> Array[Json] {
  [Json::number(at.row.to_double()), Json::number(at.column.to_double())]
}

///|
/// The explorer tree of a parsed module, or `None` when the parser made no
/// AST (a module without a valid header).
fn ax_tree(text : String, result : @krueger.ParseResult) -> Json? {
  guard @syntax.NodeRef::of_result(result) is Some(root) else { return None }
  let rows = AxRows::new(text)
  let stack : Array[AxFrame] = []
  let mut tree = Json::null()
  @syntax.walk(
    root,
    node => {
      let range = node.range()
      let fields : Map[String, Json] = {
        "type": Json::string(node.category() + "." + node.kind()),
      }
      if stack.last() is Some(parent) &&
        parent.node.field_of(node) is Some(field) {
        fields["field"] = Json::string(field)
      }
      fields["range"] = Json::array(
        ax_location_json(range.start) + ax_location_json(range.end),
      )
      let start = rows.offset(range.start)
      let end = rows.offset(range.end)
      fields["start"] = Json::number(start.to_double())
      fields["end"] = Json::number(end.to_double())
      stack.push({ node, start, end, fields, children: [], })
      Continue
    },
    leave=_ => {
      guard stack.pop() is Some(frame) else { return }
      let fields = frame.fields
      if frame.children.is_empty() {
        let value = text.view(start_offset=frame.start, end_offset=frame.end)
        fields["value"] = Json::string(value.to_owned())
      }
      fields["children"] = Json::array(frame.children)
      match stack.last() {
        Some(parent) => parent.children.push(Json::object(fields))
        None => tree = Json::object(fields)
      }
    },
  )
  Some(tree)
}

///|
fn ax_tree_of(text : String) -> Json? {
  ax_tree(text, @krueger.parse_module(@krueger.SourceText::new(text)))
}
```

To read the tree in a test, print it as an outline: one line per node, with
the node's JSON object without its `children` key. The indentation shows the
nesting. The loop uses an explicit stack, as `walk` does.

```mbt check
///|
fn ax_outline(tree : Json) -> String {
  let out = StringBuilder()
  let stack = [(tree, 0)]
  while stack.pop() is Some((node, depth)) {
    guard node is Object(fields) else { continue }
    let own : Map[String, Json] = Map([])
    for key, value in fields {
      if key != "children" {
        own[key] = value
      }
    }
    out.write_string("  ".repeat(depth) + Json::object(own).stringify() + "\n")
    if fields.get("children") is Some(Array(children)) {
      for i = children.length() - 1; i >= 0; i = i - 1 {
        stack.push((children[i], depth + 1))
      }
    }
  }
  out.to_string()
}

///|
test "the explorer tree of a small module" {
  let tree = ax_tree_of("module A exposing (..)\n\nx =\n    f 1\n")
  guard tree is Some(tree) else { fail("no AST") }
  inspect(
    ax_outline(tree),
    content=(
      #|{"type":"file.file","range":[1,1,4,8],"start":0,"end":35}
      #|  {"type":"module.normal","field":"moduleDefinition","range":[1,1,1,23],"start":0,"end":22}
      #|    {"type":"module_name.module_name","field":"moduleName","range":[1,8,1,9],"start":7,"end":8,"value":"A"}
      #|    {"type":"exposing.all","field":"exposingList","range":[1,10,1,23],"start":9,"end":22,"value":"exposing (..)"}
      #|  {"type":"declaration.function","field":"declarations","range":[3,1,4,8],"start":24,"end":35}
      #|    {"type":"implementation.implementation","field":"declaration","range":[3,1,4,8],"start":24,"end":35}
      #|      {"type":"name.name","field":"name","range":[3,1,3,2],"start":24,"end":25,"value":"x"}
      #|      {"type":"expression.application","field":"expression","range":[4,5,4,8],"start":32,"end":35}
      #|        {"type":"expression.functionOrValue","field":"application","range":[4,5,4,6],"start":32,"end":33,"value":"f"}
      #|        {"type":"expression.integer","field":"application","range":[4,7,4,8],"start":34,"end":35,"value":"1"}
      #|
    ),
  )
}
```

The full JSON nests the same objects in `children` arrays. Here is the leaf
`1` with `stringify(indent=2)`:

```mbt check
///|
test "one node as JSON" {
  let tree = ax_tree_of("module A exposing (..)\n\nx =\n    f 1\n")
  guard tree is Some(tree) else { fail("no AST") }
  // file > declaration > implementation > application > integer
  let path = [1, 0, 1, 1]
  let mut node = tree
  for i in path {
    guard node is { "children": Array(children), .. } else { fail("no node") }
    node = children[i]
  }
  inspect(
    node.stringify(indent=2),
    content=(
      #|{
      #|  "type": "expression.integer",
      #|  "field": "application",
      #|  "range": [
      #|    4,
      #|    7,
      #|    4,
      #|    8
      #|  ],
      #|  "start": 34,
      #|  "end": 35,
      #|  "value": "1",
      #|  "children": []
      #|}
    ),
  )
}
```

`@syntax.EventReader` is another way to do the same work. Its `Enter` event
has the `field` already, so it does not need `field_of`, which looks through
the parent's fields each time. For most modules the difference is small.

## Check that the offsets select the right text

The `start` and `end` offsets are only useful when they slice exactly the
node's text. This test puts an emoji and a non-ASCII letter before other
nodes on the same row, collects every leaf, and compares its `value` (the
slice of the source) with the text you expect.

```mbt check
///|
/// The `value` of each leaf, in source order. It uses an explicit stack too.
fn ax_leaf_values(tree : Json) -> Array[String] {
  let values = []
  let stack = [tree]
  while stack.pop() is Some(node) {
    match node {
      { "children": Array(children), .. } if !children.is_empty() =>
        for i = children.length() - 1; i >= 0; i = i - 1 {
          stack.push(children[i])
        }
      { "value": String(value), .. } => values.push(value)
      _ => ()
    }
  }
  values
}

///|
test "offsets slice the text after an emoji" {
  let text = "module A exposing (s)\n\n\ns =\n    [ \"😀é\", \"b\" ]\n"
  guard ax_tree_of(text) is Some(tree) else { fail("no AST") }
  debug_inspect(
    ax_leaf_values(tree),
    content=(
      #|["A", "s", "s", "\"😀é\"", "\"b\""]
    ),
  )
}
```

The literal `"😀é"` is 4 columns (quotes, emoji, `é`) but 5 UTF-16 units.
If you add the column to the row start, every node after the literal on that
row starts one unit too early. The slice for `"b"` is then ` "b` (a space, a
quote and `b`).

## Escape the JSON for a script tag

The page carries the data in a `<script type="application/json">` element.
The browser reads its content as raw text until it finds `</script`. The text
`<!--` also changes how the browser looks for that end tag. Elm source can
contain both (in a string literal or a comment), so the JSON must not.

The character `<` occurs in JSON text only inside strings. So replace every
`<` with the JSON escape `\u003c`. The JSON stays valid, `JSON.parse` gives
back the same string, and the text contains no `</` and no `<!--`.

```mbt check
///|
/// JSON text that is safe inside a `<script>` element.
fn ax_script_json(json : Json) -> String {
  json.stringify().replace_all(old="<", new="\\u003c")
}

///|
test "escape the JSON for a script tag" {
  let json = Json::string("</script><!-- x")
  inspect(
    ax_script_json(json),
    content=(
      #|"\u003c/script>\u003c!-- x"
    ),
  )
  // The escaped text parses back to the same JSON.
  @expect.expect(@json.parse(ax_script_json(json))).to_equal(json)
}
```

## Make the viewer page

`ax_viewer_html` puts everything in one HTML file with inline CSS and
JavaScript. It needs no server and no network. The data object has the
source text, the tree (`null` when there is no AST) and the diagnostics with
their UTF-16 offsets (`Span.start.offset` and `Span.end.offset`).

The script:

- builds the tree pane from `<details>` elements, with a loop and its own
  stack, not recursion;
- marks a node's `start`..`end` in the source when you move the pointer over
  it, and keeps the mark when you click it;
- finds the innermost node that contains the caret (or the selected text)
  when you click in the source, then opens and selects that node. The
  offset of the caret is the length of the text from the start of the source
  pane to the caret, which is in UTF-16 units, as the tree's offsets are.

```mbt check
///|
fn ax_diagnostics_json(result : @krueger.ParseResult) -> Json {
  Json::array(
    result.diagnostics.map(d => {
      let fields : Map[String, Json] = {
        "code": Json::string(d.code),
        "title": Json::string(d.title),
        "message": Json::string(d.message),
        "start": Json::number(d.span.start.offset.to_double()),
        "end": Json::number(d.span.end.offset.to_double()),
      }
      Json::object(fields)
    }),
  )
}

///|
/// A self-contained HTML page that shows `source` and its syntax tree.
fn ax_viewer_html(source : String) -> String {
  let result = @krueger.parse_module(@krueger.SourceText::new(source))
  let data : Map[String, Json] = {
    "source": Json::string(source),
    "tree": ax_tree(source, result).unwrap_or(Json::null()),
    "diagnostics": ax_diagnostics_json(result),
  }
  ax_page_head + ax_script_json(Json::object(data)) + ax_page_tail
}

///|
let ax_page_head : String =
  #|<!doctype html>
  #|<html lang="en">
  #|<head>
  #|<meta charset="utf-8">
  #|<meta name="viewport" content="width=device-width, initial-scale=1">
  #|<title>Elm AST explorer</title>
  #|<style>
  #|:root { color-scheme: light dark; --bg: #ffffff; --fg: #1f2328;
  #|  --muted: #656d76; --line: #d0d7de; --mark: #fff1a8; --sel: #dbeafe;
  #|  --value: #0b6e4f; --error: #b42318; }
  #|@media (prefers-color-scheme: dark) {
  #|  :root { --bg: #16181d; --fg: #e6edf3; --muted: #8d96a0; --line: #30363d;
  #|    --mark: #5a4b00; --sel: #1d3557; --value: #7ee2b8; --error: #ff8a80; } }
  #|* { box-sizing: border-box; }
  #|body { margin: 0; background: var(--bg); color: var(--fg);
  #|  font: 13px/1.5 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
  #|main { display: grid; grid-template-columns: 1fr 1fr; height: 100vh; }
  #|#src, #side { margin: 0; padding: 12px 16px; overflow: auto; }
  #|#src { border-right: 1px solid var(--line); white-space: pre; }
  #|#src mark { background: var(--mark); color: inherit; }
  #|#diags { margin: 0 0 8px; padding: 0; list-style: none; color: var(--error); }
  #|#diags li { cursor: pointer; }
  #|details details { margin-left: 16px; }
  #|summary { cursor: pointer; white-space: nowrap; border-radius: 3px; }
  #|summary.leaf { list-style: none; padding-left: 13px; }
  #|summary.leaf::-webkit-details-marker { display: none; }
  #|summary.selected { background: var(--sel); }
  #|.field, .range { color: var(--muted); }
  #|.type { font-weight: 600; }
  #|.value { color: var(--value); }
  #|@media (max-width: 720px) {
  #|  main { grid-template-columns: 1fr; height: auto; }
  #|  #src { border-right: 0; border-bottom: 1px solid var(--line); } }
  #|</style>
  #|</head>
  #|<body>
  #|<main><pre id="src"></pre><div id="side"><ul id="diags"></ul><div id="tree"></div></div></main>
  #|<script id="ax-data" type="application/json">

///|
let ax_page_tail : String =
  #|</script>
  #|<script>
  #|(function () {
  #|  "use strict";
  #|  var data = JSON.parse(document.getElementById("ax-data").textContent);
  #|  var text = data.source, root = data.tree, selected = null;
  #|  var src = document.getElementById("src");
  #|  var treeEl = document.getElementById("tree");
  #|
  #|  // Draw the source and mark the text from start to end.
  #|  function mark(item, scroll) {
  #|    src.textContent = "";
  #|    if (!item) { src.textContent = text; return; }
  #|    var m = document.createElement("mark");
  #|    m.textContent = text.slice(item.start, item.end);
  #|    src.append(text.slice(0, item.start), m, text.slice(item.end));
  #|    if (scroll) m.scrollIntoView({ block: "nearest" });
  #|  }
  #|
  #|  function span(cls, s) {
  #|    var e = document.createElement("span");
  #|    e.className = cls; e.textContent = s; return e;
  #|  }
  #|
  #|  // Build the tree pane with a loop and a stack: trees can be 400 deep.
  #|  function build() {
  #|    var stack = [[root, null, treeEl, 0]];
  #|    while (stack.length) {
  #|      var top = stack.pop(), n = top[0], r = n.range;
  #|      n.parent = top[1];
  #|      var d = document.createElement("details");
  #|      var s = document.createElement("summary");
  #|      if (n.field) s.append(span("field", n.field + ": "));
  #|      s.append(span("type", n.type), " ",
  #|        span("range", "[" + r[0] + ":" + r[1] + "-" + r[2] + ":" + r[3] + "]"));
  #|      if (n.children.length === 0) {
  #|        s.className = "leaf";
  #|        var v = JSON.stringify(n.value);
  #|        s.append(" ", span("value", v.length > 60 ? v.slice(0, 57) + "..." : v));
  #|      }
  #|      s.axNode = n; n.el = d; n.summary = s;
  #|      d.open = top[3] < 3;
  #|      d.append(s); top[2].append(d);
  #|      for (var i = n.children.length - 1; i >= 0; i--) {
  #|        stack.push([n.children[i], n, d, top[3] + 1]);
  #|      }
  #|    }
  #|  }
  #|
  #|  function select(n) {
  #|    if (selected) selected.summary.classList.remove("selected");
  #|    selected = n;
  #|    n.summary.classList.add("selected");
  #|    for (var p = n.parent; p; p = p.parent) p.el.open = true;
  #|    n.summary.scrollIntoView({ block: "nearest" });
  #|    mark(n, true);
  #|  }
  #|
  #|  // The innermost node that contains the offsets a..b.
  #|  function innermost(a, b) {
  #|    var n = root, found = true;
  #|    while (found) {
  #|      found = false;
  #|      for (var i = 0; i < n.children.length; i++) {
  #|        var c = n.children[i];
  #|        if (c.start <= a && b <= c.end) { n = c; found = true; break; }
  #|      }
  #|    }
  #|    return n;
  #|  }
  #|
  #|  // The UTF-16 offset of a DOM position in the source pane.
  #|  function offsetOf(node, offset) {
  #|    var r = document.createRange();
  #|    r.selectNodeContents(src);
  #|    r.setEnd(node, offset);
  #|    return r.toString().length;
  #|  }
  #|
  #|  src.addEventListener("mouseup", function () {
  #|    var sel = window.getSelection();
  #|    if (!root || !sel.rangeCount) return;
  #|    var r = sel.getRangeAt(0);
  #|    if (!src.contains(r.startContainer)) return;
  #|    var a = offsetOf(r.startContainer, r.startOffset);
  #|    var b = offsetOf(r.endContainer, r.endOffset);
  #|    // A caret selects the character after it.
  #|    if (a === b && b < text.length) b = a + 1;
  #|    select(innermost(a, b));
  #|  });
  #|  treeEl.addEventListener("mouseover", function (e) {
  #|    var s = e.target.closest("summary");
  #|    if (s && s.axNode) mark(s.axNode, false);
  #|  });
  #|  treeEl.addEventListener("mouseleave", function () { mark(selected, false); });
  #|  treeEl.addEventListener("click", function (e) {
  #|    var s = e.target.closest("summary");
  #|    if (s && s.axNode) select(s.axNode);
  #|  });
  #|
  #|  var diags = document.getElementById("diags");
  #|  data.diagnostics.forEach(function (d) {
  #|    var li = document.createElement("li");
  #|    li.textContent = d.code + " " + d.title + ": " + d.message;
  #|    li.addEventListener("click", function () { mark(d, true); });
  #|    diags.append(li);
  #|  });
  #|  if (root) build(); else treeEl.textContent = "No AST.";
  #|  mark(null, false);
  #|})();
  #|</script>
  #|</body>
  #|</html>
  #|
```

Test the page. The source below has `</script>` and `<!--` in a comment and
in a string literal. The test takes the data out of the page, checks that it
has no `</` and no `<!--`, and parses it back.

```mbt check
///|
/// The JSON text between the page's head and tail.
fn ax_embedded_json(html : String) -> String {
  html
  .view(
    start_offset=ax_page_head.length(),
    end_offset=html.length() - ax_page_tail.length(),
  )
  .to_owned()
}

///|
test "the viewer page embeds the source and the tree safely" {
  let source =
    #|module A exposing (x)
    #|
    #|{- </script> <!-- -}
    #|
    #|
    #|x =
    #|    "</b>"
    #|
  let html = ax_viewer_html(source)
  let embedded = ax_embedded_json(html)
  let data = @json.parse(embedded)
  guard data is { "source": text, "tree": tree, "diagnostics": diagnostics, .. } else {
    fail("the data has no source, tree or diagnostics")
  }
  @expect.expect_all(s => {
    s.expect(html.has_prefix("<!doctype html>")).to_be_true()
    s.expect(embedded.contains("</")).to_be_false()
    s.expect(embedded.contains("<!--")).to_be_false()
    // The page has two script elements, so two end tags and no more.
    s.expect(html.split("</script>").count()).to_equal(3)
    s.expect(text).to_equal(Json::string(source))
    s.expect(diagnostics).to_equal(Json::array([]))
  })
  debug_inspect(
    ax_leaf_values(tree),
    content=(
      #|["A", "x", "{- </script> <!-- -}", "x", "\"</b>\""]
    ),
  )
}

///|
test "the viewer page without an AST shows the diagnostics" {
  let data = @json.parse(ax_embedded_json(ax_viewer_html("x = 1\n")))
  guard data is { "tree": tree, "diagnostics": diagnostics, .. } else {
    fail("the data has no tree or diagnostics")
  }
  @expect.expect_all(s => {
    s.expect(tree).to_equal(Json::null())
    s.expect(diagnostics.stringify()).to_contain("KR-PARSE-006")
  })
}
```

## Write the page to a file

A test cannot write files on every target. To make a page, call
`ax_viewer_html` from a `main` function on the native target and write the
result with `moonbitlang/x/fs`. Add `moonbitlang/x` to `moon.mod` and import
`"moonbitlang/x/fs"` in the `moon.pkg` of the main package. The function
reads `Main.elm` and writes `ast-explorer.html`:

```mbt nocheck
///|
fn main {
  let source = @fs.read_file_to_string("Main.elm") catch {
    e => abort("cannot read Main.elm: \{e}")
  }
  @fs.write_string_to_file("ast-explorer.html", ax_viewer_html(source)) catch {
    e => abort("cannot write ast-explorer.html: \{e}")
  }
}
```

Open `ast-explorer.html` in a browser. Move the pointer over a node in the
right pane to mark its text. Click a node to keep the mark. Click a word in
the source to select the innermost node that contains it.
[ast-explorer.example.html](ast-explorer.example.html) is a page made from a
small module.

## Complete code

The functions in this article, in the order of the data flow:

- `AxRows::new` and `AxRows::offset` convert elm-syntax locations to UTF-16
  offsets.
- `ax_tree` walks the `@syntax` tree with `@syntax.walk` and a stack of
  `AxFrame`s, and makes the JSON tree.
- `ax_script_json` writes JSON that is safe inside a `<script>` element.
- `ax_viewer_html` parses the source and puts the data between
  `ax_page_head` and `ax_page_tail`.

## See also

- [Choose a traversal](traversal.mbt.md): `walk`, `fold`, `accept`,
  `EventReader` and `TreeCursor`.
- [Build a unist tree](unist.mbt.md): another JSON tree with positions.
- [Build editor features](editor-features.mbt.md): find the node at a
  position in the editor.
- [Read and write elm-syntax JSON](elm-syntax-json.mbt.md): the AST as
  elm-syntax JSON, with `@ast.encode_file`.
- `@syntax.NodeRef`: `category`, `kind`, `range`, `children` and `field_of`.
- `@syntax.Tree::node_at`: the innermost node at a location, on the MoonBit
  side.
- `@lawkit.offset_of`: the same row and column to offset conversion, in the
  test-support package.
