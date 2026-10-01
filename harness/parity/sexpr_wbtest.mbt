///|
/// Render elm-syntax JSON as a compact S-expression, in the style of
/// tree-sitter `parse` output. Nodes print as `<value> @r1:c1-r2:c2`,
/// tagged values as `(tag <value>)`, and objects as `(key: value ...)`.
fn sexpr(json : Json) -> String {
  match json {
    Null => "nil"
    True => "true"
    False => "false"
    Number(n, ..) => Json::number(n).stringify()
    String(s) => s.to_json().stringify()
    Array(items) => "[" + items.map(sexpr).join(" ") + "]"
    Object(o) =>
      match (o.get("range"), o.get("value"), o.get("type")) {
        (
          Some(
            Array(
              [Number(r1, ..), Number(c1, ..), Number(r2, ..), Number(c2, ..)]
            )
          ),
          Some(value),
          None,
        ) if o.length() == 2 =>
          "\{sexpr(value)} @\{r1.to_int()}:\{c1.to_int()}-\{r2.to_int()}:\{c2.to_int()}"
        (_, _, Some(String(tag))) if o.length() == 2 =>
          match o.get(tag) {
            Some(value) => "(\{tag} \{sexpr(value)})"
            None => fields_sexpr(o)
          }
        _ => fields_sexpr(o)
      }
  }
}

///|
fn fields_sexpr(o : Map[String, Json]) -> String {
  let keys = o.keys().collect()
  keys.sort()
  "(" + keys.map(k => "\{k}: \{sexpr(o.get(k).unwrap())}").join(" ") + ")"
}

///|
/// The first place where two JSON values differ.
priv struct Difference {
  path : String
  expected : Json
  actual : Json
}

///|
/// Depth-first search for the first difference; object keys are visited in
/// sorted order. Returns `None` when the values are equal.
fn first_difference(expected : Json, actual : Json) -> Difference? {
  diff_at("$", expected, actual)
}

///|
fn diff_at(path : String, expected : Json, actual : Json) -> Difference? {
  match (expected, actual) {
    (Array(e), Array(a)) => {
      let n = if e.length() < a.length() { e.length() } else { a.length() }
      for i in 0..<n {
        if diff_at("\{path}[\{i}]", e[i], a[i]) is Some(d) {
          return Some(d)
        }
      }
      if e.length() != a.length() {
        Some({ path, expected, actual, })
      } else {
        None
      }
    }
    (Object(e), Object(a)) => {
      let keys = e.keys().collect()
      for k in a.keys() {
        if !e.contains(k) {
          keys.push(k)
        }
      }
      keys.sort()
      for k in keys {
        match (e.get(k), a.get(k)) {
          (Some(ev), Some(av)) =>
            if diff_at("\{path}.\{k}", ev, av) is Some(d) {
              return Some(d)
            }
          _ => return Some({ path: "\{path}.\{k}", expected, actual, })
        }
      }
      None
    }
    (Number(e, ..), Number(a, ..)) =>
      if e == a {
        None
      } else {
        Some({ path, expected, actual, })
      }
    _ =>
      if expected == actual {
        None
      } else {
        Some({ path, expected, actual, })
      }
  }
}
