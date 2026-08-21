#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
spec="$project_root/SPEC.md"
test -f "$spec"

for section in {1..17}; do
    test "$(rg -c "^## ${section}\. " "$spec")" = "1"
done

# Spec Forge checks 1–17. Each check maps to one explicit contract marker.
! rg -n '\b(fast|easy|secure)\b' "$spec" >/dev/null
for requirement in {001..009}; do
    rg -q "REQ-$requirement.*Acceptance:" "$spec"
    rg -q "REQ-$requirement.*Scripts/verify-requirement.sh REQ-$requirement.*PASS REQ-$requirement" "$spec"
done
rg -q 'NFR-001.*0\.2%' "$spec"
rg -q 'NFR-002.*50 MB' "$spec"
rg -q 'NFR-003.*two seconds' "$spec"
rg -q 'Architecture dependencies are mirrored in Constraints and Build vs Buy' "$spec"
rg -q 'MVP contains REQ-001 through REQ-009 only' "$spec"
test "$(rg -c '^\- NG-' "$spec")" -ge 2
rg -q '^## 9\. Build vs Buy Decisions' "$spec"
rg -q 'XCTest' "$spec"
rg -q 'at least 90%' "$spec"
rg -q 'Greenfield — no existing code to scan' "$spec"
rg -q 'Canonical owner.*ModeController' "$spec"
rg -q 'No business rule has two owners' "$spec"
rg -qi 'Amphetamine.*system of record|system of record.*Amphetamine' "$spec"
rg -qi 'authority map' "$spec"
rg -qi 'forbidden transitions' "$spec"
rg -q 'replaceable seams' "$spec"
rg -q 'No speculative fallback' "$spec"

printf 'PASS SPEC\n'
