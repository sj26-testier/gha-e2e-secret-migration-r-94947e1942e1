#!/usr/bin/env bash
# Compares migrated Buildkite secrets with expected SHA-256 digests.
# Never prints secret values: only key names, digests and pass/fail.
set -uo pipefail

expected_file=".buildkite/expected.tsv"
failures=0

hash_value() {
  # Reads `buildkite-agent secret get --format json KEY` output on stdin and
  # prints the SHA-256 of the exact value bytes (no added newline).
  local key="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import hashlib, json, sys; print(hashlib.sha256(json.load(sys.stdin)[sys.argv[1]].encode("utf-8")).hexdigest())' "$key"
  else
    jq -j --arg key "$key" '.[$key]' | sha256sum | cut -d" " -f1
  fi
}

echo "--- Tools: python3=$(command -v python3 || echo none) jq=$(command -v jq || echo none)"
while IFS=$'\t' read -r key state digest; do
  [[ -z "$key" || "$key" == \#* ]] && continue
  if output=$(buildkite-agent secret get --format json "$key" 2>/dev/null); then
    actual=$(printf '%s' "$output" | hash_value "$key")
    unset output
    if [[ "$state" == "present" && "$actual" == "$digest" ]]; then
      echo "PASS $key present sha256=$actual"
    elif [[ "$state" == "present" ]]; then
      echo "FAIL $key present but sha256=$actual expected=$digest"; failures=$((failures + 1))
    else
      echo "FAIL $key should be absent but exists sha256=$actual"; failures=$((failures + 1))
    fi
  else
    unset output
    if [[ "$state" == "absent" ]]; then
      echo "PASS $key absent (secret get failed as expected)"
    else
      echo "FAIL $key expected present but secret get failed"; failures=$((failures + 1))
    fi
  fi
done < "$expected_file"

echo "--- $failures failure(s)"
exit "$((failures > 0))"
