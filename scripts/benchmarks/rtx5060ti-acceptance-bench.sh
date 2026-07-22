#!/bin/bash
# =============================================================================
# Phase 2: Acceptance Rate Measurement
# =============================================================================
# Measures draft acceptance rate for each speculative decoding method.
# Acceptance rate = accepted tokens / generated tokens
# This is the key metric for draft quality, not raw t/s.
#
# Usage:
#   EAGLE3_MODEL=/path/to/eagle3.gguf ./rtx5060ti-acceptance-bench.sh
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

EAGLE3_MODEL="${EAGLE3_MODEL:-}"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

BENCHMARK_PROMPT="Write a detailed technical explanation of how transformer attention mechanisms work, including multi-head self-attention, key, query, value projections, and the computational complexity involved."
MAX_TOKENS=256
N_RUNS=5

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }

SERVER_PID=""

mkdir -p "${OUTPUT_DIR}"

# --- Server ---
start_server() {
    local ctx_size="$1"
    local spec_type="$2"
    local spec_draft="$3"
    local extra="$4"

    kill_server 2>/dev/null || true
    sleep 2

    local args=(
        -m "${MODEL_PATH}"
        --port "${SERVER_PORT}"
        -c "${ctx_size}"
        -ngl 99
        -fa
    )

    if [[ "${spec_type}" != "none" ]]; then
        args+=(--spec-type "${spec_type}")
        [[ -n "${spec_draft}" ]] && args+=(-md "${spec_draft}")
    fi

    [[ -n "${extra}" ]] && args+=(${extra})

    "${LLAMA_SERVER}" "${args[@]}" > "${OUTPUT_DIR}/server-accept-${TIMESTAMP}.log" 2>&1 &
    SERVER_PID=$!

    local retries=60
    while [[ $retries -gt 0 ]]; do
        curl -s --max-time 2 "http://127.0.0.1:${SERVER_PORT}/health" > /dev/null 2>&1 && return 0
        sleep 1
        ((retries--))
    done
    warn "Server failed to start"
    return 1
}

kill_server() {
    [[ -n "${SERVER_PID}" ]] && kill "${SERVER_PID}" 2>/dev/null && wait "${SERVER_PID}" 2>/dev/null
    pkill -f "llama-server.*--port ${SERVER_PORT}" 2>/dev/null || true
    SERVER_PID=""
    sleep 1
}

# --- Parse server stats ---
# llama-server prints stats after each generation:
#   draft acceptance rate = X.XX (  Y accepted /   Z generated)
#   statistics ngram_mod: #calls = X, #gen drafts = Y, #acc drafts = Z, ...

parse_stats() {
    local log_file="$1"
    local spec_type="$2"

    # Extract draft acceptance rate
    local accept_rate
    accept_rate=$(grep -oP "draft acceptance rate = \K[0-9.]+" "${log_file}" 2>/dev/null | tail -1 || echo "N/A")

    # Extract method-specific stats
    local gen_drafts=0 acc_drafts=0 gen_tokens=0 acc_tokens=0
    case "${spec_type}" in
        draft-mtp)
            # MTP doesn't print ngram stats — extract from draft acceptance line
            gen_drafts=$(grep -oP '\d+ accepted / \K\d+' "${log_file}" | grep -v "accepted" | tail -1 || echo "0")
            acc_drafts=$(grep -oP '(\d+) accepted /' "${log_file}" | grep -oP '\d+' | tail -1 || echo "0")
            ;;
        ngram-mod|ngram-simple|ngram-map-k|ngram-map-k4v)
            gen_drafts=$(grep -oP "#gen drafts = \K\d+" "${log_file}" | tail -1 || echo "0")
            acc_drafts=$(grep -oP "#acc drafts = \K\d+" "${log_file}" | tail -1 || echo "0")
            gen_tokens=$(grep -oP "#gen tokens = \K\d+" "${log_file}" | tail -1 || echo "0")
            acc_tokens=$(grep -oP "#acc tokens = \K\d+" "${log_file}" | tail -1 || echo "0")
            ;;
        draft-eagle3|draft-dflash)
            gen_drafts=$(grep -oP "#gen drafts = \K\d+" "${log_file}" | tail -1 || echo "0")
            acc_drafts=$(grep -oP "#acc drafts = \K\d+" "${log_file}" | tail -1 || echo "0")
            ;;
    esac

    echo "${accept_rate},${gen_drafts},${acc_drafts},${gen_tokens},${acc_tokens}"
}

# --- Benchmark single config ---
bench_acceptance() {
    local ctx_size="$1"
    local spec_type="$2"
    local spec_draft="$3"
    local label="$4"

    log "Testing: ${label} | ctx=${ctx_size} | spec=${spec_type}"

    start_server "${ctx_size}" "${spec_type}" "${spec_draft}" "" || return

    local output_log="${OUTPUT_DIR}/accept-${label}-${ctx_size}-${TIMESTAMP}.log"

    # Run benchmark and capture output + server stats
    for ((run=1; run<=N_RUNS; run++)); do
        local start_time end_time
        start_time=$(date +%s.%N)

        curl -s --max-time 300 "http://127.0.0.1:${SERVER_PORT}/v1/completions" \
            -H "Content-Type: application/json" \
            -d "{
                \"prompt\": \"${BENCHMARK_PROMPT}\",
                \"max_tokens\": ${MAX_TOKENS},
                \"temperature\": 0,
                \"stream\": false
            }" >> "${output_log}" 2>&1

        end_time=$(date +%s.%N)
        local latency
        latency=$(echo "${end_time} - ${start_time}" | bc 2>/dev/null || echo "0")

        local tokens
        tokens=$(tail -1 "${output_log}" | jq -r '.usage.completion_tokens' 2>/dev/null || echo "0")
        local tps
        tps=$(echo "scale=2; ${tokens} / ${latency}" | bc 2>/dev/null || echo "0")

        log "  Run ${run}: ${tokens} tokens in ${latency}s = ${tps} t/s"
    done

    kill_server

    # Parse stats from server log
    local stats
    stats=$(parse_stats "${OUTPUT_DIR}/server-accept-${TIMESTAMP}.log" "${spec_type}")

    local accept_rate gen_drafts acc_drafts gen_tokens acc_tokens
    accept_rate=$(echo "${stats}" | cut -d',' -f1)
    gen_drafts=$(echo "${stats}" | cut -d',' -f2)
    acc_drafts=$(echo "${stats}" | cut -d',' -f3)
    gen_tokens=$(echo "${stats}" | cut -d',' -f4)
    acc_tokens=$(echo "${stats}" | cut -d',' -f5)

    # Average tps from runs
    local avg_tps=0 count=0
    while IFS= read -r line; do
        local t
        t=$(echo "${line}" | jq -r '.usage.completion_tokens' 2>/dev/null || echo "0")
        [[ "${t}" =~ ^[0-9.]+$ ]] && avg_tps=$(echo "scale=2; ${avg_tps} + ${t}" | bc 2>/dev/null) && ((count++))
    done < "${output_log}"
    [[ ${count} -gt 0 ]] && avg_tps=$(echo "scale=2; ${avg_tps} / ${count}" | bc 2>/dev/null || echo "0")

    echo "${label},${ctx_size},${spec_type},${gen_drafts},${acc_drafts},${accept_rate},${gen_tokens},${acc_tokens},${avg_tps},${N_RUNS}" \
        >> "${OUTPUT_DIR}/acceptance-results-${TIMESTAMP}.csv"

    log "  Acceptance: ${accept_rate} | Drafts: ${acc_drafts}/${gen_drafts} | Tokens: ${acc_tokens}/${gen_tokens} | Avg: ${avg_tps} t/s"
}

# ============================================================================
log "=== Acceptance Rate Benchmark ==="

if [[ ! -f "${MODEL_PATH}" ]]; then
    error "Model not found: ${MODEL_PATH}"
    exit 1
fi

echo "label,ctx,spec_type,gen_drafts,acc_drafts,accept_rate,gen_tokens,acc_tokens,avg_tps,n_runs" \
    > "${OUTPUT_DIR}/acceptance-results-${TIMESTAMP}.csv"

# --- Baseline: no speculative ---
log ""
log "=== Baseline: No Speculative Decoding ==="
for ctx in 4096 32768 65536 98304; do
    bench_acceptance "${ctx}" none "" "baseline-ctx${ctx}"
done

# --- MTP sweep ---
log ""
log "=== MTP n-max Sweep ==="
for mtp_n in 3 5 7; do
    for ctx in 4096 32768 65536 98304; do
        bench_acceptance "${ctx}" draft-mtp "" "mtp-n${mtp_n}-ctx${ctx}"
    done
done

# --- n-gram methods ---
log ""
log "=== n-gram Methods ==="
for spec in ngram-mod ngram-simple ngram-map-k; do
    for ctx in 4096 32768 65536; do
        bench_acceptance "${ctx}" "${spec}" "" "${spec}-ctx${ctx}"
    done
done

# --- EAGLE-3 if available ---
if [[ -n "${EAGLE3_MODEL}" && -f "${EAGLE3_MODEL}" ]]; then
    log ""
    log "=== EAGLE-3 Draft (Qwen3 MoE on Qwen3.6 target) ==="
    for ctx in 4096 32768 65536; do
        bench_acceptance "${ctx}" draft-eagle3 "${EAGLE3_MODEL}" "eagle3-moemismatch-ctx${ctx}"
    done
else
    info "EAGLE3_MODEL not set or file not found — skipping EAGLE-3 tests"
    info "  Set: EAGLE3_MODEL=/path/to/Qwen3-30B_moe_eagle3-eagle3.gguf"
fi

log ""
log "=== Acceptance Benchmark Complete ==="
log "Results: ${OUTPUT_DIR}/acceptance-results-${TIMESTAMP}.csv"

echo ""
echo "=== SUMMARY (sorted by accept_rate) ==="
if command -v column &>/dev/null; then
    sort -t',' -k6 -rn "${OUTPUT_DIR}/acceptance-results-${TIMESTAMP}.csv" 2>/dev/null | column -t -s',' | head -30
fi

kill_server 2>/dev/null || true
