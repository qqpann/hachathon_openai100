#!/bin/zsh
set -eu
SEEDLAB_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
SEEDLAB_GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
if [[ ! -x "$SEEDLAB_GODOT" ]]; then
  SEEDLAB_GODOT="$(command -v godot || command -v godot4 || true)"
fi
if [[ -z "$SEEDLAB_GODOT" || ! -x "$SEEDLAB_GODOT" ]]; then
  print 'Godot 4.5以降を用意するか、GODOT_BINに実行ファイルを指定してください。'
  exit 1
fi
SEEDLAB_NODE="$(command -v node || true)"
if [[ -z "$SEEDLAB_NODE" && -x "$HOME/.local/share/mise/shims/node" ]]; then
  SEEDLAB_NODE="$HOME/.local/share/mise/shims/node"
fi
SEEDLAB_BRIDGE_PID=""
seedlab_cleanup() {
  if [[ -n "$SEEDLAB_BRIDGE_PID" ]]; then kill "$SEEDLAB_BRIDGE_PID" 2>/dev/null || true; fi
}
trap seedlab_cleanup EXIT INT TERM
if [[ -n "$SEEDLAB_NODE" ]]; then
  if ! curl -fsS --max-time 2 http://127.0.0.1:4873/health 2>/dev/null | "$SEEDLAB_NODE" -e 'let s="";process.stdin.on("data",c=>s+=c);process.stdin.on("end",()=>{try{process.exit(JSON.parse(s).service==="seedlab-coach-v1"?0:1)}catch{process.exit(1)}})'; then
    "$SEEDLAB_NODE" "$SEEDLAB_DIR/bridge/server.mjs" &
    SEEDLAB_BRIDGE_PID=$!
    for SEEDLAB_ATTEMPT in {1..20}; do
      if curl -fsS --max-time 1 http://127.0.0.1:4873/health >/dev/null 2>&1; then break; fi
      sleep .1
    done
  fi
else
  print 'Node.js 22.23.4以上の22系、24.22.1以上の24系、または26.12.1以上の26系が見つかりません。手動育成で起動します。'
fi
env -u OPENAI_API_KEY "$SEEDLAB_GODOT" --path "$SEEDLAB_DIR" "$@"
