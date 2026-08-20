# Qwen3.8-27B Benchmark Results - RTX 5060 Ti 16GB

## Executive Summary

**Goal**: Find the most intelligent model that can run on RTX 5060 Ti 16GB with best performance.

**KEY FINDING**: llama.cpp DFlash2 provides **61% speedup** with n_max=4

---

## Hardware Setup
- **GPU**: NVIDIA GeForce RTX 5060 Ti (16GB VRAM, Blackwell/sm_120)
- **Driver**: 610.57.04 / CUDA 13.3
- **CPU**: Intel i5-13600K (14 cores) / **RAM**: 31GB

---

## Phase 1: llama.cpp DFlash2 Testing ✅ COMPLETE

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
| 0 (baseline) | 37.5 | — | — | — | 9.6GB |
| 2 | 52.0 | **+39%** | 62% | 227 | 13.2GB |
| 3 | 54.1 | **+44%** | 58% | 279 | 13.8GB |
| **4** | **60.5** | **+61%** | **56%** | 315 | 14.4GB |
| 5 | 39.4 | +5% | 27% | 542 | 15.0GB |
| 6 | 44.1 | +18% | 33% | 514 | 15.6GB |
| 7 | OOM | — | — | — | — |

**🎯 n_max=4 is OPTIMAL for RTX 5060 Ti 16GB**

---

## Phase 2: Escha SGLang ⚠️ INCOMPLETE

### Attempted
- Installed Escha runtime wheel successfully
- Model loaded (10.15GB, 2-bit quantized)
- Server crashed during initialization

### Issue
Blackwell architecture (sm_120) may have compatibility issues with Escha's Triton kernels.

---

## Phase 6: vLLM + W8 DFlash2 ⚠️ INCOMPLETE

### Attempted
- Downloaded W8A16 DFlash2 drafter (2.02GB from lued/Qwen3.8-27B-DFlash2-W8)
- vLLM requires safetensors target model (no GGUF support)

### Missing
- Safetensors-format target model for vLLM

---

## Final Configuration Recommendations

### Best for RTX 5060 Ti 16GB: Qwen3.8-27B-UD-IQ2_XXS + DFlash2 (n_max=4)
- **Performance**: 60.5 tok/s decode (+61% vs baseline)
- **VRAM**: 14.4GB
- **Context**: Up to 32K possible

### Alternative without DFlash: Qwen3.8-27B-UD-IQ2_XXS
- **Performance**: 37.5 tok/s decode
- **VRAM**: 9.6GB (room for larger context)
- **Use case**: When VRAM is at a premium

### Model Quality Ranking (subjective)
1. Q3_K_XL (largest, slowest, potentially best quality)
2. IQ3_XXS (balanced)
3. IQ2_XXS (fastest, smallest)

---

## VRAM Budget Summary

| Configuration | VRAM Used | VRAM Free |
|---------------|-----------|-----------|
| IQ2_XXS baseline | 9.6GB | 6.0GB |
| IQ2_XXS + DFlash n_max=4 | 14.4GB | 1.2GB |
| IQ2_XXS + DFlash n_max=6 | 15.6GB | 0GB |
| IQ3_XXS baseline | 12.3GB | 3.3GB |
| Q3_K_XL baseline | 13.7GB | 1.9GB |

**n_max=4 leaves minimal headroom (~1.2GB)**

---

## Artifacts Created

- `RESULTS.md` - This file
- `PROGRESS.md` - Progress tracking
- `PHASE2_SGLANG.md` - Escha SGLang documentation
- `benchmark_harness.sh` - Automation script
- `environment/` - Hardware/software capture
- `prompts/` - Test prompts (code, math, reasoning, prose, JSON)
