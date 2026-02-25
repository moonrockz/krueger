# CI Coverage Reporting And PR Coverage Gate Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add CI-only coverage reporting with PR blocking gate at 80% and push warning mode, while increasing baseline coverage with targeted tests.

**Architecture:** Implement a repository coverage script that computes aggregate branch coverage from MoonBit raw coverage artifacts produced by `moon test --enable-coverage`. Expose it via mise tasks and wire a CI coverage job that selects `warn` vs `gate` mode by event type.

**Tech Stack:** MoonBit, Bash, jq, file-based mise tasks, GitHub Actions.

---

### Task 1: Add failing parser tests for uncovered behavior

**Files:**
- Modify: `src/parser/lib_test.mbt`

**Steps:**
1. Add failing tests for `parse_module` passthrough when scanner returns diagnostics.
2. Run targeted parser tests and verify RED.
3. Implement minimal parser/test support if needed.
4. Re-run parser tests to GREEN.
5. Commit.

### Task 2: Implement coverage aggregation script with warn/gate modes

**Files:**
- Create: `scripts/coverage_ci.sh`

**Steps:**
1. Add script tests by running script with expected arguments and verify failure states (RED behavior checks).
2. Implement script to:
   - clear prior coverage artifacts,
   - run `moon test src --target js --enable-coverage`,
   - run `moon test src/bdd --target js --enable-coverage`,
   - run `moon test src/e2e --target js --enable-coverage`,
   - aggregate coverage with jq,
   - print summary,
   - fail only in `gate` mode when below threshold.
3. Validate script locally in `warn` and `gate` mode.
4. Commit.

### Task 3: Add mise coverage tasks

**Files:**
- Create: `mise-tasks/coverage/ci-warn`
- Create: `mise-tasks/coverage/ci-gate`
- Create: `mise-tasks/coverage/_default`

**Steps:**
1. Add task files referencing `scripts/coverage_ci.sh` with threshold 80.
2. Run `mise run coverage:ci-warn` and verify success output.
3. Run `mise run coverage:ci-gate` and verify behavior.
4. Commit.

### Task 4: Wire coverage into CI workflow

**Files:**
- Modify: `.github/workflows/ci.yml`

**Steps:**
1. Add `coverage` job with setup steps aligned to existing jobs.
2. In job commands, select mode by event:
   - `pull_request` -> `mise run coverage:ci-gate`
   - otherwise -> `mise run coverage:ci-warn`
3. Validate workflow YAML formatting.
4. Commit.

### Task 5: Final verification and tracking

**Files:**
- Modify: `.beads/issues.jsonl` (auto)

**Steps:**
1. Run full checks: `mise run check`.
2. Run coverage tasks explicitly.
3. Close `krueger-8fg` with completion reason.
4. Push branch.
