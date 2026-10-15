///|
fn location_json(p : @scanner.Position) -> Json {
  { "line": Json(p.line), "column": Json(p.column) }
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
          parts.push(Json(plain.to_string()))
          plain.reset()
        }
        parts.push({
          "bold": Json(bold),
          "underline": Json(underline),
          "color": match color {
            Some(c) => Json(c.json_name())
            None => Json::null()
          },
          "string": Json(text),
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
    parts.push(Json(rest))
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
///
/// The result is `{"type": "compile-errors", "errors": [...]}`, with one
/// entry for the file when it has errors and none otherwise. The entry's
/// `name` is `source.module_name` (default `Main`). Each problem has the
/// title, the region of the problem and the message as `elm make` chunks.
///
/// ```mbt check
/// test {
///   let source = @scanner.SourceText::new(
///     "module Main exposing (..)\n\nmain =\n    (1 + 2\n",
///     module_name="Main",
///   )
///   let result = @parser.parse_module(source, @scanner.DefaultScanner::new())
///   let json = @report.render_elm_json(result.diagnostics, source, "src/Main.elm")
///   guard json is { "errors": [{ "problems": [problem], .. }], .. } else {
///     fail("unexpected shape")
///   }
///   guard problem is { "title": String(title), "region": region, .. } else {
///     fail("unexpected problem")
///   }
///   inspect(title, content="UNFINISHED PARENTHESES")
///   inspect(
///     region.stringify(),
///     content=(
///       #|{"start":{"line":4,"column":11},"end":{"line":4,"column":11}}
///     ),
///   )
/// }
/// ```
pub fn render_elm_json(
  diags : Array[@scanner.Diagnostic],
  source : @scanner.SourceText,
  path : String,
) -> Json {
  let problems : Array[Json] = diags
    .filter(d => d.severity is Error)
    .map(d => {
      "title": Json(d.title),
      "region": span_json(region(d)),
      "message": message_json(d, source),
    })
  let errors : Array[Json] = if problems.is_empty() {
    []
  } else {
    [
      {
        "path": Json(path),
        "name": Json(source.module_name.unwrap_or("Main")),
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
///
/// Each diagnostic is an object with `code`, `severity` (`error`,
/// `warning` or `info`), `title`, `message` and `span`, and `detail` when
/// the diagnostic has one (`KR-PARSE-010`:
/// `{"outOfFuel": {"fuel": 1200, "walk": "nesting"}}`). The long report is
/// not included; use `render_plain` or `render_elm_json` for it.
///
/// ```mbt check
/// test {
///   let source = @scanner.SourceText::new(
///     "module Main exposing (..)\n\nmain =\n    (1 + 2\n",
///   )
///   let result = @parser.parse_module(source, @scanner.DefaultScanner::new())
///   let json = @report.encode_diagnostics(result.diagnostics)
///   inspect(
///     json.stringify(),
///     content=(
///       #|[{"code":"KR-PARSE-004","severity":"error","title":"UNFINISHED PARENTHESES","message":"Malformed function declaration: expected `,` or `)`, found end of input","span":{"start":{"line":4,"column":11},"end":{"line":4,"column":11}}}]
///     ),
///   )
/// }
/// ```
pub fn encode_diagnostics(diags : Array[@scanner.Diagnostic]) -> Json {
  Json::array(
    diags.map(d => {
      let fields : Map[String, Json] = {
        "code": Json(d.code),
        "severity": Json(severity_name(d.severity)),
        "title": Json(d.title),
        "message": Json(d.message),
        "span": span_json(d.span),
      }
      match d.detail {
        Some(OutOfFuel(fuel~, walk~)) =>
          fields["detail"] = {
            "outOfFuel": {
              "fuel": Json::number(fuel.to_double()),
              "walk": Json(
                match walk {
                  Nesting => "nesting"
                  Chain => "chain"
                },
              ),
            },
          }
        None => ()
      }
      Json::object(fields)
    }),
  )
}
