#!/usr/bin/env bash
# scripts/dev/reset-mos-state.sh
#
# Fully resets Mos's on-disk + TCC state for BOTH the release and the debug
# build, so a fresh install / fresh permission grant behaves like a first run.
#
# Why this exists
# ---------------
# 1. All Mos settings — including the *button bindings* — are stored in
#    UserDefaults (NOT a separate file), i.e.:
#        ~/Library/Preferences/com.caldis.Mos.plist          (Release)
#        ~/Library/Preferences/com.caldis.Mos.debug.plist    (Debug)
#    Deleting just the .plist file does NOT work reliably: `cfprefsd` keeps the
#    domain cached in memory and rewrites the file, so App Cleaner / `brew zap`
#    appear to "fail" and your config reappears after reinstall. The reliable
#    way is `defaults delete` (which goes through cfprefsd) + killing cfprefsd.
#
# 2. Accessibility permission is keyed by the app's *code signature*, not just
#    its bundle id. A locally built Release (signed "Apple Development" / ad-hoc)
#    is a different signature than the notarized Homebrew cask even though both
#    are `com.caldis.Mos`, so a grant given to one does not apply to the other
#    and AXIsProcessTrusted() returns false ("granted but not detected").
#    `tccutil reset` clears the stale grant so you can re-grant cleanly.
#
# Usage:  bash scripts/dev/reset-mos-state.sh
set -euo pipefail

RELEASE_ID="com.caldis.Mos"
DEBUG_ID="com.caldis.Mos.debug"

echo "==> Quitting any running Mos instances"
osascript -e 'tell application "Mos" to quit' >/dev/null 2>&1 || true
osascript -e 'tell application "Mos Debug" to quit' >/dev/null 2>&1 || true
killall "Mos" "Mos Debug" >/dev/null 2>&1 || true
sleep 1

for ID in "$RELEASE_ID" "$DEBUG_ID"; do
    echo "==> Resetting TCC (Accessibility) for $ID"
    tccutil reset Accessibility "$ID" >/dev/null 2>&1 || true
    # Mos does not need Input Monitoring, but reset it too in case it was granted.
    tccutil reset ListenEvent "$ID" >/dev/null 2>&1 || true

    echo "==> Clearing UserDefaults domain for $ID (includes button bindings)"
    defaults delete "$ID" >/dev/null 2>&1 || true

    echo "==> Removing preference files for $ID"
    rm -f "$HOME/Library/Preferences/${ID}.plist" || true
    rm -f "$HOME/Library/Preferences/ByHost/${ID}."*.plist 2>/dev/null || true
    # Sparkle / misc caches occasionally land here; harmless if absent.
    rm -rf "$HOME/Library/Caches/${ID}" || true
    rm -rf "$HOME/Library/HTTPStorages/${ID}" "$HOME/Library/HTTPStorages/${ID}.binarycookies" 2>/dev/null || true
done

echo "==> Flushing cfprefsd so deletions stick (it will respawn automatically)"
killall cfprefsd >/dev/null 2>&1 || true

cat <<'DONE'

Done. State for com.caldis.Mos and com.caldis.Mos.debug has been cleared.

Next:
  - Re-launch the build you want to test.
  - When prompted, grant Accessibility to THAT build's name in
    System Settings > Privacy & Security > Accessibility
    ("Mos" for Release, "Mos Debug" for the Debug build).
  - For day-to-day development prefer the Debug build: its bundle id is
    com.caldis.Mos.debug, so its permission + settings never collide with an
    officially installed (Homebrew cask) "Mos".
DONE
