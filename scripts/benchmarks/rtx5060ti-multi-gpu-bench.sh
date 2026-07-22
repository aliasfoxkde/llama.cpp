#!/bin/bash
# =============================================================================
# Multi-GPU Benchmark Framework (RTX 5060 Ti + V100 + any combo)
# =============================================================================
# Auto-detects available GPUs, runs single and multi-GPU benchmarks, compares
# throughput, latency, and efficiency across all configurations.
#
# llama.cpp multi-GPU modes:
#   --split-mode none   : single GPU only
#   --split-mode layer  : pipeline parallelism (layer split, DEFAULT)
#   --split-mode row    : row parallelism (weight row split)
#   --split-mode tensor : tensor parallelism (experimental)
#
# Hardware configurations tested:
#   - Each GPU individually (single-GPU baselines)
#   - Pipeline parallelism: --split-mode layer -ngl 99 --device 0,1
#   - Row parallelism:       --split-mode row -ngl 99 --device 0,1
#   - Tensor parallelism:    --split-mode tensor -ngl 99 --device 0,1
#   - Parallel instances:     one server per GPU, aggregate throughput
#
# Usage:
#   ./rtx5060ti-multi-gpu-bench.sh           # auto-detect + full suite
#   ./rtx5060ti-multi-gpu-bench.sh --single  # single GPU per-stream only
#   ./rtx5060ti-multi-gpu-bench.sh --multi   # multi-GPU only
#   ./rtx5060ti-multi-gpu-bench.sh --quick   # quick sweep
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

MODEL_DIR="${MODEL_DIR:-/nas/AI/Models/gguf/Qwen3.6-35B-REAP-MTP-UD}"
MODEL_NAME="${MODEL_NAME:-Qwen3.6-35B-A3B-UD-Q3_K_XL-REAP.gguf}"
MODEL_PATH="${MODEL_DIR}/${MODEL_NAME}"

BUILD_DIR="${BUILD_DIR:-${REPO_DIR}/build}"
LLAMA_SERVER="${BUILD_DIR}/bin/llama-server"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_DIR}/results/multi-gpu}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

MAX_TOKENS="${MAX_TOKENS:-512}"
N_RUNS="${N_RUNS:-3}"

SINGLE_ONLY=false
MULTI_ONLY=false
QUICK=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --single) SINGLE_ONLY=true; MULTI_ONLY=false; shift ;;
        --multi)  MULTI_ONLY=true; SINGLE_ONLY=false; shift ;;
        --quick)  QUICK=true; export N_RUNS=2 MAX_TOKENS=256; shift ;;
        *) shift ;;
    esac
done

mkdir -p "${OUTPUT_DIR}"

# =============================================================================
# COLORS
# =============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log()   { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
h1()    { echo -e "\n${CYAN}==== $* ====${NC}"; }

# =============================================================================
# GPU DETECTION
# =============================================================================
GPU_COUNT=0
CUDA_DEVICES=()
GPU_NAMES=()
GPU_MEMORY=()
GPU_ARCH=()
GPU_VRAM=()

detect_gpus() {
    h1 "GPU Detection"

    GPU_COUNT=0
    CUDA_DEVICES=()
    GPU_NAMES=()
    GPU_MEMORY=()
    GPU_ARCH=()
    GPU_VRAM=()

    if ! command -v nvidia-smi &> /dev/null; then
        warn "nvidia-smi not found — cannot detect GPUs"
        return
    fi

    # Parse nvidia-smi output
    while IFS=',' read -r idx name memory; do
        idx=$(echo "${idx}" | tr -d ' ' | grep -oE '[0-9]+' || echo "")
        name=$(echo "${name}" | xargs)
        memory=$(echo "${memory}" | grep -oE '[0-9]+' | head -1)

        if [[ -n "${idx}" && "${idx}" =~ ^[0-9]+$ && -n "${memory}" ]]; then
            CUDA_DEVICES+=("${idx}")
            GPU_NAMES+=("${name}")
            GPU_MEMORY+=("${memory}")
            ((GPU_COUNT++))

            # Determine architecture
            case "${name}" in
                *5060*)   GPU_ARCH+=("blackwell") ;;
                *5070*)   GPU_ARCH+=("blackwell") ;;
                *5080*)   GPU_ARCH+=("blackwell") ;;
                *5090*)   GPU_ARCH+=("blackwell") ;;
                *V100*)   GPU_ARCH+=("volta") ;;
                *A100*)   GPU_ARCH+=("ampere") ;;
                *H100*)   GPU_ARCH+=("hopper") ;;
                *RTX*)    GPU_ARCH+=("ada") ;;
                *)        GPU_ARCH+=("unknown") ;;
            esac
        fi
    done < <(nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader 2>/dev/null || true)

    if [[ ${GPU_COUNT} -eq 0 ]]; then
        warn "No GPUs detected via nvidia-smi"
        return
    fi

    log "Detected ${GPU_COUNT} GPU(s):"
    for ((i=0; i<GPU_COUNT; i++)); do
        info "  [${CUDA_DEVICES[$i]}] ${GPU_NAMES[$i]} | ${GPU_MEMORY[$i]} MB | ${GPU_ARCH[$i]}"
    done

    # Save GPU config
    cat > "${OUTPUT_DIR}/gpu-config-${TIMESTAMP}.sh" << EOF
# GPU config — generated ${TIMESTAMP}
export GPU_COUNT=${GPU_COUNT}
$(for ((i=0; i<GPU_COUNT; i++)); do
    echo "export CUDA_DEVICE_${i}=${CUDA_DEVICES[$i]}"
    echo "export GPU_NAME_${i}='${GPU_NAMES[$i]}'"
    echo "export GPU_MEMORY_${i}=${GPU_MEMORY[$i]}"
    echo "export GPU_ARCH_${i}='${GPU_ARCH[$i]}'"
done)
EOF
}

# =============================================================================
# GPU SELECTION
# =============================================================================
GPU_5060TI_IDX=-1
GPU_V100_IDX=-1

select_gpus() {
    h1 "GPU Assignment"

    for ((i=0; i<GPU_COUNT; i++)); do
        case "${GPU_NAMES[$i]}" in
            *5060*) GPU_5060TI_IDX=$i; info "RTX 5060 Ti  -> GPU index ${i}" ;;
            *V100*) GPU_V100_IDX=$i;  info "NVIDIA V100  -> GPU index ${i}" ;;
        esac
    done
}

# =============================================================================
# SERVER MANAGEMENT
# =============================================================================
SERVER_PIDS=()

start_server() {
    local port="$1"
    local ctx_size="$2"
    local ngl="$3"
    local split_mode="${4:-none}"
    local devices="${5:-}"       # comma-separated or empty
    local extra="${6:-}"

    # Kill existing on this port
    pkill -f "llama-server.*--port ${port}" 2>/dev/null || true
    sleep 2

    local args=(
        -m "${MODEL_PATH}"
        --host 127.0.0.1
        --port "${port}"
        -c "${ctx_size}"
        -fa
        --split-mode "${split_mode}"
    )

    [[ -n "${devices}" ]] && args+=(--device "${devices}")
    [[ -n "${ngl}" ]]    && args+=(-ngl "${ngl}")
    [[ -n "${extra}" ]]   && args+=(${extra})

    "${LLAMA_SERVER}" "${args[@]}" > "${OUTPUT_DIR}/server-${port}-${TIMESTAMP}.log" 2>&1 &
    local pid=$!
    SERVER_PIDS+=("${pid}")

    # Wait for ready
    local retries=60
    while [[ ${retries} -gt 0 ]]; do
        curl -s --max-time 2 "http://127.0.0.1:${port}/health" > /dev/null 2>&1 && return 0
        if ! kill -0 "${pid}" 2>/dev/null; then
            error "Server died. Log:"
            tail -5 "${OUTPUT_DIR}/server-${port}-${TIMESTAMP}.log"
            return 1
        fi
        sleep 1
        ((retries--))
    done
    error "Server failed to start on port ${port}"
    return 1
}

kill_servers() {
    for pid in "${SERVER_PIDS[@]}"; do
        kill "${pid}" 2>/dev/null && wait "${pid}" 2>/dev/null || true
    done
    SERVER_PIDS=()
    pkill -f "llama-server" 2>/dev/null || true
    sleep 1
}

# =============================================================================
# SINGLE BENCHMARK RUN
# =============================================================================
bench() {
    local label="$1"
    local port="$2"
    local concurrency="$3"

    local start_time end_time
    start_time=$(date +%s.%N)

    local pids=()
    for ((i=1; i<=concurrency; i++)); do
        (
            curl -s --max-time 600 "http://127.0.0.1:${port}/v1/completions" \
                -H "Content-Type: application/json" \
                -d "{
                    \"prompt\": \"Explain the theory of relativity in one paragraph.\",
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
    local latency
    latency=$(echo "${end_time} - ${start_time}" | bc 2>/dev/null || echo "1")
    local total_tokens=$((concurrency * MAX_TOKENS))
    local throughput
    throughput=$(echo "scale=2; ${total_tokens} / ${latency}" | bc 2>/dev/null || echo "0")

    echo "${label},${concurrency},${throughput},${latency},${total_tokens},${failures}" \
        >> "${OUTPUT_DIR}/results-${TIMESTAMP}.csv"

    log "  ${label}: ${throughput} t/s (${concurrency}x${MAX_TOKENS}=${total_tokens} tokens in ${latency}s) [${failures} fails]"
}

# =============================================================================
# PHASE 1: SINGLE-GPU BASELINES
# =============================================================================
phase1_single() {
    h1 "Phase 1: Single-GPU Baselines"

    echo "label,gpu_name,gpu_arch,gpu_mem_mb,device,ctx,ngl,split_mode,mtp_n,concurrency,throughput_tps,wall_time,total_tokens,failures" \
        > "${OUTPUT_DIR}/phase1-single-${TIMESTAMP}.csv"

    local ctx_sizes=(4096 32768 98304 131072)
    local mtp_n_vals=(0 3 5 7)

    [[ "${QUICK}" == "true" ]] && ctx_sizes=(4096 32768 98304) && mtp_n_vals=(0 3 7)

    for ((gpu_idx=0; gpu_idx<GPU_COUNT; gpu_idx++)); do
        local gpu_name="${GPU_NAMES[$gpu_idx]}"
        local gpu_arch="${GPU_ARCH[$gpu_idx]}"
        local gpu_mem="${GPU_MEMORY[$gpu_idx]}"
        local device="${CUDA_DEVICES[$gpu_idx]}"

        info "Testing: ${gpu_name} [${device}] (${gpu_mem}MB, ${gpu_arch})"

        for ctx in "${ctx_sizes[@]}"; do
            for mtp_n in "${mtp_n_vals[@]}"; do
                local label="${gpu_name// /_}-d${device}-ctx${ctx}-mtp${mtp_n}"
                local port=$((8080 + gpu_idx * 100 + ctx / 1024))
                local extra=""
                [[ ${mtp_n} -gt 0 ]] && extra="--spec-type draft-mtp --spec-draft-n-max ${mtp_n}"

                log "  Config: ${label}"

                if start_server "${port}" "${ctx}" 99 "none" "${device}" "${extra}"; then
                    for conc in 1 4 8 12; do
                        bench "${label}" "${port}" "${conc}"

                        # Write detailed CSV line
                        local result_line
                        result_line=$(grep "${label}" "${OUTPUT_DIR}/results-${TIMESTAMP}.csv" | tail -1)
                        echo "${label},${gpu_name},${gpu_arch},${gpu_mem},${device},${ctx},99,none,${mtp_n},${result_line}" \
                            >> "${OUTPUT_DIR}/phase1-single-${TIMESTAMP}.csv"
                    done
                fi
                pkill -f "llama-server.*--port ${port}" 2>/dev/null || true
            done
        done
    done

    log "Phase 1 complete"
}

# =============================================================================
# PHASE 2: MULTI-GPU SPLIT MODES
# =============================================================================
phase2_multi_split() {
    h1 "Phase 2: Multi-GPU Split Modes"

    if [[ ${GPU_COUNT} -lt 2 ]]; then
        warn "Need 2+ GPUs for multi-GPU — skipping"
        return
    fi

    echo "label,gpu_count,split_mode,devices,ctx,mtp_n,concurrency,throughput_tps,wall_time,total_tokens,failures" \
        > "${OUTPUT_DIR}/phase2-multisplit-${TIMESTAMP}.csv"

    # Build device list string
    local all_devices
    all_devices=$(IFS=','; echo "${CUDA_DEVICES[*]}")
    local device_count=${#CUDA_DEVICES[@]}
    local device_list="${all_devices}"

    info "Testing split modes across ${device_count} GPUs: ${device_list}"

    for split_mode in layer row tensor; do
        for ctx in 32768 98304; do
            for mtp_n in 0 3; do
                local label="multi-${split_mode}-ctx${ctx}-mtp${mtp_n}"
                local port=9090
                local extra=""
                [[ ${mtp_n} -gt 0 ]] && extra="--spec-type draft-mtp --spec-draft-n-max ${mtp_n}"

                log "  Testing: ${label} (split=${split_mode}, devs=${device_list})"

                pkill -f "llama-server.*--port ${port}" 2>/dev/null || true
                sleep 2

                "${LLAMA_SERVER}" \
                    -m "${MODEL_PATH}" \
                    --host 127.0.0.1 \
                    --port "${port}" \
                    -c "${ctx}" \
                    -fa \
                    --split-mode "${split_mode}" \
                    -ngl 99 \
                    --device "${device_list}" \
                    ${extra} \
                    > "${OUTPUT_DIR}/server-${split_mode}-${port}-${TIMESTAMP}.log" 2>&1 &

                local pid=$!
                SERVER_PIDS+=("${pid}")
                sleep 5

                if curl -s --max-time 5 "http://127.0.0.1:${port}/health" > /dev/null 2>&1; then
                    for conc in 1 4 8 12; do
                        bench "${label}" "${port}" "${conc}"

                        local result_line
                        result_line=$(grep "${label}" "${OUTPUT_DIR}/results-${TIMESTAMP}.csv" | tail -1)
                        echo "${label},${device_count},${split_mode},${device_list},${ctx},${mtp_n},${result_line}" \
                            >> "${OUTPUT_DIR}/phase2-multisplit-${TIMESTAMP}.csv"
                    done
                else
                    warn "Failed to start with split-mode=${split_mode}"
                    tail -10 "${OUTPUT_DIR}/server-${split_mode}-${port}-${TIMESTAMP}.log"
                fi
                pkill -f "llama-server.*--port ${port}" 2>/dev/null || true
            done
        done
    done

    log "Phase 2 complete"
}

# =============================================================================
# PHASE 3: PARALLEL INSTANCES (aggregate throughput)
# =============================================================================
phase3_parallel_instances() {
    h1 "Phase 3: Parallel Instances (one server per GPU)"

    if [[ ${GPU_COUNT} -lt 2 ]]; then
        warn "Need 2+ GPUs — skipping"
        return
    fi

    echo "label,gpu_count,mode,ctx,concurrency_per_gpu,total_concurrency,throughput_tps,wall_time,total_tokens,failures" \
        > "${OUTPUT_DIR}/phase3-parallel-${TIMESTAMP}.csv"

    # Start one server per GPU
    local ports=()
    SERVER_PIDS=()

    for ((gpu_idx=0; gpu_idx<GPU_COUNT; gpu_idx++)); do
        local port=$((8080 + gpu_idx * 100))
        local device="${CUDA_DEVICES[$gpu_idx]}"
        ports+=("${port}")

        info "Starting server on GPU [${gpu_idx}] ${GPU_NAMES[$gpu_idx]} port ${port} device ${device}"

        "${LLAMA_SERVER}" \
            -m "${MODEL_PATH}" \
            --host 127.0.0.1 \
            --port "${port}" \
            -c 32768 \
            -ngl 99 \
            --split-mode none \
            --device "${device}" \
            > "${OUTPUT_DIR}/server-gpu${gpu_idx}-${port}-${TIMESTAMP}.log" 2>&1 &

        SERVER_PIDS+=($!)
        sleep 3
    done

    sleep 5

    # Verify all ready
    local all_ready=true
    for port in "${ports[@]}"; do
        if ! curl -s --max-time 5 "http://127.0.0.1:${port}/health" > /dev/null 2>&1; then
            warn "Server on port ${port} not ready"
            all_ready=false
        fi
    done

    if [[ "${all_ready}" != "true" ]]; then
        warn "Not all servers ready — skipping aggregate test"
        kill_servers
        return
    fi

    log "  All ${GPU_COUNT} servers ready"

    # Test aggregate throughput
    for conc_per_gpu in 1 4 8; do
        local total_conc=$((conc_per_gpu * GPU_COUNT))
        local start_time end_time
        start_time=$(date +%s.%N)

        local pids=()
        for ((g=0; g<GPU_COUNT; g++)); do
            local port="${ports[$g]}"
            for ((i=1; i<=conc_per_gpu; i++)); do
                (
                    curl -s --max-time 600 "http://127.0.0.1:${port}/v1/completions" \
                        -H "Content-Type: application/json" \
                        -d "{
                            \"prompt\": \"Explain the theory of relativity in one paragraph.\",
                            \"max_tokens\": ${MAX_TOKENS},
                            \"temperature\": 0
                        }" > /dev/null 2>&1 || true
                ) &
                pids+=($!)
            done
        done

        local failures=0
        for pid in "${pids[@]}"; do
            wait "${pid}" || ((failures++))
        done

        end_time=$(date +%s.%N)
        local latency
        latency=$(echo "${end_time} - ${start_time}" | bc 2>/dev/null || echo "1")
        local total_tokens=$((total_conc * MAX_TOKENS))
        local throughput
        throughput=$(echo "scale=2; ${total_tokens} / ${latency}" | bc 2>/dev/null || echo "0")

        echo "parallel-instances,${GPU_COUNT},none,32768,${conc_per_gpu},${total_conc},${throughput},${latency},${total_tokens},${failures}" \
            >> "${OUTPUT_DIR}/phase3-parallel-${TIMESTAMP}.csv"

        log "  ${GPU_COUNT}x${conc_per_gpu}=${total_conc} total: ${throughput} t/s (${latency}s wall)"
    done

    kill_servers
    log "Phase 3 complete"
}

# =============================================================================
# PHASE 4: GPU-TO-GPU COMPARISON
# =============================================================================
phase4_comparison() {
    h1 "Phase 4: GPU-to-GPU Comparison"

    local report="${OUTPUT_DIR}/GPU-COMPARISON-${TIMESTAMP}.md"

    # Find best per-stream per GPU
    local best_5060ti="" best_v100=""
    if [[ ${GPU_5060TI_IDX} -ge 0 ]]; then
        best_5060ti=$(grep "RTX_5060" "${OUTPUT_DIR}/phase1-single-${TIMESTAMP}.csv" 2>/dev/null | \
                      sort -t',' -k11 -rn | head -1 || echo "")
    fi
    if [[ ${GPU_V100_IDX} -ge 0 ]]; then
        best_v100=$(grep "V100" "${OUTPUT_DIR}/phase1-single-${TIMESTAMP}.csv" 2>/dev/null | \
                    sort -t',' -k11 -rn | head -1 || echo "")
    fi

    cat > "${report}" << EOF
# GPU Comparison Report

**Date**: ${TIMESTAMP}
**Model**: Qwen3.6-35B-A3B-UD-Q3_K_XL-REAP.gguf (~13.4GB)

---

## Hardware Detected

| Slot | GPU | Architecture | Memory |
|------|-----|-------------|--------|
EOF

    for ((i=0; i<GPU_COUNT; i++)); do
        echo "| ${CUDA_DEVICES[$i]} | ${GPU_NAMES[$i]} | ${GPU_ARCH[$i]} | ${GPU_MEMORY[$i]} MB |" >> "${report}"
    done

    cat >> "${report}" << 'EOF'

## Per-Stream Best (single request, 1 token)

EOF

    if [[ -n "${best_5060ti}" ]]; then
        echo "| RTX 5060 Ti | $(echo "${best_5060ti}" | cut -d',' -f11) t/s | $(echo "${best_5060ti}" | cut -d',' -f6) ctx |" >> "${report}"
    fi
    if [[ -n "${best_v100}" ]]; then
        echo "| V100 | $(echo "${best_v100}" | cut -d',' -f11) t/s | $(echo "${best_v100}" | cut -d',' -f6) ctx |" >> "${report}"
    fi

    cat >> "${report}" << 'EOF'

## Concurrent Scaling

| Config | GPUs | Mode | Concurrency | Total t/s |
|--------|------|------|-------------|-----------|
EOF

    if [[ -f "${OUTPUT_DIR}/phase3-parallel-${TIMESTAMP}.csv" ]]; then
        while IFS=',' read -r label gc mode ctx cp tcon tp lt to fa; do
            [[ "${label" =~ ^label ]] && continue
            [[ -z "${tp}" ]] && continue
            echo "| ${label} | ${gc} | ${mode} | ${tcon} | ${tp} t/s |" >> "${report}"
        done < "${OUTPUT_DIR}/phase3-parallel-${TIMESTAMP}.csv"
    fi

    cat >> "${report}" << 'EOF'

## Key Findings

1. **Per-stream**: Which GPU wins at single-request latency?
2. **Concurrent**: Which configuration wins at high concurrency?
3. **Split modes**: Does tensor/row/layer parallelism beat parallel instances?
4. **Scaling**: How does V100 HBM2 bandwidth compare to 5060 Ti GDDR7?

## Conclusions

TODO: Fill in after running benchmarks

EOF

    log "Comparison: ${report}"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    log "=== Multi-GPU Benchmark Suite ==="
    log "Output: ${OUTPUT_DIR}"
    log "Timestamp: ${TIMESTAMP}"

    detect_gpus

    if [[ ${GPU_COUNT} -eq 0 ]]; then
        error "No GPUs detected — cannot run multi-GPU benchmarks"
        exit 1
    fi

    select_gpus

    if [[ "${SINGLE_ONLY}" == "true" ]]; then
        phase1_single
    elif [[ "${MULTI_ONLY}" == "true" ]]; then
        phase2_multi_split
        phase3_parallel_instances
    else
        phase1_single
        phase2_multi_split
        phase3_parallel_instances
        phase4_comparison
    fi

    kill_servers

    log ""
    log "=== All phases complete ==="
    log "Results: ${OUTPUT_DIR}"
    log ""
    log "Key files:"
    log "  GPU config:     ${OUTPUT_DIR}/gpu-config-${TIMESTAMP}.sh"
    log "  Phase 1:        ${OUTPUT_DIR}/phase1-single-${TIMESTAMP}.csv"
    log "  Phase 2:        ${OUTPUT_DIR}/phase2-multisplit-${TIMESTAMP}.csv"
    log "  Phase 3:        ${OUTPUT_DIR}/phase3-parallel-${TIMESTAMP}.csv"
    log "  Comparison:     ${OUTPUT_DIR}/GPU-COMPARISON-${TIMESTAMP}.md"
}

trap 'kill_servers 2>/dev/null' EXIT
main
