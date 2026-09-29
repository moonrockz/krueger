///|
/// Canonical JSON text: object keys sorted, numbers rebuilt from their value,
/// no whitespace. Oracle output and krueger output both pass through here.
fn canonical(json : Json) -> String {
  normalize(json).stringify()
}

///|
fn normalize(json : Json) -> Json {
  match json {
    Number(n, ..) => Json::number(n)
    Array(items) => Json::array(items.map(normalize))
    Object(fields) => {
      let keys = fields.keys().collect()
      keys.sort()
      let sorted : Map[String, Json] = Map([])
      for k in keys {
        sorted[k] = normalize(fields.get(k).unwrap())
      }
      Json::object(sorted)
    }
    other => other
  }
}

///|
/// Lowercase hex SHA-256 of the UTF-8 bytes of `text`.
fn sha256_hex(text : String) -> String {
  @hex.encode(Bytes::from_array(@crypto.sha256(@utf8.encode(text))))
}

///|
/// Lowercase hex SHA-256 of raw bytes (corpus source files).
fn sha256_bytes_hex(bytes : Bytes) -> String {
  @hex.encode(Bytes::from_array(@crypto.sha256(bytes)))
}
