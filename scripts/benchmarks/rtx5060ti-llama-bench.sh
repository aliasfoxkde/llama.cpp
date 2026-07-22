#!/bin/bash
# =============================================================================
# RTX 5060 Ti llama.cpp Benchmark Script
# =============================================================================
# Purpose: Systematic throughput sweep for Qwen3.6-35B-REAP on RTX 5060 Ti 16GB
# Hardware: NVIDIA RTX 5060 Ti 16GB (Blackwell GB206), CUDA 12.9+, Driver 570+
# Model: Qwen3.6-35B-A3B-UD-Q3_K_XL-REAP.gguf
#
# Supports: MTP (draft-mtp), DFlash (draft-dflash), EAGLE-3 (draft-eagle3),
#           n-gram methods (ngram-simple, ngram-mod, etc.)
# =============================================================================

set -euo pipefail

# --- Configuration ---
MODEL_DIR="${MODEL_DIR:-/nas/AI/Models/gguf/Qwen3.6-35B-REAP-MTP-UD}"
MODEL_NAME="${MODEL_NAME:-Qwen3.6-35B-A3B-UD-Q3_K_XL-REAP.gguf}"
MODEL_PATH="${MODEL_DIR}/${MODEL_NAME}"

# Draft model for DFlash/EAGLE-3 (optional — set path if available)
DFLASH_MODEL="${DFLASH_MODEL:-}"
EAGLE3_MODEL="${EAGLE3_MODEL:-}"

BUILD_DIR="${BUILD_DIR:-/nas/Temp/repos/llama.cpp/build}"
LLAMA_SERVER="${BUILD_DIR}/bin/llama-server"
SERVER_PORT="${SERVER_PORT:-8080}"
OUTPUT_DIR="${OUTPUT_DIR:-/nas/Temp/repos/llama.cpp/results/rtx5060ti}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Benchmark settings
BENCHMARK_PROMPT="Explain the theory of relativity in one paragraph."
MAX_TOKENS="${MAX_TOKENS:-512}"
N_RUNS="${N_RUNS:-3}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

SERVER_PID=""

# --- Setup ---
mkdir -p "${OUTPUT_DIR}"

if [[ ! -f "${MODEL_PATH}" ]]; then
    error "Model not found: ${MODEL_PATH}"
    error "Set MODEL_DIR and MODEL_NAME env vars."
    exit 1
fi

if [[ ! -f "${LLAMA_SERVER}" ]]; then
    error "llama-server not found: ${LLAMA_SERVER}"
    error "Build llama.cpp first: cmake --build build --config release -j\$(nproc)"
    exit 1
fi

log "Model: ${MODEL_PATH}"
log "Build: ${LLAMA_SERVER}"
log "Output: ${OUTPUT_DIR}"

# --- Server Management ---
start_server() {
    local ctx_size="$1"
    local ngl="$2"
    local spec_type="$3"
    local spec_draft="$4"
    local extra_args="$5"

    kill_server 2>/dev/null || true
    sleep 2

    local server_args=(
        -m "${MODEL_PATH}"
        --host 127.0.0.1
        --port "${SERVER_PORT}"
        -c "${ctx_size}"
        -ngl "${ngl}"
        -fa
    )

    if [[ "${spec_type}" != "none" ]]; then
        server_args+=(--spec-type "${spec_type}")
        if [[ -n "${spec_draft}" ]]; then
            server_args+=(-md "${spec_draft}")
        fi
    fi

    if [[ -n "${extra_args}" ]]; then
        server_args+=(${extra_args})
    fi

    log "Starting: ${server_args[*]}"
    "${LLAMA_SERVER}" "${server_args[@]}" > "${OUTPUT_DIR}/server-${TIMESTAMP}.log" 2>&1 &
    SERVER_PID=$!

    # Wait for server ready
    local retries=60
    while [[ $retries -gt 0 ]]; do
        if curl -s --max-time 2 "http://127.0.0.1:${SERVER_PORT}/health" > /dev/null 2>&1; then
            log "Server ready"
            sleep 2
            return 0
        fi
        if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
            error "Server died. Log:"
            tail -10 "${OUTPUT_DIR}/server-${TIMESTAMP}.log"
            return 1
        fi
        sleep 1
        ((retries--))
    done
    error "Server failed to start after 60s"
    return 1
}

kill_server() {
    if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
        kill "${SERVER_PID}" 2>/dev/null || true
        wait "${SERVER_PID}" 2>/dev/null || true
    fi
    pkill -f "llama-server.*--port ${SERVER_PORT}" 2>/dev/null || true
    SERVER_PID=""
    sleep 1
}

# --- Benchmark Single Config ---
bench_config() {
    local ctx_size="$1"
    local ngl="$2"
    local spec_type="$3"
    local spec_draft="$4"
    local tb="$5"
    local ub="$6"
    local ctk="$7"
    local ctv="$8"
    local label="$9"
    local extra_args="${10:-}"

    local config_desc="${label}|ctx=${ctx_size}|ngl=${ngl}|spec=${spec_type}|tb=${tb}|ub=${ub}|kv=${ctk:-na}_${ctv:-na}"

    log "Benchmarking: ${config_desc}"

    # Build extra args
    local extra=""
    [[ -n "${tb}" ]]         && extra+=" -tb ${tb}"
    [[ -n "${ub}" ]]         && extra+=" -ub ${ub}"
    [[ -n "${ctk}" ]]        && extra+=" -ctk ${ctk}"
    [[ -n "${ctv}" ]]       && extra+=" -ctv ${ctv}"
    [[ -n "${extra_args}" ]] && extra+=" ${extra_args}"

    start_server "${ctx_size}" "${ngl}" "${spec_type}" "${spec_draft}" "${extra}" || return

    local total_tps=0
    local total_latency=0
    local runs=()
    local acceptances=()

    for ((run=1; run<=N_RUNS; run++)); do
        local start_time end_time
        start_time=$(date +%s.%N)

        local output
        output=$(curl -s --max-time 300 "http://127.0.0.1:${SERVER_PORT}/v1/completions" \
            -H "Content-Type: application/json" \
            -d "{
                \"prompt\": \"${BENCHMARK_PROMPT}\",
                \"max_tokens\": ${MAX_TOKENS},
                \"temperature\": 0,
                \"stream\": false
            }")

        end_time=$(date +%s.%N)

        if echo "${output}" | jq -e '.error' > /dev/null 2>&1; then
            warn "Run ${run} error: $(echo "${output}" | jq -r '.error.message' 2>/dev/null || echo "${output}")"
            continue
        fi

        local tokens_gen
        tokens_gen=$(echo "${output}" | jq -r '.usage.completion_tokens' 2>/dev/null || echo "0")
        local latency
        latency=$(echo "${end_time} - ${start_time}" | bc 2>/dev/null || echo "1")
        local tps
        tps=$(echo "scale=2; ${tokens_gen} / ${latency}" | bc 2>/dev/null || echo "0")

        runs+=("${tps}")
        total_tps=$(echo "scale=4; ${total_tps} + ${tps}" | bc 2>/dev/null || echo "0")
        total_latency=$(echo "scale=4; ${total_latency} + ${latency}" | bc 2>/dev/null || echo "0")

        log "  Run ${run}: ${tps} t/s (${latency}s wall, ${tokens_gen} tokens)"
    done

    kill_server

    if [[ ${#runs[@]} -eq 0 ]]; then
        warn "No successful runs: ${config_desc}"
        return
    fi

    local avg_tps
    avg_tps=$(echo "scale=2; ${total_tps} / ${#runs[@]}" | bc 2>/dev/null || echo "0")
    local avg_latency
    avg_latency=$(echo "scale=4; ${total_latency} / ${#runs[@]}" | bc 2>/dev/null || echo "0")

    # Write CSV: label,ctx,ngl,spec_type,tb,ub,ctk,ctv,avg_tps,avg_latency,n_runs
    echo "${label},${ctx_size},${ngl},${spec_type},${spec_draft:-},${tb:-},${ub:-},${ctk:-},${ctv:-},${avg_tps},${avg_latency},${#runs[@]}" \
        >> "${OUTPUT_DIR}/llama-results-${TIMESTAMP}.csv"

    log "Result: avg=${avg_tps} t/s, latency=${avg_latency}s (${#runs[@]} runs)"
}

# --- Run Full Sweep ---
log "=== Starting llama.cpp Benchmark Sweep ==="
log "Timestamp: ${TIMESTAMP}"

# CSV header
echo "label,ctx,ngl,spec_type,spec_draft,tb,ub,ctk,ctv,avg_tps,avg_latency,n_runs" \
    > "${OUTPUT_DIR}/llama-results-${TIMESTAMP}.csv"

# ============================================================
# Phase 1: Context Size Sweep (MTP off, baseline)
# ============================================================
log "=== Phase 1: Context Size Sweep (baseline, MTP off) ==="
for ctx in 4096 32768 65536 98304 131072; do
    bench_config "${ctx}" 99 none "" "" "" "" "" "baseline-ctx${ctx}"
done

# ============================================================
# Phase 2: NGL Layer Sweep (MTP off, 32K ctx)
# ============================================================
log "=== Phase 2: NGL Layer Sweep ==="
for ngl in 0 35 50 99; do
    bench_config 32768 "${ngl}" none "" "" "" "" "" "ngl${ngl}"
done

# ============================================================
# Phase 3: MTP n-max Sweep
# ============================================================
log "=== Phase 3: MTP n-max Sweep ==="
for mtp_n in 3 5 7; do
    for ctx in 4096 32768 98304 131072; do
        bench_config "${ctx}" 99 draft-mtp "" "" "" "" "" "mtp${mtp_n}-ctx${ctx}"
    done
done

# ============================================================
# Phase 4: Batch Size Sweep
# ============================================================
log "=== Phase 4: Batch Size Sweep ==="
for tb_ub in "256 128" "512 256" "1024 512" "2048 1024"; do
    tb=$(echo "${tb_ub}" | cut -d' ' -f1)
    ub=$(echo "${tb_ub}" | cut -d' ' -f2)
    bench_config 32768 99 none "" "${tb}" "${ub}" "" "" "batch-${tb}-${ub}"
done

# ============================================================
# Phase 5: KV Cache Quantization Sweep
# ============================================================
log "=== Phase 5: KV Cache Quantization Sweep ==="
for ctk in q4_0 q4_1 q5_0; do
    bench_config 65536 99 none "" 512 256 "${ctk}" "${ctk}" "kv-${ctk}"
done

# ============================================================
# Phase 6: DFlash (draft-dflash)
# DFlash requires a separate draft model (e.g. z-lab/Qwen3-4B-DFlash)
# Convert with: python convert_hf_to_gguf.py z-lab/Qwen3-4B-DFlash \
#     --target-model-dir Qwen/Qwen3-4B --outtype bf16 --outfile Qwen3-4B-DFlash.gguf
# ============================================================
if [[ -n "${DFLASH_MODEL}" && -f "${DFLASH_MODEL}" ]]; then
    log "=== Phase 6: DFlash Sweep ==="
    for ctx in 4096 32768 98304; do
        for n_max in 7 15; do
            bench_config "${ctx}" 99 draft-dflash "${DFLASH_MODEL}" "" "" "" "" "dflash-n${n_max}-ctx${ctx}"
        done
    done
else
    info "Phase 6: DFlash skipped (set DFLASH_MODEL env var to enable)"
    info "  Download: huggingface.co/z-lab/Qwen3-4B-DFlash"
    info "  Convert:  python convert_hf_to_gguf.py z-lab/Qwen3-4B-DFlash \\"
    info "    --target-model-dir Qwen/Qwen3-4B --outtype bf16 --outfile Qwen3-4B-DFlash.gguf"
fi

# ============================================================
# Phase 7: EAGLE-3 (draft-eagle3)
# EAGLE-3 requires a separate draft model (e.g. AngelSlim/Qwen3-4B_eagle3)
# Convert with: python convert_hf_to_gguf.py AngelSlim/Qwen3-4B_eagle3 \
#     --target-model-dir Qwen/Qwen3-4B --outtype bf16 --outfile Qwen3-4B-eagle3.gguf
# ============================================================
if [[ -n "${EAGLE3_MODEL}" && -f "${EAGLE3_MODEL}" ]]; then
    log "=== Phase 7: EAGLE-3 Sweep ==="
    for ctx in 4096 32768 98304; do
        for n_max in 3 5; do
            bench_config "${ctx}" 99 draft-eagle3 "${EAGLE3_MODEL}" "" "" "" "" "eagle3-n${n_max}-ctx${ctx}"
        done
    done
else
    info "Phase 7: EAGLE-3 skipped (set EAGLE3_MODEL env var to enable)"
    info "  Download: huggingface.co/AngelSlim/Qwen3-4B_eagle3"
    info "  Convert:  python convert_hf_to_gguf.py AngelSlim/Qwen3-4B_eagle3 \\"
    info "    --target-model-dir Qwen/Qwen3-4B --outtype bf16 --outfile Qwen3-4B-eagle3.gguf"
fi

# ============================================================
# Phase 8: n-gram methods (no extra model needed)
# ============================================================
log "=== Phase 8: n-gram Methods Sweep ==="
for spec in ngram-simple ngram-mod; do
    for ctx in 4096 32768 98304; do
        bench_config "${ctx}" 99 "${spec}" "" "" "" "" "" "${spec}-ctx${ctx}"
    done
done

# ============================================================
# Phase 9: Best config with concurrent load
# ============================================================
log "=== Phase 9: Concurrent Throughput (best single config) ==="
info "Concurrent test is run by run-all-benchmarks.sh"
info "  Use: ./scripts/benchmarks/run-all-benchmarks.sh --concurrent"

# --- Done ---
log "=== Sweep Complete ==="
log "Results: ${OUTPUT_DIR}/llama-results-${TIMESTAMP}.csv"

echo ""
echo "=== SUMMARY (sorted by avg_tps) ==="
if command -v column &>/dev/null; then
    sort -t',' -k10 -nr "${OUTPUT_DIR}/llama-results-${TIMESTAMP}.csv" 2>/dev/null | column -t -s',' | head -40
else
    sort -t',' -k10 -nr "${OUTPUT_DIR}/llama-results-${TIMESTAMP}.csv" 2>/dev/null | head -40
fi

kill_server 2>/dev/null || true
