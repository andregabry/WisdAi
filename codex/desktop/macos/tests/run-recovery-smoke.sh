#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/wisdai-state-smoke.XXXXXX")
trap 'rm -rf "$work"' EXIT
python3 - "$source_dir" "$work" <<'PY'
import sys
from pathlib import Path
source, target = map(Path, sys.argv[1:])
for path in source.glob('*.swift'):
    text = path.read_text()
    if path.name == 'WisdCode.swift':
        text = text[:text.index('@main')]
    (target / path.name).write_text(text)
PY
swiftc -swift-version 5 -parse-as-library "$work"/*.swift "$source_dir/tests/RecoverySmoke.swift" -o "$work/WisdAIRecoverySmoke"
"$work/WisdAIRecoverySmoke"
