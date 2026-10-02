///|
/// The elm-syntax JSON of `file` without ranges. The `range` field of each
/// node is removed. The range of an `exposing (..)` (field `all`) and of an
/// exposed type's `(..)` (field `open`) becomes `true`; an `open` with no
/// `(..)` stays `null`. In elm-syntax 7.3.9 JSON, `all` and `open` are the
/// only fields other than `range` that hold a range, so no other range
/// stays. Comments stay.
///
/// Int literals keep their exact value: the JSON comes from
/// `@ast.encode_file_with(file, exact_ints=true)`, and `Json` equality
/// compares numbers as Doubles, so an Int literal that a Double cannot hold
/// (above 2^53, such as `9007199254740993`) becomes a JSON string of its
/// digits. Other numbers stay numbers.
/// Two files with the same shape differ only in their ranges.
///
/// ```mbt check
/// test {
///   let a = @ast.File::{
///     module_definition: {
///       range: { start: { row: 1, column: 1, }, end: { row: 1, column: 9, }, },
///       value: NormalModule({
///         module_name: {
///           range: { start: { row: 1, column: 8, }, end: { row: 1, column: 9, }, },
///           value: ["A"][:],
///         },
///         exposing_list: {
///           range: {
///             start: { row: 1, column: 10, },
///             end: { row: 1, column: 23, },
///           },
///           value: All({
///             start: { row: 1, column: 20, },
///             end: { row: 1, column: 22, },
///           }),
///         },
///       }),
///     },
///     imports: [][:],
///     declarations: [][:],
///     comments: [][:],
///   }
///   inspect(
///     @lawkit.without_ranges(a).stringify(),
///     content=(
///       #|{"moduleDefinition":{"value":{"type":"normal","normal":{"moduleName":{"value":["A"]},"exposingList":{"value":{"type":"all","all":true}}}}},"imports":[],"declarations":[],"comments":[]}
///     ),
///   )
/// }
/// ```
pub fn without_ranges(file : @ast.File) -> Json {
  strip_ranges(@ast.encode_file_with(file, exact_ints=true))
}

///|
fn strip_ranges(j : Json) -> Json {
  match j {
    Object(o) => {
      let out : Map[String, Json] = Map([])
      for k, v in o {
        match (k, v) {
          ("range", _) => ()
          ("all" | "open", Array(_)) => out[k] = Json::boolean(true)
          _ => out[k] = strip_ranges(v)
        }
      }
      Json::object(out)
    }
    Array(xs) => Json::array(xs.map(strip_ranges))
    // An Int that the Double does not hold exactly; `==` on `Json` would
    // see only the Double.
    Number(d, repr=Some(digits)) if d.to_int64().to_string() != digits =>
      Json::string(digits)
    _ => j
  }
}
