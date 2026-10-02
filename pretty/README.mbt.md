# moonrockz/pretty

A Wadler-style pretty printer for MoonBit. Build a document from text,
line breaks and groups; `render` lays it out to fit a line width.

```moonbit
let items = [@pretty.text("a"), @pretty.text("b"), @pretty.text("c")]
let doc = @pretty.group(
  @pretty.text("[") +
  @pretty.nest(2, @pretty.line() + @pretty.join(items, @pretty.text(",") + @pretty.line())) +
  @pretty.line() +
  @pretty.text("]"),
)
@pretty.render(doc) // "[ a, b, c ]"
@pretty.render(doc, width=6) // "[\n  a,\n  b,\n  c\n]"
```

| Function | Flat | Broken |
|---|---|---|
| `text(s)` | `s` | `s` |
| `verbatim(s)` | `s` | `s`, no indentation after its line feeds |
| `line()` | a space | a line break |
| `softline()` | nothing | a line break |
| `hardline()` | always a line break | |
| `nest(n, d)` | `d` | `d`, indented by `n` more |
| `align(d)` | `d` | `d`, indented to its start column |
| `group(d)` | flat if it fits | else broken |
| `if_break(b, f)` | `f` | `b` |

- A group is flat when it fits together with the rest of its line, up to
  the next possible break (the fit rule of Wadler's "A prettier printer").
- Evaluation is strict (Lindig, "Strictly Pretty") and uses explicit
  stacks, so deep documents render on wasm, wasm-gc, js and native.
- The engine writes no trailing whitespace and no indentation on empty
  lines. Width counts code points.
