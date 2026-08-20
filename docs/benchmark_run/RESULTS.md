# Qwen3.8-27B Benchmark Results - RTX 5060 Ti 16GB

## Executive Summary

**Goal**: Find the most intelligent model that can run on RTX 5060 Ti 16GB with best performance.

| Engine | Model | tok/s | VRAM | Notes |
|--------|-------|-------|------|-------|
| llama.cpp DFlash2 | Qwen3.8-27B IQ2_XXS | **60.5** | 14.4GB | n_max=4 |
| Escha SGLang | Escha W2 (2-bit) | 31 | 14.7GB | 16K ctx |
| Escha SGLang (16 streams) | Escha W2 | **299** | 14.7GB | aggregate |

---

## Hardware Setup
- **GPU**: NVIDIA GeForce RTX 5060 Ti (16GB VRAM, Blackwell/sm_120)
- **Driver**: 610.57.04 / CUDA 13.3
- **CPU**: Intel i5-13600K (14 cores) / **RAM**: 31GB

---

## Phase 1: llama.cpp DFlash2 [COMPLETE]

### Configuration
- **Target Model**: Qwen3.8-27B-UD-IQ2_XXS (8.4GB GGUF)
- **Draft Model**: Qwen3.8-27B-DFlash-bootstrap-Q8_0 (1.8GB)
- **Context**: 8192 | **KV Cache**: Q8_0 | **Max Tokens**: 256

### Baseline Results

| Model | Size | VRAM | Decode tok/s |
|-------|------|------|--------------|
| **Qwen3.8-27B-UD-IQ2_XXS** | 8.4GB | 9.6GB | **37.5** |
| Qwen3.8-27B-UD-IQ3_XXS | 12GB | 12.3GB | 30.4 |
| Qwen3.8-27B-UD-Q3_K_XL | 13GB | 13.7GB | 28.7 |

### DFlash n-max Sweep

| n_max | Decode tok/s | Speedup | Acceptance | VRAM |
|-------|--------------|---------|------------|------|
| 0 (baseline) | 37.5 | - | - | 9.6GB |
| 2 | 52.0 | +39% | 62% | 13.2GB |
| 3 | 54.1 | +44% | 58% | 13.8GB |
| **4** | **60.5** | **+61%** | **56%** | 14.4GB |
| 5 | 39.4 | +5% | 27% | 15.0GB |
| 6 | 44.1 | +18% | 33% | 15.6GB |
| 7 | OOM | - | - | - |

**n_max=4 is OPTIMAL for RTX 5060 Ti 16GB**

---

## Phase 2: Escha SGLang [WORKING]

### Configuration That Works
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

### Throughput Scaling (16 streams mode)

| Concurrent | Aggregate tok/s |
|------------|-----------------|
| 1 | 31 |
| 2 | 54 |
| 4 | 110 |
| 8 | 187 |
| 16 | **299** |

### Context Sweep Results

| Context | tok/s | Notes |
|---------|-------|-------|
| 4K | 31.3 | |
| 8K | 31.3 | |
| 16K | 31.1 | baseline |
| 24K | 31.1 | |
| 32K | 31.2 | |
| 48K | 30.9 | MEM=0.80 |
| 64K | 30.4 | no graphs, MEM=0.78 |

**Decode is compute-bound**: constant ~31 tok/s regardless of context length. This is a GPU compute ceiling, not memory bandwidth.

### Notes
- VENV must point to cp312 venv (not system Python 3.14)
- ATTN_BACKEND=triton required on Blackwell
- 64K requires MEM=0.78 and GRAPHS=0 (CUDA graph capture fails)
- THINK=1 produces `<think>` blocks in output (Qwen3 native behavior)

---

## Phase 6: vLLM DFlash2 [NOT COMPATIBLE]

### Issue
- vLLM does not support `escha` quantization method
- Error: `Unknown quantization method: escha`
- vLLM only supports: awq, fp8, gptq, compressed-tensors, bitsandbytes, etc.

### lued DFlash2 W8A16 (club-3090)
- Requires **dual 24GB GPUs** (RTX 3090/4090/5090) — NOT compatible with RTX 5060 Ti 16GB
- Model size: 28GB (INT8-W8A16)
- Requires vLLM with club-3090 patch set (PR 52816)
- club-3090 is a Docker-based multi-engine serving system for 3090/4090/5090 cards

**vLLM + DFlash2 is not viable on RTX 5060 Ti 16GB**

---

## Cross-Engine Comparison

| Engine | Model | Quant | tok/s | VRAM | Context |
|--------|-------|-------|-------|------|---------|
| llama.cpp | Qwen3.8-27B | IQ2_XXS | 37.5 | 9.6GB | 8K |
| llama.cpp + DFlash2 | Qwen3.8-27B | IQ2_XXS | **60.5** | 14.4GB | 8K |
| Escha SGLang | Escha W2 | 2-bit escha | 31 | 14.7GB | 16K |
| Escha SGLang (16 streams) | Escha W2 | 2-bit escha | **299** | 14.7GB | 16K |

---

## Recommendations

### Best Single-User Speed: llama.cpp DFlash2
- 60.5 tok/s with n_max=4
- 14.4GB VRAM
- 8K context

### Best Multi-User Throughput: Escha SGLang
- 299 tok/s at 16 concurrent users
- 14.7GB VRAM
- 16K context

### Best Context Length: Escha SGLang
- 16K context vs 8K
- 2-bit escha quantization (higher quality per bit)

### Best Quality: Escha W2
- escha 2-bit has better quality than IQ2_XXS per benchmark

---

## Artifacts Created
- `RESULTS.md` - This file
- `PROGRESS.md` - Progress tracking
- `PHASE2_SGLANG.md` - Escha SGLang documentation
- `benchmark_harness.sh` - Automation script
- `environment/` - Hardware/software capture
- `prompts/` - Test prompts
