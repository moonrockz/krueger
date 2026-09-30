///|
/// Rendered krueger messages for rejected fixtures, and the side-by-side
/// report of krueger's and elm make's messages.

///|
let messages_dir : String = "tests/rejection/messages"

///|
let reports_dir : String = "_build/reports/rejection"

///|
/// The path fixtures are compiled as, used in rendered headers.
let fixture_path : String = "src/Fixture.elm"

///|
fn fixture_source(text : String) -> @krueger.SourceText {
  { module_name: Some("Fixture"), text, }
}

///|
/// krueger's first error for `text` in `dialect`, if it rejects it.
fn first_error(
  text : String,
  dialect : @krueger.Dialect,
) -> @krueger.Diagnostic? {
  @krueger.parse_module(fixture_source(text), dialect~).diagnostics
  .iter()
  .find_first(d => d.severity is Error)
}

///|
/// A title mismatch for a fixture that both elm make and krueger (in
/// `elm-0.19.1`) reject. A fixture krueger accepts has a verdict mismatch,
/// not a title mismatch.
fn title_mismatch(fixture : String, text : String, elm : Json) -> Pending? {
  guard elm is Object(v) &&
    v.get("accepted") is Some(False) &&
    v.get("title") is Some(String(title)) else {
    return None
  }
  match first_error(text, @krueger.Dialect::elm_0_19_1()) {
    Some(d) if d.title != title =>
      Some({ fixture, dialect: "elm-0.19.1", check: "title", })
    _ => None
  }
}

///|
/// `tests/rejection/messages/<fixture without .elm>.txt`.
fn snapshot_path(fixture : String) -> String {
  let stem = if fixture.has_suffix(".elm") {
    fixture.unsafe_substring(start=0, end=fixture.length() - 4)
  } else {
    fixture
  }
  "\{messages_dir}/\{stem}.txt"
}

///|
/// An elm make message array as plain text.
fn elm_message_text(message : Json) -> String {
  guard message is Array(parts) else { return "" }
  let sb = StringBuilder()
  for part in parts {
    match part {
      String(s) => sb.write_string(s)
      Object(o) if o.get("string") is Some(String(s)) => sb.write_string(s)
      _ => ()
    }
  }
  sb.to_string()
}

///|
/// One row of the side-by-side report.
priv struct ReportRow {
  fixture : String
  elm_title : String
  elm_message : String
  krueger_title : String
  krueger_message : String
  elm_accepted : Bool
  krueger_accepted : Bool
}

///|
fn html_escape(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
}

///|
fn verdict_word(accepted : Bool) -> String {
  if accepted {
    "accepts"
  } else {
    "rejects"
  }
}

///|
/// The side-by-side HTML report: per fixture, elm make's and krueger's
/// verdicts, titles and messages.
fn report_html(rows : Array[ReportRow]) -> String {
  let sb = StringBuilder()
  sb.write_string(
    (
      #|<!doctype html>
      #|<html lang="en"><head><meta charset="utf-8">
      #|<meta name="viewport" content="width=device-width, initial-scale=1">
      #|<title>Rejection parity</title>
      #|<style>
      #|body{font-family:system-ui,sans-serif;margin:16px;background:#fff;color:#111}
      #|table{border-collapse:collapse;width:100%}
      #|td,th{border:1px solid #ccc;padding:6px;vertical-align:top;text-align:left}
      #|pre{white-space:pre-wrap;margin:0;font-size:12px}
      #|.same{background:#e8f7e8}.diff{background:#fdecea}
      #|@media (prefers-color-scheme: dark){body{background:#111;color:#eee}td,th{border-color:#444}.same{background:#123312}.diff{background:#3a1616}}
      #|</style></head><body>
      #|<h1>Rejection parity: elm make 0.19.1 and krueger (elm-0.19.1)</h1>
      #|<table><thead><tr><th>Fixture</th><th>elm make</th><th>krueger</th></tr></thead><tbody>
      #|
    ),
  )
  for row in rows {
    let same = row.elm_accepted == row.krueger_accepted &&
      row.elm_title == row.krueger_title
    let class = if same { "same" } else { "diff" }
    sb.write_string(
      "<tr class=\"\{class}\"><td>\{html_escape(row.fixture)}</td>" +
      "<td><b>\{verdict_word(row.elm_accepted)} \{html_escape(row.elm_title)}</b><pre>\{html_escape(row.elm_message)}</pre></td>" +
      "<td><b>\{verdict_word(row.krueger_accepted)} \{html_escape(row.krueger_title)}</b><pre>\{html_escape(row.krueger_message)}</pre></td></tr>\n",
    )
  }
  sb.write_string("</tbody></table></body></html>\n")
  sb.to_string()
}

///|
/// Create `path` and its parents (like `mkdir -p`).
fn ensure_dir(path : String) -> Unit raise {
  let mut prefix = ""
  for part in path.split("/") {
    prefix = if prefix == "" { part.to_owned() } else { "\{prefix}/\{part}" }
    if !@fs.path_exists(prefix) {
      @fs.create_dir(prefix)
    }
  }
}

///|
fn parent_dir(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path.unsafe_substring(start=0, end=i)
    None => "."
  }
}

///|
/// Report rows and krueger's rendered messages (by snapshot path) for every
/// fixture.
fn report_rows(
  verdicts : Json,
  read : (String) -> String raise,
) -> (Array[ReportRow], Map[String, String]) raise {
  guard verdicts is Object(entries) else { return ([], Map([])) }
  let rows = []
  let messages : Map[String, String] = Map([])
  for fixture, entry in entries {
    guard entry is Object(e) && e.get("elm-0.19.1") is Some(Object(v)) else {
      continue
    }
    let text = read(fixture)
    let error = first_error(text, @krueger.Dialect::elm_0_19_1())
    let krueger_message = match error {
      Some(d) => {
        let rendered = @krueger.render_plain(
          d,
          fixture_source(text),
          fixture_path,
        )
        messages[snapshot_path(fixture)] = rendered
        rendered
      }
      None => ""
    }
    rows.push({
      fixture,
      elm_title: match v.get("title") {
        Some(String(t)) => t
        _ => ""
      },
      elm_message: match v.get("message") {
        Some(m) => elm_message_text(m)
        None => ""
      },
      krueger_title: error.map(d => d.title).unwrap_or(""),
      krueger_message,
      elm_accepted: v.get("accepted") is Some(True),
      krueger_accepted: error is None,
    })
  }
  (rows, messages)
}

///|
/// Snapshot files under `messages/`, as paths.
fn snapshot_files() -> Array[String] raise {
  if !@fs.path_exists(messages_dir) {
    return []
  }
  let found = []
  fn go(dir : String) raise {
    for entry in @fs.read_dir(dir) {
      let path = "\{dir}/\{entry}"
      if @fs.is_dir(path) {
        go(path)
      } else if path.has_suffix(".txt") {
        found.push(path)
      }
    }
  }

  go(messages_dir)
  found
}

///|
/// Compare krueger's rendered messages with the snapshots. With `approve`,
/// write them (and remove stale snapshots) instead. Returns the problems.
fn check_snapshots(
  messages : Map[String, String],
  approve : Bool,
) -> Array[String] raise {
  let problems = []
  for path in snapshot_files() {
    if !messages.contains(path) {
      if approve {
        @fs.remove_file(path)
      } else {
        problems.push("stale snapshot (fixture no longer rejected): \{path}")
      }
    }
  }
  for path, rendered in messages {
    let current = if @fs.path_exists(path) {
      Some(@fs.read_file_to_string(path))
    } else {
      None
    }
    if current == Some(rendered) {
      continue
    }
    if approve {
      ensure_dir(parent_dir(path))
      @fs.write_string_to_file(path, rendered)
    } else if current is None {
      problems.push("missing snapshot: \{path}")
    } else {
      problems.push("message changed: \{path}")
    }
  }
  if !problems.is_empty() {
    problems.push(
      "review the messages, then run KRUEGER_REJECTION_MODE=approve mise run test:rejection",
    )
  }
  problems
}
