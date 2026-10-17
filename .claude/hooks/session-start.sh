#!/bin/bash
# Cloud sessions only: install Flutter + graphify so `flutter analyze`, `flutter test` and graphify work.
set -euo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

FLUTTER_DIR=/home/claude/flutter  # same path the preview scripts in project files expect
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  git clone -q --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
echo "export PATH=\"$FLUTTER_DIR/bin:\$HOME/.local/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
export PATH="$FLUTTER_DIR/bin:$HOME/.local/bin:$PATH"
flutter config --no-analytics >/dev/null 2>&1 || true

cd "$CLAUDE_PROJECT_DIR"
flutter pub get
# Hive adapters (*.g.dart) are generated, as in CI.
dart run build_runner build --delete-conflicting-outputs

if ! command -v graphify >/dev/null; then
  rm -rf /tmp/graphify-src
  git clone -q --depth 1 https://github.com/Graphify-Labs/graphify.git /tmp/graphify-src
  uv tool install -q /tmp/graphify-src
fi
# Fresh code graph each session (code-only, no LLM); query with `graphify ... --graph $G`.
graphify extract . --code-only --out /tmp/gfy >/dev/null 2>&1
echo 'export G=/tmp/gfy/graphify-out/graph.json' >> "$CLAUDE_ENV_FILE"
