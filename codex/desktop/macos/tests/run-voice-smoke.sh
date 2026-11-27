#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$(cd "$script_dir/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/wisdai-voice-smoke.XXXXXX")"
trap 'rm -rf "$work"' EXIT

python3 - "$source_dir" "$work" <<'PY'
import sys
from pathlib import Path
source, work = Path(sys.argv[1]), Path(sys.argv[2])
for path in source.glob('*.swift'):
    text = path.read_text()
    if path.name == 'WisdCode.swift':
        text = text[:text.index('@main')]
    (work / path.name).write_text(text)
PY

swiftc -swift-version 5 -target arm64-apple-macosx14.0 -parse-as-library -O "$work"/*.swift "$source_dir/tests/VoiceSmokeTests.swift" -o "$work/WisdAIVoiceSmoke"
"$work/WisdAIVoiceSmoke"
