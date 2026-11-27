#!/bin/sh
set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    printf 'Usage: %s <compiled arm64 codex binary> <output.dmg> [codex-code-mode-host binary]\n' "$0" >&2
    exit 2
fi

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(CDPATH= cd -- "$source_dir/../.." && pwd)
binary=$1
output=$2
host_binary=${3:-"$(dirname -- "$binary")/codex-code-mode-host"}
if [ -e "$output" ] || [ -L "$output" ]; then
    printf 'Output already exists: %s\n' "$output" >&2
    exit 1
fi
file "$binary" | grep -q 'Mach-O 64-bit executable arm64'
if [ -f "$host_binary" ]; then
    file "$host_binary" | grep -q 'Mach-O 64-bit executable arm64'
else
    printf 'Missing required codex-code-mode-host binary: %s\n' "$host_binary" >&2
    exit 1
fi
work=$(mktemp -d "${TMPDIR:-/tmp}/wisdai-desktop.XXXXXX")
trap 'python3 -c "import shutil, sys; shutil.rmtree(sys.argv[1])" "$work"' EXIT
app="$work/image/WisdAI.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 -parse-as-library -O \
    "$source_dir/DesktopRecovery.swift" "$source_dir/DesktopAccounts.swift" "$source_dir/DesktopModels.swift" "$source_dir/DesktopModals.swift" "$source_dir/DesktopCodexVoiceWebRTC.swift" "$source_dir/VoiceNativeAudioEngine.swift" "$source_dir/VoiceGateway.swift" "$source_dir/VoiceConversationEngine.swift" "$source_dir/VoiceSpeechUnderstanding.swift" "$source_dir/VoiceBehaviorEngine.swift" "$source_dir/VoiceVocalizationCache.swift" "$source_dir/LocalIntelligenceEngine.swift" "$source_dir/VoiceIdentityProfile.swift" "$source_dir/VoiceNeuralRuntime.swift" "$source_dir/VoiceMemoryAndTelemetry.swift" "$source_dir/VoiceOrchestrator.swift" "$source_dir/VoiceHUDViews.swift" "$source_dir/VoiceLaboratoryView.swift" "$source_dir/DesktopVoice.swift" "$source_dir/DesktopInspector.swift" "$source_dir/WisdCode.swift" "$source_dir/DesktopPanels.swift" "$source_dir/DesktopShell.swift" "$source_dir/DesktopSettings.swift" "$source_dir/DesktopSpace.swift" -o "$app/Contents/MacOS/WisdAI"
cp -c "$binary" "$app/Contents/MacOS/codex"
xcrun strip -S -x "$app/Contents/MacOS/codex"
if [ -f "$host_binary" ]; then
    cp -c "$host_binary" "$app/Contents/MacOS/codex-code-mode-host"
    xcrun strip -S -x "$app/Contents/MacOS/codex-code-mode-host"
    codesign --force --sign - "$app/Contents/MacOS/codex-code-mode-host"
fi
cp "$source_dir/Info.plist" "$app/Contents/"
git_commit=$(git -C "$repo" rev-parse HEAD 2>/dev/null || printf 'unknown')
git_branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown')
build_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
/usr/libexec/PlistBuddy -c "Add :WisdAIGitCommit string $git_commit" "$app/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :WisdAIGitCommit $git_commit" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :WisdAIGitBranch string $git_branch" "$app/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :WisdAIGitBranch $git_branch" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :WisdAIBuildTimestamp string $build_ts" "$app/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :WisdAIBuildTimestamp $build_ts" "$app/Contents/Info.plist"
cp "$source_dir/Resources/"* "$app/Contents/Resources/" 2>/dev/null || true
cp "$repo/LICENSE" "$repo/NOTICE" "$app/Contents/Resources/" 2>/dev/null || cp "$repo/codex/LICENSE" "$repo/codex/NOTICE" "$app/Contents/Resources/" 2>/dev/null || true
codesign --force --sign - "$app/Contents/MacOS/codex"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
ln -s /Applications "$work/image/Applications"
hdiutil create -srcfolder "$work/image" -volname "WisdAI Desktop" -fs HFS+ -format UDZO "$work/WisdAI.dmg"
hdiutil verify "$work/WisdAI.dmg"
mv -n "$work/WisdAI.dmg" "$output"
