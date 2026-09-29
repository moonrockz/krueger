///|
/// First diagnostic krueger reported for a corpus file.
priv struct DiagnosticInfo {
  code : String
  message : String
  line : Int
  column : Int
}

///|
/// Parity result for one corpus file.
priv struct FileReport {
  key : String
  tokenized : Bool
  parsed : Bool
  matched : Bool
  diagnostic : DiagnosticInfo?
  /// Path of the first difference from the elm-syntax JSON, when known.
  difference : String?
}

///|
/// Everything the parity reports show.
priv struct ParityReport {
  commit : String?
  counts : Counts
  baseline : Counts?
  regressions : Array[String]
  files : Array[FileReport]
}

///|
fn parity_report(
  files : Array[FileReport],
  baseline : Counts?,
  commit? : String? = None,
) -> ParityReport {
  let counts = {
    files: files.length(),
    tokenized: files.filter(f => f.tokenized).length(),
    parsed: files.filter(f => f.parsed).length(),
    matched: files.filter(f => f.matched).length(),
  }
  let regressions = match baseline {
    Some(b) => regressions(counts, b)
    None => []
  }
  { commit, counts, baseline, regressions, files, }
}

///|
/// Package part of a corpus key (`author/name@version`).
fn package_of(key : String) -> String {
  match key.find("@") {
    Some(at) =>
      match key.unsafe_substring(start=at, end=key.length()).find("/") {
        Some(slash) => key.unsafe_substring(start=0, end=at + slash)
        None => key
      }
    None => key
  }
}

///|
/// File part of a corpus key (`src/...`).
fn path_of(key : String) -> String {
  let pkg = package_of(key)
  if pkg.length() < key.length() {
    key.unsafe_substring(start=pkg.length() + 1, end=key.length())
  } else {
    key
  }
}

///|
/// `matched`, `parsed` (AST with no diagnostics, but not equal), or `failing`.
fn status_of(f : FileReport) -> String {
  if f.matched {
    "matched"
  } else if f.parsed {
    "parsed"
  } else {
    "failing"
  }
}

///|
/// Why a file does not match, or `None` when it matches.
fn reason_of(f : FileReport) -> String? {
  if f.matched {
    return None
  }
  match (f.diagnostic, f.difference) {
    (Some(d), _) => Some("\{d.code} at \{d.line}:\{d.column}: \{d.message}")
    (None, Some(path)) => Some("differs from elm-syntax at \{path}")
    (None, None) =>
      Some(if f.parsed { "AST differs from elm-syntax" } else { "no AST" })
  }
}

///|
/// Files grouped by package, in first-seen order.
fn by_package(files : Array[FileReport]) -> Array[(String, Array[FileReport])] {
  let groups : Map[String, Array[FileReport]] = Map([])
  for f in files {
    let pkg = package_of(f.key)
    match groups.get(pkg) {
      Some(list) => list.push(f)
      None => groups[pkg] = [f]
    }
  }
  groups.to_array()
}

///|
fn delta(now : Int, before : Int) -> String {
  let d = now - before
  if d > 0 {
    "+\{d}"
  } else {
    d.to_string()
  }
}

///|
fn counts_delta(now : Counts, before : Counts) -> Counts {
  {
    files: now.files - before.files,
    tokenized: now.tokenized - before.tokenized,
    parsed: now.parsed - before.parsed,
    matched: now.matched - before.matched,
  }
}

///|
/// Diagnostic codes by number of files, most common first.
fn top_diagnostics(files : Array[FileReport]) -> Array[(String, Int)] {
  let counts : Map[String, Int] = Map([])
  for f in files {
    if f.diagnostic is Some(d) {
      counts[d.code] = counts.get(d.code).unwrap_or(0) + 1
    }
  }
  let list = counts.to_array()
  list.sort_by((a, b) => {
    let by_count = b.1.compare(a.1)
    if by_count != 0 {
      by_count
    } else {
      compare_lexical(a.0, b.0)
    }
  })
  list
}

///|
fn optional_string(value : String?) -> Json {
  match value {
    Some(s) => s.to_json()
    None => Json::null()
  }
}

///|
/// JSON report: counts, baseline, delta, regressions and every file.
fn report_json(r : ParityReport) -> Json {
  let files = r.files.map(f => {
    let diagnostic : Json = match f.diagnostic {
      Some(d) =>
        {
          "code": d.code.to_json(),
          "message": d.message.to_json(),
          "line": d.line.to_json(),
          "column": d.column.to_json(),
        }
      None => Json::null()
    }
    let file : Json = {
      "key": f.key.to_json(),
      "package": package_of(f.key).to_json(),
      "path": path_of(f.key).to_json(),
      "status": status_of(f).to_json(),
      "tokenized": f.tokenized.to_json(),
      "parsed": f.parsed.to_json(),
      "matched": f.matched.to_json(),
      "diagnostic": diagnostic,
      "difference": optional_string(f.difference),
    }
    file
  })
  {
    "commit": optional_string(r.commit),
    "counts": counts_to_json(r.counts),
    "baseline": match r.baseline {
      Some(b) => counts_to_json(b)
      None => Json::null()
    },
    "delta": match r.baseline {
      Some(b) => counts_to_json(counts_delta(r.counts, b))
      None => Json::null()
    },
    "regressions": Json::array(r.regressions.map(s => s.to_json())),
    "files": Json::array(files),
  }
}

///|
/// Escape text for XML and HTML attributes and content.
fn escape_markup(text : String) -> String {
  let sb = StringBuilder()
  for c in text {
    match c {
      '&' => sb.write_string("&amp;")
      '<' => sb.write_string("&lt;")
      '>' => sb.write_string("&gt;")
      '"' => sb.write_string("&quot;")
      '\'' => sb.write_string("&#39;")
      _ => sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
/// JUnit XML: one testsuite per package, one testcase per file. Files that do
/// not match yet are skipped (known gaps); only a baseline regression fails.
fn report_junit(r : ParityReport) -> String {
  let groups = by_package(r.files)
  let skipped = r.files.filter(f => !f.matched).length()
  let failures = if r.regressions.is_empty() { 0 } else { 1 }
  let sb = StringBuilder()
  sb.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
  sb.write_string(
    "<testsuites name=\"elm-parity\" tests=\"\{r.files.length() + 1}\" failures=\"\{failures}\" skipped=\"\{skipped}\">\n",
  )
  sb.write_string(
    "  <testsuite name=\"baseline\" tests=\"1\" failures=\"\{failures}\" skipped=\"0\">\n",
  )
  if r.regressions.is_empty() {
    sb.write_string(
      "    <testcase classname=\"baseline\" name=\"counts do not drop below the baseline\"/>\n",
    )
  } else {
    let message = escape_markup(r.regressions.join("; "))
    sb.write_string(
      "    <testcase classname=\"baseline\" name=\"counts do not drop below the baseline\">\n",
    )
    sb.write_string("      <failure message=\"\{message}\"/>\n")
    sb.write_string("    </testcase>\n")
  }
  sb.write_string("  </testsuite>\n")
  for group in groups {
    let (pkg, files) = group
    let pkg_skipped = files.filter(f => !f.matched).length()
    let name = escape_markup(pkg)
    sb.write_string(
      "  <testsuite name=\"\{name}\" tests=\"\{files.length()}\" failures=\"0\" skipped=\"\{pkg_skipped}\">\n",
    )
    for f in files {
      let path = escape_markup(path_of(f.key))
      match reason_of(f) {
        None =>
          sb.write_string(
            "    <testcase classname=\"\{name}\" name=\"\{path}\"/>\n",
          )
        Some(reason) => {
          sb.write_string(
            "    <testcase classname=\"\{name}\" name=\"\{path}\">\n",
          )
          sb.write_string(
            "      <skipped message=\"\{escape_markup(reason)}\"/>\n",
          )
          sb.write_string("    </testcase>\n")
        }
      }
    }
    sb.write_string("  </testsuite>\n")
  }
  sb.write_string("</testsuites>\n")
  sb.to_string()
}

///|
/// Markdown summary for the CI job summary.
fn report_markdown(r : ParityReport) -> String {
  let sb = StringBuilder()
  sb.write_string("## Elm parity\n\n")
  if r.commit is Some(sha) {
    sb.write_string("Commit `\{sha}` against elm-syntax 7.3.9.\n\n")
  }
  sb.write_string("| Count | Now | Baseline | Change |\n|---|---:|---:|---:|\n")
  let rows = [
    ("Files", r.counts.files, r.baseline.map(b => b.files)),
    ("Tokenized", r.counts.tokenized, r.baseline.map(b => b.tokenized)),
    ("Parsed", r.counts.parsed, r.baseline.map(b => b.parsed)),
    ("Matched", r.counts.matched, r.baseline.map(b => b.matched)),
  ]
  for row in rows {
    let (label, now, before) = row
    match before {
      Some(b) =>
        sb.write_string("| \{label} | \{now} | \{b} | \{delta(now, b)} |\n")
      None => sb.write_string("| \{label} | \{now} | – | – |\n")
    }
  }
  if !r.regressions.is_empty() {
    sb.write_string("\n**Regressions:** \{r.regressions.join("; ")}\n")
  }
  let top = top_diagnostics(r.files)
  if !top.is_empty() {
    sb.write_string(
      "\n### Most common diagnostics\n\n| Code | Files |\n|---|---:|\n",
    )
    for i, entry in top {
      if i >= 10 {
        break
      }
      sb.write_string("| \{entry.0} | \{entry.1} |\n")
    }
  }
  sb.write_string(
    "\nFull reports: `parity-report` artifact (HTML, JSON, JUnit XML).\n",
  )
  sb.to_string()
}

///|
let html_style : String =
  #|:root { --bg: #ffffff; --fg: #1f2328; --muted: #59636e; --line: #d1d9e0;
  #|  --card: #f6f8fa; --ok: #1a7f37; --warn: #9a6700; --bad: #cf222e; }
  #|@media (prefers-color-scheme: dark) { :root { --bg: #0d1117; --fg: #e6edf3;
  #|  --muted: #9198a1; --line: #3d444d; --card: #151b23; --ok: #3fb950;
  #|  --warn: #d29922; --bad: #f85149; } }
  #|* { box-sizing: border-box; }
  #|body { margin: 0; padding: 24px 16px; background: var(--bg); color: var(--fg);
  #|  font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  #|main { max-width: 1100px; margin: 0 auto; }
  #|h1 { font-size: 22px; margin: 0 0 4px; }
  #|.meta { color: var(--muted); margin: 0 0 20px; }
  #|.tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  #|  gap: 12px; margin-bottom: 20px; }
  #|.tile { background: var(--card); border: 1px solid var(--line); border-radius: 8px;
  #|  padding: 12px 14px; }
  #|.tile .label { color: var(--muted); font-size: 12px; text-transform: uppercase; }
  #|.tile .value { font-size: 26px; font-weight: 600; font-variant-numeric: tabular-nums; }
  #|.tile .delta { font-size: 12px; color: var(--muted); }
  #|.regressions { border: 1px solid var(--bad); color: var(--bad); border-radius: 8px;
  #|  padding: 10px 14px; margin-bottom: 20px; }
  #|.filters { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 12px; }
  #|.filters button { background: var(--card); color: var(--fg); border: 1px solid var(--line);
  #|  border-radius: 999px; padding: 4px 12px; cursor: pointer; font: inherit; }
  #|.filters button[aria-pressed="true"] { border-color: var(--fg); font-weight: 600; }
  #|.table-wrap { overflow-x: auto; }
  #|table { width: 100%; border-collapse: collapse; }
  #|th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid var(--line);
  #|  vertical-align: top; }
  #|tr.package td { background: var(--card); font-weight: 600; }
  #|td.reason { color: var(--muted); word-break: break-word; }
  #|.status { font-weight: 600; }
  #|.status.matched { color: var(--ok); }
  #|.status.parsed { color: var(--warn); }
  #|.status.failing { color: var(--bad); }
  #|.hidden { display: none; }

///|
let html_script : String =
  #|document.querySelectorAll('.filters button').forEach(function (button) {
  #|  button.addEventListener('click', function () {
  #|    var status = button.getAttribute('data-filter');
  #|    document.querySelectorAll('.filters button').forEach(function (b) {
  #|      b.setAttribute('aria-pressed', b === button ? 'true' : 'false');
  #|    });
  #|    document.querySelectorAll('tr.file').forEach(function (row) {
  #|      var show = status === 'all' || row.getAttribute('data-status') === status;
  #|      row.classList.toggle('hidden', !show);
  #|    });
  #|    document.querySelectorAll('tr.package').forEach(function (header) {
  #|      var pkg = header.getAttribute('data-package');
  #|      var visible = document.querySelectorAll(
  #|        'tr.file[data-package="' + pkg + '"]:not(.hidden)').length;
  #|      header.classList.toggle('hidden', visible === 0);
  #|    });
  #|    var any = document.querySelectorAll('tr.file:not(.hidden)').length > 0;
  #|    document.querySelector('tr.empty').classList.toggle('hidden', any);
  #|  });
  #|});

///|
/// Self-contained HTML report: count tiles, regressions, and a table of every
/// file grouped by package with a status filter.
fn report_html(r : ParityReport) -> String {
  let sb = StringBuilder()
  sb.write_string(
    "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>Elm parity</title>\n<link rel=\"icon\" href=\"data:,\">\n<style>\n",
  )
  sb.write_string(html_style)
  sb.write_string("\n</style>\n</head>\n<body>\n<main>\n<h1>Elm parity</h1>\n")
  let commit = match r.commit {
    Some(sha) => " · commit <code>\{escape_markup(sha)}</code>"
    None => ""
  }
  sb.write_string(
    "<p class=\"meta\">krueger against stil4m/elm-syntax 7.3.9\{commit}</p>\n<div class=\"tiles\">\n",
  )
  let tiles = [
    ("Files", r.counts.files, r.baseline.map(b => b.files)),
    ("Tokenized", r.counts.tokenized, r.baseline.map(b => b.tokenized)),
    ("Parsed", r.counts.parsed, r.baseline.map(b => b.parsed)),
    ("Matched", r.counts.matched, r.baseline.map(b => b.matched)),
  ]
  for tile in tiles {
    let (label, now, before) = tile
    let change = match before {
      Some(b) => "baseline \{b} (\{delta(now, b)})"
      None => "no baseline"
    }
    sb.write_string(
      "<div class=\"tile\"><div class=\"label\">\{label}</div><div class=\"value\">\{now}</div><div class=\"delta\">\{change}</div></div>\n",
    )
  }
  sb.write_string("</div>\n")
  if !r.regressions.is_empty() {
    sb.write_string(
      "<div class=\"regressions\">Regressions: \{escape_markup(r.regressions.join("; "))}</div>\n",
    )
  }
  sb.write_string(
    "<div class=\"filters\" role=\"group\" aria-label=\"Filter by status\">\n<button data-filter=\"all\" aria-pressed=\"true\">All</button>\n<button data-filter=\"matched\" aria-pressed=\"false\">Matched</button>\n<button data-filter=\"parsed\" aria-pressed=\"false\">Parsed</button>\n<button data-filter=\"failing\" aria-pressed=\"false\">Failing</button>\n</div>\n",
  )
  sb.write_string(
    "<div class=\"table-wrap\"><table>\n<thead><tr><th>File</th><th>Status</th><th>Reason</th></tr></thead>\n<tbody>\n",
  )
  for group in by_package(r.files) {
    let (pkg, files) = group
    let matched = files.filter(f => f.matched).length()
    sb.write_string(
      "<tr class=\"package\" data-package=\"\{escape_markup(pkg)}\"><td colspan=\"3\">\{escape_markup(pkg)} · \{matched}/\{files.length()} matched</td></tr>\n",
    )
    for f in files {
      let status = status_of(f)
      let reason = escape_markup(reason_of(f).unwrap_or(""))
      sb.write_string(
        "<tr class=\"file\" data-status=\"\{status}\" data-package=\"\{escape_markup(package_of(f.key))}\"><td>\{escape_markup(path_of(f.key))}</td><td class=\"status \{status}\">\{status}</td><td class=\"reason\">\{reason}</td></tr>\n",
      )
    }
  }
  sb.write_string(
    "<tr class=\"empty hidden\"><td colspan=\"3\">No files with this status.</td></tr>\n",
  )
  sb.write_string("</tbody>\n</table></div>\n</main>\n<script>\n")
  sb.write_string(html_script)
  sb.write_string("\n</script>\n</body>\n</html>\n")
  sb.to_string()
}
