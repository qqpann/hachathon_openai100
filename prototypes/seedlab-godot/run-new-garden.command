#!/bin/zsh
set -eu
SEEDLAB_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
exec "$SEEDLAB_DIR/run.command" "$@" -- --new-garden
