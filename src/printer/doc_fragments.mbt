///|
/// A token-based repair of fragments, without touching strings or comments.
/// Tuple functions have no elm-syntax AST case. A fresh name carries one
/// through the printer and is restored after layout.
fn prepare_code(
  code : String,
  dialect : @dialect.Dialect,
) -> (String, Array[(String, String)]) {
  guard @scanner.DefaultScanner::new(dialect~).tokenize(
      @scanner.SourceText::new(code),
    )
    is Ok(stream) else {
    return (code, [])
  }
  let stem = fresh_code_name(code, "tuple__")
  let replacements : Array[(String, String)] = []
  let out = StringBuilder()
  let mut copied = 0
  let mut i = 0
  while i < stream.tokens.length() {
    let t = stream.tokens[i]
    if t.span.start.column == 1 && t.kind is (LParen | LBracket | LBrace) {
      let mut j = i
      let mut depth = 0
      while j < stream.tokens.length() {
        if j > i && depth == 0 && stream.tokens[j].span.start.column == 1 {
          break
        }
        match stream.tokens[j].kind {
          LParen | LBracket | LBrace => depth += 1
          RParen | RBracket | RBrace => depth -= 1
          Equals if depth == 0 => break
          _ => ()
        }
        j += 1
      }
      if stream.tokens.get(j) is Some({ kind: Equals, .. }) &&
        j > i &&
        stream.tokens[i:j]
        .iter()
        .all(t => {
          t.trivia_before.iter().all(v => !(v is Comment(_))) &&
          t.trivia_after.iter().all(v => !(v is Comment(_)))
        }) {
        let end = stream.tokens[j - 1].span.end.offset
        let pattern = code
          .view(start_offset=t.span.start.offset, end_offset=end)
          .to_owned()
        if code_pattern(pattern, dialect) is Some(pattern) {
          let name = stem + "pattern" + i.to_string() + "__"
          out.write_string(
            code
            .view(start_offset=copied, end_offset=t.span.start.offset)
            .to_owned(),
          )
          out.write_string(name)
          copied = end
          replacements.push((name, pattern))
          i = j
          continue
        }
      }
    }
    if t.kind is LParen {
      let mut j = i + 1
      while stream.tokens.get(j) is Some({ kind: Comma, .. }) {
        j += 1
      }
      if j > i + 1 &&
        stream.tokens.get(j) is Some({ kind: RParen, .. } as close) &&
        stream.tokens[i:j + 1]
        .iter()
        .all(t => {
          t.trivia_before.iter().all(v => !(v is Comment(_))) &&
          t.trivia_after.iter().all(v => !(v is Comment(_)))
        }) {
        let name = stem + (j - i).to_string() + "__"
        out.write_string(
          code
          .view(start_offset=copied, end_offset=t.span.start.offset)
          .to_owned(),
        )
        out.write_string(name)
        copied = close.span.end.offset
        replacements.push((name, "(" + ",".repeat(j - i - 1) + ")"))
        i = j + 1
        continue
      }
    }
    // elm-format accepts a negative literal touching the opening bracket.
    if t.kind is Operator("-") &&
      i > 0 &&
      stream.tokens[i - 1].kind is LBracket &&
      stream.tokens[i - 1].span.end.offset == t.span.start.offset {
      out.write_string(
        code
        .view(start_offset=copied, end_offset=t.span.start.offset)
        .to_owned(),
      )
      out.write_string(" ")
      copied = t.span.start.offset
    }
    if t.kind is Operator("-") &&
      i > 0 &&
      t.span.start.column == 1 &&
      stream.tokens.get(i + 1) is Some(next) &&
      next.span.start.offset == t.span.end.offset {
      out.write_string(
        code.view(start_offset=copied, end_offset=t.span.end.offset).to_owned(),
      )
      out.write_string(" ")
      copied = t.span.end.offset
    }
    i += 1
  }
  out.write_string(code.view(start_offset=copied).to_owned())
  (out.to_string(), replacements)
}

///|
fn fresh_code_name(code : String, stem : String) -> String {
  let mut name = stem
  while code.contains(name) {
    name += "_"
  }
  name
}

///|
/// Give an orphan annotation a temporary implementation. After formatting,
/// its last two rows are removed. A token in column one ends the type;
/// a matching implementation already there is left alone.
fn complete_annotations(
  code : String,
  dialect : @dialect.Dialect,
) -> (String, String) {
  let marker = fresh_code_name(code, "annotation__")
  guard @scanner.DefaultScanner::new(dialect~).tokenize(
      @scanner.SourceText::new(code),
    )
    is Ok(stream) else {
    return (code, marker)
  }
  let tokens = stream.tokens
  let out = StringBuilder()
  let mut copied = 0
  for i, t in tokens {
    guard t.span.start.column == 1 &&
      t.kind is Identifier &&
      tokens.get(i + 1) is Some({ kind: Colon, .. }) else {
      continue
    }
    let mut next = i + 2
    while next < tokens.length() && tokens[next].span.start.column > 1 {
      next += 1
    }
    guard next > i + 2 else { continue }
    guard !(tokens.get(next) is Some(n) &&
      n.lexeme == t.lexeme &&
      !(tokens.get(next + 1) is Some({ kind: Colon, .. }))) else {
      continue
    }
    let end = tokens[next - 1].span.end.offset
    out.write_string(code.view(start_offset=copied, end_offset=end).to_owned())
    out.write_string("\n" + t.lexeme + " = " + marker + "\n")
    copied = end
  }
  out.write_string(code.view(start_offset=copied).to_owned())
  (out.to_string(), marker)
}

///|
/// Parse a documentation-only top-level destructuring pattern in a let,
/// where elm-syntax permits it, then print it with the pattern printer.
fn code_pattern(pattern : String, dialect : @dialect.Dialect) -> String? {
  let source = code_header +
    "f =\n    let\n        " +
    pattern.replace_all(old="\n", new="\n        ") +
    " = 0\n    in\n        0\n"
  let result = @parser.parse_module(
    @scanner.SourceText::new(source),
    @scanner.DefaultScanner::new(dialect~),
    dialect~,
  )
  guard result.diagnostics.iter().all(d => !(d.severity is Error)) &&
    result.ast is Some(file) &&
    file.declarations is [{ value: FunctionDeclaration(f), .. }] &&
    f.declaration.value.expression.value is LetExpression(body) &&
    body.declarations is [{ value: LetDestructuring(p, _), .. }] else {
    return None
  }
  Some(print_pattern(p, dialect~)) catch {
    _ => None
  }
}

///|
/// elm-format still reads backtick infix functions in documentation. Scan a
/// same-length mask to find names between backticks outside literals and
/// comments, carry them as fresh operators, then restore their spelling.
fn prepare_infix_functions(
  code : String,
  dialect : @dialect.Dialect,
) -> (String, @dialect.Dialect, Array[(String, String)]) {
  guard code.contains("`") else { return (code, dialect, []) }
  let masked = code.replace_all(old="`", new=" ")
  guard @scanner.DefaultScanner::new(dialect~).tokenize(
      @scanner.SourceText::new(masked),
    )
    is Ok(stream) else {
    return (code, dialect, [])
  }
  let out = StringBuilder()
  let restored = []
  let operators = [..dialect.operators]
  let symbols = [..dialect.operator_symbols]
  let mut copied = 0
  for token in stream.tokens {
    let start = token.span.start.offset
    let end = token.span.end.offset
    guard token.kind is Identifier &&
      is_name(token.lexeme, @scanner.is_lower_start) &&
      start > copied &&
      end < code.length() &&
      code.code_unit_at(start - 1).to_int() == 0x60 &&
      code.code_unit_at(end).to_int() == 0x60 else {
      continue
    }
    let mut count = 1
    let mut symbol = "<?>"
    while code.contains(symbol) || symbols.contains(symbol) {
      count += 1
      symbol = "<" + "?".repeat(count) + ">"
    }
    out.write_string(
      code.view(start_offset=copied, end_offset=start - 1).to_owned(),
    )
    out.write_string(symbol)
    copied = end + 1
    symbols.push(symbol)
    operators.push({ symbol, precedence: 9, direction: Left, })
    restored.push((symbol, "`" + token.lexeme + "`"))
  }
  out.write_string(code.view(start_offset=copied).to_owned())
  (
    out.to_string(),
    { ..dialect, operators, operator_symbols: symbols, },
    restored,
  )
}

///|
/// Remove the temporary implementation of an orphan annotation, retaining
/// its formatted signature and any separate comment items.
fn annotation_rows(rows : Array[String], marker : String) -> Array[String] {
  if rows.last() == Some("    " + marker) && rows.length() >= 2 {
    rows[:rows.length() - 2].to_owned()
  } else {
    rows
  }
}
