///|
/// The benchmarks. `KRUEGER_BENCH_MODE` selects smoke or run (see
/// `mode_wbtest.mbt`); `scripts/bench.mbtx run` sets it.
test "benchmarks" {
  let mode = bench_mode()
  let sources = sources_for(mode)
  run_cases(corpus_cases(sources), mode)
}
