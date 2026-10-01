///|
/// Width of a report line, as in `elm make`.
let line_width : Int = 80

///|
fn code_points(text : String) -> Int {
  let mut n = 0
  for _ in text {
    n += 1
  }
  n
}

///|
fn chunk_text(chunk : @scanner.Chunk) -> String {
  match chunk {
    Plain(text) => text
    Styled(text~, ..) => text
  }
}

///|
/// A word for reflow: a run of chunks with no space between them, or a hard
/// line break.
priv enum Word {
  Chunks(Array[@scanner.Chunk])
  Break
}

///|
/// Split paragraph chunks into words. A styled chunk is never split; plain
/// text splits at spaces, and a newline is a hard break.
fn words(chunks : Array[@scanner.Chunk]) -> Array[Word] {
  let result = []
  let current : Array[@scanner.Chunk] = []
  let buffer = StringBuilder()
  fn flush_buffer() {
    let text = buffer.to_string()
    if text != "" {
      current.push(Plain(text))
      buffer.reset()
    }
  }

  fn flush_word() {
    flush_buffer()
    if !current.is_empty() {
      result.push(Chunks(current.copy()))
      current.clear()
    }
  }

  for chunk in chunks {
    match chunk {
      Plain(text) =>
        for c in text {
          match c {
            ' ' => flush_word()
            '\n' => {
              flush_word()
              result.push(Break)
            }
            _ => buffer.write_char(c)
          }
        }
      styled => {
        flush_buffer()
        current.push(styled)
      }
    }
  }
  flush_word()
  result
}

///|
/// Reflow a paragraph to `line_width` columns.
fn reflow(chunks : Array[@scanner.Chunk]) -> Array[@scanner.Chunk] {
  let out : Array[@scanner.Chunk] = []
  let mut column = 0
  for word in words(chunks) {
    match word {
      Break => {
        out.push(Plain("\n"))
        column = 0
      }
      Chunks(parts) => {
        let width = parts.fold(init=0, (n, p) => n + code_points(chunk_text(p)))
        if column > 0 && column + 1 + width > line_width {
          out.push(Plain("\n"))
          column = 0
        } else if column > 0 {
          out.push(Plain(" "))
          column += 1
        }
        out.append(parts)
        column += width
      }
    }
  }
  out
}

///|
fn label(name : String) -> @scanner.Chunk {
  Styled(text=name, color=None, bold=false, underline=true)
}

///|
/// The report body as chunks, blocks separated like `elm make` output: a blank
/// line between blocks, but a caret line runs straight into the next block.
fn body(
  diag : @scanner.Diagnostic,
  source : @scanner.SourceText,
) -> Array[@scanner.Chunk] {
  let out : Array[@scanner.Chunk] = []
  let mut after_caret = false
  for i, block in diag.report {
    if i > 0 && !after_caret {
      out.push(Plain("\n"))
    }
    after_caret = false
    match block {
      Text(chunks) => {
        out.append(reflow(chunks))
        out.push(Plain("\n"))
      }
      Hint(chunks) => {
        out.append(reflow([label("Hint"), Plain(": "), ..chunks]))
        out.push(Plain("\n"))
      }
      Note(chunks) => {
        out.append(reflow([label("Note"), Plain(": "), ..chunks]))
        out.push(Plain("\n"))
      }
      Example(code) =>
        for line in code.split("\n") {
          let line = line.to_owned()
          out.push(Plain(if line == "" { "\n" } else { "    " + line + "\n" }))
        }
      Excerpt(context~, highlight~) => {
        let (chunks, caret) = excerpt_chunks(source, context, highlight)
        out.append(chunks)
        after_caret = caret
      }
    }
  }
  out
}

///|
fn header(title : String, path : String) -> String {
  let dashes = @cmp.maximum(1, line_width - 5 - title.length() - path.length())
  "-- " + title + " " + "-".repeat(dashes) + " " + path
}

///|
/// A diagnostic as plain text, laid out like `elm make` output.
///
/// The text starts with a `-- TITLE ---- path` header. The report follows,
/// reflowed to 80 columns, with numbered source lines from `source` and `^`
/// markers under the problem. `path` is only shown in the header.
///
/// ```mbt check
/// test {
///   let source = @scanner.SourceText::new(
///     "module Main exposing (..)\n\nmain =\n    (1 + 2\n",
///   )
///   let result = @parser.parse_module(source, @scanner.DefaultScanner::new())
///   let text = @report.render_plain(result.diagnostics[0], source, "src/Main.elm")
///   inspect(
///     text,
///     content=(
///       #|-- UNFINISHED PARENTHESES ----------------------------------------- src/Main.elm
///       #|
///       #|I was partway through parsing an expression in parentheses, but I got stuck
///       #|here:
///       #|
///       #|4|     (1 + 2
///       #|             ^
///       #|I was expecting to see `,` or `)` next.
///       #|
///     ),
///   )
/// }
/// ```
pub fn render_plain(
  diag : @scanner.Diagnostic,
  source : @scanner.SourceText,
  path : String,
) -> String {
  let sb = StringBuilder()
  sb.write_string(header(diag.title, path))
  sb.write_string("\n\n")
  for chunk in body(diag, source) {
    sb.write_string(chunk_text(chunk))
  }
  sb.to_string()
}

///|
fn ansi_color(color : @scanner.Color) -> Int {
  match color {
    Black => 30
    Red => 31
    Green => 32
    Yellow => 33
    Blue => 34
    Magenta => 35
    Cyan => 36
    White => 37
    VividBlack => 90
    VividRed => 91
    VividGreen => 92
    VividYellow => 93
    VividBlue => 94
    VividMagenta => 95
    VividCyan => 96
    VividWhite => 97
  }
}

///|
fn ansi(chunk : @scanner.Chunk) -> String {
  match chunk {
    Plain(text) => text
    Styled(text~, color~, bold~, underline~) => {
      let codes = []
      if bold {
        codes.push("1")
      }
      if underline {
        codes.push("4")
      }
      if color is Some(c) {
        codes.push(ansi_color(c).to_string())
      }
      if codes.is_empty() {
        text
      } else {
        "\u{1b}[" + codes.join(";") + "m" + text + "\u{1b}[0m"
      }
    }
  }
}

///|
/// A diagnostic for a terminal, with ANSI colors like `elm make`.
///
/// The text is `render_plain`'s text with ANSI escape codes around the
/// header, the `^` markers and the styled chunks of the report.
///
/// ```mbt check
/// test {
///   let source = @scanner.SourceText::new(
///     "module Main exposing (..)\n\nmain =\n    (1 + 2\n",
///   )
///   let result = @parser.parse_module(source, @scanner.DefaultScanner::new())
///   let text = @report.render_terminal(
///     result.diagnostics[0],
///     source,
///     "src/Main.elm",
///   )
///   // The header is cyan: ESC [36m.
///   inspect(
///     text.has_prefix("\u{1b}[36m-- UNFINISHED PARENTHESES"),
///     content="true",
///   )
/// }
/// ```
pub fn render_terminal(
  diag : @scanner.Diagnostic,
  source : @scanner.SourceText,
  path : String,
) -> String {
  let sb = StringBuilder()
  sb.write_string(
    ansi(
      Styled(
        text=header(diag.title, path),
        color=Some(Cyan),
        bold=false,
        underline=false,
      ),
    ),
  )
  sb.write_string("\n\n")
  for chunk in body(diag, source) {
    sb.write_string(ansi(chunk))
  }
  sb.to_string()
}
