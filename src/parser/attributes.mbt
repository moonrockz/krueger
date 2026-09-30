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
}

///|
fn is_blank(text : String) -> Bool {
  text.trim().is_empty()
}

///|
/// Attribute lines of a doc comment. Skips the first line, fenced code
/// blocks and indented code blocks (4 spaces after a blank line).
fn raw_attributes(lines : Array[DocLine]) -> Array[RawAttribute] {
  let found : Array[RawAttribute] = []
  let mut current : RawAttribute? = None
  let mut in_fence = false
  let mut in_code = false
  let mut previous_blank = false
  for i, line in lines {
    let text = line.text
    if i == 0 {
      previous_blank = is_blank(text)
      continue
    }
    if in_fence {
      if text.has_prefix("```") {
        in_fence = false
      }
      continue
    }
    if text.has_prefix("```") {
      current = None
      in_fence = true
      continue
    }
    if is_blank(text) {
      current = None
      previous_blank = true
      continue
    }
    if text.has_prefix("    ") && (previous_blank || in_code) && current is None {
      in_code = true
      previous_blank = false
      continue
    }
    in_code = false
    previous_blank = false
    if text.has_prefix("@") {
      let attribute = { lines: [line], }
      found.push(attribute)
      current = Some(attribute)
    } else if text.has_prefix(" ") && current is Some(attribute) {
      attribute.lines.push(line)
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
/// A token moved from attribute-text coordinates to file coordinates.
fn shift_token(
  t : @scanner.Token,
  base : DocLine,
  column_shift : Int,
) -> @scanner.Token {
  let relocate = fn(p : @scanner.Position) -> @scanner.Position {
    {
      offset: p.offset + base.offset + column_shift,
      line: p.line + base.line - 1,
      column: if p.line == 1 {
        p.column + column_shift
      } else {
        p.column
      },
    }
  }
  { ..t, span: { start: relocate(t.span.start), end: relocate(t.span.end), }, }
}

///|
fn malformed(line : DocLine, reason : String) -> @scanner.Diagnostic {
  let start : @scanner.Position = {
    offset: line.offset,
    line: line.line,
    column: line.column,
  }
  let span : @scanner.Span = {
    start,
    end: { ..start, column: start.column + 1, offset: start.offset + 1, },
  }
  {
    code: "KR-ATTR-001",
    severity: Warning,
    message: "Malformed doc attribute: \{reason}",
    span,
    title: "MALFORMED ATTRIBUTE",
    report: [
      plain("I could not read this attribute:"),
      Excerpt(context=point(start), highlight=point(start)),
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
    return Err(malformed(first, "`@\{name}` is not a valid attribute name."))
  }
  let name_node : @ast.Node[String] = {
    range: range_at(first.line, first.column + 1, name.length()),
    value: name,
  }
  let last = raw.lines[raw.lines.length() - 1]
  let range : @ast.Range = {
    start: { row: first.line, column: first.column, },
    end: { row: last.line, column: last.column + last.text.length(), },
  }
  let rest = [text.unsafe_substring(start=name_end, end=text.length())]
  for line in raw.lines[1:] {
    rest.push(line.text)
  }
  let body = rest.join("\n")
  if name == "docs" {
    let names : Array[@ast.Node[String]] = []
    for li, line_text in rest {
      let line = raw.lines[li]
      let base = if li == 0 { first.column + name_end } else { line.column }
      let mut index = 0
      for piece in line_text.split(",") {
        let piece = piece.to_owned()
        let trimmed = piece.trim().to_owned()
        if trimmed != "" {
          let lead = piece.length() - piece.trim_start().length()
          names.push({
            range: range_at(line.line, base + index + lead, trimmed.length()),
            value: trimmed,
          })
        }
        index += piece.length() + 1
      }
    }
    return Ok(Docs(names~, range~))
  }
  let source = @scanner.SourceText::{ module_name: None, text: body, }
  guard @scanner.lex_raw(source, dialect~) is Ok(raw_tokens) else {
    return Err(malformed(first, "I could not read the values of `@\{name}`."))
  }
  let tokens = @scanner.normalize_tokens(raw_tokens).tokens.map(t => {
    shift_token(t, first, name_end)
  })
  let c = Cursor::new(tokens, dialect)
  let arguments = []
  while !c.at_end() {
    let argument = sub_expression(c) catch {
      SyntaxError(_, _, _) =>
        return Err(
          malformed(first, "I could not read the values of `@\{name}`."),
        )
    }
    if !is_data(argument.value) {
      return Err(
        malformed(first, "The values of `@\{name}` must be Elm data, not code."),
      )
    }
    arguments.push(argument)
  }
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
    match parse_attribute(raw, dialect) {
      Ok(a) => attributes.push(a)
      Err(w) => warnings.push(w)
    }
  }
  (attributes, warnings)
}

///|
fn encode_attribute(a : DocAttribute) -> Json {
  match a {
    Attribute(name~, arguments~, range~) =>
      {
        "name": @ast.encode_node(name, n => n.to_json()),
        "arguments": Json::array(
          arguments.map(arg => @ast.encode_node(arg, @ast.encode_expression)),
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
  Json::array(
    groups.map(g => {
      "target": match g.target {
        Module => "module".to_json()
        Declaration(name~, range~) =>
          { "declaration": name.to_json(), "range": @ast.encode_range(range) }
      },
      "attributes": Json::array(g.attributes.map(encode_attribute)),
    }),
  )
}
