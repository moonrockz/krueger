///|
/// Parity counts over the corpus.
priv struct Counts {
  files : Int
  tokenized : Int
  parsed : Int
  matched : Int
}

///|
fn counts_to_json(c : Counts) -> Json {
  {
    "files": c.files.to_json(),
    "tokenized": c.tokenized.to_json(),
    "parsed": c.parsed.to_json(),
    "matched": c.matched.to_json(),
  }
}

///|
fn counts_from_json(json : Json) -> Counts raise {
  guard json is Object(o) &&
    o.get("files") is Some(Number(files, ..)) &&
    o.get("tokenized") is Some(Number(tokenized, ..)) &&
    o.get("parsed") is Some(Number(parsed, ..)) &&
    o.get("matched") is Some(Number(matched, ..)) else {
    fail("baseline: expected files, tokenized, parsed and matched counts")
  }
  {
    files: files.to_int(),
    tokenized: tokenized.to_int(),
    parsed: parsed.to_int(),
    matched: matched.to_int(),
  }
}

///|
/// Names of the counts that are below the baseline, with both values.
fn regressions(current : Counts, baseline : Counts) -> Array[String] {
  let found = []
  let pairs = [
    ("files", current.files, baseline.files),
    ("tokenized", current.tokenized, baseline.tokenized),
    ("parsed", current.parsed, baseline.parsed),
    ("matched", current.matched, baseline.matched),
  ]
  for p in pairs {
    let (name, now, min) = p
    if now < min {
      found.push("\{name}: \{now} < baseline \{min}")
    }
  }
  found
}

///|
/// One-line scoreboard, for example `parity: 363 files | tokenized 12 | parsed 3 | matched 0`.
fn scoreboard(c : Counts) -> String {
  "parity: \{c.files} files | tokenized \{c.tokenized} | parsed \{c.parsed} | matched \{c.matched}"
}

///|
/// The new baseline for a ratchet: the current counts, or an error when any
/// count is below the baseline (a ratchet never lowers it).
fn ratchet(current : Counts, baseline : Counts) -> Result[Counts, String] {
  let found = regressions(current, baseline)
  if found.is_empty() {
    Ok(current)
  } else {
    Err(found.join("; "))
  }
}
