///|
/// The sort key of an exposed item (elm-format `varOrder`): operators, then
/// types, then values; by name in each kind.
fn expose_order(x : @ast.TopLevelExpose) -> (Int, String) {
  match x {
    InfixExpose(s) => (1, s)
    TypeOrAliasExpose(name) => (2, name)
    TypeExpose(t) => (2, t.name)
    FunctionExpose(name) => (3, name)
  }
}

///|
/// The name of an exposed item as a `@docs` line names it (elm-format
/// `varName`): the symbol of an operator, else the name.
fn expose_name(x : @ast.TopLevelExpose) -> String {
  expose_order(x).1
}

///|
/// Compares two names by code point, as Haskell compares strings.
fn compare_names(a : String, b : String) -> Int {
  let xs : Array[Char] = []
  for c in a {
    xs.push(c)
  }
  let ys : Array[Char] = []
  for c in b {
    ys.push(c)
  }
  let n = if xs.length() < ys.length() { xs.length() } else { ys.length() }
  for i in 0..<n {
    if xs[i] != ys[i] {
      return xs[i].compare(ys[i])
    }
  }
  xs.length().compare(ys.length())
}

///|
fn compare_order(a : (Int, String), b : (Int, String)) -> Int {
  if a.0 != b.0 {
    a.0.compare(b.0)
  } else {
    compare_names(a.1, b.1)
  }
}

///|
/// Whether an exposed type exposes its constructors (`T(..)`).
fn is_open(x : @ast.TopLevelExpose) -> Bool {
  x is TypeExpose({ open: Some(_), .. })
}

///|
/// The exposed items as a set, sorted by `expose_order` (elm-format keeps
/// them in maps). Of the items with the same key, the first stays, unless
/// a later one exposes the constructors of a type that the first does not
/// (`T` and `T(..)` give `T(..)`).
fn normalize_exposes(
  items : ArrayView[@ast.Node[@ast.TopLevelExpose]],
) -> Array[@ast.Node[@ast.TopLevelExpose]] {
  let index : Map[(Int, String), Int] = Map([])
  let out = []
  for x in items {
    let key = expose_order(x.value)
    match index.get(key) {
      None => {
        index[key] = out.length()
        out.push(x)
      }
      Some(i) => if is_open(x.value) && !is_open(out[i].value) { out[i] = x }
    }
  }
  out.sort_by((a, b) => {
    compare_order(expose_order(a.value), expose_order(b.value))
  })
  out
}

///|
fn normalize_exposing(e : @ast.Node[@ast.Exposing]) -> @ast.Node[@ast.Exposing] {
  match e.value {
    All(_) => e
    Explicit(items) =>
      { range: e.range, value: Explicit(normalize_exposes(items)), }
  }
}

///|
/// The exposing list of two imports of the same module (elm-format
/// `mergeListing`): `(..)` wins over a list; two lists are joined.
fn merge_exposing(
  a : @ast.Node[@ast.Exposing]?,
  b : @ast.Node[@ast.Exposing]?,
) -> @ast.Node[@ast.Exposing]? {
  match (a, b) {
    (None, x) | (x, None) => x
    (Some({ value: All(_), .. }), _) => a
    (_, Some({ value: All(_), .. })) => b
    (Some({ range, value: Explicit(xs), }), Some({ value: Explicit(ys), .. })) =>
      Some({ range, value: Explicit([..xs, ..ys]), })
  }
}

///|
/// The text of a module name, `A.B`.
fn module_key(name : @ast.ModuleName) -> String {
  name.iter().collect().join(".")
}

///|
/// The imports as elm-format writes them: sorted by module name, the
/// imports of one module merged into the first (a later alias wins, the
/// exposing lists are joined), each exposing list a sorted set, and an
/// alias equal to the module name removed (`import A as A`).
fn normalize_imports(
  imports : ArrayView[@ast.Node[@ast.Import]],
) -> Array[@ast.Node[@ast.Import]] {
  let index : Map[String, Int] = Map([])
  let out : Array[@ast.Node[@ast.Import]] = []
  for imp in imports {
    let key = module_key(imp.value.module_name.value)
    match index.get(key) {
      None => {
        index[key] = out.length()
        out.push(imp)
      }
      Some(i) => {
        let first = out[i]
        out[i] = {
          range: first.range,
          value: {
            module_name: first.value.module_name,
            module_alias: if imp.value.module_alias is Some(_) {
              imp.value.module_alias
            } else {
              first.value.module_alias
            },
            exposing_list: merge_exposing(
              first.value.exposing_list,
              imp.value.exposing_list,
            ),
          },
        }
      }
    }
  }
  let normalized = out.map(fn(imp) -> @ast.Node[@ast.Import] {
    let name = imp.value.module_name
    let kept = match imp.value.module_alias {
      Some(a) if module_key(a.value) == module_key(name.value) &&
        a.value.length() == 1 => None
      other => other
    }
    {
      range: imp.range,
      value: {
        module_name: name,
        module_alias: kept,
        exposing_list: imp.value.exposing_list.map(normalize_exposing),
      },
    }
  })
  normalized.sort_by((a, b) => {
    compare_names(
      module_key(a.value.module_name.value),
      module_key(b.value.module_name.value),
    )
  })
  normalized
}

///|
/// The file in the order and with the parentheses that elm-format gives
/// it. Parsing the output of `print_file` gives this AST (without ranges
/// and regular comments). `format` gives it too, except that it keeps
/// parentheses that have a comment inside them, and keeps a chain of
/// operators of the same precedence and different directions flat
/// (`a |> f <| g`), as elm-format does.
///
/// - The module's exposed items are a set: a duplicate is removed (`T` and
///   `T(..)` give `T(..)`). They are sorted: operators, then types, then
///   values, each by name. When the module documentation has `@docs`
///   lines, the items that they name come first, in the order of those
///   lines.
/// - The imports are sorted by module name. The imports of one module are
///   merged into the first: a later alias replaces an earlier one, and
///   the exposing lists are joined (`(..)` wins). An alias equal to the
///   module name is removed (`import A as A`). Each exposing list is a
///   sorted set, as above.
/// - Parentheses that neither the parser nor elm-format needs go
///   (elm-format `formatExpression`, `syntaxParens`): `case (f x) of`
///   gives `case f x of`, `a - (f b)` gives `a - f b`, `f (-x)` gives
///   `f -x`. Parentheses around an operator chain in a chain stay.
/// - elm-format's parentheses are added: around a lambda, `if`, `case` or
///   `let` at the end of an operator chain, except after `<|`
///   (`x |> (\y -> y)`); around a constructor pattern with arguments
///   before or after `::` and in an `as` (`(Just a) :: rest`).
///
/// Nodes keep their ranges; an expression that replaces its parentheses
/// takes their range. Nothing else changes.
///
/// ```mbt check
/// test {
///   let text = "module A exposing (b, a)\n\nimport C\nimport B as B\n\n\na =\n    1\n"
///   let file = @parser.parse_module(
///     @scanner.SourceText::new(text),
///     @scanner.DefaultScanner::new(),
///   ).ast.unwrap()
///   inspect(
///     @printer.print_file(@printer.normalize_file(file)),
///     content=(
///       #|module A exposing (a, b)
///       #|
///       #|import B
///       #|import C
///       #|
///       #|
///       #|a =
///       #|    1
///       #|
///     ),
///   )
/// }
/// ```
pub fn normalize_file(file : @ast.File) -> @ast.File {
  normalize_parens(normalize_header(file))
}

///|
/// The module header and the imports of `file` in elm-format's order (see
/// `normalize_file`). The printer prints the declarations of the source
/// and decides their parentheses while it prints, so that comments and
/// error paths stay those of the source.
fn normalize_header(file : @ast.File) -> @ast.File {
  let sorted = {
    ..with_exposing(file, normalize_exposing),
    imports: normalize_imports(file.imports),
  }
  // The order of the printed list: the groups of `@docs` lines first.
  let groups = exposing_groups(sorted, Join).groups
  with_exposing(sorted, e => {
    match e.value {
      All(_) => e
      Explicit(_) => {
        let items = []
        for g in groups {
          items.append(g)
        }
        { range: e.range, value: Explicit(items), }
      }
    }
  })
}

///|
/// `file` with its module's exposing list changed by `f`.
fn with_exposing(
  file : @ast.File,
  f : (@ast.Node[@ast.Exposing]) -> @ast.Node[@ast.Exposing],
) -> @ast.File {
  let m = file.module_definition
  let value : @ast.Module = match m.value {
    NormalModule(d) => NormalModule({ ..d, exposing_list: f(d.exposing_list), })
    PortModule(d) => PortModule({ ..d, exposing_list: f(d.exposing_list), })
    EffectModule(d) => EffectModule({ ..d, exposing_list: f(d.exposing_list), })
  }
  { ..file, module_definition: { range: m.range, value, }, }
}

///|
fn exposing_of(m : @ast.Module) -> @ast.Node[@ast.Exposing] {
  match m {
    NormalModule(d) | PortModule(d) => d.exposing_list
    EffectModule(d) => d.exposing_list
  }
}

///|
/// The index of the port declaration that doc comment `c` documents (it
/// ends on the row before the port), if any.
fn documented_port(file : @ast.File, c : @ast.Node[String]) -> Int? {
  for j, decl in file.declarations {
    if decl.value is PortDeclaration(_) &&
      decl.range.start.row == c.range.end.row + 1 {
      return Some(j)
    }
  }
  None
}

///|
/// The module documentation: the first doc comment of `File.comments` that
/// does not document a port.
fn module_documentation(file : @ast.File) -> @ast.Node[String]? {
  for c in file.comments {
    if c.value.has_prefix("{-|") && documented_port(file, c) is None {
      return Some(c)
    }
  }
  None
}

///|
/// The number of spaces at the start of `line`.
fn indentation(line : String) -> Int {
  let mut n = 0
  for c in line {
    guard c == ' ' else { break }
    n += 1
  }
  n
}

///|
/// The fence that `text` opens (three or more `` ` `` or `~`), if any: the
/// run of fence characters, without the info string after it.
fn fence_start(text : String) -> String? {
  let mark = if text.has_prefix("```") {
    '`'
  } else if text.has_prefix("~~~") {
    '~'
  } else {
    return None
  }
  let mut n = 0
  for c in text {
    guard c == mark else { break }
    n += 1
  }
  Some(text.view(end_offset=n).to_owned())
}

///|
/// Whether `text` starts a list item (`- `, `* `, `+ `, `1. `, `1) `) or a
/// block quote (`>`).
fn starts_nested(text : String) -> Bool {
  let after_marker = (rest : StringView) => {
    rest.is_empty() || rest.has_prefix(" ")
  }
  if text.has_prefix(">") {
    return true
  }
  if text.has_prefix("-") || text.has_prefix("*") || text.has_prefix("+") {
    return after_marker(text.view(start_offset=1))
  }
  let mut digits = 0
  for c in text {
    guard c >= '0' && c <= '9' else { break }
    digits += 1
  }
  guard digits > 0 && digits < 10 else { return false }
  let rest = text.view(start_offset=digits)
  (rest.has_prefix(".") || rest.has_prefix(")")) &&
  after_marker(rest.view(start_offset=1))
}

///|
/// Whether `text` is an ATX header (`# Title`) or a thematic break (`---`).
fn is_header_or_rule(text : String) -> Bool {
  let mut hashes = 0
  for c in text {
    guard c == '#' else { break }
    hashes += 1
  }
  if hashes > 0 && hashes <= 6 {
    let rest = text.view(start_offset=hashes)
    if rest.is_empty() || rest.has_prefix(" ") {
      return true
    }
  }
  for mark in ['-', '*', '_'] {
    let mut count = 0
    let mut other = false
    for c in text {
      if c == mark {
        count += 1
      } else if c != ' ' {
        other = true
      }
    }
    if !other && count >= 3 {
      return true
    }
  }
  false
}

///|
priv enum DocBlock {
  Top
  Fenced(String)
  IndentedCode
  Nested
}

///|
/// The names of the `@docs` lines of a module documentation, one array per
/// line (elm-format reads them with its Markdown parser, Cheapskate
/// `processElts`). A `@docs` line is a paragraph line at the top level of
/// the Markdown; the text lines right after it are `@docs` lines too.
/// Lines in code blocks, lists and block quotes are not. Names are split
/// at `,` and trimmed.
fn docs_lines(doc : String) -> Array[Array[String]] {
  let body = if doc.has_prefix("{-|") &&
    doc.has_suffix("-}") &&
    doc.length() >= 5 {
    doc.view(start_offset=3, end_offset=doc.length() - 2).to_owned()
  } else {
    doc
  }
  let out = []
  let mut block = Top
  // The line before is a paragraph line (a lazy continuation can follow).
  let mut after_text = false
  // The line before is a `@docs` line.
  let mut in_docs = false
  for raw in body.split("\n") {
    let line = raw.to_owned()
    let line = if line.has_suffix("\r") {
      line.view(end_offset=line.length() - 1).to_owned()
    } else {
      line
    }
    let indent = indentation(line)
    let text = line.view(start_offset=indent).to_owned().trim_end().to_owned()
    if block is Fenced(fence) {
      // Cheapskate closes a fence with any line that starts with it, also
      // with text after it (CommonMark allows only spaces).
      if indent < 4 && text.has_prefix(fence) {
        block = Top
      }
      continue
    }
    if text.is_empty() {
      after_text = false
      in_docs = false
      continue
    }
    match block {
      IndentedCode => if indent >= 4 { continue } else { block = Top }
      Nested => if indent > 0 || after_text { continue } else { block = Top }
      _ => ()
    }
    if indent >= 4 && !after_text {
      block = IndentedCode
      continue
    }
    if indent < 4 {
      if fence_start(text) is Some(fence) {
        block = Fenced(fence)
        after_text = false
        in_docs = false
        continue
      }
      if is_header_or_rule(text) {
        after_text = false
        in_docs = false
        continue
      }
      if starts_nested(text) {
        block = Nested
        after_text = true
        in_docs = false
        continue
      }
    }
    let names = if text.has_prefix("@docs") {
      Some(text.view(start_offset=5).to_owned())
    } else if in_docs {
      Some(text)
    } else {
      None
    }
    if names is Some(list) {
      out.push(
        list
        .split(",")
        .map(s => s.trim().to_owned())
        .filter(s => !s.is_empty())
        .collect(),
      )
      in_docs = true
    }
    after_text = true
  }
  out
}

///|
/// The name of the exposed item that a `@docs` name refers to (elm-format
/// `textToRef`): `(+)` and `(<=)` name an operator; other names are taken
/// as they are, so `(</>)` and `T(..)` name no exposed item.
fn docs_key(name : String) -> String {
  let chars : Array[Char] = []
  for c in name {
    chars.push(c)
  }
  if chars.length() is (3 | 4) &&
    chars[0] == '(' &&
    chars[chars.length() - 1] == ')' {
    name.view(start_offset=1, end_offset=name.length() - 1).to_owned()
  } else {
    name
  }
}

///|
/// The groups of a module's exposing list, one per line of the printed
/// list (elm-format `sortVars`). The first `documented` groups come from
/// `@docs` lines.
priv struct ExposingGroups {
  groups : Array[Array[@ast.Node[@ast.TopLevelExpose]]]
  documented : Int
}

///|
/// One group with all `items`.
fn ExposingGroups::single(
  items : ArrayView[@ast.Node[@ast.TopLevelExpose]],
) -> ExposingGroups {
  { groups: [items.iter().collect()], documented: 0, }
}

///|
/// The groups of the exposing list of a normalized file (see
/// `normalize_file`). With `@docs` lines in the module documentation: one
/// group per `@docs` line, in line order, with the exposed items that the
/// line names (an item stays in the first group that names it); then one
/// group of the other items. Without them: one group, or one group per
/// item when `split` is `Split` (the source list is multi-line). Empty
/// groups are left out; `(..)` has none.
fn exposing_groups(file : @ast.File, split : Split) -> ExposingGroups {
  guard exposing_of(file.module_definition.value).value is Explicit(items) else {
    return { groups: [], documented: 0, }
  }
  let by_name : Map[String, @ast.Node[@ast.TopLevelExpose]] = Map([])
  for x in items {
    by_name[expose_name(x.value)] = x
  }
  let seen : Map[String, Unit] = Map([])
  let groups = []
  if module_documentation(file) is Some(doc) {
    for line in docs_lines(doc.value) {
      let group = []
      for name in line {
        let key = docs_key(name)
        if by_name.get(key) is Some(x) && !seen.contains(key) {
          seen[key] = ()
          group.push(x)
        }
      }
      if !group.is_empty() {
        groups.push(group)
      }
    }
  }
  let documented = groups.length()
  let rest = items
    .iter()
    .filter(x => !seen.contains(expose_name(x.value)))
    .collect()
  if documented == 0 && split is Split {
    for x in rest {
      groups.push([x])
    }
  } else if !rest.is_empty() {
    groups.push(rest)
  }
  { groups, documented, }
}
