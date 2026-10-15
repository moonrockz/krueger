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
/// `j` without ranges (see `without_ranges`), built without recursion: a
/// JSON value from a deep AST (a long operator chain has no parser limit)
/// is thousands of levels deep, and wasm overflows at a few hundred
/// frames. Each container is copied with `null` in the slot of each child;
/// the child is queued and fills its slot when it is popped. `Map` keeps
/// its insertion order, so the keys keep theirs.
fn strip_ranges(j : Json) -> Json {
  let root : Array[Json] = [Json::null()]
  let pending : Array[(Json, (Json) -> Unit)] = [(j, v => root[0] = v)]
  while pending.pop() is Some((value, fill)) {
    match value {
      Object(o) => {
        let out : Map[String, Json] = Map([])
        for k, v in o {
          match (k, v) {
            ("range", _) => ()
            ("all" | "open", Array(_)) => out[k] = Json::boolean(true)
            _ => {
              out[k] = Json::null()
              pending.push((v, stripped => out[k] = stripped))
            }
          }
        }
        fill(Json::object(out))
      }
      Array(xs) => {
        let out : Array[Json] = Array::make(xs.length(), Json::null())
        for i, x in xs {
          pending.push((x, stripped => out[i] = stripped))
        }
        fill(Json::array(out))
      }
      // An Int that the Double does not hold exactly; `==` on `Json` would
      // see only the Double.
      Number(d, repr=Some(digits)) if d.to_int64().to_string() != digits =>
        fill(Json::string(digits))
      _ => fill(value)
    }
  }
  root[0]
}
