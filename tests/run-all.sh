#!/usr/bin/env bash
# Claude Census — Test Runner
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0
ERRORS=""

for test_file in "$SCRIPT_DIR"/test-*.sh; do
  [ -f "$test_file" ] || continue
  test_name="$(basename "$test_file")"
  echo "── $test_name ──"
  if bash "$test_file"; then
    echo "  ✓ PASS"
    PASS=$((PASS + 1))
  else
    echo "  ✗ FAIL"
    FAIL=$((FAIL + 1))
    ERRORS="$ERRORS  - $test_name\n"
  fi
  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  echo "Failed tests:"
  printf "$ERRORS"
  exit 1
fi
echo "All tests passed!"
