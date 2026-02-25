#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
threshold="${2:-80}"

if [ "$mode" != "warn" ] && [ "$mode" != "gate" ]; then
  echo "Usage: scripts/coverage_ci.sh <warn|gate> [threshold]" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to parse MoonBit coverage artifacts" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

rm -f _build/moonbit_coverage_*.txt

moon test src/scanner --target js --enable-coverage
moon test src/parser --target js --enable-coverage
moon test src --target js --enable-coverage
moon test src/bdd --target js --enable-coverage
moon test src/e2e --target js --enable-coverage

shopt -s nullglob
coverage_files=( _build/moonbit_coverage_*.txt )
if [ ${#coverage_files[@]} -eq 0 ]; then
  echo "No MoonBit coverage artifacts were produced" >&2
  exit 1
fi

tmp_json="$(mktemp)"
tmp_agg="$(mktemp)"
trap 'rm -f "$tmp_json" "$tmp_agg"' EXIT

for file in "${coverage_files[@]}"; do
  awk '/----- BEGIN MOONBIT COVERAGE -----/{flag=1;next}/----- END MOONBIT COVERAGE -----/{flag=0; print ""; next}flag' "$file" >> "$tmp_json"
done

if [ ! -s "$tmp_json" ]; then
  echo "Coverage artifacts exist but contain no coverage payloads" >&2
  exit 1
fi

jq -s '
  reduce .[] as $obj (
    {};
    reduce ($obj | to_entries[]) as $e (
      .;
      .[$e.key] = (
        if has($e.key) then
          [ .[$e.key], $e.value ] | transpose | map(max)
        else
          $e.value
        end
      )
    )
  )
' "$tmp_json" > "$tmp_agg"

summary_json="$(
  jq -c '
    def is_test_module: test("(_test|wbtest|blackbox_test|internal_test)");
    [
      to_entries[]
      | select((.key | is_test_module) | not)
      | .value[]
    ] as $vals
    | {
        total: ($vals | length),
        covered: ($vals | map(select(. > 0)) | length),
        percent: (
          if ($vals | length) == 0 then 100
          else (($vals | map(select(. > 0)) | length) * 100 / ($vals | length))
          end
        )
      }
  ' "$tmp_agg"
)"

total="$(jq -r '.total' <<<"$summary_json")"
covered="$(jq -r '.covered' <<<"$summary_json")"
percent="$(jq -r '.percent' <<<"$summary_json")"

printf 'Coverage summary: %.2f%% (%s/%s covered branch points)\n' "$percent" "$covered" "$total"

jq -r '
  def is_test_module: test("(_test|wbtest|blackbox_test|internal_test)");
  to_entries
  | map(
      select((.key | is_test_module) | not)
      | {
          module: .key,
          total: (.value | length),
          covered: (.value | map(select(. > 0)) | length),
          pct: (
            if (.value | length) == 0 then 100
            else ((.value | map(select(. > 0)) | length) * 100 / (.value | length))
            end
          )
        }
    )
  | sort_by(.pct)
  | .[]
  | " - \(.module): \((.pct * 100 | round) / 100)% (\(.covered)/\(.total))"
' "$tmp_agg"

below_threshold="$(awk -v p="$percent" -v t="$threshold" 'BEGIN { if ((p + 0) < (t + 0)) print 1; else print 0 }')"

if [ "$below_threshold" -eq 1 ]; then
  if [ "$mode" = "gate" ]; then
    echo "::error::Coverage ${percent}% is below threshold ${threshold}%"
    exit 1
  fi
  echo "::warning::Coverage ${percent}% is below threshold ${threshold}% (warn mode)"
fi

echo "Coverage check mode=${mode} threshold=${threshold}% completed"
