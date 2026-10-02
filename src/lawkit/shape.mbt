///|
/// The elm-syntax JSON of `file` without ranges. The `range` field of each
/// node is removed. The range of an `exposing (..)` (field `all`) and of an
/// exposed type's `(..)` (field `open`) becomes `true`; an `open` with no
/// `(..)` stays `null`.
/// Two files with the same shape differ only in their ranges. Comments stay.
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
  strip_ranges(@ast.encode_file(file))
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
    _ => j
  }
}
