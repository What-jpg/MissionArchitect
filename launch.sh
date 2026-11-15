#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if command -v godot >/dev/null 2>&1; then
  exec godot --path "$PWD" "$@"
elif command -v godot4 >/dev/null 2>&1; then
  exec godot4 --path "$PWD" "$@"
else
  echo 'Потрібен Godot 4. Відкрийте project.godot у редакторі й натисніть F5.' >&2
  exit 1
fi
