///|
/// Whether the block comments `{- c0 -}`, `{- c1 -}`, ... up to `count`
/// are all in `text`, in that order.
fn markers_in_order(text : String, count : Int32) -> Bool {
  let mut from = 0
  for i in 0..<count {
    let marker = "{- c\{i} -}"
    match text.view(start_offset=from).find(marker) {
      Some(at) => from = from + at + marker.length()
      None => return false
    }
  }
  true
}

///|
/// A short description of a format failure.
fn failure(e : @printer.FormatError) -> String {
  match e {
    ParseFailed(diags) => "parse failed: " + diags.map(d => d.code).join(", ")
    Unprintable(PrintError(problem=UnplacedComment(_), ..)) =>
      "unplaced comment"
    Unprintable(_) => "unprintable"
  }
}

///|
/// `format` in both layouts places every comment of `text` (no
/// `UnplacedComment`), keeps them in order, and is idempotent.
fn deep_comments_hold(
  s : @expect.Scope,
  name : String,
  text : String,
  count : Int32,
) -> Unit raise {
  s.expect((name, markers_in_order(text, count))).to_equal((name, true))
  for layout in [@printer.Layout::ElmFormat, Width(120)] {
    let once = @printer.format(text, layout~) catch {
      e => {
        s.expect((name, failure(e))).to_equal((name, "formatted"))
        continue
      }
    }
    s.expect((name, markers_in_order(once, count))).to_equal((name, true))
    let twice = @printer.format(once, layout~) catch {
      e => {
        s.expect((name, failure(e))).to_equal((name, "formatted twice"))
        continue
      }
    }
    s.expect((name, twice == once)).to_equal((name, true))
  }
}

///|
test "format keeps a comment at each level of deep patterns and types" {
  let head = "module M exposing (..)\n\n\n"
  // A 300-step `::` pattern (a chain: within the default fuel's 596 steps).
  let cons = StringBuilder()
  cons.write_string(head + "f x =\n    case x of\n        ")
  for i in 0..<300 {
    cons.write_string("a\{i} {- c\{i} -} :: ")
  }
  cons.write_string("[] ->\n            1\n\n        _ ->\n            2\n")
  // 140 nested parenthesized patterns (within the 149 nesting levels).
  let parens = StringBuilder()
  parens.write_string(head + "f ")
  for i in 0..<140 {
    parens.write_string("({- c\{i} -} ")
  }
  parens.write_string("x" + ")".repeat(140) + " =\n    1\n")
  // A 300-step `->` signature.
  let arrows = StringBuilder()
  arrows.write_string(head + "f : ")
  for i in 0..<300 {
    arrows.write_string("Int {- c\{i} -} -> ")
  }
  arrows.write_string("Int\nf =\n    f\n")
  @expect.expect_all(s => {
    deep_comments_hold(s, "cons", cons.to_string(), 300)
    deep_comments_hold(s, "parens", parens.to_string(), 140)
    deep_comments_hold(s, "arrows", arrows.to_string(), 300)
  })
}
