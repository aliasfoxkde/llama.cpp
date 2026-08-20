# Comprehensive Testing Plan: All Inference Backends

**Date**: 2026-07-30
**Goal**: Determine best total throughput method for Qwen3.6-35B MoE on RTX 5060 Ti 16GB

---

## Priority #1: Fix vLLM GGUF Plugin (CURRENT)

### Issue
- vLLM GGUF plugin has transformers compatibility issue
- `Qwen3_5MoeConfig` missing `vocab_size` attribute

### Fix Needed
- Downgrade transformers OR fix vLLM GGUF plugin
- Target: Use vLLM with MTP for Qwen3.6-35B-REAP

### Status
- vLLM loading with small model (Qwen3-0.6B) - in progress
- Need to test GGUF model loading after fixing compatibility

---

## Backend Comparison Matrix

| Backend | MTP | DSpark | EAGLE-3 | KV Quant | RTX 5060 Ti | Complexity |
|---------|-----|--------|----------|----------|--------------|------------|
| **llama.cpp** | ✅ | ❌ | ⚠️ | ✅ q4_1 | ✅ Best | Low |
| **vLLM + GGUF plugin** | ✅ | ❌ | ⚠️ | ✅ fp8 | ✅ Good | Medium |
| **vLLM Avesed** | ✅ | ✅ | ✅ | ✅ | ❌ 96GB only | High |
| **SGLang** | ✅ | ? | ✅ | ✅ | ✅ Good | Medium |
| **TensorRT-LLM** | ✅ | ✅ | ✅ | ✅ | ✅ Best | High |
| **xinfer** | ✅ | ❌ | ❌ | ✅ turbo4 | ✅ Good | Low |

---

## SGLang Analysis

### What is SGLang?
- High-performance LLM inference server with RadixAttention
- Supports speculative decoding, prefix caching, continuous batching
- Native vLLM backend integration

### Repository
- https://github.com/sgl-project/sglang

### Features
- ✅ MTP support
- ✅ EAGLE-3 support
- ✅ Continuous batching with RadixAttention
- ✅ GGUF support via vLLM integration
- ✅ DAP (Dynamic Speculative Decoding)

### Installation
```bash
pip install sglang
# or
pip install sglang[all]  # with all features
```

### RTX 5060 Ti Compatibility
- ✅ Should work with CUDA
- Single GPU support available
- Need to test GGUF models

### Speculative Decoding
SGLang supports:
- EAGLE-1/2/3
- MTP (Multi-Token Prediction)
- NVIDIA DAP (Draft Anchor Prompting)

---

## TensorRT-LLM Analysis

### What is TensorRT-LLM?
- NVIDIA's optimized inference engine for LLMs
- TensorRT-based with custom kernels
- Best performance on NVIDIA GPUs

### Repository
- https://github.com/NVIDIA/TensorRT-LLM

### Features
- ✅ MTP support
- ✅ DSpark/EAGLE-3 via DeepSeek integration
- ✅ FP8/BF16 quantization
- ✅ Best throughput on NVIDIA GPUs
- ✅ Qwen3.5/3.6 support

### RTX 5060 Ti Compatibility
- ✅ Blackwell support (sm_120)
- ✅ CUDA 12.x compatible
- **Note**: Requires compilation for specific GPU

### Installation Complexity
- High: Requires building TensorRT-LLM from source
- Need: TensorRT 10.x, CUDA 12.x, cuBLAS, cuDNN

### Benchmarking
```bash
# Build Qwen3-35B
python build.py --model_dir=Qwen/Qwen3-35B-A3B --quantization=fp8 --tensor-parallel=1

# Run benchmark
python run.py --model=qwen3-35b-a3b-fp8-tp1 --num_tokens=1000 --batch_size=1
```

---

## Testing Priority Queue

### P0 (Critical - Must Test)
1. **llama.cpp MTP** - DONE ✅
   - Peak: 165.1 TPS @ conc=4 (+39%)
   - Settings: CTX=128K, KV=q4_1, n_max=3

2. **vLLM + GGUF plugin** - IN PROGRESS 🔄
   - Need to fix transformers compatibility
   - Test MTP with Qwen3.6-35B-REAP

### P1 (High Priority)
3. **SGLang** - PENDING
   - Install and test
   - Compare throughput vs llama.cpp

4. **vLLM with MTP (working)** - PENDING
   - Run full benchmark once fixed

### P2 (Nice to Have)
5. **TensorRT-LLM** - PLANNING
   - High effort to build
   - Potentially best throughput

### P3 (Future)
6. **xinfer** - Needs NCCL
7. **vLLM Avesed DSpark** - Needs 96GB GPU

---

## VRAM Budget Analysis (RTX 5060 Ti 16GB)

### Qwen3.6-35B-A3B MoE Models

| Model | Quant | Weights | KV Cache (128K) | Total | Headroom |
|-------|-------|---------|------------------|-------|----------|
| REAP-MTP | Q3_K_M | ~13 GB | ~6 GB (fp8) | ~19 GB | ❌ OOM |
| REAP-MTP | Q3_K_M | ~13 GB | ~3 GB (q4_1) | ~16 GB | ⚠️ Tight |
| REAP-MTP | IQ3_XXS | ~10.5 GB | ~3 GB (q4_1) | ~13.5 GB | ✅ Good |
| REAP-48 | Q3_K_M | ~8.8 GB | ~3 GB (q4_1) | ~11.8 GB | ✅ Good |

### Recommendation
- Use Q3_K_M or smaller for 128K context with MTP
- Consider IQ3_XXS if memory issues arise

---

## Concurrency Benchmark Plan

### Test Matrix

| Backend | Concurrency | TPS | Latency | Notes |
|---------|-------------|-----|---------|-------|
| llama.cpp baseline | 1,2,4,8,12,16,20,24 | | | |
| llama.cpp MTP | 1,2,4,8,12,16,20,24 | | | |
| vLLM baseline | 1,2,4,8,12,16,20,24 | | | |
| vLLM MTP | 1,2,4,8,12,16,20,24 | | | |
| SGLang baseline | 1,2,4,8,12,16,20,24 | | | |
| SGLang MTP | 1,2,4,8,12,16,20,24 | | | |

### Test Parameters
- **Model**: Qwen3.6-35B-A3B-REAP (Q3_K_M or IQ3_XXS)
- **Context**: 128K
- **KV Cache**: q4_1 (llama.cpp) / fp8 (vLLM)
- **Prompt**: "Explain X in 2 sentences" (short)
- **Max Tokens**: 100
- **Early Stop**: TPS decrease 2x in a row

---

## Environment Setup Checklist

### llama.cpp ✅
- [x] CUDA build with Flash Attention
- [x] Models downloaded
- [x] Benchmark script ready

### vLLM + GGUF Plugin 🔄
- [x] vLLM installed
- [ ] Fix transformers compatibility
- [ ] Test GGUF loading
- [ ] Run benchmark

### SGLang 📋
- [ ] Install: `pip install sglang`
- [ ] Test with Qwen3.6-35B
- [ ] Run benchmark

### TensorRT-LLM 📋
- [ ] Install TensorRT 10.x
- [ ] Build from source
- [ ] Compile Qwen3.6-35B
- [ ] Run benchmark

---

## Quick Start Commands

### llama.cpp
```bash
./build/bin/llama-server \
  -m models/Qwen3.6-35B-A3B-UD-Q3_K_M-REAP.gguf \
  -c 131072 -ctk q4_1 -ctv q4_1 -fa on -ngl 99 \
  --spec-type draft-mtp --spec-draft-n-max 3 \
  -tb 512 -ub 256 --port 8080
```

### vLLM (once fixed)
```bash
FLASHINFER_DISABLE_VERSION_CHECK=1 vllm serve \
  /path/to/Qwen3.6-35B-REAP.gguf \
  --tokenizer Qwen/Qwen3-8B \
  --max-model-len 131072 \
  --gpu-memory-utilization 0.85 \
  --kv-cache-dtype fp8 \
  --speculative-config '{"method":"mtp","num_speculative_tokens":1}'
```

### SGLang (after install)
```bash
python -m sglang.launch_server \
  --model-path Qwen/Qwen3.5-32B \
  --port 30000 \
  --speculative-decoding eagle
```

### TensorRT-LLM (after build)
```bash
trtllm-run --model=/path/to/model --tokenizer=Qwen/Qwen3-8B --max_tokens=100
```

---

## Expected Results

| Backend | Expected TPS | Notes |
|---------|-------------|-------|
| llama.cpp baseline | ~110-120 | |
| llama.cpp MTP | ~150-170 | +30-40% |
| vLLM | ~120-140 | Better batching |
| vLLM + MTP | ~160-180 | Combined benefits |
| SGLang | ~130-150 | RadixAttention |
| TensorRT-LLM | ~180-220 | Best possible |

**Note**: These are estimates based on RTX 5060 Ti 16GB. Actual results may vary.
