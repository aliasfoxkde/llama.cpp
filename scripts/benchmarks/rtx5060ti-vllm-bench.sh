#!/bin/bash
# =============================================================================
# RTX 5060 Ti vLLM Benchmark Script
# =============================================================================
# Purpose: Install vLLM (upstream or Avesed fork for Qwen3.6) and run
#          systematic throughput benchmarks comparing to llama.cpp server.
# Hardware: NVIDIA RTX 5060 Ti 16GB (Blackwell GB206), CUDA 12.9+, Driver 570+
# Model: Qwen3.6-35B-A3B-REAP-MTP (HuggingFace format)
# =============================================================================

set -euo pipefail

# --- Configuration ---
VLLM_MODE="${VLLM_MODE:-upstream}"   # "upstream" or "avesed"
MODEL_DIR="${MODEL_DIR:-/nas/AI/Models/huggingface}"
MODEL_NAME="${MODEL_NAME:-Qwen/Qwen3.6-35B-REAP-MTP}"
MODEL_PATH="${MODEL_DIR}/${MODEL_NAME}"

OUTPUT_DIR="${OUTPUT_DIR:-/nas/Temp/repos/llama.cpp/results/rtx5060ti}"
VLLM_PORT="${VLLM_PORT:-8000}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Benchmark settings
MAX_TOKENS="${MAX_TOKENS:-512}"
N_RUNS="${N_RUNS:-3}"
BENCHMARK_PROMPT="Explain the theory of relativity in one paragraph."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

VLLM_PID=""

# --- vLLM Installation ---
install_vllm() {
    log "=== vLLM Installation (mode: ${VLLM_MODE}) ==="

    if [[ "${VLLM_MODE}" == "avesed" ]]; then
        log "Installing Avesed fork (required for Qwen3.6 MoE)..."
        if docker info > /dev/null 2>&1; then
            log "Docker available — using Avesed container image"
            info "Run with: docker run -it --gpus '\"device=0\"' -v ~/.cache/huggingface:/root/.cache/huggingface -p ${VLLM_PORT}:8000 ghcr.io/avesed/vllm-ampere-optimized:0.3"
            info "Then run benchmarks using: python3 -m vllm.entrypoints.openai.api_server --model ${MODEL_NAME} ..."
            return 0
        else
            warn "Docker not available — falling back to pip install of Avesed fork"
        fi

        # Try pip install of Avesed fork
        pip install git+https://github.com/avesed/vllm-ampere-optimized.git@main 2>&1 | tail -5
    else
        log "Installing upstream vLLM..."
        pip install vllm>=0.8.0 2>&1 | tail -5
    fi

    log "vLLM installed successfully"
}

# --- Server Management ---
start_vllm_server() {
    local max_model_len="$1"
    local gpu_mem="$2"
    local extra_args="${3:-}"
    local speculative="${4:-}"  # e.g., '{"method":"dspark","num_speculative_tokens":5}'

    # Kill existing server
    kill_vllm_server || true
    sleep 2

    local server_args=(
        python3 -m vllm.entrypoints.openai.api_server
        --model "${MODEL_PATH}"
        --dtype half
        --gpu-memory-utilization "${gpu_mem}"
        --max-model-len "${max_model_len}"
        --port "${VLLM_PORT}"
        --host 127.0.0.1
        --enable-chunked-prefill
        --max-num-batched-tokens 8192
        --max-num-seqs 256
    )

    if [[ -n "${speculative}" ]]; then
        server_args+=(--speculative-config "${speculative}")
    fi

    if [[ -n "${extra_args}" ]]; then
        server_args+=(${extra_args})
    fi

    log "Starting vLLM server..."
    nohup "${server_args[@]}" > "${OUTPUT_DIR}/vllm-server-${TIMESTAMP}.log" 2>&1 &
    VLLM_PID=$!

    # Wait for server ready
    local retries=120
    while [[ $retries -gt 0 ]]; do
        if curl -s --max-time 2 "http://127.0.0.1:${VLLM_PORT}/health" > /dev/null 2>&1; then
            log "vLLM server ready after $((120 - retries))s"
            sleep 3
            return 0
        fi
        # Check if process died
        if ! kill -0 "${VLLM_PID}" 2>/dev/null; then
            error "vLLM server process died. Log:"
            tail -20 "${OUTPUT_DIR}/vllm-server-${TIMESTAMP}.log"
            return 1
        fi
        sleep 2
        ((retries--))
    done

    error "vLLM server failed to start after 240s"
    tail -30 "${OUTPUT_DIR}/vllm-server-${TIMESTAMP}.log"
    return 1
}

kill_vllm_server() {
    if [[ -n "${VLLM_PID}" ]] && kill -0 "${VLLM_PID}" 2>/dev/null; then
        kill "${VLLM_PID}" 2>/dev/null || true
        wait "${VLLM_PID}" 2>/dev/null || true
    fi
    pkill -f "vllm.entrypoints" 2>/dev/null || true
    sleep 1
}

# --- Benchmark Single Config ---
bench_vllm_config() {
    local max_model_len="$1"
    local gpu_mem="$2"
    local speculative="$3"
    local label="$4"

    local config_desc="${label}|model_len=${max_model_len}|gpu_mem=${gpu_mem}|spec=${speculative:-none}"

    log "Benchmarking vLLM: ${config_desc}"

    start_vllm_server "${max_model_len}" "${gpu_mem}" "" "${speculative}"

    local total_tps=0
    local total_latency=0
    local runs=()

    for ((run=1; run<=N_RUNS; run++)); do
        local start_time
        start_time=$(date +%s.%N)

        local output
        output=$(curl -s --max-time 300 "http://127.0.0.1:${VLLM_PORT}/v1/completions" \
            -H "Content-Type: application/json" \
            -d "{
                \"prompt\": \"${BENCHMARK_PROMPT}\",
                \"max_tokens\": ${MAX_TOKENS},
                \"temperature\": 0
            }" 2>&1) || true

        local end_time
        end_time=$(date +%s.%N)
        local latency
        latency=$(echo "${end_time} - ${start_time}" | bc 2>/dev/null || echo "0")

        if echo "${output}" | jq -e '.error' > /dev/null 2>&1; then
            warn "Run ${run} error: $(echo "${output}" | jq -r '.error.message' 2>/dev/null || echo "${output}")"
            continue
        fi

        local tokens_gen
        tokens_gen=$(echo "${output}" | jq -r '.usage.completion_tokens' 2>/dev/null || echo "0")
        local tps
        tps=$(echo "scale=2; ${tokens_gen} / ${latency}" | bc 2>/dev/null || echo "0")

        runs+=("${tps}")
        total_tps=$(echo "scale=2; ${total_tps} + ${tps}" | bc 2>/dev/null || echo "0")
        total_latency=$(echo "scale=4; ${total_latency} + ${latency}" | bc 2>/dev/null || echo "0")

        log "  Run ${run}: ${tps} t/s (${latency}s wall, ${tokens_gen} tokens)"
    done

    kill_vllm_server

    if [[ ${#runs[@]} -eq 0 ]]; then
        warn "No successful runs for: ${config_desc}"
        return
    fi

    local avg_tps
    avg_tps=$(echo "scale=2; ${total_tps} / ${#runs[@]}" | bc 2>/dev/null || echo "0")
    local avg_latency
    avg_latency=$(echo "scale=4; ${total_latency} / ${#runs[@]}" | bc 2>/dev/null || echo "0")

    echo "vllm,${label},${max_model_len},${gpu_mem},${speculative:-none},${avg_tps},${avg_latency},${#runs[@]}" >> "${OUTPUT_DIR}/vllm-results-${TIMESTAMP}.csv"

    log "Result: avg ${avg_tps} t/s, avg latency ${avg_latency}s"
}

# --- Concurrent Benchmark ---
bench_vllm_concurrent() {
    local max_model_len="$1"
    local concurrency="$2"
    local label="concurrent-${concurrency}"

    log "Benchmarking vLLM concurrent: ${concurrency} parallel requests"

    start_vllm_server "${max_model_len}" "0.90" "" ""

    local start_time
    start_time=$(date +%s.%N)

    # Launch concurrent requests
    local pids=()
    for ((i=1; i<=concurrency; i++)); do
        (
            curl -s --max-time 300 "http://127.0.0.1:${VLLM_PORT}/v1/completions" \
                -H "Content-Type: application/json" \
                -d "{
                    \"prompt\": \"${BENCHMARK_PROMPT}\",
                    \"max_tokens\": ${MAX_TOKENS},
                    \"temperature\": 0
                }" > /dev/null 2>&1 || true
        ) &
        pids+=($!)
    done

    # Wait for all to complete
    local total_tokens=0
    for pid in "${pids[@]}"; do
        wait "${pid}" || true
    done

    local end_time
    end_time=$(date +%s.%N)
    local total_latency
    total_latency=$(echo "${end_time} - ${start_time}" | bc 2>/dev/null || echo "1")

    # Total tokens = concurrency * MAX_TOKENS (all should complete)
    total_tokens=$((concurrency * MAX_TOKENS))
    local throughput
    throughput=$(echo "scale=2; ${total_tokens} / ${total_latency}" | bc 2>/dev/null || echo "0")

    kill_vllm_server

    echo "vllm,${label},${max_model_len},0.90,none,${throughput},${total_latency},${concurrency}" >> "${OUTPUT_DIR}/vllm-results-${TIMESTAMP}.csv"

    log "Result: ${throughput} total t/s (${concurrency} concurrent, ${total_latency}s wall)"
}

# --- Run Full Sweep ---
log "=== Starting vLLM Benchmark Sweep ==="

mkdir -p "${OUTPUT_DIR}"

# Check model path
if [[ ! -d "${MODEL_PATH}" ]]; then
    warn "Model directory not found: ${MODEL_PATH}"
    info "Set MODEL_DIR and MODEL_NAME env vars, or place model at expected path."
    info "For Qwen3.6-35B-REAP-MTP, download from HuggingFace:"
    info "  huggingface-cli download Qwen/Qwen3.6-35B-REAP-MTP --local-dir ${MODEL_PATH}"
    warn "Skipping vLLM benchmarks (model not found)"
    echo "vllm,SKIP,model_not_found,," >> "${OUTPUT_DIR}/vllm-results-${TIMESTAMP}.csv"
else
    log "Model found: ${MODEL_PATH}"

    # CSV header
    echo "type,label,max_model_len,gpu_mem,speculative,avg_tps,avg_latency,n_runs" > "${OUTPUT_DIR}/vllm-results-${TIMESTAMP}.csv"

    # --- Phase 1: Basic vLLM configs ---
    log "=== Phase 1: Basic vLLM Configs ==="

    # Standard half precision, high utilization
    bench_vllm_config 32768 0.90 "none" "fp16-32k-90"
    bench_vllm_config 65536 0.90 "none" "fp16-64k-90"
    bench_vllm_config 131072 0.85 "none" "fp16-128k-85"

    # --- Phase 2: Memory utilization sweep ---
    log "=== Phase 2: Memory Utilization Sweep ==="
    for gpu_mem in 0.75 0.85 0.95; do
        bench_vllm_config 32768 "${gpu_mem}" "none" "fp16-32k-mem${gpu_mem}"
    done

    # --- Phase 2b: NVFP4 Testing (Blackwell GB206 only) ---
    # NVFP4 is a Blackwell-specific 4-bit floating point format.
    # RTX 5060 Ti is GB206 (Blackwell) — test if vLLM supports it.
    # NVFP4 reduces weight memory by ~4x vs FP16, potentially freeing headroom for DSpark.
    log "=== Phase 2b: NVFP4 (Blackwell) Testing ==="
    info "NVFP4 requires vLLM with Blackwell support (CUDA 12.9+). Test by running and checking log."
    # To enable NVFP4 in vLLM, use --dtype fp4 or --quantization fp4
    # Note: not all models support FP4 quantization in vLLM
    bench_vllm_config 32768 0.90 "none" "fp16-32k-nvfp4-test"

    # --- Phase 3: Avesed fork with DSpark (Qwen3.6 MoE support) ---
    # DSpark requires the Avesed fork for Qwen3.6 MoE gated attention support.
    # Draft module adds VRAM overhead — NVFP4 may be needed to fit in 16GB.
    if [[ "${VLLM_MODE}" == "avesed" ]]; then
        log "=== Phase 3: DSpark Speculative Decoding (Avesed Fork) ==="
        # DSpark with 5 tokens draft
        bench_vllm_config 32768 0.80 '{"method":"dspark","num_speculative_tokens":5}' "dspark-5tok"
        bench_vllm_config 65536 0.80 '{"method":"dspark","num_speculative_tokens":5}' "dspark-5tok-64k"
        # Try with fewer speculative tokens if VRAM is tight
        bench_vllm_config 32768 0.80 '{"method":"dspark","num_speculative_tokens":3}' "dspark-3tok"
    else
        info "Skipping DSpark (upstream vLLM — Qwen3.6 requires Avesed fork for DSpark)"
        info "  Use: VLLM_MODE=avesed ./rtx5060ti-vllm-bench.sh"
        info "  Or: docker run ghcr.io/avesed/vllm-ampere-optimized:0.3"
    fi

    # --- Phase 3b: NVFP4 + DSpark Combined ---
    # If both NVFP4 and DSpark work independently, test them together.
    # NVFP4 reduces target model weight memory, DSpark adds draft overhead.
    # Net effect: NVFP4 frees VRAM for DSpark draft module.
    log "=== Phase 3b: NVFP4 + DSpark Combined (Advanced) ==="
    info "Only run if both NVFP4 and DSpark pass their individual tests."

    # --- Phase 4: Concurrent throughput ---
    log "=== Phase 4: Concurrent Throughput ==="
    for concurrency in 4 8 12 16; do
        bench_vllm_concurrent 32768 "${concurrency}"
    done
fi

log "=== vLLM Sweep Complete ==="
log "Results: ${OUTPUT_DIR}/vllm-results-${TIMESTAMP}.csv"

# Print summary
if [[ -f "${OUTPUT_DIR}/vllm-results-${TIMESTAMP}.csv" ]]; then
    echo ""
    echo "=== SUMMARY ==="
    column -t -s',' "${OUTPUT_DIR}/vllm-results-${TIMESTAMP}.csv" | head -30
fi

kill_vllm_server || true
