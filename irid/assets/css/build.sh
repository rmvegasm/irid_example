#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────
# build.sh — Tailwind CSS compilation for local development
#
# Compiles irid/assets/css/input.css → irid/assets/css/app.css
# Shiny serves the compiled CSS directly from this directory via
# addResourcePath("css", ...) — no www/ folder needed.
#
# Usage (run from project root):
#   bash irid/assets/css/build.sh           # one-shot compile
#   bash irid/assets/css/build.sh --watch   # watch mode
# ────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")/../../.."  # project root

WATCH_FLAG=""
if [[ "${1:-}" == "--watch" ]] || [[ "${1:-}" == "-w" ]]; then
  WATCH_FLAG="--watch"
fi

npx @tailwindcss/cli \
  -i irid/assets/css/input.css \
  -o irid/assets/css/app.css \
  $WATCH_FLAG

echo "✓ CSS compiled to irid/assets/css/app.css"
