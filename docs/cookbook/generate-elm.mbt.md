# Generate Elm code

This article shows how to build an Elm AST in MoonBit and print it as Elm
source. The printer uses the elm-format layout. Declaration bodies, custom
types, `if`, `case` and `let` are always on several lines. Lists, records,
applications and operator chains stay on one line when they fit in the line
width (120 by default).

## Build an AST

The printer ignores ranges. A generator can use one empty range for every
node.

```mbt check
///|
let ge_r : @krueger.Range = {
  start: { row: 0, column: 0, },
  end: { row: 0, column: 0, },
}

///|
fn[T] ge_n(value : T) -> @krueger.Node[T] {
  { range: ge_r, value, }
}

///|
fn ge_v(name : String) -> @krueger.Node[@krueger.Expression] {
  ge_n(@krueger.Expression::FunctionOrValue([], name))
}

///|
test "print a generated function" {
  let sum : @krueger.Node[@krueger.Expression] = ge_n(
    OperatorApplication("+", Left, ge_v("a"), ge_v("b")),
  )
  let body : @krueger.Node[@krueger.Expression] = ge_n(
    OperatorApplication("*", Left, sum, ge_v("c")),
  )
  let f : @krueger.Function = {
    documentation: Some(ge_n("{-| Scale a sum. -}")),
    signature: None,
    declaration: ge_n({
      name: ge_n("scale"),
      arguments: [
        ge_n(@krueger.Pattern::VarPattern("a")),
        ge_n(VarPattern("b")),
        ge_n(VarPattern("c")),
      ],
      expression: body,
    }),
  }
  let file : @krueger.File = {
    module_definition: ge_n(
      NormalModule({
        module_name: ge_n(["Scale"]),
        exposing_list: ge_n(All(ge_r)),
      }),
    ),
    imports: [],
    declarations: [ge_n(@krueger.Declaration::FunctionDeclaration(f))],
    comments: [],
  }
  // The printer adds the parentheses that precedence needs.
  inspect(
    @krueger.print_file(file),
    content=(
      #|module Scale exposing (..)
      #|
      #|
      #|{-| Scale a sum. -}
      #|scale a b c =
      #|    (a + b) * c
      #|
    ),
  )
}
```

## Print a parsed module

`print_file` also takes the AST that `parse_module` returns. The output has
the elm-format layout. A module with no regular comments, in the layout that
the printer chooses, prints back unchanged. The printer does not print
regular comments yet, and elm-format keeps some layouts that the printer
changes (for example, a list that fits on one line but is written on
several lines).

```mbt check
///|
test "print a parsed module" {
  let text = "module Main exposing (main)\n\n\nmain =\n    1 + 2\n"
  let result = @krueger.parse_module(@krueger.SourceText::new(text))
  guard result.ast is Some(file) else { fail("no AST") }
  inspect(@krueger.print_file(file) == text, content="true")
}
```

## Bind the tail of a list pattern

krueger and elm-syntax read `a :: b as c` as `a :: (b as c)`: `c` is the
tail. `elm make` 0.19.1 and elm-format read it as `(a :: b) as c`: `c` is
the whole list. The printer writes `UnConsPattern(a, AsPattern(b, c))` as
`a :: b as c`, so that krueger reads it back as the same AST. To bind only
the tail, use `ParenthesizedPattern`: `a :: (b as c)`.

```mbt check
///|
test "bind the tail of a list pattern" {
  let tail : @krueger.Node[@krueger.Pattern] = ge_n(
    AsPattern(ge_n(@krueger.Pattern::VarPattern("b")), ge_n("c")),
  )
  let p : @krueger.Node[@krueger.Pattern] = ge_n(
    UnConsPattern(ge_n(VarPattern("a")), ge_n(ParenthesizedPattern(tail))),
  )
  inspect(@krueger.print_pattern(p), content="a :: (b as c)")
}
```

## Handle ASTs that Elm cannot write

A name that is not valid Elm, a negative literal pattern or an empty `case`
raises `PrintError`. Its `path` leads from the node you printed to the bad
node. It uses the elm-syntax field names. Here the bad node is item 1 of
the `application` field.

```mbt check
///|
test "a bad name raises PrintError" {
  let bad = ge_n(@krueger.Expression::Application([ge_v("f"), ge_v("if")]))
  try @krueger.print_expression(bad) catch {
    PrintError(path~, problem~) => {
      debug_inspect(
        problem,
        content=(
          #|InvalidName(Lower, "if")
        ),
      )
      debug_inspect(
        path,
        content=(
          #|{ steps: [{ field: "application", index: 1 }] }
        ),
      )
    }
  } noraise {
    _ => fail("expected an error")
  }
}
```
