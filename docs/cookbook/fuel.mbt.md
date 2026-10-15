# Set the nesting budget

This article shows what the parser's fuel bounds, how to read a `TOO MUCH
NESTING` refusal, how to give the parser more fuel, and what the host must
do with its stack when you do.

## What fuel bounds

The parser is a recursive-descent parser: each nested construct (a
parenthesis, a list, a record, a lambda, a `let`, a `case`, a type or
pattern in parentheses) is one more call on the stack. On wasm and js the
stack holds a few hundred such calls. So the parser keeps a budget, the
fuel, as the Scala compiler keeps `-Xmax-fuel`: a walk spends units when it
enters a nested construct and gets them back when it leaves. When the budget
would be exceeded, the declaration is refused with `TOO MUCH NESTING`
(`KR-PARSE-010`) instead of a stack overflow.

The default is `DEFAULT_FUEL`, 1200. With it the parser accepts 150 nesting
levels: a declaration body and 149 nested parentheses, lists, records,
lambdas, `let`s or `case`s, or 74 nested constructor patterns or type
applications (they count two levels each); and 596 steps of a `::`, `->` or
right-associative operator chain. A
left-associative operator chain (`a + b + c + ...`) and a record access chain
(`r.a.b.c...`) are loops in the parser and have no limit.

Only the parser spends fuel. The AST encoder, the printer, the formatter and
the syntax tree walks use explicit stacks and print or encode a tree of any
depth.

```mbt check
///|
fn fu_parens(depth : Int32) -> @krueger.SourceText {
  @krueger.SourceText::new(
    "module M exposing (..)\n\n\nf =\n    " +
    "(".repeat(depth) +
    "1" +
    ")".repeat(depth) +
    "\n",
  )
}

///|
test "the default fuel accepts 149 nested parentheses and refuses 150" {
  inspect(@krueger.DEFAULT_FUEL, content="1200")
  let ok = @krueger.parse_module(fu_parens(149))
  inspect(ok.diagnostics.length(), content="0")
  let refused = @krueger.parse_module(fu_parens(150))
  debug_inspect(
    refused.diagnostics.map(d => d.code),
    content="[\"KR-PARSE-010\"]",
  )
  inspect(refused.diagnostics[0].title, content="TOO MUCH NESTING")
}
```

## Read the refusal

A `KR-PARSE-010` diagnostic carries its cause as data in `detail`: the fuel
the parser had and the walk that spent the last of it, `Nesting`
(expressions, types and patterns) or `Chain` (a `::`, `->` or
right-associative operator chain). A tool that maps krueger's diagnostics
to its own codes reads `detail`; it does not parse the message. The report
names the fuel and says how to raise it.

```mbt check
///|
test "the detail says which walk ran out and at what fuel" {
  let refused = @krueger.parse_module(fu_parens(150))
  let d = refused.diagnostics[0]
  match d.detail {
    Some(OutOfFuel(fuel~, walk~)) => {
      inspect(fuel, content="1200")
      debug_inspect(walk, content="Nesting")
    }
    _ => fail("expected OutOfFuel")
  }
  let text = @krueger.render_plain(d, fu_parens(150), "src/M.elm")
  inspect(text.contains("I ran out of fuel at 1200."), content="true")
}

///|
test "a chain that runs out reports Chain" {
  let source = @krueger.SourceText::new(
    "module M exposing (..)\n\n\nf =\n    " + "1 :: ".repeat(600) + "[]\n",
  )
  let refused = @krueger.parse_module(source)
  debug_inspect(
    refused.diagnostics.map(d => d.detail),
    content="[Some(OutOfFuel(fuel=1200, walk=Chain))]",
  )
}
```

The parser gives every other diagnostic `detail: None`.

## Give the parser more fuel

Pass `fuel~` to `parse_module`, `parse_tokens`, `format` or `format_parsed`
(`format` parses, and both format the Elm code in doc comments, which
parses again). Less fuel refuses sooner; fuel at or below zero refuses the
first expression.

```mbt check
///|
test "more fuel accepts deeper input, less fuel refuses sooner" {
  let deep = @krueger.parse_module(fu_parens(200), fuel=1700)
  inspect(deep.diagnostics.length(), content="0")
  let shallow = @krueger.parse_module(fu_parens(100), fuel=800)
  debug_inspect(
    shallow.diagnostics.map(d => d.detail),
    content="[Some(OutOfFuel(fuel=800, walk=Nesting))]",
  )
  let formatted = try {
    ignore(@krueger.format(fu_parens(20).text, fuel=100))
    "formatted"
  } catch {
    ParseFailed(diags) => diags[0].code
    Unprintable(_) => "unprintable"
  }
  inspect(formatted, content="KR-PARSE-010")
}
```

## Give the host more stack

Fuel does not make the parser stack-safe: it only stops it before the
default stack of each target runs out. More fuel needs more stack, and the
stack is the host's setting, not krueger's. A MoonBit library cannot set
it.

| Target | Where the stack is set | Example |
|---|---|---|
| native | the thread that calls krueger: the main thread's limit, or a thread created with a larger stack | `ulimit -s 65532` before the program starts |
| js (Node) | the V8 flag, up to the OS thread's stack | `node --stack-size=4000 main.js` |
| wasm, wasm-gc (wasmtime) | the engine's option | `wasmtime -W max-wasm-stack=8388608 main.wasm` |
| wasm, wasm-gc (browser) | not settable by a page | lower the fuel instead |

How much one unit of fuel costs in stack depends on the target and on the
code the engine runs. These numbers were measured with the checks off, each
input parsed once in a cold process, with MoonBit 0.10.15 debug builds: the
first depth that overflows the default stack.

| Input | wasm (moonrun, V8) | js (Node) | wasm-gc (moonrun, V8) | native (8 MiB) |
|---|---|---|---|---|
| nested `let` | 125 | 250 | 275 | above 800 |
| nested parentheses | 182 | 330 | 400 | above 3200 |
| `::` chain | 780 | 1200 | 1200 | above 12800 |
| `->` chain | 1250 | 1800 | 1700 | above 6400 |

Two things follow:

- On native, one MiB of stack holds about 100 nested `let`s or 1600 chain
  steps; the default fuel is far inside an 8 MiB stack.
- On wasm under V8, a cold process (the baseline tier) overflows at about
  125 nested `let`s, inside the 150 that the default fuel allows; a warm
  process (the optimizing tier) parses 150. A `::` chain overflows cold at
  about 780 steps against the 596 the fuel allows (a margin of 1.3). A wasm
  host that must parse such input in a cold process lowers the fuel to 960
  (120 levels, 476 chain steps) or raises its stack.

Raising the fuel without more stack turns a `TOO MUCH NESTING` diagnostic
into a stack overflow. Raise both.

## Compare deep ASTs through their JSON

`derive(Eq)` and `derive(Debug)` on the AST types recurse once per level,
so `==` on two very deep ASTs can overflow the stack where the parser, the
encoder and the printer do not. Compare such ASTs through their JSON text:
`@ast.encode_file` and `Json::stringify` both use explicit stacks.

```mbt check
///|
test "deep ASTs compare through their JSON" {
  let source = @krueger.SourceText::new(
    "module M exposing (..)\n\n\nf =\n    1" + " + 1".repeat(2000) + "\n",
  )
  let a = @krueger.parse_module(source)
  let b = @krueger.parse_module(source)
  guard a.ast is Some(fa) && b.ast is Some(fb) else { fail("no AST") }
  let ja = @ast.encode_file(fa).stringify()
  let jb = @ast.encode_file(fb).stringify()
  inspect(ja == jb, content="true")
}
```
