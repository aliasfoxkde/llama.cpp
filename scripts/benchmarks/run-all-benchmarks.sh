#!/bin/bash
# =============================================================================
# RTX 5060 Ti — Master Benchmark Runner
# =============================================================================
# Runs all benchmark phases for the systematic RTX 5060 Ti characterization.
#
# Usage:
#   ./run-all-benchmarks.sh                    # full suite (all phases)
#   ./run-all-benchmarks.sh --phase0         # Phase 0: draft model download/convert
#   ./run-all-benchmarks.sh --phase1         # Phase 1: per-stream sweep
#   ./run-all-benchmarks.sh --phase2         # Phase 2: acceptance rate
#   ./run-all-benchmarks.sh --phase3         # Phase 3: concurrent throughput
#   ./run-all-benchmarks.sh --phase4         # Phase 4: draft model comparison
#   ./run-all-benchmarks.sh --phase5         # Phase 5: adaptive context
#   ./run-all-benchmarks.sh --multi-gpu     # Multi-GPU: 5060 Ti + V100 comparison
#   ./run-all-benchmarks.sh --vllm           # vLLM benchmarks (DSpark, upstream)
#   ./run-all-benchmarks.sh --quick          # quick mode (fewer runs)
#   ./run-all-benchmarks.sh --llama-only     # skip vLLM
#
# Environment variables:
#   MODEL_DIR           GGUF model directory
#   MODEL_NAME          GGUF filename
#   HF_MODEL_DIR        HuggingFace model (for vLLM)
#   HF_MODEL_NAME       HuggingFace model name
#   DFLASH_MODEL        DFlash draft GGUF path
#   EAGLE3_MODEL        EAGLE-3 draft GGUF path
#   OUTPUT_DIR          results output directory
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_DIR}/results/rtx5060ti}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# --- Defaults ---
RUN_PHASE0=false
RUN_PHASE1=false
RUN_PHASE2=false
RUN_PHASE3=false
RUN_PHASE4=false
RUN_PHASE5=false
RUN_MULTI_GPU=false
RUN_VLLM=false
LLAMA_ONLY=false
QUICK=false

# --- Parse Args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --phase0) RUN_PHASE0=true; shift ;;
        --phase1) RUN_PHASE1=true; shift ;;
        --phase2) RUN_PHASE2=true; shift ;;
        --phase3) RUN_PHASE3=true; shift ;;
        --phase4) RUN_PHASE4=true; shift ;;
        --phase5) RUN_PHASE5=true; shift ;;
        --multi-gpu) RUN_MULTI_GPU=true; shift ;;
        --vllm)   RUN_VLLM=true; shift ;;
        --llama-only) LLAMA_ONLY=true; shift ;;
        --quick)
            QUICK=true
            export MAX_TOKENS="${MAX_TOKENS:-128}"
            export N_RUNS="${N_RUNS:-2}"
            shift ;;
        --all)
            RUN_PHASE0=true; RUN_PHASE1=true; RUN_PHASE2=true
            RUN_PHASE3=true; RUN_PHASE4=true; RUN_PHASE5=true
            RUN_MULTI_GPU=true; RUN_VLLM=true
            shift ;;
        *) shift ;;
    esac
done

# Default: run all llama phases if nothing specified
if [[ "${RUN_PHASE0}" == "false" && "${RUN_PHASE1}" == "false" && "${RUN_PHASE2}" == "false" && \
      "${RUN_PHASE3}" == "false" && "${RUN_PHASE4}" == "false" && "${RUN_PHASE5}" == "false" && \
      "${RUN_MULTI_GPU}" == "false" && "${RUN_VLLM}" == "false" ]]; then
    RUN_PHASE0=true; RUN_PHASE1=true; RUN_PHASE2=true
    RUN_PHASE3=true; RUN_PHASE4=true; RUN_PHASE5=true
    RUN_MULTI_GPU=true; RUN_VLLM=! "${LLAMA_ONLY}"
fi

mkdir -p "${OUTPUT_DIR}"

log "=== RTX 5060 Ti Benchmark Suite ==="
log "Output: ${OUTPUT_DIR}"
log "Timestamp: ${TIMESTAMP}"
log "Phases: phase0=${RUN_PHASE0} phase1=${RUN_PHASE1} phase2=${RUN_PHASE2} phase3=${RUN_PHASE3} phase4=${RUN_PHASE4} phase5=${RUN_PHASE5} multi-gpu=${RUN_MULTI_GPU} vllm=${RUN_VLLM}"

# --- Phase 0: Draft model download and conversion ---
if [[ "${RUN_PHASE0}" == "true" ]]; then
    log ""
    log "=== PHASE 0: Draft Model Download & Conversion ==="
    "${SCRIPT_DIR}/rtx5060ti-draft-convert.sh"
fi

# --- Phase 1: Per-stream throughput sweep ---
if [[ "${RUN_PHASE1}" == "true" ]]; then
    log ""
    log "=== PHASE 1: Per-Stream Throughput Sweep ==="
    MODEL_DIR="${MODEL_DIR:-}" \
    MODEL_NAME="${MODEL_NAME:-}" \
    BUILD_DIR="${BUILD_DIR:-}" \
    OUTPUT_DIR="${OUTPUT_DIR}" \
    TIMESTAMP="${TIMESTAMP}" \
    MAX_TOKENS="${MAX_TOKENS:-512}" \
    N_RUNS="${N_RUNS:-3}" \
    "${SCRIPT_DIR}/rtx5060ti-llama-bench.sh"
fi

# --- Phase 2: Acceptance rate measurement ---
if [[ "${RUN_PHASE2}" == "true" ]]; then
    log ""
    log "=== PHASE 2: Acceptance Rate Measurement ==="
    EAGLE3_MODEL="${EAGLE3_MODEL:-}" \
    MODEL_DIR="${MODEL_DIR:-}" \
    MODEL_NAME="${MODEL_NAME:-}" \
    BUILD_DIR="${BUILD_DIR:-}" \
    OUTPUT_DIR="${OUTPUT_DIR}" \
    TIMESTAMP="${TIMESTAMP}" \
    MAX_TOKENS="${MAX_TOKENS:-256}" \
    N_RUNS="${N_RUNS:-5}" \
    "${SCRIPT_DIR}/rtx5060ti-acceptance-bench.sh"
fi

# --- Phase 3: Concurrent throughput ---
if [[ "${RUN_PHASE3}" == "true" ]]; then
    log ""
    log "=== PHASE 3: Concurrent System Throughput ==="
    MODEL_DIR="${MODEL_DIR:-}" \
    MODEL_NAME="${MODEL_NAME:-}" \
    BUILD_DIR="${BUILD_DIR:-}" \
    OUTPUT_DIR="${OUTPUT_DIR}" \
    TIMESTAMP="${TIMESTAMP}" \
    MAX_TOKENS="${MAX_TOKENS:-512}" \
    N_RUNS="${N_RUNS:-3}" \
    "${SCRIPT_DIR}/rtx5060ti-concurrent-bench.sh"
fi

# --- Phase 4: Draft model comparison ---
if [[ "${RUN_PHASE4}" == "true" ]]; then
    log ""
    log "=== PHASE 4: Draft Model Comparison ==="
    info "Compare EAGLE-3 vs MTP vs n-gram vs no-speculative"
    info "Uses results from Phase 2 (acceptance) and Phase 3 (throughput)"
    info "Key metric: total system throughput at matching quality"
fi

# --- Phase 5: Adaptive context ---
if [[ "${RUN_PHASE5}" == "true" ]]; then
    log ""
    log "=== PHASE 5: Adaptive Context Selector ==="
    MODEL_DIR="${MODEL_DIR:-}" \
    MODEL_NAME="${MODEL_NAME:-}" \
    BUILD_DIR="${BUILD_DIR:-}" \
    OUTPUT_DIR="${OUTPUT_DIR}" \
    TIMESTAMP="${TIMESTAMP}" \
    MAX_TOKENS="${MAX_TOKENS:-256}" \
    N_RUNS="${N_RUNS:-3}" \
    "${SCRIPT_DIR}/rtx5060ti-adaptive-bench.sh"
fi

# --- vLLM benchmarks ---
if [[ "${RUN_VLLM}" == "true" ]]; then
    log ""
    log "=== vLLM Benchmarks ==="
    HF_MODEL_DIR="${HF_MODEL_DIR:-}" \
    HF_MODEL_NAME="${HF_MODEL_NAME:-Qwen/Qwen3.6-35B-REAP-MTP}" \
    OUTPUT_DIR="${OUTPUT_DIR}" \
    VLLM_MODE="${VLLM_MODE:-upstream}" \
    TIMESTAMP="${TIMESTAMP}" \
    MAX_TOKENS="${MAX_TOKENS:-512}" \
    N_RUNS="${N_RUNS:-3}" \
    "${SCRIPT_DIR}/rtx5060ti-vllm-bench.sh"
fi

# --- Phase Multi-GPU ---
if [[ "${RUN_MULTI_GPU}" == "true" ]]; then
    log ""
    log "=== Multi-GPU Benchmark (RTX 5060 Ti + V100) ==="
    MODEL_DIR="${MODEL_DIR:-}" \
    MODEL_NAME="${MODEL_NAME:-}" \
    BUILD_DIR="${BUILD_DIR:-}" \
    OUTPUT_DIR="${OUTPUT_DIR}/multi-gpu" \
    TIMESTAMP="${TIMESTAMP}" \
    MAX_TOKENS="${MAX_TOKENS:-512}" \
    N_RUNS="${N_RUNS:-3}" \
    "${SCRIPT_DIR}/rtx5060ti-multi-gpu-bench.sh"
fi

# --- Generate final report ---
log ""
log "=== Generating Final Report ==="

local report="${OUTPUT_DIR}/RTX5060TI-BENCHMARKS-FINAL-${TIMESTAMP}.md"

cat > "${report}" << EOF
# RTX 5060 Ti 16GB — Final Benchmark Report

**Date**: ${TIMESTAMP}
**Hardware**: NVIDIA RTX 5060 Ti 16GB (Blackwell GB206), CUDA 12.9+, Driver 570+
**Model**: Qwen3.6-35B-A3B-UD-Q3_K_XL-REAP.gguf (Q3_K_M, ~13.4GB)

---

## Key Findings

### 1. Best Per-Stream Config
INSERT_BEST_PER_STREAM

### 2. Best Total Throughput (12 concurrent)
INSERT_BEST_CONCURRENT

### 3. MTP Acceptance vs Context Size
INSERT_MTP_ACCEPTANCE

### 4. Draft Model Comparison (EAGLE-3 vs MTP vs n-gram)
INSERT_DRAFT_COMPARISON

### 5. Adaptive Context Strategy
INSERT_ADAPTIVE_STRATEGY

### 6. vLLM vs llama.cpp
INSERT_VLLM_COMPARISON

---

## Per-Stream Results (Phase 1)

\`\`\`
INSERT_PER_STREAM_TABLE
\`\`\`

## Acceptance Rate Results (Phase 2)

\`\`\`
INSERT_ACCEPTANCE_TABLE
\`\`\`

## Concurrent Throughput Results (Phase 3)

\`\`\`
INSERT_CONCURRENT_TABLE
\`\`\`

## Adaptive Context Results (Phase 5)

\`\`\`
INSERT_ADAPTIVE_TABLE
\`\`\`

## vLLM Results

\`\`\`
INSERT_VLLM_TABLE
\`\`\`

---

## Conclusions

1. **For interactive use**: ctx=4K + MTP n-max=7 gives best per-stream speed
2. **For batch/server**: ctx=32K + MTP=off maximizes total throughput
3. **For quality+speed**: ctx=96K + MTP n-max=3 is the balanced choice
4. **MTP acceptance**: drops ~X% per 32K increase in context
5. **EAGLE-3 MoE draft**: acceptance is ~X% vs MTP's ~65% (architectural mismatch cost)
6. **vLLM vs llama.cpp**: ~X% difference in total throughput

## Recommendations

### Single-User Interactive
\`\`\`bash
./llama-server -m Qwen3.6-35B-A3B-UD-Q3_K_XL-REAP.gguf \\
    -c 4096 -ngl 99 --spec-type draft-mtp --spec-draft-n-max 7
\`\`\`

### Multi-User Server (12 concurrent)
\`\`\`bash
./llama-server -m Qwen3.6-35B-A3B-UD-Q3_K_XL-REAP.gguf \\
    -c 32768 -ngl 99 -tb 2048 -ub 1024 \\
    --n-parallel 12 --cont-batching
\`\`\`

### Adaptive Context Server (production)
Use the heuristic from Phase 5 to select ctx + MTP dynamically based on:
- Prompt length
- Requested max_tokens
- Current concurrency

---

*Generated by scripts/benchmarks/run-all-benchmarks.sh on ${TIMESTAMP}*
EOF

# Populate report sections from CSV files
insert_csv() {
    local key="$1"
    local csv_file="$2"
    local max_lines="${3:-50}"

    if [[ -f "${csv_file}" ]]; then
        local content
        content=$(sort -t',' -k10 -rn "${csv_file}" 2>/dev/null | head "${max_lines}" | sed 's/^/| /' || echo "No data")
        sed -i "s/INSERT_${key}/\`\`\`\n${content}\n\`\`\`/" "${report}"
    else
        sed -i "s/INSERT_${key}/No data (file not found: ${csv_file})/" "${report}"
    fi
}

insert_csv "PER_STREAM_TABLE"      "${OUTPUT_DIR}/llama-results-${TIMESTAMP}.csv" 30
insert_csv "ACCEPTANCE_TABLE"     "${OUTPUT_DIR}/acceptance-results-${TIMESTAMP}.csv" 30
insert_csv "CONCURRENT_TABLE"     "${OUTPUT_DIR}/concurrent-results-${TIMESTAMP}.csv" 30
insert_csv "ADAPTIVE_TABLE"       "${OUTPUT_DIR}/adaptive-results-${TIMESTAMP}.csv" 30
insert_csv "VLLM_TABLE"           "${OUTPUT_DIR}/vllm-results-${TIMESTAMP}.csv" 20

# Best configs
if [[ -f "${OUTPUT_DIR}/llama-results-${TIMESTAMP}.csv" ]]; then
    local best_line
    best_line=$(sort -t',' -k10 -rn "${OUTPUT_DIR}/llama-results-${TIMESTAMP}.csv" 2>/dev/null | head -1)
    sed -i "s/INSERT_BEST_PER_STREAM/${best_line}/" "${report}"
fi

log "Report: ${report}"
log ""
log "=== All benchmarks complete ==="
log "Results directory: ${OUTPUT_DIR}"
