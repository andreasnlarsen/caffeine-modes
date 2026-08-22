#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
power_pattern='pmset[^\n]*disablesleep|AXIsProcessTrusted|kAXTrustedCheckOptionPrompt'
osascript_pattern='(^|[^[:alnum:]_])(/usr/bin/)?osascript([^[:alnum:]_]|$)'
defaults_executable_pattern='/usr/bin/defaults|(^|[^[:alnum:]_])defaults[[:space:]]+(read|read-type|write|rename|delete|domains|find|help|export|import)([[:space:]]|$)|"defaults"'
termination_pattern='(^|[^[:alnum:]_])(kill|killpg|killall|pkill)[[:space:]]*\(|/usr/bin/(kill|killall|pkill)|/bin/kill|(^|[^[:alnum:]_])(forceTerminate|terminate)[[:space:]]*\(|(^|[;&|[:space:]])(kill|killall|pkill)([[:space:]]|$)'
allowed_termination_line='Sources/CaffeineModesApp/SystemAdapters\.swift:[0-9]+:[[:space:]]*_ = Darwin\.kill\(pid, SIG(TERM|KILL)\)[[:space:]]*$|Sources/CaffeineModesApp/main\.swift:[0-9]+:[[:space:]]*requestQuit: \{ NSApplication\.shared\.terminate\(nil\) \}[[:space:]]*$'
helper_pattern='SMJobBless|AuthorizationExecuteWithPrivileges|kSMRightBlessPrivilegedHelper|PrivilegedHelperTools|SMPrivilegedExecutables|SMAuthorizedClients|ServiceManagement\.blesshelper'
scan_targets=("$project_root/Sources" "$project_root/Tests" "$project_root/Scripts" "$project_root/Resources" "$project_root/Package.swift")

if rg -n --glob '!verify-safety.sh' "$power_pattern" "${scan_targets[@]}" >/dev/null; then
    print -u2 "Forbidden power or permission mechanism found."
    exit 1
fi
if rg -n --glob '!verify-safety.sh' "$osascript_pattern" "${scan_targets[@]}" >/dev/null; then
    print -u2 "Forbidden osascript mechanism found."
    exit 1
fi
if rg -n --glob '!verify-safety.sh' "$defaults_executable_pattern" "${scan_targets[@]}" >/dev/null; then
    print -u2 "Forbidden defaults executable found."
    exit 1
fi
if rg -n --glob '!verify-safety.sh' 'disablesleep' "${scan_targets[@]}" >/dev/null; then
    print -u2 "Forbidden pmset disablesleep argument found."
    exit 1
fi
termination_matches="$(rg -n --glob '!verify-safety.sh' "$termination_pattern" "${scan_targets[@]}" || true)"
unexpected_termination_matches="$(print -r -- "$termination_matches" | rg -v "$allowed_termination_line" || true)"
if [[ -n "$unexpected_termination_matches" ]]; then
    print -u2 "External-process termination mechanism found."
    exit 1
fi
if rg -n --glob '!verify-safety.sh' "$helper_pattern" "${scan_targets[@]}" >/dev/null; then
    print -u2 "Privileged-helper mechanism found."
    exit 1
fi

print -r -- 'process.executableURL = URL(fileURLWithPath: "/usr/bin/kill")' | rg -q "$termination_pattern"
for fixture in \
    '_ = kill(pid, SIGTERM)' \
    '_ = Darwin.killpg(pid, SIGTERM)' \
    '_ = app?.forceTerminate()' \
    'process.terminate()' \
    'kill "$pid"'
do
    print -r -- "$fixture" | rg -q "$termination_pattern"
done
print -r -- 'SMJobBless(kSMDomainSystemLaunchd, label, authorization, error)' | rg -q "$helper_pattern"
print -r -- $'executable: "/usr/bin/pmset"\narguments: ["disablesleep", "1"]' | rg -q 'disablesleep'
for fixture in \
    'osascript -e '\''tell application "Amphetamine" to end session'\''' \
    'process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")'
do
    print -r -- "$fixture" | rg -q "$osascript_pattern"
done
for fixture in \
    'defaults write com.if.Amphetamine Example -bool true' \
    $'executable: "/usr/bin/defaults"\narguments: ["write", "com.if.Amphetamine", "Example", "true"]'
do
    print -r -- "$fixture" | rg -q "$defaults_executable_pattern"
done

rg -q 'NSAppleScript' "$project_root/Sources/CaffeineModesApp/AmphetamineClient.swift"
rg -q 'IOPMCopyAssertionsByProcess' "$project_root/Sources/CaffeineModesApp/SystemAdapters.swift"
rg -q 'MKBDeviceGetGracePeriod' "$project_root/Sources/CaffeineModesApp/SystemAdapters.swift"
rg -q '\["displaysleepnow"\]' "$project_root/Sources/CaffeineModesApp/SystemAdapters.swift"
rg -q 'posix_spawn\(' "$project_root/Sources/CaffeineModesApp/SystemAdapters.swift"
rg -q 'waitpid\(pid,' "$project_root/Sources/CaffeineModesApp/SystemAdapters.swift"
test "$(print -r -- "$termination_matches" | rg -c "$allowed_termination_line")" = "3"
test "$(rg -c 'Darwin\.kill\(pid, SIGTERM\)' "$project_root/Sources/CaffeineModesApp/SystemAdapters.swift")" = "1"
test "$(rg -c 'Darwin\.kill\(pid, SIGKILL\)' "$project_root/Sources/CaffeineModesApp/SystemAdapters.swift")" = "1"
test "$(rg -c 'NSApplication\.shared\.terminate\(nil\)' "$project_root/Sources/CaffeineModesApp/main.swift")" = "1"
if rg -q 'Process\(\)' "$project_root/Sources/CaffeineModesApp/SystemAdapters.swift"; then
    print -u2 "Foundation Process must not share child ownership with waitpid."
    exit 1
fi
rg -q 'com.apple.security.automation.apple-events' "$project_root/Resources/CaffeineModes.entitlements"
if rg -q 'com.apple.security.accessibility' "$project_root/Resources"; then
    print -u2 "Accessibility entitlement found."
    exit 1
fi

printf 'PASS SAFETY\n'
