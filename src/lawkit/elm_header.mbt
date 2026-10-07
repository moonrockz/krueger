///|
/// A valid Elm module whose header and imports exercise elm-format's
/// order: an exposing list of operators, types (with and without `(..)`)
/// and values in any order, with duplicates; module documentation with
/// `@docs` lines that name some of the items; imports of a few modules in
/// any order, with aliases and exposing lists. Edge values: one exposed
/// item; a multi-line exposing list; no documentation; `@docs` lines that
/// name an item twice, `T(..)`, an operator of three characters or a name
/// that is not exposed; no imports; the same module imported more than
/// once; an alias equal to the module name; `(..)` and a list for the same
/// module.
pub(all) struct ElmHeader(String) derive(Debug)

///|
/// The module's source text.
pub fn ElmHeader::text(self : ElmHeader) -> String {
  let ElmHeader(text) = self
  text
}

///|
/// The items that a header can expose, as an exposing list writes them.
let header_items : Array[String] = [
  "a", "b", "zed", "map", "T", "T(..)", "Msg", "Model(..)", "(+)", "(</>)", "(<?>)",
]

///|
/// The names that a `@docs` line can give (some name no exposed item).
let header_docs_names : Array[String] = [
  "a", "b", "zed", "map", "T", "T(..)", "Msg", "Model", "(+)", "(</>)", "(<?>)",
  "missing",
]

///|
let header_modules : Array[String] = [
  "Dict", "Html.Events", "Html", "A.B", "Set",
]

///|
let header_import_items : Array[String] = ["x", "y", "T", "T(..)", "(+)", "Z"]

///|
/// `count` items from `pool`, picked at random (duplicates allowed).
fn some_of(
  rs : @splitmix.RandomState,
  pool : Array[String],
  count : Int,
) -> Array[String] {
  let out = []
  for _ in 0..<count {
    out.push(one(rs, pool))
  }
  out
}

///|
fn header_import(rs : @splitmix.RandomState) -> String {
  let name = one(rs, header_modules)
  let alias_part = match pick(rs, 4) {
    0 => " as D"
    1 if !name.contains(".") => " as " + name
    _ => ""
  }
  let exposing_part = match pick(rs, 3) {
    0 => " exposing (..)"
    1 =>
      " exposing (" +
      some_of(rs, header_import_items, 1 + pick(rs, 3)).join(", ") +
      ")"
    _ => ""
  }
  "import " + name + alias_part + exposing_part
}

///|
pub impl @quickcheck.Arbitrary for ElmHeader with fn arbitrary(size, rs) {
  let count = 1 + pick(rs, size / 2 + 2)
  let items = some_of(rs, header_items, count)
  let separator = if pick(rs, 3) == 0 { ",\n    " } else { ", " }
  let sb = StringBuilder()
  sb.write_string("module M exposing (" + items.join(separator) + ")\n\n")
  if pick(rs, 3) > 0 {
    sb.write_string("{-| Doc.\n\n")
    for _ in 0..<pick(rs, 4) {
      let names = some_of(rs, header_docs_names, 1 + pick(rs, 3))
      sb.write_string("@docs " + names.join(", ") + "\n")
    }
    sb.write_string("\n-}\n\n")
  }
  for _ in 0..<pick(rs, size / 3 + 2) {
    sb.write_string(header_import(rs) + "\n")
  }
  sb.write_string("\n\na =\n    1\n")
  ElmHeader(sb.to_string())
}

///|
pub impl @quickcheck.Shrink for ElmHeader
