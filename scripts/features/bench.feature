Feature: Benchmarks
  The benchmark script merges the raw results of each target, compares a
  run with a baseline run from the history and writes the summary.

  Scenario: All targets when none are given
    When I choose the targets ""
    Then the targets are "native,js,wasm-gc,wasm"

  Scenario: Targets with spaces and an empty item
    When I choose the targets " native, js,"
    Then the targets are "native,js"

  Scenario: Repeated targets are kept once, in the order given
    When I choose the targets "js,native,js"
    Then the targets are "js,native"

  Scenario: An unknown target names the valid ones
    When I choose the targets "native,llvm"
    Then target selection fails with "unknown target llvm; valid targets: native, js, wasm-gc, wasm"

  Scenario: Run file path from the run date, commit and run id
    Given a results file from "refs/heads/main" at commit "8e2daea33050cff6e323dde1c9825a42814d383b" on "2026-10-01T18:05:12Z" with run id "1234567890"
    Then its run file path is "runs/2026/10/20261001T180512Z-8e2daea-1234567890.json"

  Scenario: A results file survives a JSON round trip
    Given a results file from "refs/heads/main" at commit "8e2daea33050cff6e323dde1c9825a42814d383b" on "2026-10-01T18:05:12Z" with run id "1"
    And the current run has "native" "syntax/walk/large" with median 100, q1 95 and q3 105
    Then the results file reads back unchanged

  Scenario: CPU model from /proc/cpuinfo
    When I read the CPU from:
      """
      processor	: 0
      vendor_id	: AuthenticAMD
      model name	: AMD EPYC 7763 64-Core Processor
      """
    Then the CPU is "AMD EPYC 7763 64-Core Processor"

  Scenario: CPU model from sysctl
    When I read the CPU from:
      """
      Apple M3 Max
      """
    Then the CPU is "Apple M3 Max"

  Scenario: Slower, faster and within noise
    Given a baseline run from "refs/heads/main" at commit "1111111aaaa" on "2026-09-30T10:00:00Z" with run id "1"
    And the baseline run has "native" "syntax/walk/large" with median 100, q1 95 and q3 105
    And the baseline run has "native" "syntax/node_at/large" with median 100, q1 95 and q3 105
    And the baseline run has "native" "corpus/parse/corpus" with median 100, q1 90 and q3 110
    And a results file from "refs/heads/main" at commit "2222222bbbb" on "2026-10-01T10:00:00Z" with run id "2"
    And the current run has "native" "syntax/walk/large" with median 130, q1 125 and q3 135
    And the current run has "native" "syntax/node_at/large" with median 50, q1 45 and q3 55
    And the current run has "native" "corpus/parse/corpus" with median 115, q1 105 and q3 125
    When I compare the runs
    Then the marks are:
      """
      native syntax/walk/large slower
      native syntax/node_at/large faster
      native corpus/parse/corpus ~
      """

  Scenario: Exactly 10 percent is within noise
    Given a baseline run from "refs/heads/main" at commit "1111111aaaa" on "2026-09-30T10:00:00Z" with run id "1"
    And the baseline run has "js" "syntax/walk/large" with median 100, q1 100 and q3 100
    And a results file from "refs/heads/main" at commit "2222222bbbb" on "2026-10-01T10:00:00Z" with run id "2"
    And the current run has "js" "syntax/walk/large" with median 110, q1 110 and q3 110
    When I compare the runs
    Then the marks are:
      """
      js syntax/walk/large ~
      """

  Scenario: New and removed cases
    Given a baseline run from "refs/heads/main" at commit "1111111aaaa" on "2026-09-30T10:00:00Z" with run id "1"
    And the baseline run has "native" "syntax/old/large" with median 100, q1 95 and q3 105
    And a results file from "refs/heads/main" at commit "2222222bbbb" on "2026-10-01T10:00:00Z" with run id "2"
    And the current run has "native" "syntax/new/large" with median 100, q1 95 and q3 105
    When I compare the runs
    Then the marks are:
      """
      native syntax/new/large new
      native syntax/old/large removed
      """

  Scenario: Targets that this run did not measure are listed once
    Given a baseline run from "refs/heads/main" at commit "1111111aaaa" on "2026-09-30T10:00:00Z" with run id "1"
    And the baseline run has "native" "syntax/walk/large" with median 100, q1 95 and q3 105
    And the baseline run has "wasm" "syntax/walk/large" with median 100, q1 95 and q3 105
    And a results file from "refs/heads/main" at commit "2222222bbbb" on "2026-10-01T10:00:00Z" with run id "2"
    And the current run has "native" "syntax/walk/large" with median 100, q1 95 and q3 105
    When I compare the runs
    Then the marks are:
      """
      native syntax/walk/large ~
      """
    And the targets not run are "wasm"

  Scenario: Different CPU and toolchain
    Given a baseline run from "refs/heads/main" at commit "1111111aaaa" on "2026-09-30T10:00:00Z" with run id "1"
    And the baseline ran on CPU "Intel Xeon" with toolchain "t0"
    And a results file from "refs/heads/main" at commit "2222222bbbb" on "2026-10-01T10:00:00Z" with run id "2"
    When I compare the runs
    Then the warnings are:
      """
      The baseline ran on another CPU (Intel Xeon; this run: cpu-a). Compare with care.
      The baseline used another toolchain (t0; this run: t1). Compare with care.
      """

  Scenario: No baseline
    Given a results file from "refs/heads/main" at commit "2222222bbbb" on "2026-10-01T10:00:00Z" with run id "2"
    And the current run has "native" "syntax/walk/large" with median 1500, q1 1400 and q3 1600
    When I compare the runs
    Then the summary is:
      """
      ## Benchmarks

      Current: `main` @ `2222222` (2026-10-01T10:00:00Z, [run 2](https://example.test/run/2)) on Linux, cpu-a
      Baseline: none (no earlier run in the history)

      ### native

      | Case | Baseline | Current | Change | Mark |
      |---|---:|---:|---:|---|
      | syntax/walk/large |  | 1.5 ms |  | new |

      Marks: slower or faster when the median changes by more than 10% and the interquartile ranges do not overlap; ~ otherwise. Benchmarks are not a gate.
      """

  Scenario: Summary with a baseline puts changed rows first
    Given a baseline run from "refs/heads/main" at commit "1111111aaaa" on "2026-09-30T10:00:00Z" with run id "1"
    And the baseline run has "native" "corpus/parse/corpus" with median 100, q1 90 and q3 110
    And the baseline run has "native" "syntax/node_path_all/large" with median 470000, q1 465000 and q3 475000
    And a results file from "refs/heads/main" at commit "2222222bbbb" on "2026-10-01T10:00:00Z" with run id "2"
    And the current run has "native" "corpus/parse/corpus" with median 101, q1 91 and q3 111
    And the current run has "native" "syntax/node_path_all/large" with median 20100, q1 20000 and q3 20200
    When I compare the runs
    Then the summary is:
      """
      ## Benchmarks

      Current: `main` @ `2222222` (2026-10-01T10:00:00Z, [run 2](https://example.test/run/2)) on Linux, cpu-a
      Baseline: `main` @ `1111111` (2026-09-30T10:00:00Z, [run 1](https://example.test/run/1)) on Linux, cpu-a

      ### native

      | Case | Baseline | Current | Change | Mark |
      |---|---:|---:|---:|---|
      | syntax/node_path_all/large | 470.0 ms | 20.1 ms | -95.7% | faster |
      | corpus/parse/corpus | 100.0 µs | 101.0 µs | +1.0% | ~ |

      Marks: slower or faster when the median changes by more than 10% and the interquartile ranges do not overlap; ~ otherwise. Benchmarks are not a gate.
      """

  Scenario: Baseline selection
    Given the history:
      """
      runs/a.json refs/heads/main 1111111aaaa 1 2026-09-01T00:00:00Z
      runs/b.json refs/heads/main 2222222bbbb 2 2026-09-15T00:00:00Z
      runs/c.json refs/heads/feature 3333333cccc 3 2026-09-20T00:00:00Z
      """
    And a results file from "refs/heads/main" at commit "4444444dddd" on "2026-10-01T10:00:00Z" with run id "4"
    Then the baseline for "" is "runs/b.json"
    And the baseline for "1111111" is "runs/a.json"
    And the baseline for "run:3" is "runs/c.json"
    And the baseline for "9999999" is "none"

  Scenario: The HTML report has the tables and a trend per case
    Given the history:
      """
      runs/a.json refs/heads/main 1111111aaaa 1 2026-09-01T00:00:00Z
      runs/b.json refs/heads/main 2222222bbbb 2 2026-09-15T00:00:00Z
      """
    And every history run has "native" "syntax/walk/large" with median 100, q1 95 and q3 105
    And a results file from "refs/heads/main" at commit "4444444dddd" on "2026-10-01T10:00:00Z" with run id "4"
    And the current run has "native" "syntax/walk/large" with median 90, q1 85 and q3 95
    And the current run has "native" "syntax/<new>/large" with median 1, q1 1 and q3 1
    When I compare the runs with the history
    Then the HTML report contains "<h2>native</h2>"
    And the HTML report contains "syntax/walk/large"
    And the HTML report contains "syntax/&lt;new&gt;/large"
    And the HTML report contains 1 trend chart
    And the HTML report loads nothing from the network

  Scenario: The default baseline covers every target of the run
    Given the history:
      """
      runs/full.json refs/heads/main 1111111aaaa 1 2026-09-01T00:00:00Z
      runs/native.json refs/heads/main 2222222bbbb 2 2026-09-15T00:00:00Z
      """
    And history run "runs/full.json" measured "native,js,wasm-gc,wasm"
    And history run "runs/native.json" measured "native"
    And a results file from "refs/heads/main" at commit "4444444dddd" on "2026-10-01T10:00:00Z" with run id "4"
    And the current run has "native" "syntax/walk/large" with median 100, q1 95 and q3 105
    And the current run has "js" "syntax/walk/large" with median 100, q1 95 and q3 105
    Then the baseline for "" is "runs/full.json"

  Scenario: A native-only run takes the latest run with native
    Given the history:
      """
      runs/full.json refs/heads/main 1111111aaaa 1 2026-09-01T00:00:00Z
      runs/native.json refs/heads/main 2222222bbbb 2 2026-09-15T00:00:00Z
      """
    And history run "runs/full.json" measured "native,js,wasm-gc,wasm"
    And history run "runs/native.json" measured "native"
    And a results file from "refs/heads/main" at commit "4444444dddd" on "2026-10-01T10:00:00Z" with run id "4"
    And the current run has "native" "syntax/walk/large" with median 100, q1 95 and q3 105
    Then the baseline for "" is "runs/native.json"

  Scenario: A baseline that matches nothing is an error, not an empty history
    Given the history:
      """
      runs/a.json refs/heads/main 1111111aaaa 1 2026-09-01T00:00:00Z
      """
    And a results file from "refs/heads/main" at commit "4444444dddd" on "2026-10-01T10:00:00Z" with run id "4"
    Then choosing the baseline "main" fails with "no run file for main in the history"
    And choosing the baseline "run:77" fails with "no run file for run:77 in the history"
    And choosing the baseline "" gives "runs/a.json"
