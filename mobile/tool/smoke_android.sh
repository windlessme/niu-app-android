#!/usr/bin/env bash
# Kept for existing docs and habits; the smoke test lives in smoke_android.py.
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 tool/smoke_android.py "$@"
