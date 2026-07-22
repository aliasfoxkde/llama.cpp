#!/bin/bash
# =============================================================================
# Phase 0: Draft Model Download and Conversion
# =============================================================================
# Downloads EAGLE-3 draft models and converts them for llama.cpp use
# with Qwen3.6-35B-A3B as the target model.
#
# Usage:
#   ./rtx5060ti-draft-convert.sh [--download-only] [--convert-only]
#
# Requirements:
#   huggingface-cli (pip install huggingface_hub)
#   python3 with llama.cpp scripts in PYTHONPATH
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DRAFT_DIR="${DRAFT_DIR:-${REPO_DIR}/draft-models}"
TARGET_MODEL_DIR="${TARGET_MODEL_DIR:-Qwen/Qwen3-35B-A3B}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

DOWNLOAD_ONLY=false
CONVERT_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --download-only) DOWNLOAD_ONLY=true; CONVERT_ONLY=false; shift ;;
        --convert-only)  CONVERT_ONLY=true; DOWNLOAD_ONLY=false; shift ;;
        *) shift ;;
    esac
done

mkdir -p "${DRAFT_DIR}"

# --- Check prerequisites ---
check_huggingface_cli() {
    if ! command -v huggingface-cli &> /dev/null; then
        warn "huggingface-cli not found — installing..."
        pip install huggingface_hub -q
    fi
}

check_convert_script() {
    if [[ ! -f "${REPO_DIR}/convert_hf_to_gguf.py" ]]; then
        error "convert_hf_to_gguf.py not found at ${REPO_DIR}/"
        exit 1
    fi
}

# --- Download a model ---
download_model() {
    local repo="$1"
    local local_dir="${DRAFT_DIR}/$(basename "${repo}")"

    if [[ -d "${local_dir}" ]] && [[ $(ls -A "${local_dir}" 2>/dev/null) ]]; then
        info "Already downloaded: ${repo} -> ${local_dir}"
        return 0
    fi

    log "Downloading: ${repo}"
    if huggingface-cli download "${repo}" --local-dir "${local_dir}" 2>&1; then
        log "Downloaded: ${local_dir}"
    else
        warn "Failed to download: ${repo}"
        return 1
    fi
}

# --- Convert a model ---
convert_model() {
    local draft_dir="$1"
    local target_model="$2"
    local output_name="$3"

    local draft_name
    draft_name=$(basename "${draft_dir}")

    # Determine output path
    local output_path="${DRAFT_DIR}/${output_name}.gguf"

    if [[ -f "${output_path}" ]]; then
        info "Already converted: ${output_path}"
        return 0
    fi

    log "Converting: ${draft_name} (target: ${target_model})"
    log "  Input:  ${draft_dir}"
    log "  Output: ${output_path}"

    python3 "${REPO_DIR}/convert_hf_to_gguf.py" \
        "${draft_dir}" \
        --target-model-dir "${target_model}" \
        --outtype bf16 \
        --outfile "${output_path}" 2>&1

    if [[ -f "${output_path}" ]]; then
        local size
        size=$(du -h "${output_path}" | cut -f1)
        log "Converted: ${output_path} (${size})"
    else
        error "Conversion failed: ${output_name}"
        return 1
    fi
}

# --- EAGLE-3 Draft Models to Download ---
# These are trained against Qwen3-30B MoE (standard, not Qwen3.6)
# The architectural mismatch (gated attention in Qwen3.6) will reduce acceptance
EAGLE3_MODELS=(
    "AngelSlim/Qwen3-30B_moe_eagle3:Qwen3-30B_moe_eagle3"
    "Tengyunw/qwen3_30b_moe_eagle3:qwen3_30b_moe_eagle3"
    "AngelSlim/Qwen3-14B_eagle3:Qwen3-14B_eagle3"
    "AngelSlim/Qwen3-8B_eagle3:Qwen3-8B_eagle3"
    "AngelSlim/Qwen3-4B_eagle3:Qwen3-4B_eagle3"
)

# ============================================================================
log "=== Phase 0: Draft Model Download and Conversion ==="
log "Draft directory: ${DRAFT_DIR}"
log "Target model:    ${TARGET_MODEL_DIR}"
log ""

if [[ "${CONVERT_ONLY}" == "false" ]]; then
    check_huggingface_cli

    log "=== Downloading EAGLE-3 Draft Models ==="
    for entry in "${EAGLE3_MODELS[@]}"; do
        local repo="${entry%%:*}"
        download_model "${repo}"
    done
fi

if [[ "${DOWNLOAD_ONLY}" == "false" ]]; then
    check_convert_script

    log ""
    log "=== Converting EAGLE-3 Draft Models for llama.cpp ==="
    for entry in "${EAGLE3_MODELS[@]}"; do
        local repo="${entry%%:*}"
        local name="${entry##*:}"
        local local_dir="${DRAFT_DIR}/${name}"
        local output_name="${name}-eagle3"

        if [[ -d "${local_dir}" ]]; then
            convert_model "${local_dir}" "${TARGET_MODEL_DIR}" "${output_name}"
        else
            warn "Not found, skipping conversion: ${local_dir}"
        fi
    done

    log ""
    log "=== Conversion Summary ==="
    if [[ -d "${DRAFT_DIR}" ]]; then
        ls -lh "${DRAFT_DIR}"/*.gguf 2>/dev/null || echo "No .gguf files found"
    fi
fi

log ""
log "=== Phase 0 Complete ==="
info "Set these env vars to use in benchmarks:"
info "  EAGLE3_MODEL=${DRAFT_DIR}/Qwen3-30B_moe_eagle3-eagle3.gguf"
info "  EAGLE3_8B_MODEL=${DRAFT_DIR}/Qwen3-8B_eagle3-eagle3.gguf"
