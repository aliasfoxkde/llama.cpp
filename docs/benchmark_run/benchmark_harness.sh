#!/bin/bash
# Qwen3.8-27B Benchmark Harness for llama.cpp
# Phase 1: Establish baseline, test DFlash2, sweep n-max 2-7

set -e

# Configuration
LLAMA_SERVER="/home/mkinney/Repos/llama.cpp/build-cuda-new/bin/llama-server"
BENCHMARK_DIR="/home/mkinney/Repos/llama.cpp/docs/benchmark_run"
LOGS_DIR="${BENCHMARK_DIR}/logs"
RUNS_DIR="${BENCHMARK_DIR}/runs/llama"
PROMPTS_DIR="${BENCHMARK_DIR}/prompts"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default settings
PORT=8080
CONTEXT=8192
MAX_TOKENS=512
WARMUP_RUNS=1
RUNS=3
TEMPERATURE=0.7
TOP_P=0.9
NGL=99

# Model configurations to test
declare -A MODEL_CONFIGS=(
    ["iq2_xxs"]="/home/mkinney/Models/unsloth/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-IQ2_XXS.gguf"
    ["iq3_xxs"]="/home/mkinney/Models/unsloth/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-IQ3_XXS.gguf"
    ["q3_k_xl"]="/home/mkinney/Models/unsloth/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-Q3_K_XL.gguf"
)

# KV cache types
declare -A KV_CONFIGS=(
    ["q8_0"]="q8_0"
    ["q4_0"]="q4_0"
    ["f16"]="f16"
)

# DFlash n-max values
N_MAX_VALUES=(2 3 4 5 6 7)

# Context sizes to test
CONTEXT_SIZES=(8192 16384 32768 65536)

# DFlash drafter (when available)
DFLASH_DRAFTER=""

log() {
    echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +%H:%M:%S)] ✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[$(date +%H:%M:%S)] ⚠${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +%H:%M:%S)] ✗${NC} $1"
}

check_vram() {
    local vram=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
    log "VRAM used: ${vram} MiB"
    echo $vram
}

wait_for_server() {
    local url=$1
    local max_attempts=30
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if curl -s --max-time 2 "${url}/health" > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    return 1
}

stop_server() {
    log "Stopping llama-server on port ${PORT}..."
    pkill -f "llama-server.*port ${PORT}" 2>/dev/null || true
    sleep 2
}

start_server() {
    local model=$1
    local extra_args="${2:-}"

    stop_server

    log "Starting server with model: $(basename $model)"
    log "Extra args: ${extra_args}"

    ${LLAMA_SERVER} \
        -m "${model}" \
        -c ${CONTEXT} \
        -tb 256 \
        -ctk q8_0 \
        -ctv q8_0 \
        -ngl ${NGL} \
        -t 16 \
        -np 4 \
        -fa on \
        --sleep-idle-seconds 300 \
        --host 0.0.0.0 \
        --port ${PORT} \
        ${extra_args} \
        > "${LOGS_DIR}/server_$(basename $model)_$$.log" 2>&1 &

    if wait_for_server "http://localhost:${PORT}"; then
        log_success "Server started successfully"
        return 0
    else
        log_error "Server failed to start"
        return 1
    fi
}

get_vram_usage() {
    nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | tr ',' ' '
}

run_benchmark() {
    local prompt=$1
    local run_id=$2
    local output_file="${RUNS_DIR}/${run_id}.json"

    local temp_output=$(mktemp)
    local start_time=$(date +%s%3N)

    curl -s -X POST "http://localhost:${PORT}/completion" \
        -H "Content-Type: application/json" \
        -d "{
            \"prompt\": $(echo $prompt | jq -Rs),
            \"n_predict\": ${MAX_TOKENS},
            \"temperature\": ${TEMPERATURE},
            \"top_p\": ${TOP_P},
            \"stream\": false
        }" > "${temp_output}" 2>/dev/null

    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))

    # Parse response
    local tokens=$(jq -r '.tokens_predicted' "${temp_output}" 2>/dev/null || echo "0")
    local prompt_tokens=$(jq -r '.tokens_evaluated' "${temp_output}" 2>/dev/null || echo "0")
    local dynatemp=$(jq -r '.dynatemp_range_min' "${temp_output}" 2>/dev/null || echo "null")
    local acceptance=$(jq -r '.accepted_tokens' "${temp_output}" 2>/dev/null || echo "null")
    local rejection=$(jq -r '.rejected_tokens' "${temp_output}" 2>/dev/null || echo "null")
    local content=$(jq -r '.content' "${temp_output}" 2>/dev/null || echo "")

    # Calculate TPS
    local prefill_tps=$(echo "scale=2; ${prompt_tokens} / ${duration} * 1000" | bc 2>/dev/null || echo "0")
    local decode_tps=$(echo "scale=2; ${tokens} / ${duration} * 1000" | bc 2>/dev/null || echo "0")

    local vram_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)

    # Create JSON output
    cat > "${output_file}" << EOF
{
    "run_id": "${run_id}",
    "timestamp": "$(date -Iseconds)",
    "engine": "llama.cpp",
    "model": "$(basename $model)",
    "context_length": ${CONTEXT},
    "max_tokens": ${MAX_TOKENS},
    "temperature": ${TEMPERATURE},
    "top_p": ${TOP_P},
    "ngl": ${NGL},
    "kv_type": "q8_0",
    "prompt_tokens": ${prompt_tokens},
    "output_tokens": ${tokens},
    "duration_ms": ${duration},
    "prefill_tps": ${prefill_tps},
    "decode_tps": ${decode_tps},
    "vram_mb": ${vram_used},
    "draft_tokens": ${acceptance:-0},
    "rejected_tokens": ${rejection:-0},
    "n_max": ${n_max:-1},
    "content": $(echo "${content}" | jq -Rs)
}
EOF

    log "Run ${run_id}: ${tokens} tokens in ${duration}ms (${decode_tps} tok/s)"

    rm -f "${temp_output}"
}

run_benchmark_with_dflash() {
    local prompt=$1
    local run_id=$2
    local n_max=$3
    local output_file="${RUNS_DIR}/${run_id}.json"

    local temp_output=$(mktemp)
    local start_time=$(date +%s%3N)

    curl -s -X POST "http://localhost:${PORT}/completion" \
        -H "Content-Type: application/json" \
        -d "{
            \"prompt\": $(echo $prompt | jq -Rs),
            \"n_predict\": ${MAX_TOKENS},
            \"temperature\": ${TEMPERATURE},
            \"top_p\": ${TOP_P},
            \"stream\": false,
            \"n_max\": ${n_max}
        }" > "${temp_output}" 2>/dev/null

    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))

    # Parse response - llama.cpp returns these in extended stats
    local tokens=$(jq -r '.tokens_predicted' "${temp_output}" 2>/dev/null || echo "0")
    local prompt_tokens=$(jq -r '.tokens_evaluated' "${temp_output}" 2>/dev/null || echo "0")
    local content=$(jq -r '.content' "${temp_output}" 2>/dev/null || echo "")
    local accepted=$(jq -r '.accepted_tokens' "${temp_output}" 2>/dev/null || echo "null")
    local rejected=$(jq -r '.rejected_tokens' "${temp_output}" 2>/dev/null || echo "null")

    local decode_tps=$(echo "scale=2; ${tokens} / ${duration} * 1000" | bc 2>/dev/null || echo "0")
    local vram_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)

    cat > "${output_file}" << EOF
{
    "run_id": "${run_id}",
    "timestamp": "$(date -Iseconds)",
    "engine": "llama.cpp",
    "model": "$(basename $model)",
    "context_length": ${CONTEXT},
    "max_tokens": ${MAX_TOKENS},
    "temperature": ${TEMPERATURE},
    "top_p": ${TOP_P},
    "ngl": ${NGL},
    "kv_type": "q8_0",
    "n_max": ${n_max},
    "draft_model": "$(basename ${DFLASH_DRAFTER})",
    "prompt_tokens": ${prompt_tokens},
    "output_tokens": ${tokens},
    "duration_ms": ${duration},
    "decode_tps": ${decode_tps},
    "vram_mb": ${vram_used},
    "accepted_tokens": ${accepted:-0},
    "rejected_tokens": ${rejected:-0},
    "content": $(echo "${content}" | jq -Rs)
}
EOF

    log "Run ${run_id}: n_max=${n_max}, accepted=${accepted}, tokens=${tokens}, ${decode_tps} tok/s"

    rm -f "${temp_output}"
}

# Create necessary directories
mkdir -p "${LOGS_DIR}" "${RUNS_DIR}"

# Check prerequisites
if [ ! -f "${LLAMA_SERVER}" ]; then
    log_error "llama-server not found at ${LLAMA_SERVER}"
    exit 1
fi

log "=========================================="
log "  llama.cpp Benchmark Harness"
log "  Phase 1: DFlash2 Testing"
log "=========================================="
log ""
log "Configuration:"
log "  Context: ${CONTEXT}"
log "  Max tokens: ${MAX_TOKENS}"
log "  Temperature: ${TEMPERATURE}"
log "  Runs per test: ${RUNS}"
log ""

# Select test prompt
TEST_PROMPT=$(cat "${PROMPTS_DIR}/code/001_fizzbuzz.txt")

# Phase 1.1: Baseline without DFlash
log "${CYAN}=== Phase 1.1: Baseline (no DFlash) ===${NC}"

for model_name in "${!MODEL_CONFIGS[@]}"; do
    model="${MODEL_CONFIGS[$model_name]}"
    if [ ! -f "${model}" ]; then
        log_warn "Model not found: ${model}"
        continue
    fi

    log "Testing model: ${model_name} ($(basename $model))"

    if ! start_server "${model}"; then
        log_error "Failed to start server for ${model_name}"
        continue
    fi

    check_vram

    for run in $(seq 1 ${RUNS}); do
        run_id="llama_${model_name}_baseline_run${run}"
        run_benchmark "${TEST_PROMPT}" "${run_id}"
    done

    stop_server
done

# Phase 1.2: Context ceiling tests
log "${CYAN}=== Phase 1.2: Context Ceiling ===${NC}"

smallest_model="/home/mkinney/Models/unsloth/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-IQ2_XXS.gguf"

for ctx in "${CONTEXT_SIZES[@]}"; do
    CONTEXT=${ctx}
    log "Testing context: ${CONTEXT}"

    if start_server "${smallest_model}"; then
        run_id="llama_iq2_xxs_ctx${ctx}"
        run_benchmark "${TEST_PROMPT}" "${run_id}"
        stop_server
    else
        log_error "Failed at context ${ctx}"
        break
    fi
done

# Phase 1.3: DFlash n-max sweep (when drafter available)
if [ -n "${DFLASH_DRAFTER}" ] && [ -f "${DFLASH_DRAFTER}" ]; then
    log "${CYAN}=== Phase 1.3: DFlash n-max Sweep ===${NC}"

    target_model="/home/mkinney/Models/unsloth/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-IQ2_XXS.gguf"

    for n_max in "${N_MAX_VALUES[@]}"; do
        log "Testing n_max: ${n_max}"

        extra_args="--spec-type draft-dflash --spec-draft-model ${DFLASH_DRAFTER} --spec-draft-n-max ${n_max}"

        if start_server "${target_model}" "${extra_args}"; then
            for run in $(seq 1 ${RUNS}); do
                run_id="llama_dflash_n${n_max}_run${run}"
                run_benchmark_with_dflash "${TEST_PROMPT}" "${run_id}" ${n_max}
            done
            stop_server
        else
            log_error "Failed to start with n_max=${n_max}"
        fi
    done
else
    log_warn "DFlash drafter not available. Set DFLASH_DRAFTER path to enable DFlash testing."
    log "Available draft models:"
    find /home/mkinney/Models -name "*dflash*" -o -name "*DFlash*" -type d 2>/dev/null | head -10
fi

log_success "Benchmark harness complete!"
log "Results saved to: ${RUNS_DIR}/"
