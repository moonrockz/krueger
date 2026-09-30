///|
fn location_json(p : @scanner.Position) -> Json {
  { "line": p.line.to_json(), "column": p.column.to_json() }
}

///|
fn span_json(span : @scanner.Span) -> Json {
  { "start": location_json(span.start), "end": location_json(span.end) }
}

///|
/// The report as an `elm make` message array: plain text merged into strings,
/// styled chunks as objects. The final newline is dropped, as in `elm make`.
fn message_json(
  diag : @scanner.Diagnostic,
  source : @scanner.SourceText,
) -> Json {
  let parts : Array[Json] = []
  let plain = StringBuilder()
  for chunk in body(diag, source) {
    match chunk {
      Plain(text) => plain.write_string(text)
      Styled(text~, color~, bold~, underline~) => {
        if plain.to_string() != "" {
          parts.push(plain.to_string().to_json())
          plain.reset()
        }
        parts.push({
          "bold": bold.to_json(),
          "underline": underline.to_json(),
          "color": match color {
            Some(c) => c.json_name().to_json()
            None => Json::null()
          },
          "string": text.to_json(),
        })
      }
    }
  }
  let rest = plain.to_string()
  let rest = if rest.has_suffix("\n") {
    rest.unsafe_substring(start=0, end=rest.length() - 1)
  } else {
    rest
  }
  if rest != "" {
    parts.push(rest.to_json())
  }
  Json::array(parts)
}

///|
/// Where the problem is: the highlight of the report's first excerpt, as
/// `elm make` reports it, else the diagnostic's span.
fn region(d : @scanner.Diagnostic) -> @scanner.Span {
  for block in d.report {
    if block is Excerpt(highlight~, ..) {
      return highlight
    }
  }
  d.span
}

///|
/// Errors in `diags` in the shape of `elm make --report=json` output.
/// Warnings are left out: `elm make` has none.
pub fn render_elm_json(
  diags : Array[@scanner.Diagnostic],
  source : @scanner.SourceText,
  path : String,
) -> Json {
  let problems : Array[Json] = diags
    .filter(d => d.severity is Error)
    .map(d => {
      "title": d.title.to_json(),
      "region": span_json(region(d)),
      "message": message_json(d, source),
    })
  let errors : Array[Json] = if problems.is_empty() {
    []
  } else {
    [
      {
        "path": path.to_json(),
        "name": source.module_name.unwrap_or("Main").to_json(),
        "problems": Json::array(problems),
      },
    ]
  }
  { "type": "compile-errors", "errors": Json::array(errors) }
}

///|
fn severity_name(severity : @scanner.Severity) -> String {
  match severity {
    Error => "error"
    Warning => "warning"
    Info => "info"
  }
}

///|
/// All diagnostics (warnings too) with krueger's codes, as JSON.
pub fn encode_diagnostics(diags : Array[@scanner.Diagnostic]) -> Json {
  Json::array(
    diags.map(d => {
      "code": d.code.to_json(),
      "severity": severity_name(d.severity).to_json(),
      "title": d.title.to_json(),
      "message": d.message.to_json(),
      "span": span_json(d.span),
    }),
  )
}
