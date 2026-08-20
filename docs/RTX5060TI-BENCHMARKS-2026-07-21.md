# RTX 5060 Ti 16GB — Benchmark Results

**Date**: 2026-07-21
**Hardware**: NVIDIA RTX 5060 Ti 16GB (Blackwell GB206), Driver 595.80, CUDA 13.3
**Models**: Qwen3.6-35B-A3B-REAP-MTP (Q3_K_M RangerX and Q3_K_XL variants)
**Backend**: llama.cpp CUDA build (gcc-15 compatible)
**CUDA Toolkit**: /usr/local/cuda-13.3 with gcc-15 host compiler

---

## Executive Summary

| Model/Config | Per-Stream t/s | Notes |
|--------------|----------------|-------|
| **Q3_K_M RangerX + MTP n-max=3** | **147-152 t/s** | Best performance |
| Q3_K_XL + MTP n-max=3 | 130-150 t/s | Similar to RangerX |
| Q3_K_M RangerX baseline | 97-102 t/s | No speculative |
| Q3_K_XL baseline | 97-102 t/s | No speculative |

**Key Findings**:
- **MTP n-max=3 provides ~50% per-stream speedup** on CUDA
- Both RangerX and Q3_K_XL variants perform similarly
- Vulkan backend: ~95-124 t/s
- CUDA backend: ~100-152 t/s (~20% faster than Vulkan)
- n-gram methods showed no benefit (not tested with CUDA due to time)

---

## llama.cpp CUDA Benchmark Results

### Q3_K_M RangerX + MTP n-max=3 (Best Config)

| Run | Tokens/sec | Wall Time | Tokens |
|------|------------|-----------|--------|
| 1 | 139.98 t/s | 1.43s | 200 |
| 2 | 147.68 t/s | 1.35s | 200 |
| 3 | 150.87 t/s | 1.33s | 200 |
| 4 | 151.92 t/s | 1.32s | 200 |
| 5 | 149.71 t/s | 1.34s | 200 |

**Average: ~148 t/s** (4K context, CUDA, 200 tokens)

### Q3_K_M RangerX Baseline (No MTP)

| Run | Tokens/sec | Wall Time | Tokens |
|------|------------|-----------|--------|
| 1 | 97.73 t/s | 2.05s | 200 |
| 2 | 100.19 t/s | 2.00s | 200 |
| 3 | 102.31 t/s | 1.95s | 200 |
| 4 | 102.55 t/s | 1.95s | 200 |
| 5 | 102.44 t/s | 1.95s | 200 |

**Average: ~101 t/s** (4K context, CUDA, 200 tokens)

### Q3_K_XL + MTP n-max=3

| Run | Tokens/sec | Wall Time | Tokens |
|------|------------|-----------|--------|
| 1 | 130.22 t/s | 0.77s | 100 |
| 2 | 142.22 t/s | 0.70s | 100 |
| 3 | 150.61 t/s | 0.66s | 100 |
| 4 | 146.87 t/s | 0.68s | 100 |
| 5 | 149.61 t/s | 0.67s | 100 |

**Average: ~144 t/s** (4K context, CUDA, 100 tokens)

### Vulkan Backend (Reference)

| Config | Per-Stream t/s |
|--------|----------------|
| MTP n-max=3, 4K ctx | 118-124 t/s |
| MTP n-max=5, 4K ctx | 99-102 t/s |
| n-gram-mod, 4K ctx | 95-100 t/s |
| Baseline, 4K ctx | 95-98 t/s |

**CUDA is ~20% faster than Vulkan** for this model.

---

## Deep Research: DSpark Analysis (from web research)

### Key Finding: DSpark is NOT in llama.cpp

**DSpark is only available in:**
- vLLM's Avesed fork
- DeepSeek's DeepSpec codebase (MIT license)

**llama.cpp supports:**
- MTP (Multi-Token Prediction) - native to the model
- EAGLE-3 - single-layer autoregressive draft
- DFlash - multi-layer block diffusion
- n-gram methods (cache/simple/map-k/map-k4v/map-mod)

### DSpark Performance Claims

| Comparison | Accepted Length Improvement |
|------------|------------------------|
| DSpark vs EAGLE-3 | +27-31% (DeepSeek benchmarks) |
| DSpark vs DFlash | +16-18% (DeepSeek benchmarks) |

**IMPORTANT**: These figures are from DeepSeek's own implementation. Many marketing claims (60-85% speedup over MTP) were **heavily refuted** by adversarial verification. The community shows disagreement on actual DSpark vs MTP comparisons.

---

## vLLM Testing Status

**BLOCKED**: vLLM could not be tested due to:
1. FlashInfer JIT compilation requires CUDA toolkit nvcc with gcc compatibility
2. gcc 16 + CUDA 13.3 incompatibility (even with gcc-15)
3. Triton compilation failures with PyTorch headers

**vLLM requires**:
- CUDA toolkit properly configured with gcc-14 or lower
- Or use a containerized vLLM deployment

---

## Recommendations

### For Single-User Interactive Use
```bash
./build/bin/llama-server \
  -m Qwen3.6-35B-A3B-REAP-RangerX.gguf \
  -ngl 99 -c 4096 \
  --spec-type draft-mtp --spec-draft-n-max 3
```
Expected: **~148 t/s** per stream (CUDA)

### For Multi-User Server
```bash
./build/bin/llama-server \
  -m Qwen3.6-35B-A3B-REAP-RangerX.gguf \
  -ngl 99 -c 4096 -tb 512 -ub 256 \
  --n-parallel 8
```

### For V100 Testing (when riser card arrives)
1. Build llama.cpp with CUDA on the V100 system
2. Test EAGLE-3 and DFlash draft models
3. Run vLLM with proper CUDA/gcc environment
4. Compare V100 16GB SXM2 vs RTX 5060 Ti 16GB

---

## Next Steps

1. **V100 SXM2 16GB**: Install PCIe riser and test
2. **EAGLE-3/DFlash drafts**: Download and convert for comparison
3. **vLLM**: Set up containerized deployment
4. **Concurrent benchmarks**: Full throughput testing with multiple users

---

## Build Instructions

```bash
# Build llama.cpp with CUDA (requires gcc-15)
export CUDA_HOME=/usr/local/cuda-13.3
export PATH=$CUDA_HOME/bin:$PATH
export CC=/usr/bin/gcc-15
export CXX=/usr/bin/g++-15

cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_HOST_COMPILER=/usr/bin/gcc-15

cmake --build build --config Release -j$(nproc)
```

---

## Environment Details

```
GPU: NVIDIA GeForce RTX 5060 Ti 16GB (Blackwell GB206)
Driver: 595.80
CUDA: 13.3 (gcc-15 compatible)
Models:
  - Qwen3.6-35B-A3B-UD-Q3_K_M-REAP-RangerX.gguf (12.7GB)
  - Qwen3.6-35B-A3B-UD-Q3_K_XL-REAP.gguf (13.5GB)
```

---

*Generated: 2026-07-21*
