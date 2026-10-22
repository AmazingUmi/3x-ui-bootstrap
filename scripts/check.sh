#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export PYTHONDONTWRITEBYTECODE=1
bash -n "$ROOT/install-3x-ui.sh"
bash -n "$ROOT/scripts/check.sh"
python3 -m json.tool "$ROOT/config.example.json" >/dev/null
python3 -m unittest discover -s "$ROOT/tests" -v
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT" diff --check
fi
