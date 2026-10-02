///|
/// A document description for laws: it builds a `Doc` and is the input of
/// the reference model. Texts hold no spaces.
enum Spec {
  SText(String)
  SLine
  SSoft
  SHard
  SNest(Int, Spec)
  STab(Int, Spec)
  SGroup(Spec)
  SCat(Spec, Spec)
} derive(Debug)

///|
fn pick(rs : @splitmix.RandomState, n : Int) -> Int {
  rs.next_uint(limit=n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
fn gen_spec(size : Int, rs : @splitmix.RandomState) -> Spec {
  if size <= 1 {
    return match pick(rs, 8) {
      0 => SLine
      1 => SSoft
      2 => SHard
      _ => SText(["a", "bb", "ccc", "é😀", "dddd"][pick(rs, 5)])
    }
  }
  let s = size / 2
  match pick(rs, 7) {
    0 => SNest(pick(rs, 5), gen_spec(s, rs))
    6 => STab(pick(rs, 5), gen_spec(s, rs))
    1 | 2 => SGroup(gen_spec(s, rs))
    _ => SCat(gen_spec(s, rs), gen_spec(s, rs))
  }
}

///|
struct Arb(Spec) derive(Debug)

///|
impl @quickcheck.Arbitrary for Arb with fn arbitrary(size, rs) {
  Arb(gen_spec(size, rs))
}

///|
impl @quickcheck.Shrink for Arb

///|
struct Three(Spec, Spec, Spec) derive(Debug)

///|
impl @quickcheck.Arbitrary for Three with fn arbitrary(size, rs) {
  Three(gen_spec(size, rs), gen_spec(size, rs), gen_spec(size, rs))
}

///|
impl @quickcheck.Shrink for Three

///|
fn to_doc(s : Spec) -> @pretty.Doc {
  match s {
    SText(t) => @pretty.text(t)
    SLine => @pretty.line()
    SSoft => @pretty.softline()
    SHard => @pretty.hardline()
    SNest(n, x) => @pretty.nest(n, to_doc(x))
    STab(n, x) => @pretty.tab(n, to_doc(x))
    SGroup(x) => @pretty.group(to_doc(x))
    SCat(a, b) => to_doc(a) + to_doc(b)
  }
}

///|
fn has_hard(s : Spec) -> Bool {
  match s {
    SHard => true
    SNest(_, x) | STab(_, x) | SGroup(x) => has_hard(x)
    SCat(a, b) => has_hard(a) || has_hard(b)
    _ => false
  }
}

///|
fn flat_text(s : Spec) -> String {
  match s {
    SText(t) => t
    SLine => " "
    SSoft | SHard => ""
    SNest(_, x) | STab(_, x) | SGroup(x) => flat_text(x)
    SCat(a, b) => flat_text(a) + flat_text(b)
  }
}

///|
fn cols(s : String) -> Int {
  let mut n = 0
  for _ in s {
    n += 1
  }
  n
}

///|
struct Item {
  indent : Int
  flat : Bool
  spec : Spec
}

///|
/// The spec's fit rule, written naively: the items fit when the text up to
/// the first break (a line in break mode or a hard line) fits in `left`.
fn model_fits(left : Int, items : @list.List[Item]) -> Bool {
  match items {
    Empty => left >= 0
    More(item, tail~) =>
      left >= 0 &&
      (match item.spec {
        SText(t) => model_fits(left - cols(t), tail)
        SLine => if item.flat { model_fits(left - 1, tail) } else { true }
        SSoft => if item.flat { model_fits(left, tail) } else { true }
        SHard => true
        SNest(_, x) | STab(_, x) | SGroup(x) =>
          model_fits(left, tail.add({ ..item, spec: x, }))
        SCat(a, b) =>
          model_fits(
            left,
            tail.add({ ..item, spec: b, }).add({ ..item, spec: a, }),
          )
      })
  }
}

///|
/// Reference renderer: writes indentation and spaces at once, then removes
/// trailing spaces from each line.
fn model_render(spec : Spec, width : Int) -> String {
  let lines : Array[String] = []
  let mut line = ""
  let mut items : @list.List[Item] = @list.empty().add({
    indent: 0,
    flat: false,
    spec,
  })
  while items is More(item, tail~) {
    items = tail
    match item.spec {
      SText(t) => line = line + t
      SLine | SSoft if item.flat =>
        line = line + (if item.spec is SLine { " " } else { "" })
      SLine | SSoft | SHard => {
        lines.push(line)
        line = " ".repeat(item.indent)
      }
      SNest(n, x) =>
        items = items.add({ ..item, indent: item.indent + n, spec: x, })
      STab(n, x) => {
        // Written apart from the engine's `next_stop`: count up to the stop.
        let mut stop = item.indent
        if n > 0 {
          stop += 1
          while stop % n != 0 {
            stop += 1
          }
        }
        items = items.add({ ..item, indent: stop, spec: x, })
      }
      SGroup(x) => {
        let flat = item.flat ||
          (
            !has_hard(x) &&
            model_fits(
              width - cols(line),
              items.add({ ..item, flat: true, spec: x, }),
            )
          )
        items = items.add({ ..item, flat, spec: x, })
      }
      SCat(a, b) =>
        items = items.add({ ..item, spec: b, }).add({ ..item, spec: a, })
    }
  }
  lines.push(line)
  lines.map(l => l.trim_end(chars=" ").to_owned()).join("\n")
}

///|
let widths : Array[Int] = [0, 1, 5, 10, 20, 80]

///|
test "law: render agrees with the reference model at every width" {
  @quickcheck.check(
    (a : Arb) => {
      let Arb(s) = a
      widths
      .iter()
      .all(w => @pretty.render(to_doc(s), width=w) == model_render(s, w))
    },
    count=500,
    max_size=40,
    seed=2026,
  )
}

///|
test "law: concat is associative and empty is its identity" {
  @quickcheck.check(
    (t : Three) => {
      let Three(a, b, c) = t
      let (x, y, z) = (to_doc(a), to_doc(b), to_doc(c))
      widths
      .iter()
      .all(w => {
        @pretty.render(x + y + z, width=w) ==
        @pretty.render(x + (y + z), width=w) &&
        @pretty.render(@pretty.empty() + x, width=w) ==
        @pretty.render(x, width=w) &&
        @pretty.render(x + @pretty.empty(), width=w) ==
        @pretty.render(x, width=w)
      })
    },
    count=300,
    max_size=30,
    seed=2027,
  )
}

///|
test "law: nest 0 and a second group change nothing" {
  @quickcheck.check(
    (a : Arb) => {
      let Arb(s) = a
      let d = to_doc(s)
      widths
      .iter()
      .all(w => {
        @pretty.render(@pretty.nest(0, d), width=w) ==
        @pretty.render(d, width=w) &&
        @pretty.render(@pretty.group(@pretty.group(d)), width=w) ==
        @pretty.render(@pretty.group(d), width=w)
      })
    },
    count=300,
    max_size=40,
    seed=2028,
  )
}

///|
test "law: with a very large width a group without hard lines is flat" {
  @quickcheck.check(
    (a : Arb) => {
      let Arb(s) = a
      has_hard(s) ||
      @pretty.render(@pretty.group(to_doc(s)), width=1_000_000) ==
      flat_text(s).trim_end(chars=" ").to_owned()
    },
    count=300,
    max_size=40,
    seed=2029,
  )
}

///|
test "law: output has no trailing whitespace" {
  @quickcheck.check(
    (a : Arb) => {
      let Arb(s) = a
      widths
      .iter()
      .all(w => {
        @pretty.render(to_doc(s), width=w)
        .split("\n")
        .all(l => !l.has_suffix(" "))
      })
    },
    count=300,
    max_size=40,
    seed=2030,
  )
}

///|
fn without_whitespace(s : String) -> String {
  let b = StringBuilder()
  for c in s {
    if c != ' ' && c != '\n' {
      b.write_char(c)
    }
  }
  b.to_string()
}

///|
test "law: renders at two widths differ only in whitespace" {
  @quickcheck.check(
    (a : Arb) => {
      let Arb(s) = a
      let d = to_doc(s)
      without_whitespace(@pretty.render(d, width=0)) ==
      without_whitespace(@pretty.render(d, width=1000))
    },
    count=300,
    max_size=40,
    seed=2031,
  )
}
