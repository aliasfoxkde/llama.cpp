# Qwen3.8-27B Benchmark Results - RTX 5060 Ti 16GB

## Executive Summary

**Goal**: Find the most intelligent model that can run on RTX 5060 Ti 16GB with best performance.

**Phase 1**: llama.cpp DFlash2 provides **61% speedup** with n_max=4
**Phase 2**: Escha SGLang W2 baseline working at **31 tok/s**

---

## Hardware Setup
- **GPU**: NVIDIA GeForce RTX 5060 Ti (16GB VRAM, Blackwell/sm_120)
- **Driver**: 610.57.04 / CUDA 13.3
- **CPU**: Intel i5-13600K (14 cores) / **RAM**: 31GB

---

## Phase 1: llama.cpp DFlash2 Testing [COMPLETE]

### Configuration
- **Target Model**: Qwen3.8-27B-UD-IQ2_XXS (8.4GB GGUF)
- **Draft Model**: Qwen3.8-27B-DFlash-bootstrap-Q8_0 (1.8GB)
- **Context**: 8192 | **KV Cache**: Q8_0 | **Max Tokens**: 256

### Baseline Results (No DFlash)

| Model | Size | VRAM | Decode tok/s |
|-------|------|------|--------------|
| **Qwen3.8-27B-UD-IQ2_XXS** | 8.4GB | 9.6GB | **37.5** |
| Qwen3.8-27B-UD-IQ3_XXS | 12GB | 12.3GB | 30.4 |
| Qwen3.8-27B-UD-Q3_K_XL | 13GB | 13.7GB | 28.7 |

### DFlash n-max Sweep Results

| n_max | Decode tok/s | Speedup | Acceptance | Draft Tokens | VRAM |
|-------|--------------|---------|------------|--------------|------|
| 0 (baseline) | 37.5 | - | - | - | 9.6GB |
| 2 | 52.0 | **+39%** | 62% | 227 | 13.2GB |
| 3 | 54.1 | **+44%** | 58% | 279 | 13.8GB |
| **4** | **60.5** | **+61%** | **56%** | 315 | 14.4GB |
| 5 | 39.4 | +5% | 27% | 542 | 15.0GB |
| 6 | 44.1 | +18% | 33% | 514 | 15.6GB |
| 7 | OOM | - | - | - | - |

**n_max=4 is OPTIMAL for RTX 5060 Ti 16GB**

---

## Phase 2: Escha SGLang [WORKING]

### Configuration
```bash
VENV=/path/to/sglang_test_env \
MODEL=/home/mkinney/Models/EschaLabs/Qwen3.8-27B-Escha-W2 \
ATTN_BACKEND=triton \
MEM=0.90 \
CTXLEN=16384 \
CUDA_GRAPH_BS="1 2 4 8" \
GRAPHS=1 \
THINK=1 \
bash /tmp/escha-runtime/sglang/serve.sh
```

### Baseline Results

| Metric | Value |
|--------|-------|
| **Decode Speed** | 31 tok/s |
| **VRAM Used** | 14.7 GB / 16 GB |
| **Context Length** | 16K |
| **Max Concurrent** | 4 streams |

### Notes
- VENV must point to cp312 venv (not system Python 3.14)
- ATTN_BACKEND=triton required on Blackwell
- 16GB config from escha docs (untested by EschaLabs)

---

## Phase 6: vLLM DFlash2 [BLOCKED]

### Issue
- vLLM requires patched PR 52816 for DFlash2 support
- lued/Qwen3.8-27B-DFlash2-W8 is specifically for vLLM
- SGLang escha fork does not have DFlash2 integration

---

## Cross-Engine Comparison

| Engine | Model | Quant | tok/s | VRAM | Context |
|--------|-------|-------|-------|------|---------|
| llama.cpp | Qwen3.8-27B | IQ2_XXS | 37.5 | 9.6GB | 8K |
| llama.cpp + DFlash2 | Qwen3.8-27B | IQ2_XXS | **60.5** | 14.4GB | 8K |
| Escha SGLang | Escha W2 | 2-bit escha | 31 | 14.7GB | 16K |

---

## Recommendations

### Best Raw Speed: llama.cpp DFlash2
- 60.5 tok/s with n_max=4
- 14.4GB VRAM

### Best Context: Escha SGLang
- 16K context vs 8K
- 2-bit escha quantization
- 31 tok/s baseline

### Best Quality/Context Balance: Escha W2
- Higher quality per bit (2-bit escha vs IQ2_XXS)
- Larger context possible

---

## Artifacts Created
- `RESULTS.md` - This file
- `PROGRESS.md` - Progress tracking
- `PHASE2_SGLANG.md` - Escha SGLang documentation
- `benchmark_harness.sh` - Automation script
- `environment/` - Hardware/software capture
- `prompts/` - Test prompts
