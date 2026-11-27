#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
MACOS_DIR="$ROOT_DIR/codex/desktop/macos"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wisdai-agentic-e2e.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

APP_BUNDLE="$WORK_DIR/WisdAIAgenticVoiceE2ESmoke.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
mkdir -p "$APP_MACOS"

cat > "$APP_CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>WisdAIAgenticVoiceE2ESmoke</string>
  <key>CFBundleIdentifier</key>
  <string>com.wisdai.AgenticVoiceE2ESmoke</string>
  <key>CFBundleName</key>
  <string>WisdAIAgenticVoiceE2ESmoke</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
</dict>
</plist>
PLIST

# Expose auxiliary Codex binaries beside Bundle.main executable when installed
if [ -x "/Applications/WisdAI.app/Contents/MacOS/codex" ]; then
    ln -s "/Applications/WisdAI.app/Contents/MacOS/codex" "$APP_MACOS/codex"
fi
if [ -x "/Applications/WisdAI.app/Contents/MacOS/codex-code-mode-host" ]; then
    ln -s "/Applications/WisdAI.app/Contents/MacOS/codex-code-mode-host" "$APP_MACOS/codex-code-mode-host"
fi

# Strip app @main entrypoint from WisdCode.swift into temp copy so AgenticVoiceE2ESmoke provides @main
cp "$MACOS_DIR"/*.swift "$WORK_DIR/"
python3 - <<PY
from pathlib import Path
p = Path("$WORK_DIR/WisdCode.swift")
src = p.read_text()
idx = src.find("@main\nstruct DesktopApp")
if idx == -1:
    idx = src.find("@main")
if idx != -1:
    src = src[:idx]
p.write_text(src)
PY

swiftc \
    -swift-version 5 \
    -target arm64-apple-macosx14.0 \
    -parse-as-library \
    -O \
    "$WORK_DIR"/*.swift \
    "$MACOS_DIR/tests/AgenticVoiceE2ESmoke.swift" \
    -o "$APP_MACOS/WisdAIAgenticVoiceE2ESmoke"

"$APP_MACOS/WisdAIAgenticVoiceE2ESmoke"
