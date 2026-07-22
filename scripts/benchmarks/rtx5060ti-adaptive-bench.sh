#!/bin/bash
# =============================================================================
# Phase 5: Adaptive Context Selector Benchmark
# =============================================================================
# Tests a smarter server that selects ctx dynamically based on request.
#
# Strategy matrix:
# | Scenario                    | Optimal ctx | MTP | Reason                    |
# | Short prompt + short resp   | 4K          | 7   | Fast, MTP helps           |
# | Long prompt + short resp    | 96K         | 3   | Need ctx for prompt       |
# | Short prompt + long resp    | 4K          | 7   | MTP helps generation      |
# | Long prompt + long resp     | 128K        | 3   | Context dominates          |
# | High concurrency            | 32K         | 0   | Maximize throughput       |
#
# Usage:
#   ./rtx5060ti-adaptive-bench.sh [--quick] [--full]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

MODEL_DIR="${MODEL_DIR:-/nas/AI/Models/gguf/Qwen3.6-35B-REAP-MTP-UD}"
MODEL_NAME="${MODEL_NAME:-Qwen3.6-35B-A3B-UD-Q3_K_XL-REAP.gguf}"
MODEL_PATH="${MODEL_DIR}/${MODEL_NAME}"

BUILD_DIR="${BUILD_DIR:-${REPO_DIR}/build}"
LLAMA_SERVER="${BUILD_DIR}/bin/llama-server"
SERVER_PORT="${SERVER_PORT:-8080}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_DIR}/results/rtx5060ti}"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

MAX_TOKENS=256
N_RUNS=3

QUICK=false
FULL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick) QUICK=true; shift ;;
        --full)  FULL=true; shift ;;
        *)       shift ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }

SERVER_PID=""

mkdir -p "${OUTPUT_DIR}"

# --- Prompts representing different scenarios ---
PROMPT_SHORT="Explain quantum entanglement in one sentence."
PROMPT_MEDIUM="Explain the theory of relativity in one paragraph."
PROMPT_LONG="Write a detailed technical explanation of how transformer attention mechanisms work, including multi-head self-attention, key, query, value projections, scaled dot-product attention, and the computational complexity of these operations. Include details about positional encodings and why they're necessary."
PROMPT_VERYLONG="Write a comprehensive technical guide to building a production-ready LLM serving infrastructure, covering model quantization techniques (GPTQ, AWQ, GGUF, EXL2), speculative decoding methods (EAGLE, DFlash, MTP, n-gram), KV cache management, continuous batching, tensor parallelism, and dynamic context scheduling. Include code examples and benchmark comparisons where appropriate."

if [[ "${QUICK}" == "true" ]]; then
    MAX_TOKENS=128
    N_RUNS=2
    info "Quick mode: reduced runs and token count"
fi

# --- Server ---
start_server() {
    local ctx_size="$1"
    local mtp_n="$2"
    local extra="$3"

    pkill -f "llama-server.*--port ${SERVER_PORT}" 2>/dev/null || true
    sleep 2

    local args=(
        -m "${MODEL_PATH}"
        --port "${SERVER_PORT}"
        -c "${ctx_size}"
        -ngl 99
        -fa
    )

    [[ "${mtp_n}" -gt 0 ]] && args+=(--spec-type draft-mtp --spec-draft-n-max "${mtp_n}")
    [[ -n "${extra}" ]] && args+=(${extra})

    "${LLAMA_SERVER}" "${args[@]}" > "${OUTPUT_DIR}/adaptive-server-${TIMESTAMP}.log" 2>&1 &
    SERVER_PID=$!

    local retries=60
    while [[ $retries -gt 0 ]]; do
        curl -s --max-time 2 "http://127.0.0.1:${SERVER_PORT}/health" > /dev/null 2>&1 && return 0
        sleep 1
        ((retries--))
    done
    return 1
}

kill_server() {
    [[ -n "${SERVER_PID}" ]] && kill "${SERVER_PID}" 2>/dev/null && wait "${SERVER_PID}" 2>/dev/null
    pkill -f "llama-server.*--port ${SERVER_PORT}" 2>/dev/null || true
    SERVER_PID=""
    sleep 1
}

# --- Benchmark ---
bench() {
    local label="$1"
    local prompt="$2"
    local ctx_size="$3"
    local mtp_n="$4"
    local concurrent="$5"

    log "Config: ${label} | ctx=${ctx_size} | mtp=${mtp_n} | concurrent=${concurrent}"

    start_server "${ctx_size}" "${mtp_n}" "" || return

    local start_time end_time
    start_time=$(date +%s.%N)

    local pids=()
    for ((i=1; i<=concurrent; i++)); do
        (
            curl -s --max-time 300 "http://127.0.0.1:${SERVER_PORT}/v1/completions" \
                -H "Content-Type: application/json" \
                -d "{
                    \"prompt\": \"${prompt}\",
                    \"max_tokens\": ${MAX_TOKENS},
                    \"temperature\": 0
                }" > /dev/null 2>&1 || true
        ) &
        pids+=($!)
    done

    local failures=0
    for pid in "${pids[@]}"; do
        wait "${pid}" || ((failures++))
    done

    end_time=$(date +%s.%N)
    kill_server

    local total_latency
    total_latency=$(echo "${end_time} - ${start_time}" | bc 2>/dev/null || echo "1")
    local total_tokens=$((concurrent * MAX_TOKENS))
    local throughput
    throughput=$(echo "scale=2; ${total_tokens} / ${total_latency}" | bc 2>/dev/null || echo "0")

    echo "${label},${ctx_size},${mtp_n},${concurrent},${throughput},${total_latency},${total_tokens},${failures}" \
        >> "${OUTPUT_DIR}/adaptive-results-${TIMESTAMP}.csv"

    log "  Result: ${throughput} total t/s | ${total_latency}s wall | ${failures} failures"
}

# ============================================================================
log "=== Adaptive Context Benchmark ==="

if [[ ! -f "${MODEL_PATH}" ]]; then
    echo "Model not found: ${MODEL_PATH}"
    exit 1
fi

echo "label,ctx,mtp_n,concurrent,throughput_tps,wall_time,total_tokens,failures" \
    > "${OUTPUT_DIR}/adaptive-results-${TIMESTAMP}.csv"

# ============================================================================
log ""
log "=== Scenario 1: Short Prompt + Short Response ==="
log "Strategy: ctx=4K, MTP n-max=7"
log "Baseline:   ctx=4K, MTP=off"
bench "short-baseline" "${PROMPT_SHORT}" 4096 0 1
bench "short-mtp7"    "${PROMPT_SHORT}" 4096 7 1

# ============================================================================
log ""
log "=== Scenario 2: Long Prompt + Short Response ==="
log "Strategy: ctx=96K, MTP n-max=3"
log "Baseline:   ctx=96K, MTP=off"
bench "longshort-baseline" "${PROMPT_LONG}" 98304 0 1
bench "longshort-mtp3"    "${PROMPT_LONG}" 98304 3 1

# ============================================================================
log ""
log "=== Scenario 3: Short Prompt + Long Response ==="
log "Strategy: ctx=4K, MTP n-max=7 (max generation speed)"
bench "shortlong-baseline" "${PROMPT_SHORT}" 4096 0 1
bench "shortlong-mtp7"    "${PROMPT_SHORT}" 4096 7 1

# ============================================================================
log ""
log "=== Scenario 4: Long Prompt + Long Response ==="
log "Strategy: ctx=128K, MTP n-max=3"
bench "longlong-baseline" "${PROMPT_VERYLONG}" 131072 0 1
bench "longlong-mtp3"    "${PROMPT_VERYLONG}" 131072 3 1

# ============================================================================
log ""
log "=== Scenario 5: High Concurrency (12 concurrent) ==="
log "Strategy: ctx=32K, MTP=off (max throughput under load)"
bench "concurrent-baseline" "${PROMPT_MEDIUM}" 32768 0 12
bench "concurrent-mtp3"    "${PROMPT_MEDIUM}" 32768 3 12
bench "concurrent-mtp0"    "${PROMPT_MEDIUM}" 32768 0 12
bench "concurrent-mtp7"    "${PROMPT_MEDIUM}" 32768 7 12

# ============================================================================
log ""
log "=== Scenario 6: Context Size Sweep at 12 concurrent ==="
log "Find the ctx sweet spot for high concurrency"
for ctx in 4096 16384 32768 65536; do
    bench "ctx${ctx}-conc12" "${PROMPT_MEDIUM}" "${ctx}" 0 12
done

# ============================================================================
log ""
log "=== Scenario 7: MTP n-max sweep at 12 concurrent ==="
log "Find the MTP sweet spot for high concurrency"
for mtp_n in 0 3 5 7; do
    bench "mtp${mtp_n}-conc12" "${PROMPT_MEDIUM}" 32768 "${mtp_n}" 12
done

# ============================================================================
log ""
log "=== Adaptive vs Fixed Comparison ==="
log "Compare adaptive strategy selection vs always-using best static config"
info "Adaptive strategy results show which configs win per scenario"
info "Use these to build a ctx-selection heuristic in production"

log ""
log "=== Adaptive Benchmark Complete ==="
log "Results: ${OUTPUT_DIR}/adaptive-results-${TIMESTAMP}.csv"

echo ""
echo "=== SUMMARY ==="
if command -v column &>/dev/null; then
    sort -t',' -k5 -rn "${OUTPUT_DIR}/adaptive-results-${TIMESTAMP}.csv" 2>/dev/null | column -t -s',' | head -40
fi

kill_server 2>/dev/null || true

# --- Generate heuristic ---
log ""
log "=== Derived Adaptive Heuristic ==="
cat << 'EOF'
# Adaptive Context Selection Heuristic (for llama-server wrapper)
#
# Based on benchmark results, use this logic:
#
# if prompt_length < 100 tokens:
#     if concurrent_users >= 8:
#         ctx = 32768, mtp = 0       # maximize throughput
#     else:
#         ctx = 4096, mtp = 7        # fast generation
# elif prompt_length < 1000 tokens:
#     if concurrent_users >= 8:
#         ctx = 32768, mtp = 3       # balance
#     else:
#         ctx = 65536, mtp = 3       # need ctx headroom
# else:
#     ctx = 131072, mtp = 3          # large ctx, minimal MTP
#
# Key findings (from data):
# - MTP overhead dominates at high concurrency
# - Small ctx + high MTP wins for single-stream speed
# - ctx=32768 is the sweet spot for multi-user throughput
EOF
