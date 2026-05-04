#!/usr/bin/env bash
set -euo pipefail

export HF_HUB_ENABLE_HF_TRANSFER=1

: "${LLAMA_HF_REPO:?Set LLAMA_HF_REPO}"
: "${LLAMA_GGUF_FILE:?Set LLAMA_GGUF_FILE}"

LLAMA_ALIAS="${LLAMA_ALIAS:-vast-current}"
LLAMA_HOST="${LLAMA_HOST:-127.0.0.1}"
LLAMA_PORT="${LLAMA_PORT:-18000}"
LLAMA_CTX_SIZE="${LLAMA_CTX_SIZE:-32768}"
LLAMA_N_GPU_LAYERS="${LLAMA_N_GPU_LAYERS:-all}"
LLAMA_MODEL_DIR="${LLAMA_MODEL_DIR:-/workspace/models}"
LLAMA_API_KEY_FILE="${LLAMA_API_KEY_FILE:-/workspace/llama-api-key.txt}"

mkdir -p "$LLAMA_MODEL_DIR"

MODEL_PATH="$LLAMA_MODEL_DIR/$LLAMA_GGUF_FILE"

if [[ ! -s "$LLAMA_API_KEY_FILE" ]]; then
  if [[ -n "${LLAMA_API_KEY:-}" ]]; then
    printf '%s\n' "$LLAMA_API_KEY" > "$LLAMA_API_KEY_FILE"
  else
    openssl rand -hex 32 > "$LLAMA_API_KEY_FILE"
  fi
  chmod 600 "$LLAMA_API_KEY_FILE"
fi

if [[ ! -f "$MODEL_PATH" ]]; then
  echo "Downloading model: $LLAMA_HF_REPO / $LLAMA_GGUF_FILE"

  HF_ARGS=()
  if [[ -n "${HF_TOKEN:-}" ]]; then
    HF_ARGS+=(--token "$HF_TOKEN")
  fi

  hf download "$LLAMA_HF_REPO" "$LLAMA_GGUF_FILE" \
    --local-dir "$LLAMA_MODEL_DIR" \
    "${HF_ARGS[@]}"
fi

ARGS=(
  --model "$MODEL_PATH"
  --alias "$LLAMA_ALIAS"
  --host "$LLAMA_HOST"
  --port "$LLAMA_PORT"
  --ctx-size "$LLAMA_CTX_SIZE"
  --n-gpu-layers "$LLAMA_N_GPU_LAYERS"
  --api-key-file "$LLAMA_API_KEY_FILE"
  --jinja
  --flash-attn auto
  --reasoning auto
)

if [[ -n "${LLAMA_DEVICE:-}" ]]; then
  ARGS+=(--device "$LLAMA_DEVICE")
fi

if [[ -n "${LLAMA_SPLIT_MODE:-}" ]]; then
  ARGS+=(--split-mode "$LLAMA_SPLIT_MODE")
fi

if [[ -n "${LLAMA_TENSOR_SPLIT:-}" ]]; then
  ARGS+=(--tensor-split "$LLAMA_TENSOR_SPLIT")
fi

if [[ -n "${LLAMA_EXTRA_ARGS:-}" ]]; then
  read -r -a EXTRA <<< "$LLAMA_EXTRA_ARGS"
  ARGS+=("${EXTRA[@]}")
fi

echo "Starting llama-server on http://$LLAMA_HOST:$LLAMA_PORT"
exec /opt/llama.cpp/build/bin/llama-server "${ARGS[@]}"
