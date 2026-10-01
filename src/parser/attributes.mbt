///|
/// One line of a doc comment, with the file position of its first character.
priv struct DocLine {
  text : String
  line : Int
  column : Int
  offset : Int
}

///|
/// The lines of a doc comment's text (without `{-|` and `-}`).
fn doc_lines(comment : @scanner.Comment) -> Array[DocLine] {
  let text = comment.text
  let start = if text.has_prefix("{-|") { 3 } else { 0 }
  let end = if text.has_suffix("-}") {
    text.length() - 2
  } else {
    text.length()
  }
  let lines = []
  let mut from = start
  let mut row = comment.span.start.line
  let mut column = comment.span.start.column + start
  for i = start; i <= end; i = i + 1 {
    if i == end || text.code_unit_at(i) == '\n' {
      let raw = text.unsafe_substring(start=from, end=i)
      let line = if raw.has_suffix("\r") {
        raw.unsafe_substring(start=0, end=raw.length() - 1)
      } else {
        raw
      }
      lines.push({
        text: line,
        line: row,
        column,
        offset: comment.span.start.offset + from,
      })
      from = i + 1
      row += 1
      column = 1
    }
  }
  lines
}

///|
/// An attribute found in the line walk: its `@` line and continuation lines.
priv struct RawAttribute {
  lines : Array[DocLine]
  /// Open brackets after the lines so far (plain attributes only).
  mut open : Int
  /// Whether the lines so far hold a value (plain attributes only).
  mut has_value : Bool
  /// From an attributes block, where continuation lines are verbatim.
  block : Bool
}

///|
fn is_blank(text : String) -> Bool {
  text.trim().is_empty()
}

///|
/// The fence info string of an attributes block: ```` ```attributes ````.
let block_info : String = "attributes"

///|
/// Brackets opened minus closed in `text`, skipping string and char
/// literals.
fn bracket_balance(text : String) -> Int {
  let mut balance = 0
  let mut quote : Char? = None
  let mut escaped = false
  for c in text {
    match quote {
      Some(q) =>
        if escaped {
          escaped = false
        } else if c == '\\' {
          escaped = true
        } else if c == q {
          quote = None
        }
      None =>
        match c {
          '"' | '\'' => quote = Some(c)
          '(' | '[' | '{' => balance += 1
          ')' | ']' | '}' => balance -= 1
          _ => ()
        }
    }
  }
  balance
}

///|
/// The fence of a fenced code block line (```` ``` ```` or `~~~`, after up to
/// three spaces) and its info string.
fn fence_of(text : String) -> (String, String)? {
  let trimmed = text.trim_start().to_owned()
  if text.length() - trimmed.length() > 3 {
    return None
  }
  for fence in ["```", "~~~"] {
    if trimmed.has_prefix(fence) {
      return Some(
        (
          fence,
          trimmed
          .unsafe_substring(start=3, end=trimmed.length())
          .trim()
          .to_owned(),
        ),
      )
    }
  }
  None
}

///|
/// The code-block state of the line walk.
priv enum Mode {
  Prose
  /// Inside a fenced block: its fence, and whether it is an attributes block.
  Fenced(String, Bool)
  /// Inside an indented code block.
  Indented
}

///|
/// Attributes of a doc comment, in three forms:
/// - an attributes block: a fenced code block with the info string
///   `attributes` (read verbatim; an attribute runs until the next `@` line
///   or a blank line);
/// - `@name` with one code span holding its values;
/// - `@name values` in prose, continuing only while brackets are open or
///   while the `@` line has no value yet.
///
/// Other code blocks, prose and the comment's first line hold no attributes.
fn raw_attributes(lines : Array[DocLine]) -> Array[RawAttribute] {
  let found : Array[RawAttribute] = []
  let mut current : RawAttribute? = None
  let mut mode : Mode = Prose
  let mut previous_blank = false
  for i, line in lines {
    let text = line.text
    match mode {
      Fenced(fence, attributes) => {
        if fence_of(text) is Some((f, _)) && f == fence {
          mode = Prose
          current = None
          previous_blank = false
        } else if !attributes {
          ()
        } else if is_blank(text) {
          current = None
        } else if text.has_prefix("@") {
          let attribute = {
            lines: [line],
            open: 0,
            has_value: true,
            block: true,
          }
          found.push(attribute)
          current = Some(attribute)
        } else if current is Some(attribute) {
          attribute.lines.push(line)
        }
        continue
      }
      Indented =>
        if is_blank(text) || text.has_prefix("    ") {
          continue
        } else {
          mode = Prose
        }
      Prose => ()
    }
    if fence_of(text) is Some((fence, info)) {
      mode = Fenced(fence, info == block_info)
      current = None
      continue
    }
    if is_blank(text) {
      current = None
      previous_blank = true
      continue
    }
    if text.has_prefix("    ") && previous_blank && current is None {
      mode = Indented
      previous_blank = false
      continue
    }
    previous_blank = false
    if i > 0 && text.has_prefix("@") {
      let value = text.unsafe_substring(start=1, end=text.length())
      let after_name = match value.find(" ") {
        Some(k) => value.unsafe_substring(start=k, end=value.length()).trim()
        None => ""
      }
      let span = after_name.has_prefix("`")
      let attribute = {
        lines: [line],
        open: if span {
          0
        } else {
          bracket_balance(after_name.to_owned())
        },
        has_value: after_name != "",
        block: false,
      }
      found.push(attribute)
      current = Some(attribute)
    } else if current is Some(attribute) &&
      (attribute.open > 0 || !attribute.has_value) {
      attribute.lines.push(line)
      attribute.open += bracket_balance(text)
      attribute.has_value = true
    } else {
      current = None
    }
  }
  found
}

///|
fn is_name_start(c : Char) -> Bool {
  c >= 'a' && c <= 'z'
}

///|
fn is_name_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// Whether `name` is `lower ("." lower)*` with `lower = [a-z][A-Za-z0-9_]*`.
fn valid_attribute_name(name : String) -> Bool {
  if name == "" {
    return false
  }
  for part in name.split(".") {
    let part = part.to_owned()
    guard part.get_char(0) is Some(first) && is_name_start(first) else {
      return false
    }
    for c in part {
      if !is_name_char(c) {
        return false
      }
    }
  }
  true
}

///|
/// Whether `e` is Elm data: literals, a negated number, unit, tuples, lists,
/// records, names, or a parenthesized constructor application of data.
fn is_data(e : @ast.Expression) -> Bool {
  match e {
    UnitExpr
    | Literal(_)
    | CharLiteral(_)
    | Integer(_)
    | Hex(_)
    | Floatable(_)
    | FunctionOrValue(_, _) => true
    Negation(n) => n.value is (Integer(_) | Hex(_) | Floatable(_))
    TupledExpression(items) | ListExpr(items) =>
      items.all(i => is_data(i.value))
    RecordExpr(setters) => setters.all(s => is_data(s.value.expression.value))
    ParenthesizedExpression(inner) =>
      match inner.value {
        Application([{ value: FunctionOrValue(_, name), .. }, .. args]) =>
          name.get_char(0) is Some(c) &&
          @scanner.is_upper_start(c) &&
          args.all(a => is_data(a.value))
        other => is_data(other)
      }
    _ => false
  }
}

///|
fn range_at(line : Int, column : Int, length : Int) -> @ast.Range {
  {
    start: { row: line, column, },
    end: { row: line, column: column + length, },
  }
}

///|
/// A token moved from attribute-text coordinates to file coordinates. `body`
/// is the values' text: its first line starts `shift` code units into the
/// attribute's first line, and its other lines are the attribute's following
/// lines, joined with `\n` (a CRLF in the file is one unit longer, so each
/// line is moved by its own start).
fn shift_token(
  t : @scanner.Token,
  raw : RawAttribute,
  shift : Int,
) -> @scanner.Token {
  let body_starts = []
  let mut at = 0
  for k, line in raw.lines {
    body_starts.push(at)
    at += line.text.length() + 1 - (if k == 0 { shift } else { 0 })
  }
  let first = raw.lines[0]
  let relocate = fn(p : @scanner.Position) -> @scanner.Position {
    let k = p.line - 1
    let line = raw.lines[k]
    let (start, column) = if k == 0 {
      (
        line.offset + shift,
        line.column +
        code_points(first.text.unsafe_substring(start=0, end=shift)),
      )
    } else {
      (line.offset, line.column)
    }
    {
      offset: start + p.offset - body_starts[k],
      line: line.line,
      column: column + p.column - 1,
    }
  }
  { ..t, span: { start: relocate(t.span.start), end: relocate(t.span.end), }, }
}

///|
fn malformed(raw : RawAttribute, reason : String) -> @scanner.Diagnostic {
  let first = raw.lines[0]
  let last = raw.lines[raw.lines.length() - 1]
  let start : @scanner.Position = {
    offset: first.offset,
    line: first.line,
    column: first.column,
  }
  let end : @scanner.Position = {
    offset: last.offset + last.text.length(),
    line: last.line,
    column: last.column + code_points(last.text),
  }
  let span : @scanner.Span = { start, end, }
  {
    code: "KR-ATTR-001",
    severity: Warning,
    message: "Malformed doc attribute: \{reason}",
    span,
    title: "MALFORMED ATTRIBUTE",
    report: [
      plain("I could not read this attribute:"),
      Excerpt(context=span, highlight=point(start)),
      plain(reason),
      Hint([
        Plain("Attribute names are lower case, like "),
        @scanner.Chunk::code("@deprecated"),
        Plain(
          ", and values are Elm data: strings, numbers, lists, records, tuples and names, like ",
        ),
        @scanner.Chunk::code("@derive [ Json.encoder ]"),
        Plain("."),
      ]),
    ],
  }
}

///|
/// Parse one attribute; `Err` is a `KR-ATTR-001` warning.
fn parse_attribute(
  raw : RawAttribute,
  dialect : @dialect.Dialect,
  warnings : Array[@scanner.Diagnostic],
) -> Result[DocAttribute, @scanner.Diagnostic] {
  let first = raw.lines[0]
  let text = first.text
  let mut name_end = 1
  while name_end < text.length() &&
        text.code_unit_at(name_end) != ' ' &&
        text.code_unit_at(name_end) != '\t' {
    name_end += 1
  }
  let name = text.unsafe_substring(start=1, end=name_end)
  if !valid_attribute_name(name) {
    return Err(malformed(raw, "`@\{name}` is not a valid attribute name."))
  }
  let name_node : @ast.Node[String] = {
    range: range_at(first.line, first.column + 1, name.length()),
    value: name,
  }
  let last = raw.lines[raw.lines.length() - 1]
  let range : @ast.Range = {
    start: { row: first.line, column: first.column, },
    end: { row: last.line, column: last.column + code_points(last.text), },
  }
  let after_name = text.unsafe_substring(start=name_end, end=text.length())
  let trimmed = after_name.trim_start().to_owned()
  if !raw.block && trimmed.has_prefix("`") {
    // `@name `values``: the values are the code span's content.
    let lead = after_name.length() - trimmed.length()
    guard trimmed.unsafe_substring(start=1, end=trimmed.length()).find("`")
      is Some(close) else {
      return Err(
        malformed(raw, "The code span after `@\{name}` is not closed."),
      )
    }
    let content = trimmed.unsafe_substring(start=1, end=close + 1)
    return parse_values(
      raw,
      name,
      name_node,
      range,
      content,
      name_end + lead + 1,
      dialect,
      warnings,
    )
  }
  let rest = [after_name]
  for line in raw.lines[1:] {
    rest.push(line.text)
  }
  let body = rest.join("\n")
  if name == "docs" {
    let names : Array[@ast.Node[String]] = []
    for li, line_text in rest {
      let line = raw.lines[li]
      // Columns count code points; `index` counts UTF-16 units.
      let base = if li == 0 {
        first.column +
        code_points(first.text.unsafe_substring(start=0, end=name_end))
      } else {
        line.column
      }
      let mut index = 0
      for piece in line_text.split(",") {
        let piece = piece.to_owned()
        let trimmed = piece.trim().to_owned()
        if trimmed != "" {
          let lead = piece.length() - piece.trim_start().length()
          let column = base +
            code_points(line_text.unsafe_substring(start=0, end=index + lead))
          names.push({
            range: range_at(line.line, column, code_points(trimmed)),
            value: trimmed,
          })
        }
        index += piece.length() + 1
      }
    }
    return Ok(Docs(names~, range~))
  }
  parse_values(raw, name, name_node, range, body, name_end, dialect, warnings)
}

///|
fn code_points(text : String) -> Int {
  let mut n = 0
  for _ in text {
    n += 1
  }
  n
}

///|
/// Parse `body`, the values of an attribute, which start `shift` code units
/// into its first line.
fn parse_values(
  raw : RawAttribute,
  name : String,
  name_node : @ast.Node[String],
  range : @ast.Range,
  body : String,
  shift : Int,
  dialect : @dialect.Dialect,
  warnings : Array[@scanner.Diagnostic],
) -> Result[DocAttribute, @scanner.Diagnostic] {
  let source = @scanner.SourceText::{ module_name: None, text: body, }
  guard @scanner.lex_raw(source, dialect~) is Ok(raw_tokens) else {
    return Err(malformed(raw, "I could not read the values of `@\{name}`."))
  }
  let tokens = @scanner.normalize_tokens(raw_tokens).tokens.map(t => {
    shift_token(t, raw, shift)
  })
  let c = Cursor::new(tokens, dialect)
  // Attribute values are not laid out like Elm code: elm-format may move
  // continuation lines to column 1.
  c.indent = 0
  let arguments = []
  while !c.at_end() {
    let argument = sub_expression(c) catch {
      SyntaxError(_, _, _) =>
        return Err(malformed(raw, "I could not read the values of `@\{name}`."))
    }
    if !is_data(argument.value) {
      return Err(
        malformed(raw, "The values of `@\{name}` must be Elm data, not code."),
      )
    }
    arguments.push(argument)
  }
  warnings.append(c.warnings)
  Ok(Attribute(name=name_node, arguments~, range~))
}

///|
/// The attributes of a doc comment, and warnings for malformed ones.
fn doc_attributes(
  comment : @scanner.Comment,
  dialect : @dialect.Dialect,
) -> (Array[DocAttribute], Array[@scanner.Diagnostic]) {
  let attributes = []
  let warnings = []
  for raw in raw_attributes(doc_lines(comment)) {
    match parse_attribute(raw, dialect, warnings) {
      Ok(a) => attributes.push(a)
      Err(w) => warnings.push(w)
    }
  }
  (attributes, warnings)
}

///|
fn encode_attribute(a : DocAttribute, exact_ints~ : Bool) -> Json {
  match a {
    Attribute(name~, arguments~, range~) =>
      {
        "name": @ast.encode_node(name, n => n.to_json()),
        "arguments": Json::array(
          arguments.map(arg => {
            @ast.encode_node(arg, e => {
              @ast.encode_expression_with(e, exact_ints~)
            })
          }),
        ),
        "range": @ast.encode_range(range),
      }
    Docs(names~, range~) =>
      {
        "docs": Json::array(
          names.map(n => @ast.encode_node(n, v => v.to_json())),
        ),
        "range": @ast.encode_range(range),
      }
  }
}

///|
/// Attribute groups as JSON, for tools.
pub fn encode_attributes(groups : Array[AttributeGroup]) -> Json {
  encode_attributes_with(groups, exact_ints=false)
}

///|
/// Attribute groups as JSON. With `exact_ints`, Int arguments are written
/// with their exact digits (see `@ast.encode_file_with`).
pub fn encode_attributes_with(
  groups : Array[AttributeGroup],
  exact_ints~ : Bool,
) -> Json {
  Json::array(
    groups.map(g => {
      "target": match g.target {
        Module => "module".to_json()
        Declaration(name~, range~) =>
          { "declaration": name.to_json(), "range": @ast.encode_range(range) }
      },
      "attributes": Json::array(
        g.attributes.map(a => encode_attribute(a, exact_ints~)),
      ),
    }),
  )
}
