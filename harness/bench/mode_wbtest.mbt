///|
/// Benchmarks of the corpus and the syntax tree, controlled by
/// `KRUEGER_BENCH_MODE`:
///
/// - unset, empty or `smoke`: run each case once on small input and check
///   its result (part of `mise run test`).
/// - `run`: measure each case and write `<raw_dir>/<target>.json`; the
///   target comes from `KRUEGER_BENCH_TARGET` (`scripts/bench.mbtx` sets
///   both).
priv enum Mode {
  Smoke
  Run(String)
} derive(Eq, Debug)

///|
let raw_dir : String = "../_build/reports/bench/raw"

///|
fn mode_of(mode : String?, target : String?) -> Result[Mode, String] {
  match mode {
    None | Some("") | Some("smoke") => Ok(Smoke)
    Some("run") =>
      match target {
        Some(t) if t != "" => Ok(Run(t))
        _ => Err("KRUEGER_BENCH_MODE=run needs KRUEGER_BENCH_TARGET")
      }
    Some(other) => Err("unknown KRUEGER_BENCH_MODE: \{other}")
  }
}

///|
fn bench_mode() -> Mode raise {
  match
    mode_of(
      @env.get_env_var("KRUEGER_BENCH_MODE"),
      @env.get_env_var("KRUEGER_BENCH_TARGET"),
    ) {
    Ok(mode) => mode
    Err(message) => fail(message)
  }
}

///|
/// One benchmark case. `run` is the measured work; it returns a size (a
/// count of tokens, nodes, …) so that the work is not optimized away.
/// `check` runs the work once and fails when its result is wrong.
priv struct Case {
  suite : String
  name : String
  input : String
  run : () -> Int32
  check : () -> Unit raise
}

///|
fn Case::id(self : Case) -> String {
  "\{self.suite}/\{self.name}/\{self.input}"
}

///|
/// Keeps the sizes that `run` returns, so the measured work is used.
let sink : Ref[Int32] = { val: 0, }

///|
fn number(o : Map[String, Json], key : String) -> Double raise {
  guard o.get(key) is Some(Number(x, ..)) else {
    fail("bench summary: missing number \{key}")
  }
  x
}

///|
/// The result of one case for the raw file, from a core `Summary` as JSON
/// (microseconds per call of `run`).
fn result_json(c : Case, target : String, summary : Json) -> Json raise {
  guard summary is Object(o) &&
    o.get("quartiles") is Some(Array([Number(q1, ..), _, Number(q3, ..)])) else {
    fail("bench summary: missing quartiles")
  }
  {
    "target": Json(target),
    "suite": Json(c.suite),
    "case": Json(c.name),
    "input": Json(c.input),
    "unit": "us",
    "median": Json(number(o, "median")),
    "mean": Json(number(o, "mean")),
    "min": Json(number(o, "min")),
    "max": Json(number(o, "max")),
    "std_dev": Json(number(o, "std_dev")),
    "q1": Json(q1),
    "q3": Json(q3),
    "iqr": Json(number(o, "iqr")),
    "runs": Json(number(o, "runs").to_int()),
    "batch_size": Json(number(o, "batch_size").to_int()),
  }
}

///|
/// Smoke: check every case. Run: check, then measure every case and write
/// the raw file (a wrong result on real input fails the run).
fn run_cases(cases : Array[Case], mode : Mode) -> Unit raise {
  match mode {
    Smoke =>
      for c in cases {
        (c.check)()
      }
    Run(target) => {
      let results : Array[Json] = []
      for c in cases {
        (c.check)()
        let summary = @bench.single_bench(
          name=c.id(),
          () => sink.val = sink.val + (c.run)(),
          count=10,
        )
        results.push(result_json(c, target, @json.to_json(summary)))
        println("bench \{target} \{c.id()}")
      }
      for
        dir in [
          "../_build", "../_build/reports", "../_build/reports/bench", raw_dir,
        ] {
        if !@fs.path_exists(dir) {
          @fs.create_dir(dir)
        }
      }
      let raw : Json = { "target": Json(target), "results": Json(results) }
      @fs.write_string_to_file("\{raw_dir}/\{target}.json", raw.stringify())
    }
  }
}

///|
test "mode_of reads smoke, run with a target, and rejects the rest" {
  @expect.expect_all(s => {
    s.expect(mode_of(None, None)).to_equal(Ok(Smoke))
    s.expect(mode_of(Some(""), None)).to_equal(Ok(Smoke))
    s.expect(mode_of(Some("smoke"), Some("js"))).to_equal(Ok(Smoke))
    s.expect(mode_of(Some("run"), Some("wasm-gc"))).to_equal(Ok(Run("wasm-gc")))
    s
    .expect(mode_of(Some("run"), None))
    .to_equal(Err("KRUEGER_BENCH_MODE=run needs KRUEGER_BENCH_TARGET"))
    s
    .expect(mode_of(Some("fast"), None))
    .to_equal(Err("unknown KRUEGER_BENCH_MODE: fast"))
  })
}

///|
test "result_json keeps the summary fields the script reads" {
  let c : Case = {
    suite: "syntax",
    name: "walk",
    input: "large",
    run: () => 1,
    check: () => (),
  }
  let summary : Json = {
    "name": "syntax/walk/large",
    "sum": 30.0,
    "min": 2.0,
    "max": 4.0,
    "mean": 3.0,
    "median": 3.0,
    "variance": 0.5,
    "std_dev": 0.7,
    "std_dev_pct": 23.0,
    "median_abs_dev": 0.5,
    "median_abs_dev_pct": 16.0,
    "quartiles": [2.5, 3.0, 3.5],
    "iqr": 1.0,
    "batch_size": 7,
    "runs": 10,
  }
  @expect.expect(result_json(c, "native", summary)).to_equal({
    "target": "native",
    "suite": "syntax",
    "case": "walk",
    "input": "large",
    "unit": "us",
    "median": 3.0,
    "mean": 3.0,
    "min": 2.0,
    "max": 4.0,
    "std_dev": 0.7,
    "q1": 2.5,
    "q3": 3.5,
    "iqr": 1.0,
    "runs": 10,
    "batch_size": 7,
  })
}
