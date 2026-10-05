///|
/// The deepest nesting of doc comments (a doc comment in Elm code in a doc
/// comment) whose code is formatted. Code in deeper doc comments stays as
/// written, so formatting does not recurse without limit.
let max_doc_depth : Int = 3

///|
/// The doc comment `text` (`{-|` to `-}`) as elm-format writes it: its
/// Markdown through `@markdown.format_doc`, with Elm code formatted by
/// `format_code` (elm-format `formatDocComment`). `depth` is the number of
/// doc comments around it. Text that is not a doc comment, or whose
/// formatted text would not end the comment at its end, stays as it is.
fn format_documentation(
  text : String,
  dialect : @dialect.Dialect,
  depth : Int,
) -> String {
  guard text.length() >= 5 && text.has_prefix("{-|") && text.has_suffix("-}") else {
    return text
  }
  let inner = text.view(start_offset=3, end_offset=text.length() - 2).to_owned()
  let formatted = "{-|" +
    @markdown.format_doc(inner, format_code=code => {
      format_code(code, dialect, depth)
    }) +
    "-}"
  if closes_at_end(formatted) {
    formatted
  } else {
    text
  }
}

///|
/// Whether the block comment `text` ends at its last character and not
/// before: Elm block comments nest, so the `{-` and `-}` in it must balance.
fn closes_at_end(text : String) -> Bool {
  let n = text.length()
  let mut depth = 0
  let mut i = 0
  while i < n {
    let c = text.code_unit_at(i).to_int()
    let next = if i + 1 < n { text.code_unit_at(i + 1).to_int() } else { 0 }
    if c == 0x7B && next == 0x2D {
      // `{-`
      depth += 1
      i += 2
    } else if c == 0x2D && next == 0x7D {
      // `-}`
      depth -= 1
      i += 2
      if depth == 0 {
        return i == n
      }
    } else {
      if depth == 0 {
        return false
      }
      i += 1
    }
  }
  false
}

///|
/// Elm code from a doc comment, formatted as elm-format formats it there
/// (`formatDocComment`): as declarations, else as expressions, else as a
/// module. `None` when the code is none of these; the code then stays as
/// written. `depth` is the number of doc comments around the code.
///
/// krueger has no parser for parts of a module, so each form wraps the
/// code in a module, formats it with the elm-format layout and removes the
/// wrapper. In a doc comment, elm-format puts one blank line between
/// top-level items, and none after a comment.
fn format_code(
  code : String,
  dialect : @dialect.Dialect,
  depth : Int,
) -> String? {
  guard depth < max_doc_depth else { return None }
  let found = code_as_declarations(code, dialect, depth)
  guard found is None else { return found }
  let found = code_as_expressions(code, dialect, depth)
  guard found is None else { return found }
  code_as_module(code, dialect, depth)
}

///|
/// The header of the modules that wrap code: a port module, because
/// elm-format reads `port` declarations in code.
let code_header : String = "port module X__ exposing (..)\n\n\n"

///|
/// The kind of a top-level item of formatted code, for the blank lines
/// between items.
priv enum CodeItem {
  Header
  Imports
  Definition
  Fixity
  Comment
}

///|
/// A top-level item of formatted code: its rows (1-based, inclusive), and
/// for a definition the name it defines (`v:` for values, `t:` for types).
priv struct CodeRows {
  start : Int
  mut end : Int
  kind : CodeItem
  name : String?
}

///|
/// `source` formatted with the elm-format layout and parsed again, or
/// `None` when it does not format.
fn format_wrapped(
  source : String,
  dialect : @dialect.Dialect,
  depth : Int,
) -> (String, @ast.File)? {
  let text = format_source(source, ElmFormat, dialect, depth + 1) catch {
    _ => return None
  }
  let result = @parser.parse_module(
    @scanner.SourceText::new(text),
    @scanner.DefaultScanner::new(dialect~),
    dialect~,
  )
  guard result.ast is Some(file) &&
    result.diagnostics.iter().all(d => !(d.severity is Error)) else {
    return None
  }
  Some((text, file))
}

///|
/// The top-level items of `file` in order. Items that share a row are one
/// item (a declaration and the comments in it or after it on its last row).
fn code_items(file : @ast.File) -> Array[CodeRows] {
  let items : Array[CodeRows] = []
  let r = file.module_definition.range
  items.push({ start: r.start.row, end: r.end.row, kind: Header, name: None, })
  if file.imports is [first, ..] && file.imports.last() is Some(last) {
    items.push({
      start: first.range.start.row,
      end: last.range.end.row,
      kind: Imports,
      name: None,
    })
  }
  for d in file.declarations {
    let (kind, name) = match d.value {
      InfixDeclaration(_) => (Fixity, None)
      FunctionDeclaration(f) =>
        (Definition, Some("v:" + f.declaration.value.name.value))
      AliasDeclaration(a) => (Definition, Some("t:" + a.name.value))
      CustomTypeDeclaration(t) => (Definition, Some("t:" + t.name.value))
      PortDeclaration(p) => (Definition, Some("v:" + p.name.value))
      Destructuring(_, _) => (Definition, None)
    }
    items.push({ start: d.range.start.row, end: d.range.end.row, kind, name, })
  }
  for c in file.comments {
    items.push({
      start: c.range.start.row,
      end: c.range.end.row,
      kind: Comment,
      name: None,
    })
  }
  items.sort_by((a, b) => a.start.compare(b.start))
  let merged : Array[CodeRows] = []
  for item in items {
    match merged.last() {
      Some(last) if item.start <= last.end =>
        if item.end > last.end {
          last.end = item.end
        }
      _ => merged.push(item)
    }
  }
  merged
}

///|
/// The blank lines between two top-level items in a doc comment (elm-format
/// `formatTopLevelBody` with one line between items): none after a
/// comment, between infix declarations, and between two definitions of
/// one name.
fn code_spacing(a : CodeRows, b : CodeRows) -> Int {
  match (a.kind, b.kind) {
    (Comment, Comment | Definition | Fixity) => 0
    (Fixity, Fixity) => 0
    (Definition, Definition) if a.name is Some(_) && a.name == b.name => 0
    _ => 1
  }
}

///|
/// The text of `items` from the formatted `text`, with doc-comment
/// spacing. `body` gives the lines of an item, or `None` when the code
/// cannot be written.
fn code_text(
  text : String,
  items : Array[CodeRows],
  body : (CodeRows, Array[String]) -> Array[String]?,
) -> String? {
  let lines = text.split("\n").map(l => l.to_owned()).collect()
  let sb = StringBuilder()
  let mut previous : CodeRows? = None
  for item in items {
    if previous is Some(p) {
      sb.write_string("\n".repeat(code_spacing(p, item)))
    }
    let rows = lines[item.start - 1:item.end].to_owned()
    guard body(item, rows) is Some(out) else { return None }
    for line in out {
      sb.write_string(line)
      sb.write_char('\n')
    }
    previous = Some(item)
  }
  Some(sb.to_string())
}

///|
/// The code as declarations after a module header: the formatted module
/// without its header. elm-format reads no imports here, and no comment
/// after the last declaration.
fn code_as_declarations(
  code : String,
  dialect : @dialect.Dialect,
  depth : Int,
) -> String? {
  guard format_wrapped(code_header + code + "\n", dialect, depth)
    is Some((text, file)) &&
    file.imports.is_empty() else {
    return None
  }
  let items = code_items(file).filter(i => !(i.kind is Header))
  guard !(items.last() is Some({ kind: Comment, .. })) else { return None }
  code_text(text, items, (_, rows) => Some(rows))
}

///|
/// The code as expressions: each line in column 1 starts one (a comment
/// line is a comment). Each expression is the body of a definition
/// `x__N =`; the formatted bodies lose that line and 4 columns. A line
/// comment after an expression on one line stays after it (elm-format
/// `withEol`, `formatEolCommented`): on the same line, or on the next line
/// when the formatted expression takes more lines.
fn code_as_expressions(
  code : String,
  dialect : @dialect.Dialect,
  depth : Int,
) -> String? {
  guard expression_groups(code, dialect) is Some(groups) else { return None }
  for g in groups {
    while g.last() is Some(l) && l.trim(chars=" ") == "" {
      ignore(g.pop())
    }
  }
  // The line comments after expressions on one line, by group.
  let eol : Map[Int, String] = Map([])
  let first = @parser.parse_module(
    @scanner.SourceText::new(wrap_expressions(groups)),
    @scanner.DefaultScanner::new(dialect~),
    dialect~,
  )
  guard first.ast is Some(parsed) else { return None }
  // elm-format reads no comment after the last expression.
  let last_end = parsed.declarations
    .iter()
    .fold(init=0, (m, d) => {
      if d.range.end.row > m {
        d.range.end.row
      } else {
        m
      }
    })
  guard parsed.comments.iter().all(c => c.range.start.row <= last_end) else {
    return None
  }
  for i, g in groups {
    guard g is [line] && !is_comment_line(line) else { continue }
    // The definition of group `i` starts on row `row`; its body is the
    // row after it.
    let row = expression_row(parsed, i)
    for c in parsed.comments {
      if c.value.has_prefix("--") && c.range.start.row == row + 1 {
        eol[i] = c.value
        let chars = line.to_array()
        let cut = c.range.start.column - 1 - 4
        if cut >= 0 && cut <= chars.length() {
          g[0] = String::from_array(chars[:cut]).trim_end(chars=" ").to_owned()
        }
      }
    }
  }
  guard format_wrapped(wrap_expressions(groups), dialect, depth)
    is Some((text, file)) &&
    file.imports.is_empty() else {
    return None
  }
  let items = code_items(file).filter(i => !(i.kind is Header))
  // Each expression is still one definition (none went into a comment).
  let expressions = groups.filter(g => {
    !(g is [line, ..] && is_comment_line(line))
  })
  guard file.declarations.length() == expressions.length() else { return None }
  code_text(text, items, (item, rows) => {
    guard item.kind is Definition else { return Some(rows) }
    guard rows is [first, .. rest] &&
      first.strip_prefix("x__") is Some(after) &&
      after.split(" ").next() is Some(number) else {
      return None
    }
    let out = []
    for line in rest {
      if line == "" {
        out.push("")
      } else if line.has_prefix("    ") {
        out.push(line.view(start_offset=4).to_owned())
      } else {
        return None
      }
    }
    let mut index = 0
    for c in number {
      guard c.is_ascii_digit() else { return None }
      index = index * 10 + (c.to_int() - '0'.to_int())
    }
    match (eol.get(index), out) {
      (Some(comment), [single]) => out[0] = single + " " + comment
      (Some(comment), _) => out.push(comment)
      (None, _) => ()
    }
    Some(out)
  })
}

///|
/// The lines of `code` in groups: a line in column 1 starts a group,
/// except in a multi-line comment or string. Groups lose their blank lines
/// at the end. `None` when the code does not scan or does not start in
/// column 1.
fn expression_groups(
  code : String,
  dialect : @dialect.Dialect,
) -> Array[Array[String]]? {
  guard @scanner.DefaultScanner::new(dialect~).tokenize(
      @scanner.SourceText::new(code),
    )
    is Ok(stream) else {
    return None
  }
  // The lines (1-based) after the first line of a multi-line token or
  // comment.
  let inside : @hashset.HashSet[Int] = @hashset.HashSet([])
  let mark = (span : @scanner.Span) => {
    for l = span.start.line + 1; l <= span.end.line; l = l + 1 {
      inside.add(l)
    }
  }
  let marks_trivia = (trivia : Array[@scanner.Trivia]) => {
    for t in trivia {
      if t is Comment(c) {
        mark(c.span)
      }
    }
  }
  marks_trivia(stream.trivia)
  for t in stream.tokens {
    mark(t.span)
    marks_trivia(t.trivia_before)
    marks_trivia(t.trivia_after)
  }
  let groups : Array[Array[String]] = []
  for i, line in code.split("\n").collect() {
    let l = line.to_owned()
    if l != "" && !l.has_prefix(" ") && !inside.contains(i + 1) {
      groups.push([l])
    } else {
      match groups.last() {
        Some(g) => g.push(l)
        None => if l.trim(chars=" ") != "" { return None }
      }
    }
  }
  guard !groups.is_empty() else { return None }
  for g in groups {
    while g.last() is Some(l) && l.trim(chars=" ") == "" {
      ignore(g.pop())
    }
  }
  Some(groups)
}

///|
fn is_comment_line(line : String) -> Bool {
  line.has_prefix("--") || line.has_prefix("{-")
}

///|
/// A module with each expression group as the body of `x__N =` (`N` is the
/// group's index), and each comment group as it is.
fn wrap_expressions(groups : Array[Array[String]]) -> String {
  let wrapped = StringBuilder()
  wrapped.write_string(code_header)
  for i, g in groups {
    if g is [line, ..] && is_comment_line(line) {
      wrapped.write_string(g.join("\n"))
    } else {
      wrapped.write_string("x__\{i} =\n")
      wrapped.write_string(
        g
        .map(l => if l.trim(chars=" ") == "" { "" } else { "    " + l })
        .join("\n"),
      )
    }
    wrapped.write_string("\n\n\n")
  }
  wrapped.to_string()
}

///|
/// The row of the definition `x__N` (`N` is `index`) in `file`, or 0.
fn expression_row(file : @ast.File, index : Int) -> Int {
  let name = "x__\{index}"
  for d in file.declarations {
    if d.value is FunctionDeclaration(f) &&
      f.declaration.value.name.value == name {
      return d.range.start.row
    }
  }
  0
}

///|
/// The code as a module, laid out as elm-format's `formatModule` lays out
/// a module in a doc comment: the comments before the header, then two
/// blank lines; the header, the module documentation and the imports, with
/// one blank line between them; then one blank line before the body, or two when the body starts
/// with a comment (also when there is nothing before it). Without a module
/// header (elm-format reads one as optional), the code gets one, and the
/// formatted text loses it again.
fn code_as_module(
  code : String,
  dialect : @dialect.Dialect,
  depth : Int,
) -> String? {
  let (text, file, has_header) = match format_wrapped(code, dialect, depth) {
    Some((text, file)) => (text, file, true)
    None =>
      match
        format_wrapped(
          "port module X__ exposing (..)\n\n" + code + "\n",
          dialect,
          depth,
        ) {
        Some((text, file)) => (text, file, false)
        None => return None
      }
  }
  let all = code_items(file)
  let lines = text.split("\n").map(l => l.to_owned()).collect()
  let rows = (item : CodeRows) => lines[item.start - 1:item.end].to_owned()
  let initial = []
  let docs = []
  let mut header : CodeRows? = None
  let mut imports : CodeRows? = None
  let body = []
  let mut leading = leading_comments(code, dialect)
  for item in all {
    match item.kind {
      Header => header = Some(item)
      Imports => imports = Some(item)
      Comment if leading > 0 && body.is_empty() && imports is None => {
        initial.push(item)
        leading -= 1
      }
      Comment if has_header &&
        header is Some(_) &&
        imports is None &&
        body.is_empty() &&
        lines[item.start - 1].has_prefix("{-|") => docs.push(item)
      _ => body.push(item)
    }
  }
  let out = []
  for item in initial {
    out.append(rows(item))
  }
  if !initial.is_empty() {
    out.append(["", ""])
  }
  if has_header && header is Some(h) {
    out.append(rows(h))
    for d in docs {
      out.push("")
      out.append(rows(d))
    }
    if imports is Some(i) {
      out.push("")
      out.append(rows(i))
    }
  } else if imports is Some(i) {
    out.append(rows(i))
  }
  match body {
    [] => ()
    [{ kind: Comment, .. }, ..] => out.append(["", ""])
    _ => out.push("")
  }
  let sb = StringBuilder()
  for line in out {
    sb.write_string(line)
    sb.write_char('\n')
  }
  guard code_text(text, body, (_, r) => Some(r)) is Some(rest) else {
    return None
  }
  Some(sb.to_string() + rest)
}

///|
/// The number of comments before the first token of `code`. A block
/// comment that ends code with only comments is not one: elm-format reads
/// it after the module header.
fn leading_comments(code : String, dialect : @dialect.Dialect) -> Int {
  guard @scanner.DefaultScanner::new(dialect~).tokenize(
      @scanner.SourceText::new(code),
    )
    is Ok(stream) else {
    return 0
  }
  let trivia = match stream.tokens {
    [first, ..] => first.trivia_before
    [] => stream.trivia
  }
  let comments = trivia.filter_map(t => {
    if t is Comment(c) {
      Some(c)
    } else {
      None
    }
  })
  match (stream.tokens, comments.last()) {
    ([], Some({ kind: Block, .. })) => comments.length() - 1
    _ => comments.length()
  }
}
