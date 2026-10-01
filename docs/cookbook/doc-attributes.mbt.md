# Read doc-comment attributes

This article shows how to put structured data in Elm doc comments and read
it with krueger. You write attributes in the three forms, read them from
`ParseResult.attributes`, encode them as JSON, and switch them off. The
example adds Morphir-style metadata to a type and a function.

An attribute is a doc-comment line that starts with `@name`, followed by Elm
data in application form: literals, lists, records, tuples, names and
constructor applications. krueger reads the attributes. Their meaning
belongs to the tools that read them.

## Know the three forms

elm-format reads a doc comment as Markdown. It changes plain text: it
escapes `_`, changes `*a*` to `_a_`, doubles backslashes and wraps URLs. It
keeps code spans and code blocks byte for byte. So there are three forms:

1. An attributes block: a fenced code block with the info string
   `attributes`. krueger reads its content verbatim. An attribute runs until
   the next `@` line or a blank line. Use this form for all attributes that
   are not trivial.
2. A value in a code span: ``@morphir `{ key = "account_id" }` ``.
3. A plain value: `@unit "EUR"`. Use it only when the value has no `_`, `*`,
   `\` or URL. A plain value continues on the next lines only while brackets
   are open, or while the `@` line has no value yet.

The name is `lower ("." lower)*`, for example `morphir` or `json.field`.
`@docs a, b` is the built-in list form that Elm uses for documentation.
Prose, other code blocks and an `@` in the middle of a line are not
attributes.

This module uses all three forms:

```mbt check
///|
fn da_source() -> @krueger.SourceText {
  @krueger.SourceText::new(
    (
      #|module Bank.Account exposing (Account, balance)
      #|
      #|{-| Bank accounts.
      #|
      #|@morphir { package = "Bank" }
      #|
      #|@docs Account, balance
      #|
      #|-}
      #|
      #|
      #|{-| A customer account.
      #|
      #|```attributes
      #|@derive [ Json.encoder, Json.decoder ]
      #|@morphir
      #|    { kind = "entity"
      #|    , key = "account_id"
      #|    }
      #|```
      #|
      #|-}
      #|type alias Account =
      #|    { account_id : String, balance : Float }
      #|
      #|
      #|{-| The balance of an account.
      #|
      #|@unit "EUR"
      #|
      #|@morphir `{ kind = "measure", precision = 2 }`
      #|
      #|-}
      #|balance : Account -> Float
      #|balance account =
      #|    account.balance
      #|
    ),
  )
}

///|
test "parse the module" {
  let result = @krueger.parse_module(da_source())
  debug_inspect(result.diagnostics, content="[]")
}
```

## Read the attribute groups

`ParseResult.attributes` is an array of `AttributeGroup`. A group has a
`target` and its `attributes`:

- The target is `Module` for the module documentation. It is
  `Declaration(name~, range~)` for a declaration.
- An attribute is `Attribute(name~, arguments~, range~)`, or `Docs(names~,
  range~)` for `@docs`. Each argument is an `@ast.Node[@ast.Expression]`.

```mbt check
///|
fn da_target(group : @krueger.AttributeGroup) -> String {
  match group.target {
    Module => "module"
    Declaration(name~, ..) => name
  }
}

///|
fn da_summary(attribute : @krueger.DocAttribute) -> String {
  match attribute {
    Attribute(name~, arguments~, ..) => {
      let n = arguments.length()
      let noun = if n == 1 { "argument" } else { "arguments" }
      "@\{name.value} (\{n} \{noun})"
    }
    Docs(names~, ..) => "@docs " + names.iter().map(n => n.value).join(", ")
  }
}

///|
test "read the attribute groups" {
  let result = @krueger.parse_module(da_source())
  let lines = []
  for group in result.attributes {
    for attribute in group.attributes {
      lines.push(da_target(group) + ": " + da_summary(attribute))
    }
  }
  inspect(
    lines.join("\n"),
    content=(
      #|module: @morphir (1 argument)
      #|module: @docs Account, balance
      #|Account: @derive (1 argument)
      #|Account: @morphir (1 argument)
      #|balance: @unit (1 argument)
      #|balance: @morphir (1 argument)
    ),
  )
}
```

## Read the values

The arguments are Elm expressions. Match the `@ast.Expression` cases to read
them. This function reads the fields of a record argument, such as the
`@morphir` record:

```mbt check
///|
fn da_record_fields(
  argument : @krueger.Node[@krueger.Expression],
) -> Array[(String, String)] {
  guard argument.value is RecordExpr(setters) else { return [] }
  setters
  .iter()
  .map(setter => {
    let value = match setter.value.expression.value {
      Literal(text) => text
      Integer(n) => n.to_string()
      FunctionOrValue(_, name) => name
      other => @ast.encode_expression(other).stringify()
    }
    (setter.value.field.value, value)
  })
  .collect()
}

///|
fn da_morphir(
  result : @krueger.ParseResult,
  target : String,
) -> Array[(String, String)] {
  for group in result.attributes {
    if da_target(group) != target {
      continue
    }
    for attribute in group.attributes {
      if attribute is Attribute(name~, arguments~, ..) &&
        name.value == "morphir" &&
        arguments.length() == 1 {
        return da_record_fields(arguments[0])
      }
    }
  }
  []
}

///|
test "read the morphir records" {
  let result = @krueger.parse_module(da_source())
  debug_inspect(
    da_morphir(result, "Account"),
    content=(
      #|[("kind", "entity"), ("key", "account_id")]
    ),
  )
  debug_inspect(
    da_morphir(result, "balance"),
    content=(
      #|[("kind", "measure"), ("precision", "2")]
    ),
  )
  debug_inspect(
    da_morphir(result, "module"),
    content=(
      #|[("package", "Bank")]
    ),
  )
}
```

The range of an attribute is a range in the file, with 1-based rows and
columns:

```mbt check
///|
test "read a range" {
  let result = @krueger.parse_module(da_source())
  let first = result.attributes[1].attributes[0]
  guard first is Attribute(name~, range~, ..) else { fail("not an attribute") }
  inspect(name.value, content="derive")
  debug_inspect(
    range,
    content=(
      #|{ start: { row: 15, column: 1 }, end: { row: 15, column: 39 } }
    ),
  )
}
```

## Encode the attributes as JSON

`encode_attributes` writes the groups as JSON. Each argument is an elm-syntax
expression node, as `@ast.encode_expression` writes it. Ranges are elm-syntax
ranges: `[startRow, startColumn, endRow, endColumn]`.

```mbt check
///|
test "encode the attributes" {
  let text =
    #|module Bank exposing (balance)
    #|
    #|{-| Bank. -}
    #|
    #|
    #|{-| The balance.
    #|
    #|@unit "EUR"
    #|-}
    #|balance =
    #|    1
    #|
  let result = @krueger.parse_module(@krueger.SourceText::new(text))
  let json = @krueger.encode_attributes(result.attributes)
  inspect(
    json.stringify(),
    content=(
      #|[{"target":{"declaration":"balance","range":[6,1,11,6]},"attributes":[{"name":{"range":[8,2,8,6],"value":"unit"},"arguments":[{"range":[8,7,8,12],"value":{"type":"literal","literal":"EUR"}}],"range":[8,1,8,12]}]}]
    ),
  )
}
```

An Int argument above 2^53 is written as the nearest Double, as elm-syntax
does. Use `encode_attributes_with(groups, exact_ints=true)` to write the
exact digits. See [Read and write elm-syntax JSON](elm-syntax-json.mbt.md).

## Find malformed attributes

A malformed attribute is a warning, `KR-ATTR-001`. krueger skips it and
reads the other attributes. Here `@bad` has a lambda, which is not data:

```mbt check
///|
test "a malformed attribute is a warning" {
  let text =
    #|module Bank exposing (..)
    #|
    #|{-| Bank. -}
    #|
    #|
    #|{-| Balance.
    #|
    #|@bad (\x -> x)
    #|@ok 1
    #|-}
    #|balance =
    #|    1
    #|
  let result = @krueger.parse_module(@krueger.SourceText::new(text))
  debug_inspect(
    result.diagnostics.map(d => d.code),
    content=(
      #|["KR-ATTR-001"]
    ),
  )
  debug_inspect(result.diagnostics.map(d => d.severity), content="[Warning]")
  let names = result.attributes[0].attributes.map(da_summary)
  debug_inspect(
    names,
    content=(
      #|["@ok (1 argument)"]
    ),
  )
}
```

## Switch attributes off

`Dialect.attributes` turns attributes on (`DocComment`, the default) or off
(`Off`). With `Off`, krueger does not read attributes and gives no
`KR-ATTR-001` warnings:

```mbt check
///|
test "switch attributes off" {
  let off = { ..@krueger.Dialect::elm_0_19_1(), attributes: Off, }
  let result = @krueger.parse_module(da_source(), dialect=off)
  inspect(result.attributes.length(), content="0")
  debug_inspect(result.diagnostics, content="[]")
}
```

## Complete code

This function gives the Morphir metadata of each declaration in a module:

```mbt check
///|
fn da_morphir_metadata(
  source : @krueger.SourceText,
) -> Array[(String, Array[(String, String)])] {
  let result = @krueger.parse_module(source)
  result.attributes
  .iter()
  .filter(group => group.target is Declaration(_))
  .map(group => (da_target(group), da_morphir(result, da_target(group))))
  .filter(entry => !entry.1.is_empty())
  .collect()
}

///|
test "collect the Morphir metadata" {
  debug_inspect(
    da_morphir_metadata(da_source()),
    content=(
      #|[
      #|  ("Account", [("kind", "entity"), ("key", "account_id")]),
      #|  ("balance", [("kind", "measure"), ("precision", "2")]),
      #|]
    ),
  )
}
```

## See also

- [Parse your first Elm module](getting-started.mbt.md)
- [Choose a dialect](dialects.mbt.md)
- [Report syntax errors](error-reports.mbt.md)
- [Read and write elm-syntax JSON](elm-syntax-json.mbt.md)
- API: `ParseResult`, `AttributeGroup`, `AttributeTarget`, `DocAttribute`,
  `encode_attributes`, `encode_attributes_with`, `AttributeSyntax`
