///|
/// The excerpt lines of a rendered report: each gutter label (`  9| `,
/// `  9|>`, also a negative or malformed number, which a law must reject) and
/// the text after its `|`. Lines whose text before the first `|` is not a
/// number are not excerpt lines.
pub fn excerpt_lines(rendered : String) -> Array[(Int, String)] {
  let out = []
  for line in rendered.split("\n") {
    let line = line.trim_start()
    guard line.find("|") is Some(bar) && bar > 0 else { continue }
    let label = line.view(end_offset=bar)
    let (negative, digits) = if label.has_prefix("-") {
      (true, label.view(start_offset=1))
    } else {
      (false, label)
    }
    if digits.is_empty() || !digits.iter().all(c => c >= '0' && c <= '9') {
      continue
    }
    let n = digits
      .iter()
      .fold(init=0, (n, c) => n * 10 + (c.to_int() - '0'.to_int()))
    out.push(
      (
        if negative {
          -n
        } else {
          n
        },
        line.view(start_offset=bar + 1).to_owned(),
      ),
    )
  }
  out
}

///|
/// The lines of `text` as a report shows them: split at `\n`, without the
/// `\r` of a CRLF. A final line break starts an empty last line, which is a
/// real position (a diagnostic at the end of the text is on it).
pub fn source_lines(text : String) -> Array[String] {
  text
  .split("\n")
  .map(line => {
    if line.has_suffix("\r") {
      line.view(end_offset=line.length() - 1).to_owned()
    } else {
      line.to_owned()
    }
  })
  .collect()
}

///|
/// The number of lines of `text` (see `source_lines`).
pub fn line_count(text : String) -> Int {
  text.split("\n").count()
}

///|
/// Whether the excerpts of `rendered` number exactly the lines `expected`, in
/// order, each between 1 and the line count of `text`, and each shows that
/// source line (after `| `, `|> ` or `|  `), without its line end.
pub fn shows_source(
  text : String,
  rendered : String,
  expected : Array[Int],
) -> Bool {
  let lines = source_lines(text)
  let found = excerpt_lines(rendered)
  found.map(f => f.0) == expected &&
  found
  .iter()
  .all(f => {
    let (n, rest) = f
    n >= 1 &&
    n <= lines.length() &&
    (
      rest == " " + lines[n - 1] ||
      rest == "> " + lines[n - 1] ||
      rest == "  " + lines[n - 1]
    )
  })
}

///|
/// `s` without ANSI style sequences (`ESC [ … m`).
pub fn strip_ansi(s : String) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < s.length() {
    if s.code_unit_at(i).to_int() == 0x1B &&
      i + 1 < s.length() &&
      s.code_unit_at(i + 1) == '[' {
      i += 2
      while i < s.length() && s.code_unit_at(i) != 'm' {
        i += 1
      }
      i += 1
    } else {
      sb.write_char(Int::unsafe_to_char(s.code_unit_at(i).to_int()))
      i += 1
    }
  }
  sb.to_string()
}

///|
/// Whether `r` is a range of positions in `text`, in order.
pub fn range_in_source(text : String, r : @ast.Range) -> Bool {
  at_or_before(r.start, r.end) &&
  offset_of(text, r.start) is Some(_) &&
  offset_of(text, r.end) is Some(_)
}

///|
/// The problems of an `elm make --report=json` report, in order: each one's
/// region (`None` when a coordinate is missing or not a whole number) and its
/// message as plain text (styled chunks flattened). `None` when the report
/// does not have that shape.
pub fn elm_json_problems(report : Json) -> Array[(@ast.Range?, String)]? {
  let whole = (j : Json) => {
    match j {
      Number(d, ..) if d.to_int().to_double() == d => Some(d.to_int())
      _ => None
    }
  }
  let location = (j : Json) => {
    match j {
      { "line": line, "column": column, .. } =>
        match (whole(line), whole(column)) {
          (Some(row), Some(column)) => Some(({ row, column, } : @ast.Location))
          _ => None
        }
      _ => None
    }
  }
  let message = (j : Json) => {
    let sb = StringBuilder()
    if j is Array(parts) {
      for p in parts {
        match p {
          String(s) => sb.write_string(s)
          { "string": String(s), .. } => sb.write_string(s)
          _ => ()
        }
      }
    }
    sb.to_string()
  }
  guard report is { "errors": Array(errors), .. } else { return None }
  let out = []
  for e in errors {
    guard e is { "problems": Array(problems), .. } else { return None }
    for p in problems {
      guard p
        is { "region": { "start": start, "end": end, .. }, "message": m, .. } else {
        return None
      }
      let region = match (location(start), location(end)) {
        (Some(a), Some(b)) => Some(({ start: a, end: b, } : @ast.Range))
        _ => None
      }
      out.push((region, message(m)))
    }
  }
  Some(out)
}
