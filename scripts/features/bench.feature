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
