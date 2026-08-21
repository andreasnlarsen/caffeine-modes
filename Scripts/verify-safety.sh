#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"

if rg -n --glob '*.swift' 'Process\(\).*osascript|/usr/bin/osascript|pmset[^\n]*disablesleep|defaults[^\n]*com\.if\.Amphetamine|AXIsProcessTrusted|kAXTrustedCheckOptionPrompt' "$project_root/Sources" >/dev/null; then
    print -u2 "Forbidden power or permission mechanism found."
    exit 1
fi

rg -q 'NSAppleScript' "$project_root/Sources/CaffeineModesApp/AmphetamineClient.swift"
rg -q 'IOPMCopyAssertionsByProcess' "$project_root/Sources/CaffeineModesApp/SystemAdapters.swift"
rg -q 'arguments = \["displaysleepnow"\]' "$project_root/Sources/CaffeineModesApp/SystemAdapters.swift"
rg -q 'com.apple.security.automation.apple-events' "$project_root/Resources/CaffeineModes.entitlements"
if rg -q 'com.apple.security.accessibility' "$project_root/Resources"; then
    print -u2 "Accessibility entitlement found."
    exit 1
fi

printf 'PASS SAFETY\n'
