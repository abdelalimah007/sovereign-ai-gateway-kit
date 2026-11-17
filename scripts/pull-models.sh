#!/usr/bin/env bash
# Pull the four kit models into the shared "models" volume, then verify each
# manifest digest against the pinned value below. Runs once, in the
# `model-init` container (the only container on a network with internet access).
# It starts its own private Ollama server on 127.0.0.1 inside this container,
# so the main `ollama` service never needs internet access.
set -euo pipefail

# name:tag                    manifest sha256 (resolved 2026-11-16, see docs/pinned-versions.md)
MODELS=(
  "granite4:3b               89962fcc75239ac434cdebceb6b7e0669397f92eaef9c487774b718bc36a3e5f"
  "qwen2.5-coder:1.5b        d7372fd828518a4d38b1eb196c673c31a85f2ed302b3d1e406c4c2d1b64a0668"
  "qwen2.5:1.5b-instruct     65ec06548149b04c096a120e4a6da9d4017ea809c91734ea5631e89f96ddc57b"
  "nomic-embed-text:v1.5     0a109f422b47e3a30ba2b10eca18548e944e8a23073ee3f3e947efcf3c45e59f"
)
BLOBS="${OLLAMA_MODELS:-/root/.ollama/models}/blobs"
export OLLAMA_HOST=127.0.0.1:11434
ollama serve >/dev/null 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
for _ in $(seq 1 60); do ollama list >/dev/null 2>&1 && break; sleep 1; done

# A model is verified when `ollama list` shows the pinned manifest digest for the
# tag AND the stored copy of the registry manifest (a blob named after its own
# sha256) really hashes to that digest.
verified() { # model want
  local id
  id=$(ollama list | awk -v m="$1" '$1 == m {print $2}')
  [[ -n "$id" && "$2" == "$id"* ]] || return 1
  [[ -f "$BLOBS/sha256-$2" ]] && [[ "$(sha256sum "$BLOBS/sha256-$2" | cut -d' ' -f1)" == "$2" ]]
}

failed=0
for entry in "${MODELS[@]}"; do
  read -r model want <<<"$entry"
  if verified "$model" "$want"; then
    echo "model-init: $model already present (sha256:${want:0:12} verified)"
    continue
  fi
  echo "model-init: pulling $model ..."
  start=$(date +%s)
  ollama pull "$model" >/dev/null 2>&1 || { echo "model-init: pull failed for $model" >&2; failed=1; continue; }
  if verified "$model" "$want"; then
    echo "model-init: $model OK in $(( $(date +%s) - start ))s (sha256:${want:0:12} verified)"
  else
    echo "model-init: DIGEST MISMATCH for $model (want sha256:$want); removed" >&2
    ollama rm "$model" >/dev/null 2>&1 || true
    failed=1
  fi
done
exit "$failed"
