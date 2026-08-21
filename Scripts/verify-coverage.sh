#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"
swift test --enable-code-coverage >/dev/null

test_binary="$(find .build -path '*debug/CaffeineModesPackageTests.xctest/Contents/MacOS/CaffeineModesPackageTests' -type f | head -1)"
profile="$(find .build -path '*debug/codecov/default.profdata' -type f | head -1)"
test -n "$test_binary"
test -n "$profile"

report="$(xcrun llvm-cov report "$test_binary" -instr-profile="$profile" -ignore-filename-regex='Tests/|Sources/CaffeineModesApp/|\.build/')"
line_coverage="$(print -r -- "$report" | awk '/^TOTAL/ {gsub(/%/, "", $(NF-3)); print $(NF-3)}')"
test -n "$line_coverage"
awk -v coverage="$line_coverage" 'BEGIN { exit !(coverage >= 90.0) }'
printf 'PASS COVERAGE %s%%\n' "$line_coverage"
