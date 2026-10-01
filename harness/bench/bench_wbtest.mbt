///|
/// The benchmarks. `KRUEGER_BENCH_MODE` selects smoke or run (see
/// `mode_wbtest.mbt`); `scripts/bench.mbtx run` sets it.
test "benchmarks" {
  let mode = bench_mode()
  let sources = sources_for(mode)
  let large : Source = {
    key: "large",
    text: large_module(
      match mode {
        Smoke => 5
        Run(_) => 1000
      },
    ),
  }
  let cases = [
    ..corpus_cases(sources),
    ..syntax_cases("corpus", sources),
    ..syntax_cases("large", [large]),
  ]
  run_cases(cases, mode)
}
