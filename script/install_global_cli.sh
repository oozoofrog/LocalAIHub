#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="$HOME/.local/bin"
DEST="$DEST_DIR/ai"

if [[ -e "$DEST" || -L "$DEST" ]]; then
  if [[ "${1:-}" != "--replace" || $# -ne 1 ]]; then
    echo "Global command already exists at $DEST; rerun with --replace to back it up and update it." >&2
    exit 2
  fi
elif (($#)); then
  echo "Usage: $0 [--replace]" >&2
  exit 2
fi

cd "$ROOT_DIR"
swift build --product ai
BUILD_DIR="$(swift build --show-bin-path)"
SOURCE="$BUILD_DIR/ai"
[[ -x "$SOURCE" ]] || { echo "SwiftPM did not produce $SOURCE" >&2; exit 1; }

mkdir -p "$DEST_DIR"
temporary="$(mktemp "$DEST_DIR/.ai.XXXXXXXX")"
trap 'rm -f "$temporary"' EXIT
cp "$SOURCE" "$temporary"
chmod 755 "$temporary"

backup=""
if [[ -e "$DEST" || -L "$DEST" ]]; then
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  backup="$DEST_DIR/ai.backup.$stamp"
  [[ ! -e "$backup" && ! -L "$backup" ]] || { echo "Backup already exists: $backup" >&2; exit 1; }
  mv "$DEST" "$backup"
  echo "Previous global command: $backup"
fi
if ! mv "$temporary" "$DEST"; then
  if [[ -n "$backup" ]]; then mv "$backup" "$DEST"; fi
  exit 1
fi
echo "Installed global command: $DEST"
echo "Model root: $($DEST status | sed -n '1s/^Local AI root: //p')"
