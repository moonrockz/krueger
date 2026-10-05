///|
/// A Markdown block, as elm-format's Markdown parser (its fork of
/// Cheapskate, `Cheapskate.Types.Block`) reads it. Text is kept as written,
/// for the inline parser.
priv enum Block {
  Leaf(Leaf)
  Quote(Array[Block])
  List(ListKind, Bool, Array[Array[Block]]) // kind, tight, items
}

///|
priv enum Leaf {
  Para(String)
  Header(Int, String)
  Code(String, String) // language, code
  Html(String)
  Rule
  References(Array[(String, String, String)]) // label, URL, title
  Docs(Array[Array[String]]) // the names of each `@docs` line
}

///|
priv enum ListKind {
  Bullet
  Numbered
}

///|
/// Format the Markdown of a doc comment as elm-format 0.8.7 does.
///
/// `text` is the text between `{-|` and `-}`, and so is the result: the
/// first line starts with a space, and the text ends with a line break, so
/// that `-}` goes on its own line (an empty doc comment gives `" "`, for
/// `{-| -}`). The rules come from elm-format's `ElmFormat.Render.Markdown`:
///
/// - Emphasis is written `_a_` and strong emphasis `**a**`. In text, `\`,
///   `` ` ``, `_` and `*` get a backslash. URLs get angle brackets.
/// - Bullet lists use `  - `, numbered lists `1.  `, from 1. Blank lines
///   separate blocks, two blank lines come before a heading.
/// - A code block in Elm (language `elm` or none) goes to `format_code`.
///   When it gives `Some(code)`, that code replaces the code block, which
///   is then indented by 4 (or fenced, right after a list). When it gives
///   `None`, the code stays as written. A code block in another language
///   stays as written.
/// - `@docs` lines lose `(..)`.
///
/// The parser is cmark (CommonMark), changed where elm-format's parser
/// differs: a setext underline makes only the line before it a heading,
/// and a `@docs` line ends a paragraph. Inlines are parsed as elm-format
/// does. A doc comment that nests deeper than this function reads (more
/// than 100 levels of block quotes and lists, 12 levels of brackets or 32
/// levels of inlines) stays as it is.
///
/// ```mbt check
/// test {
///   inspect(
///     @markdown.format_doc(" A *note* on snake_case.\n\n* one\n* two\n"),
///     content=(
///       #| A _note_ on snake\_case.
///       #|
///       #|  - one
///       #|  - two
///       #|
///       #|
///     ),
///   )
/// }
/// ```
pub fn format_doc(
  text : String,
  format_code? : (String) -> String? = _ => None,
) -> String {
  let mut md = prepare(text)
  if too_nested(md) {
    return text
  }
  // Where elm-format's parser reads the text differently, a pass edits
  // the text so that cmark reads it the same way, then parses again (an
  // edit can change what comes after it).
  for pass in 0..<8 {
    let doc = @cmark.Doc::from_string(md, layout=true, locs=true, strict=true)
    let edits = []
    let blocks = to_blocks(doc.block, md, edits) catch {
      TooDeep => return text
    }
    if edits.is_empty() || pass == 7 {
      let content = format_markdown(blocks, format_code) catch {
        TooDeep => return text
      }
      return frame(content)
    }
    md = apply_edits(md, edits)
  }
  text
}

///|
/// A change to the parsed text: `text` replaces `src[start:end]`.
priv struct Edit {
  start : Int
  end : Int
  text : String
}

///|
/// `src` with `edits`; an edit that overlaps an earlier one is left out.
fn apply_edits(src : String, edits : Array[Edit]) -> String {
  edits.sort_by((a, b) => a.start.compare(b.start))
  let sb = StringBuilder()
  let mut done = 0
  for e in edits {
    guard e.start >= done else { continue }
    sb.write_string(slice(src, done, e.start))
    sb.write_string(e.text)
    done = e.end
  }
  sb.write_string(slice(src, done, src.length()))
  sb.to_string()
}

///|
/// The text that elm-format's Markdown parser reads: without the spaces
/// after `{-|`, with LF line breaks, and with tabs as spaces to the next
/// multiple of 4 (Cheapskate `tabFilter`).
fn prepare(text : String) -> String {
  let body = strip_start_by(text, c => c == ' ').replace_all(
    old="\r\n",
    new="\n",
  )
  body.split("\n").map(l => tab_filter(l.to_owned())).join("\n")
}

///|
fn tab_filter(line : String) -> String {
  guard line.contains("\t") else { return line }
  let parts = line.split("\t").map(p => p.to_owned()).collect()
  let sb = StringBuilder()
  for i, part in parts {
    sb.write_string(part)
    if i < parts.length() - 1 {
      let n = part.char_length()
      sb.write_string(" ".repeat(4 - n % 4))
    }
  }
  sb.to_string()
}

///|
/// Whether `md` nests deeper than cmark reads safely: more than 12 levels
/// of brackets in a paragraph (cmark's link parser takes exponential time),
/// or a line that starts more than 100 levels of block quotes and lists.
fn too_nested(md : String) -> Bool {
  let mut brackets = 0
  for line in md.split("\n") {
    if line.trim(chars=" ").is_empty() {
      brackets = 0
      continue
    }
    for c in line {
      if c == '[' {
        brackets += 1
        if brackets > 12 {
          return true
        }
      } else if c == ']' && brackets > 0 {
        brackets -= 1
      }
    }
    // Each level of a block quote is a `>`; each level of a list is a
    // mark or two columns of indentation. The space after a mark is not
    // indentation.
    let mut levels = 0
    let mut spaces = 0
    let mut prev = ' '
    for c in line {
      match c {
        ' ' =>
          if prev is ('-' | '*' | '+' | '.' | ')') {
            levels += 1
          } else if prev != '>' {
            spaces += 1
          }
        '>' => levels += 1
        '-' | '*' | '+' | '.' | ')' | '0'..='9' => ()
        _ => break
      }
      prev = c
    }
    if levels + spaces / 2 > 100 {
      return true
    }
  }
  false
}

///|
/// The text between `{-|` and `-}` for the formatted Markdown `content`
/// (elm-format `formatDocCommentString`). Lines lose their trailing spaces,
/// as elm-format's output does.
fn frame(content : String) -> String {
  let lines = hs_lines(content)
  guard lines is [first, ..] else { return " " }
  let sb = StringBuilder()
  sb.write_string(strip_end_by(" " + first, is_space))
  sb.write_char('\n')
  for line in lines[1:] {
    sb.write_string(strip_end_by(line, is_space))
    sb.write_char('\n')
  }
  sb.to_string()
}

///|
/// Haskell `lines`: the lines of `text`, without a last empty line.
fn hs_lines(text : String) -> Array[String] {
  guard !text.is_empty() else { return [] }
  let lines = text.split("\n").map(l => l.to_owned()).collect()
  if text.has_suffix("\n") {
    ignore(lines.pop())
  }
  lines
}

///|
/// Haskell `unlines . prefix first rest . lines` (elm-format `prefix'`).
fn prefix_lines(first : String, rest : String, text : String) -> String {
  let sb = StringBuilder()
  for i, line in hs_lines(text) {
    sb.write_string(if i == 0 { first } else { rest })
    sb.write_string(line)
    sb.write_char('\n')
  }
  sb.to_string()
}

///|
/// A step of `to_blocks`: a sequence of cmark blocks, or the items of a
/// list.
priv enum Conv {
  ConvSeq(ConvSeq)
  ConvList(ConvList)
}

///|
priv struct ConvSeq {
  items : Array[@cmark.Block]
  mut next : Int
  out : Array[Block]
}

///|
priv struct ConvList {
  kind : ListKind
  tight : Bool
  items : Array[@cmark.Block]
  mut next : Int
  out : Array[Array[Block]]
}

///|
/// The blocks in `block` in order, with nested `Blocks` opened.
fn flatten(block : @cmark.Block) -> Array[@cmark.Block] {
  let out = []
  let todo = [block]
  while todo.pop() is Some(b) {
    match b {
      Blocks(n) => {
        let items = n.v.to_array()
        for i = items.length() - 1; i >= 0; i = i - 1 {
          todo.push(items[i])
        }
      }
      _ => out.push(b)
    }
  }
  out
}

///|
/// Whether a blank line ends `blocks`, also at the end of a list at their
/// end (elm-format's parser moves the blank line at the end of a list item
/// out of the item).
fn ends_with_blank(blocks : Array[@cmark.Block]) -> Bool {
  let mut bs = blocks
  while bs.last() is Some(last) {
    match last {
      BlankLine(_) => return true
      List(l) =>
        match l.v.items.to_array().last() {
          Some(item) => bs = flatten(item.v.block)
          None => return false
        }
      _ => return false
    }
  }
  false
}

///|
/// Whether `list` is tight for elm-format's parser (Cheapskate
/// `tightListItem`): no blank line between its items, and none between the
/// blocks of an item. A blank line at the end of an item moves out of it:
/// between the items of a nested list, it is between the blocks of the
/// enclosing item. (cmark's own flag differs: it also makes a list loose
/// for a blank line at the end of the text after a nested list.)
fn is_tight(list : @cmark.BlockList) -> Bool {
  let items = list.items.to_array().map(i => flatten(i.v.block))
  for k, blocks in items {
    if k < items.length() - 1 && ends_with_blank(blocks) {
      return false
    }
    for p, b in blocks {
      let interior = p < blocks.length() - 1
      match b {
        BlankLine(_) if interior => return false
        List(inner) => {
          if interior && ends_with_blank([b]) {
            return false
          }
          // cheapskate difference (bd krueger-rne.12): a blank line between the
          // items of a nested list makes the enclosing list loose.
          let nested = inner.v.items.to_array()
          for j in 0..<(nested.length() - 1) {
            if ends_with_blank(flatten(nested[j].v.block)) {
              return false
            }
          }
        }
        _ => ()
      }
    }
  }
  true
}

///|
/// The blocks of a cmark document, as elm-format's parser gives them.
/// `src` is the parsed text. Uses an explicit stack, so deep nesting does
/// not overflow the call stack.
fn to_blocks(
  root : @cmark.Block,
  src : String,
  edits : Array[Edit],
) -> Array[Block] raise TooDeep {
  let stack : Array[Conv] = [
    ConvSeq({ items: flatten(root), next: 0, out: [], }),
  ]
  while stack.last() is Some(top) {
    match top {
      ConvSeq(s) if s.next < s.items.length() => {
        let block = s.items[s.next]
        let after_reference = s.next > 0 &&
          s.items[s.next - 1] is LinkRefDefinition(_)
        s.next += 1
        match block {
          BlockQuote(q) =>
            stack.push(
              ConvSeq({ items: flatten(q.v.block), next: 0, out: [], }),
            )
          List(l) => {
            let kind = match l.v.ty {
              Unordered(_) => Bullet
              Ordered(_) => Numbered
            }
            stack.push(
              ConvList({
                kind,
                tight: is_tight(l.v),
                items: l.v.items.to_array().map(i => i.v.block),
                next: 0,
                out: [],
              }),
            )
          }
          Paragraph(p) => {
            let starts = []
            let lines = inline_lines(p.v.inline, src, starts~)
            edits.append(renumber_marks(lines, starts, src))
            // cheapskate difference (bd krueger-rne.12): an HTML block does not
            // interrupt a paragraph; its lines continue the paragraph.
            while s.items.get(s.next) is Some(HtmlBlock(h)) {
              for line in h.v.0.iter() {
                lines.push(strip_start_by(line.v, is_space))
              }
              s.next += 1
            }
            para_blocks(lines, s.out)
          }
          CodeBlock(c) => {
            edits.append(fence_closes(c, src))
            leaf_blocks(block, src, s.out, after_reference)
          }
          _ => leaf_blocks(block, src, s.out, after_reference)
        }
      }
      ConvSeq(s) => {
        ignore(stack.pop())
        match stack.last() {
          None => return s.out
          Some(ConvSeq(parent)) =>
            // Only a block quote opens a sequence in a sequence.
            parent.out.push(Quote(s.out))
          Some(ConvList(parent)) => parent.out.push(s.out)
        }
      }
      ConvList(l) if l.next < l.items.length() => {
        let item = l.items[l.next]
        l.next += 1
        stack.push(ConvSeq({ items: flatten(item), next: 0, out: [], }))
      }
      ConvList(l) => {
        ignore(stack.pop())
        if stack.last() is Some(ConvSeq(parent)) {
          parent.out.push(List(l.kind, l.tight, l.out))
        }
      }
    }
  }
  []
}

///|
/// Edits that renumber the ordered list marks that start a list inside a
/// paragraph for elm-format's parser, to `1.` (or `1)`) and spaces, so the
/// text after a mark stays in its column. cheapskate difference (bd
/// krueger-rne.12): there, a
/// list with any number interrupts a paragraph; in CommonMark only a list
/// from 1 does (elm-format numbers every list from 1). A mark counts when
/// it is at most 3 columns right of the paragraph's first line, and text
/// follows it.
fn renumber_marks(
  lines : Array[String],
  starts : Array[Int],
  src : String,
) -> Array[Edit] {
  let column = (offset : Int) => {
    let mut i = offset
    while i > 0 && src.code_unit_at(i - 1).to_int() != 0x0A {
      i -= 1
    }
    offset - i
  }
  guard starts is [first, ..] else { return [] }
  let base = column(first)
  let out = []
  for i in 1..<lines.length() {
    if ordered_mark_length(lines[i]) is Some(n) && column(starts[i]) - base <= 3 {
      let at = starts[i]
      out.push({
        start: at,
        end: at + n + 1,
        text: "1" + slice(src, at + n, at + n + 1) + " ".repeat(n - 1),
      })
    }
  }
  out
}

///|
/// The number of digits of the ordered list mark (`12. ` or `12) `, not
/// `1`) at the start of `line`, when text follows the mark.
fn ordered_mark_length(line : String) -> Int? {
  let chars = line.to_array()
  let mut n = 0
  while n < chars.length() && chars[n].is_ascii_digit() {
    n += 1
  }
  guard n >= 1 && n <= 9 && !(n == 1 && chars[0] == '1') else { return None }
  guard chars.get(n) is Some('.' | ')') && chars.get(n + 1) == Some(' ') else {
    return None
  }
  for c in chars[n + 2:] {
    if c != ' ' {
      return Some(n)
    }
  }
  None
}

///|
/// Edits that end a fenced code block at its first line that starts with
/// the opening fence: elm-format's parser closes the block there and leaves
/// out the rest of that line. cheapskate difference (bd krueger-rne.13):
/// in CommonMark, only a
/// fence without text after it closes the block.
fn fence_closes(c : @cmark.Node[@cmark.CodeBlock], src : String) -> Array[Edit] {
  guard c.v.layout is Fenced(_) && c.meta.loc.first_ccode >= 0 else {
    return []
  }
  let open_end = find_newline(src, c.meta.loc.first_ccode, src.length())
  let opening = strip_start_by(slice(src, c.meta.loc.first_ccode, open_end), c => {
    c == ' '
  })
  let mark = if opening.has_prefix("~") { '~' } else { '`' }
  let fence = String::make(
    opening.to_array().iter().take_while(x => x == mark).count(),
    mark,
  )
  for line in c.v.code.iter() {
    let at = line.meta.loc.first_ccode
    if at >= 0 && line.v.has_prefix(fence) {
      return [
        {
          start: at + fence.length(),
          end: find_newline(src, at, src.length()),
          text: "",
        },
      ]
    }
  }
  []
}

///|
/// Add the blocks for the cmark leaf block `block` to `out`.
fn leaf_blocks(
  block : @cmark.Block,
  src : String,
  out : Array[Block],
  after_reference : Bool,
) -> Unit raise TooDeep {
  match block {
    BlankLine(_) => ()
    Paragraph(p) => para_blocks(inline_lines(p.v.inline, src), out)
    Heading(h) =>
      match h.v.layout {
        Atx(_) => out.push(Leaf(Header(h.v.level, atx_text(h.meta.loc, src))))
        Setext(_) => {
          // cheapskate difference (bd krueger-rne.12): only the line before the
          // underline is the heading; the lines before it are a paragraph.
          let lines = inline_lines(h.v.inline, src)
          match lines {
            [] => out.push(Leaf(Header(h.v.level, "")))
            [.. before, last] => {
              if !before.is_empty() {
                para_blocks(before.to_owned(), out)
              }
              out.push(Leaf(Header(h.v.level, strip(last))))
            }
          }
        }
      }
    CodeBlock(c) => {
      let lang = match (c.v.layout, c.v.info_string) {
        (Fenced(_), Some(info)) =>
          match info.v.split(" ").next() {
            Some(word) => word.to_owned()
            None => ""
          }
        _ => ""
      }
      let code = c.v.code.to_array().map(l => l.v).join("\n")
      out.push(Leaf(Code(lang, code)))
    }
    HtmlBlock(h) => {
      let lines = h.v.0.to_array().map(l => l.v)
      if lines is [first, ..] && !starts_html_block(first) {
        // cheapskate difference (bd krueger-rne.13): elm-format's parser starts
        // an HTML block only at a block-level tag, `<!--` or `-->`; other lines
        // are a paragraph.
        para_blocks(lines.map(l => strip_start_by(l, is_space)), out)
      } else {
        out.push(Leaf(Html(lines.join("\n"))))
      }
    }
    ThematicBreak(_) => out.push(Leaf(Rule))
    LinkRefDefinition(d) => {
      let refs = []
      for line in raw_lines(d.meta.loc, src) {
        // elm-format's parser leaves out a definition that it cannot read.
        if parse_reference(line) is Some(r) {
          refs.push(r)
        }
      }
      match out.last() {
        Some(Leaf(References(previous))) if after_reference =>
          previous.append(refs)
        _ => out.push(Leaf(References(refs)))
      }
    }
    // Not in strict CommonMark: kept as written.
    ExtMathBlock(_) | ExtTable(_) | ExtFootnoteDefinition(_) =>
      out.push(Leaf(Html(raw_lines(block.meta().loc, src).join("\n"))))
    Blocks(_) | BlockQuote(_) | List(_) => ()
  }
}

///|
/// Add a paragraph with the lines `lines` to `out`. A line that starts
/// with `@docs` ends the paragraph: it and the lines after it are `@docs`
/// lines (Cheapskate `processElts`).
fn para_blocks(lines : Array[String], out : Array[Block]) -> Unit {
  let mut docs_at = None
  for i, line in lines {
    if line.has_prefix("@docs") {
      docs_at = Some(i)
      break
    }
  }
  let para_end = docs_at.unwrap_or(lines.length())
  if para_end > 0 {
    out.push(Leaf(Para(strip_end_by(lines[:para_end].join("\n"), is_space))))
  }
  guard docs_at is Some(start) else { return }
  // cheapskate difference (bd krueger-rne.12): a `@docs` line ends a paragraph.
  let names = []
  for line in lines[start:] {
    let rest = match line.strip_prefix("@docs") {
      Some(r) => r.to_owned()
      None => line
    }
    let terms = []
    for term in rest.split(",") {
      let t = strip(term.to_owned())
      if !t.is_empty() {
        terms.push(t)
      }
    }
    if !terms.is_empty() {
      names.push(terms)
    }
  }
  out.push(Leaf(Docs(names)))
}

///|
/// The lines of text of the inline `inline` (a paragraph or a setext
/// heading) as elm-format's parser reads them: as written, each without the
/// marks of its block quotes and lists and without spaces at its start.
fn inline_lines(
  inline : @cmark.Inline,
  src : String,
  starts? : Array[Int] = [],
) -> Array[String] {
  let loc = inline.meta().loc
  guard loc.first_ccode >= 0 && loc.last_ccode >= loc.first_ccode else {
    return []
  }
  let end = loc.last_ccode + 1
  // Where inline nodes start: each line's text starts at the first of them
  // on that line.
  let anchors = []
  let todo = [inline]
  while todo.pop() is Some(i) {
    let m = i.meta().loc
    match i {
      Break(_) => anchors.push(m.last_ccode + 1)
      _ => anchors.push(m.first_ccode)
    }
    match i {
      Inlines(n) => todo.append(n.v.to_array())
      Emphasis(n) | StrongEmphasis(n) => todo.push(n.v.inline)
      Link(n) | Image(n) => {
        todo.push(n.v.text)
        if n.v.reference is Inline(d) {
          if d.v.dest is Some(dest) {
            anchors.push(dest.meta.loc.first_ccode)
          }
          if d.v.title is Some(title) {
            for t in title.iter() {
              anchors.push(t.node.meta.loc.first_ccode)
            }
          }
        }
      }
      CodeSpan(n) =>
        for t in n.v.code_layout.iter() {
          anchors.push(t.node.meta.loc.first_ccode)
        }
      RawHtml(n) =>
        for t in n.v.0.iter() {
          anchors.push(t.node.meta.loc.first_ccode)
        }
      ExtStrikethrough(n) => todo.push(n.v.0)
      _ => ()
    }
  }
  anchors.sort()
  let lines = []
  let mut start = loc.first_ccode
  while true {
    let line_end = find_newline(src, start, end)
    let raw = slice(src, start, line_end)
    let line = strip_start_by(raw, is_space)
    starts.push(start + raw.length() - line.length())
    lines.push(line)
    guard line_end < end else { break }
    let next = line_end + 1
    let next_end = find_newline(src, next, end)
    start = skip_prefix(src, next, next_end)
    for a in anchors {
      if a >= next && a < next_end {
        start = a
        break
      }
    }
  }
  lines
}

///|
/// The position of the first line break in `src[start:end]`, or `end`.
fn find_newline(src : String, start : Int, end : Int) -> Int {
  let mut i = start
  while i < end && src.code_unit_at(i).to_int() != 0x0A {
    i += 1
  }
  i
}

///|
/// The position after the block quote marks and spaces at the start of
/// `src[start:end]`.
fn skip_prefix(src : String, start : Int, end : Int) -> Int {
  let mut i = start
  while i < end && src.code_unit_at(i).to_int() is (0x20 | 0x3E) {
    i += 1
  }
  i
}

///|
fn slice(src : String, start : Int, end : Int) -> String {
  src.view(start_offset=start, end_offset=end).to_owned()
}

///|
/// The text of an ATX heading as elm-format's parser reads it: without the
/// `#` marks at its start, and without the spaces and `#` marks at its end
/// unless the last mark is escaped (Cheapskate `removeATXSuffix`).
fn atx_text(loc : @cmark_base.TextLoc, src : String) -> String {
  guard loc.first_ccode >= 0 else { return "" }
  let line_end = find_newline(src, loc.first_ccode, src.length())
  let line = strip_start_by(
    strip_start_by(slice(src, loc.first_ccode, line_end), c => c == ' '),
    c => c == '#',
  )
  let trimmed = strip_end_by(line, c => c is (' ' | '#'))
  let text = if trimmed != "" && trimmed.has_suffix("\\") {
    trimmed + "#"
  } else {
    trimmed
  }
  strip(text)
}

///|
/// The lines of `src` at `loc`, to the end of the last line, each without
/// the marks of its block quotes and the spaces at its start and end.
/// (cmark's location of a link reference definition can end before a `>`
/// that closes its URL.)
fn raw_lines(loc : @cmark_base.TextLoc, src : String) -> Array[String] {
  guard loc.first_ccode >= 0 && loc.last_ccode >= loc.first_ccode else {
    return []
  }
  let end = find_newline(src, loc.last_ccode, src.length())
  let text = slice(src, loc.first_ccode, end)
  text
  .split("\n")
  .map(l => strip(strip_start_by(l.to_owned(), c => c is (' ' | '>'))))
  .collect()
}

///|
/// Cheapskate `pReference`: `[label]: url "title"` on one line.
fn parse_reference(line : String) -> (String, String, String)? raise TooDeep {
  let p = InlineParser::new(line, 0)
  guard p.label() is Some(label) && p.char(':') else { return None }
  p.scan_spnl()
  guard p.link_url() is Some(url) else { return None }
  let save = p.pos
  p.scan_spnl()
  let title = match p.link_title() {
    Some(t) => t
    None => {
      p.pos = save
      ""
    }
  }
  guard p.at_end() else { return None }
  Some((label, url, title))
}

///|
/// A step of `format_markdown`: a sequence of blocks, or the items of a
/// list.
priv enum Job {
  SeqJob(SeqJob)
  ListJob(ListJob)
}

///|
priv struct SeqJob {
  blocks : Array[Block]
  kind : SeqKind
  mut next : Int
  parts : Array[String]
}

///|
priv enum SeqKind {
  Top
  QuoteBody
  ItemBody
}

///|
priv struct ListJob {
  kind : ListKind
  tight : Bool
  items : Array[Array[Block]]
  mut next : Int
  parts : Array[String]
}

///|
/// The Markdown text of `blocks` (elm-format `formatMarkdown`). Uses an
/// explicit stack, so deep nesting does not overflow the call stack.
fn format_markdown(
  blocks : Array[Block],
  format_code : (String) -> String?,
) -> String raise TooDeep {
  let initial = match blocks {
    [] => false
    [Leaf(Para(text)), ..] => parse_inlines(text) is [Str("@"), Str("docs"), ..]
    _ => true
  }
  let trailing = match blocks {
    [] => false
    [_] => initial
    _ => true
  }
  let stack : Array[Job] = [SeqJob({ blocks, kind: Top, next: 0, parts: [], })]
  while stack.last() is Some(top) {
    match top {
      SeqJob(s) if s.next < s.blocks.length() => {
        let i = s.next
        s.next += 1
        let after_list = i > 0 && s.blocks[i - 1] is List(_)
        match s.blocks[i] {
          Quote(inner) =>
            stack.push(
              SeqJob({ blocks: inner, kind: QuoteBody, next: 0, parts: [], }),
            )
          List(kind, tight, items) =>
            stack.push(ListJob({ kind, tight, items, next: 0, parts: [], }))
          Leaf(leaf) =>
            s.parts.push(
              format_leaf(leaf, after_list, s.kind is Top, format_code),
            )
        }
      }
      SeqJob(s) => {
        ignore(stack.pop())
        // In a list item, a paragraph and the list after it are not
        // separated.
        let separator = if s.kind is ItemBody &&
          s.blocks is [Leaf(Para(_)), List(_)] {
          ""
        } else {
          "\n"
        }
        let body = s.parts.join(separator)
        match s.kind {
          Top =>
            return (if initial { "\n\n" } else { "" }) +
              body +
              (if trailing { "\n" } else { "" })
          QuoteBody => deliver(stack, prefix_lines("> ", "> ", body))
          ItemBody => deliver(stack, body)
        }
      }
      ListJob(l) if l.next < l.items.length() => {
        let item = l.items[l.next]
        l.next += 1
        stack.push(
          SeqJob({ blocks: item, kind: ItemBody, next: 0, parts: [], }),
        )
      }
      ListJob(l) => {
        ignore(stack.pop())
        deliver(stack, l.parts.join(if l.tight { "" } else { "\n" }))
      }
    }
  }
  ""
}

///|
/// Give the formatted text of a block quote or list (to a sequence) or of a
/// list item (to a list, which adds the item's mark) to the top job.
fn deliver(stack : Array[Job], text : String) -> Unit {
  match stack.last() {
    Some(SeqJob(s)) => s.parts.push(text)
    Some(ListJob(l)) => {
      let n = l.parts.length() + 1
      let mark = match l.kind {
        Bullet => "  - "
        Numbered => if n < 10 { "\{n}.  " } else { "\{n}. " }
      }
      l.parts.push(prefix_lines(mark, "    ", text))
    }
    None => ()
  }
}

///|
/// The formatted text of a leaf block (elm-format `formatMardownBlock`).
/// `after_list` is true when the block comes right after a list, `top` when
/// the block is not in a block quote or a list.
fn format_leaf(
  leaf : Leaf,
  after_list : Bool,
  top : Bool,
  format_code : (String) -> String?,
) -> String raise TooDeep {
  match leaf {
    // elm-format `cleanBlock` removes `(..)` from the `@docs` lines of the
    // top-level blocks only.
    Docs(lines) =>
      lines
      .map(names => {
        let shown = if top {
          names.map(n => n.replace_all(old="(..)", new=""))
        } else {
          names
        }
        "@docs " + shown.join(", ")
      })
      .join("\n") +
      "\n"
    Para(text) => format_inlines(parse_inlines(text), true) + "\n"
    Header(level, text) =>
      "\n" +
      "#".repeat(level) +
      " " +
      format_inlines(parse_inlines(text), true) +
      "\n"
    Code(lang, code) => {
      let is_elm = lang == "elm" || lang == ""
      let formatted = ensure_newline(
        (if is_elm { format_code(code) } else { None }).unwrap_or(code),
      )
      if is_elm && !after_list {
        prefix_lines("    ", "    ", formatted)
      } else {
        "```" + lang + "\n" + formatted + "```\n"
      }
    }
    Html(text) => text + "\n"
    Rule => "---\n"
    References(refs) => {
      let sb = StringBuilder()
      for r in refs {
        let (label, url, title) = r
        sb.write_string("[" + label + "]: " + url + format_title(title) + "\n")
      }
      sb.to_string()
    }
  }
}

///|
fn ensure_newline(text : String) -> String {
  if text.is_empty() || text.has_suffix("\n") {
    text
  } else {
    text + "\n"
  }
}
