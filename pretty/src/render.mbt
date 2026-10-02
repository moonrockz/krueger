///|
priv enum Mode {
  Flat
  Break
}

///|
priv struct Cmd {
  indent : Int
  mode : Mode
  doc : Doc
}

///|
/// The output. Indentation and the spaces of flat lines are written only
/// before the next text, so the engine writes no trailing whitespace.
priv struct Out {
  buf : StringBuilder
  mut column : Int
  mut indent : Int? // indentation not written yet, at the start of a line
  mut spaces : Int // spaces of flat lines not written yet
}

///|
fn Out::text(self : Out, s : String, width : Int) -> Unit {
  if self.indent is Some(i) {
    self.buf.write_string(" ".repeat(i))
    self.indent = None
  }
  if self.spaces > 0 {
    self.buf.write_string(" ".repeat(self.spaces))
    self.spaces = 0
  }
  self.buf.write_string(s)
  self.column += width
}

///|
fn Out::space(self : Out, n : Int) -> Unit {
  self.spaces += n
  self.column += n
}

///|
fn Out::newline(self : Out, indent : Int) -> Unit {
  self.buf.write_char('\n')
  self.indent = Some(indent)
  self.spaces = 0
  self.column = indent
}

///|
/// Lay out `doc` in lines of at most `width` columns where its groups
/// allow. A group is flat when it fits, together with the rest of its line
/// up to the next possible break. Text wider than `width` stays whole.
/// Uses explicit stacks, so deep documents render on every target.
///
/// ```mbt check
/// test {
///   let items = [@pretty.text("a"), @pretty.text("b")]
///   let d = @pretty.group(
///     @pretty.text("[") +
///     @pretty.nest(
///       2,
///       @pretty.line() + @pretty.join(items, @pretty.text(",") + @pretty.line()),
///     ) +
///     @pretty.line() +
///     @pretty.text("]"),
///   )
///   inspect(@pretty.render(d), content="[ a, b ]")
///   inspect(@pretty.render(d, width=4), content="[\n  a,\n  b\n]")
/// }
/// ```
pub fn render(doc : Doc, width? : Int = 80) -> String {
  let out : Out = {
    buf: StringBuilder::new(),
    column: 0,
    indent: None,
    spaces: 0,
  }
  let stack : Array[Cmd] = [{ indent: 0, mode: Break, doc, }]
  while stack.pop() is Some(cmd) {
    match cmd.doc.node {
      Empty => ()
      Text(s, n) => out.text(s, n)
      Line(n) =>
        match cmd.mode {
          Flat => out.space(n)
          Break => out.newline(cmd.indent)
        }
      HardLine => out.newline(cmd.indent)
      VerbatimLine => out.newline(0)
      Nest(n, d) => stack.push({ ..cmd, indent: cmd.indent + n, doc: d, })
      Align(d) => stack.push({ ..cmd, indent: out.column, doc: d, })
      Group(d) =>
        match cmd.mode {
          Flat => stack.push({ ..cmd, doc: d, })
          Break => {
            let flat = !d.has_hardline &&
              fits(width - out.column, { ..cmd, mode: Flat, doc: d, }, stack)
            stack.push({ ..cmd, mode: if flat { Flat } else { Break }, doc: d, })
          }
        }
      IfBreak(broken, flat) =>
        stack.push({
          ..cmd,
          doc: match cmd.mode {
            Flat => flat
            Break => broken
          },
        })
      Concat(a, b) => {
        stack.push({ ..cmd, doc: b, })
        stack.push({ ..cmd, doc: a, })
      }
    }
  }
  out.buf.to_string()
}

///|
/// Whether `first`, then the commands of `rest` (top of the stack first),
/// fit in `remaining` columns up to the next line break. A line in break
/// mode ends the check: the line can break there.
fn fits(remaining : Int, first : Cmd, rest : Array[Cmd]) -> Bool {
  let mut left = remaining
  let local = [first]
  let mut next = rest.length() - 1
  while left >= 0 {
    let cmd = match local.pop() {
      Some(c) => c
      None => {
        if next < 0 {
          return true
        }
        let c = rest[next]
        next -= 1
        c
      }
    }
    match cmd.doc.node {
      Empty => ()
      Text(_, n) => left -= n
      Line(n) =>
        match cmd.mode {
          Flat => left -= n
          Break => return true
        }
      HardLine | VerbatimLine => return true
      Nest(_, d) | Align(d) => local.push({ ..cmd, doc: d, })
      Group(d) =>
        local.push({
          ..cmd,
          mode: if d.has_hardline {
            Break
          } else {
            cmd.mode
          },
          doc: d,
        })
      IfBreak(broken, flat) =>
        local.push({
          ..cmd,
          doc: match cmd.mode {
            Flat => flat
            Break => broken
          },
        })
      Concat(a, b) => {
        local.push({ ..cmd, doc: b, })
        local.push({ ..cmd, doc: a, })
      }
    }
  }
  false
}
