///|
/// Source lines, without line endings. Line `n` is at index `n - 1`.
fn source_lines(source : @scanner.SourceText) -> Array[String] {
  source.text
  .split("\n")
  .map(line => {
    let line = line.to_owned()
    if line.has_suffix("\r") {
      line.unsafe_substring(start=0, end=line.length() - 1)
    } else {
      line
    }
  })
  .collect()
}

///|
fn digits(n : Int) -> Int {
  n.to_string().length()
}

///|
fn pad_left(text : String, width : Int) -> String {
  " ".repeat(width - text.length()) + text
}

///|
/// The excerpt as chunks, laid out like `elm make` (Reporting/Render/Code.hs):
/// right-aligned line numbers and `| `; a `^` line under a one-line
/// highlight; a `>` after the gutter on each line of a multi-line highlight.
/// Returns the chunks and whether a caret line ends the excerpt.
fn excerpt_chunks(
  source : @scanner.SourceText,
  context : @scanner.Span,
  highlight : @scanner.Span,
) -> (Array[@scanner.Chunk], Bool) {
  let lines = source_lines(source)
  let first = context.start.line
  let last = @cmp.maximum(context.end.line, highlight.end.line)
  let width = digits(last)
  let multi = highlight.start.line != highlight.end.line
  let chunks : Array[@scanner.Chunk] = []
  for n = first; n <= last; n = n + 1 {
    let text = lines.get(n - 1).unwrap_or("")
    let gutter = pad_left(n.to_string(), width)
    let line = if multi {
      let marked = n >= highlight.start.line && n <= highlight.end.line
      gutter + (if marked { "|>" } else { "| " }) + " " + text
    } else {
      gutter + "| " + text
    }
    chunks.push(Plain(line + "\n"))
  }
  if multi {
    return (chunks, false)
  }
  let carets = @cmp.maximum(1, highlight.end.column - highlight.start.column)
  chunks.push(Plain(" ".repeat(width + 2 + highlight.start.column - 1)))
  chunks.push(
    Styled(
      text="^".repeat(carets),
      color=Some(VividRed),
      bold=false,
      underline=false,
    ),
  )
  chunks.push(Plain("\n"))
  (chunks, true)
}
