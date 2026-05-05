#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

if [[ -f /venv/main/bin/activate ]]; then
  source /venv/main/bin/activate
fi

export HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-1}"

: "${LLAMA_HF_REPO:?Set LLAMA_HF_REPO}"
: "${LLAMA_GGUF_FILE:?Set LLAMA_GGUF_FILE}"

LLAMA_ALIAS="${LLAMA_ALIAS:-vast-current}"
LLAMA_HOST="${LLAMA_HOST:-127.0.0.1}"
LLAMA_PORT="${LLAMA_PORT:-18000}"
LLAMA_CTX_SIZE="${LLAMA_CTX_SIZE:-32768}"
LLAMA_N_GPU_LAYERS="${LLAMA_N_GPU_LAYERS:-all}"
LLAMA_MODEL_DIR="${LLAMA_MODEL_DIR:-/workspace/models}"
LLAMA_API_KEY_FILE="${LLAMA_API_KEY_FILE:-/workspace/llama-api-key.txt}"
LLAMA_DOWNLOAD_LOG_INTERVAL="${LLAMA_DOWNLOAD_LOG_INTERVAL:-30}"

LLAMA_SERVER_BIN="${LLAMA_SERVER_BIN:-/usr/local/bin/llama-server}"

if [[ ! -x "$LLAMA_SERVER_BIN" ]]; then
  log "ERROR: llama-server binary not found or not executable:"
  log "  $LLAMA_SERVER_BIN"
  log "Searching for alternatives..."
  find /opt /usr/local/bin /usr/local/lib -type f -name llama-server -o -type l -name llama-server 2>/dev/null || true
  exit 1
fi

log "Using llama-server binary:"
log "  $LLAMA_SERVER_BIN"

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

show_download_status() {
  log "Download status:"
  du -sh "$LLAMA_MODEL_DIR" 2>/dev/null || true

  find "$LLAMA_MODEL_DIR" -maxdepth 3 -type f \
    -printf "%TY-%Tm-%Td %TH:%TM %10s %p\n" 2>/dev/null \
    | sort \
    | tail -20 \
    || true
}

monitor_download() {
  while true; do
    show_download_status
    sleep "$LLAMA_DOWNLOAD_LOG_INTERVAL"
  done
}

if [[ ! -f "$MODEL_PATH" ]]; then
  log "Preparing to download model:"
  log "  repo:   $LLAMA_HF_REPO"
  log "  file:   $LLAMA_GGUF_FILE"
  log "  target: $MODEL_PATH"

  HF_ARGS=()
  if [[ -n "${HF_TOKEN:-}" ]]; then
    HF_ARGS+=(--token "$HF_TOKEN")
  fi

  log "Starting Hugging Face download..."

  monitor_download &
  MONITOR_PID="$!"

  cleanup_monitor() {
    kill "$MONITOR_PID" >/dev/null 2>&1 || true
  }
  trap cleanup_monitor EXIT

  hf download "$LLAMA_HF_REPO" "$LLAMA_GGUF_FILE" \
    --local-dir "$LLAMA_MODEL_DIR" \
    "${HF_ARGS[@]}"

  cleanup_monitor
  trap - EXIT

  log "Download command finished."
else
  log "Model already exists: $MODEL_PATH"
fi

if [[ ! -f "$MODEL_PATH" ]]; then
  log "ERROR: Expected model file was not found after download:"
  log "  $MODEL_PATH"
  log "Files currently in model directory:"
  find "$LLAMA_MODEL_DIR" -maxdepth 3 -type f -printf "%s %p\n" 2>/dev/null || true
  exit 1
fi

log "Model file is ready:"
ls -lh "$MODEL_PATH"

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

if [[ -n "${LLAMA_PARALLEL:-}" ]]; then
  ARGS+=(--parallel "$LLAMA_PARALLEL")
fi

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

log "Starting llama-server:"
log "  binary:   $LLAMA_SERVER_BIN"
log "  model:    $MODEL_PATH"
log "  alias:    $LLAMA_ALIAS"
log "  endpoint: http://$LLAMA_HOST:$LLAMA_PORT/v1"
log "  ctx size: $LLAMA_CTX_SIZE"

exec "$LLAMA_SERVER_BIN" "${ARGS[@]}"
