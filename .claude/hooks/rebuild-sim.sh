#!/bin/bash
# Rebuild PVOGame and relaunch it on the iPhone 17 Pro simulator.
# Invoked by the Stop hook (see .claude/settings.local.json) whenever the
# PostToolUse hook has marked the tree as dirty via /tmp/pvogame-dirty.
#
# Output goes to stderr so the Claude hook machinery can surface it in the UI
# without polluting the model's context (stdout is suppressed by the hook).
set -u

PROJECT_DIR="/Users/frizer/Documents/Study/IOS/PVOGame"
SCHEME="PVOGame"
BUNDLE_ID="Dick.PVOGame"
DEVICE_NAME="iPhone 17 Pro"

cd "$PROJECT_DIR" || { echo "❌ cannot cd to $PROJECT_DIR" >&2; exit 0; }

# Prefer an already-booted iPhone 17 Pro; fall back to any iPhone 17 Pro.
SIM_ID=$(xcrun simctl list devices -j 2>/dev/null \
  | /usr/bin/python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
name = sys.argv[1]
booted = None
any_ = None
for _, arr in data.get("devices", {}).items():
    for d in arr:
        if d.get("isAvailable") and d.get("name") == name:
            if d.get("state") == "Booted":
                booted = d["udid"]
            elif any_ is None:
                any_ = d["udid"]
print(booted or any_ or "")
' "$DEVICE_NAME")

if [ -z "$SIM_ID" ]; then
    echo "❌ No \"$DEVICE_NAME\" simulator found" >&2
    exit 0
fi

echo "🔨 PVOGame: building for $DEVICE_NAME ($SIM_ID)..." >&2

LOG=$(mktemp)
if ! xcodebuild \
        -project PVOGame.xcodeproj \
        -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,id=$SIM_ID" \
        -quiet \
        build >"$LOG" 2>&1; then
    echo "❌ Build failed. Last 25 lines:" >&2
    tail -25 "$LOG" >&2
    rm -f "$LOG"
    exit 0
fi
rm -f "$LOG"

APP_PATH=$(xcodebuild \
        -project PVOGame.xcodeproj \
        -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,id=$SIM_ID" \
        -showBuildSettings 2>/dev/null \
    | awk -F' = ' '
        $1 ~ /TARGET_BUILD_DIR$/ { d=$2 }
        $1 ~ /FULL_PRODUCT_NAME$/ { p=$2 }
        END { if (d && p) print d"/"p }
      ')

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Could not locate built .app (got: $APP_PATH)" >&2
    exit 0
fi

xcrun simctl boot "$SIM_ID" >/dev/null 2>&1 || true
xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
if ! xcrun simctl install "$SIM_ID" "$APP_PATH" >/dev/null 2>&1; then
    echo "❌ simctl install failed" >&2
    exit 0
fi
if xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" >/dev/null 2>&1; then
    # Bring the Simulator.app window forward (no-op if already frontmost).
    # Without this the device can be booted while the GUI wrapper is absent,
    # leaving the app running invisibly.
    open -a Simulator >/dev/null 2>&1 || true
    echo "✅ PVOGame reinstalled and relaunched" >&2
else
    echo "⚠️  install ok, launch failed" >&2
fi
