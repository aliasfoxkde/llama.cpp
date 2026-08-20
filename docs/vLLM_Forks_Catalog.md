# vLLM Forks Catalog

**Date**: 2026-07-30
**Purpose**: Catalog and evaluate vLLM forks for DSpark, MTP, and GGUF support

---

## Official vLLM

| Property | Value |
|----------|-------|
| **Repository** | https://github.com/vllm-project/vllm |
| **Latest Version** | 0.26.0 |
| **GGUF Support** | Via separate plugin (vllm-gguf-plugin) |
| **MTP Support** | Limited, model-dependent |
| **DSpark Support** | ❌ Not in mainline |
| **RTX 5060 Ti Compatible** | ✅ (sm_120 support) |
| **Notes** | Official, well-maintained, best compatibility |

---

## vLLM GGUF Plugin (Fork)

| Property | Value |
|----------|-------|
| **Repository** | https://github.com/aliasfoxkde/vllm-gguf-plugin |
| **Version** | 0.0.4 |
| **GGUF Support** | ✅ Full native |
| **MTP Support** | ✅ Qwen3.5/3.6 MTP heads (nextn) |
| **DSpark Support** | ❌ Not implemented |
| **RTX 5060 Ti Compatible** | ✅ |
| **Notes** | Extended for Qwen3.6 REAP models, MTP via `--speculative-config` |
| **Key Features** | - GatedDeltaNet + full-attention hybrid support<br>- MTP speculative decoding from baked head<br>- IQ4_XS CUDA kernels |
| **Installation** | `pip install -e . --torch-backend=auto` |

### Usage with MTP:
```bash
vllm serve JZC973/Qwen3.6-35B-REAP-MTP-UD-GGUF-Collection:Qwen3.6-35B-A3B-UD-Q3_K_XL-REAP \
  --kv-cache-dtype fp8 --enable-prefix-caching \
  --gpu-memory-utilization 0.93 --max-model-len 131072 \
  --speculative-config '{"method":"mtp","num_speculative_tokens":1}'
```

---

## fraserprice/dspark-vllm

| Property | Value |
|----------|-------|
| **Repository** | https://github.com/fraserprice/dspark-vllm |
| **Stars** | 3 |
| **GGUF Support** | Unknown |
| **MTP Support** | Unknown |
| **DSpark Support** | ✅ Yes |
| **RTX 5060 Ti Compatible** | ⚠️ Targeted at RTX Pro 6000 (96GB) |
| **Notes** | Includes DeepSeek DSpark implementation |
| **Target Hardware** | RTX Pro 6000 Blackwell (96 GB, sm_120) at TP=2 or TP=4 |
| **Build** | Docker-based (`./build.sh`) |

---

## danielwoz/vllm-dspark-nvfp4

| Property | Value |
|----------|-------|
| **Repository** | https://github.com/danielwoz/vllm-dspark-nvfp4 |
| **Stars** | 1 |
| **GGUF Support** | Unknown |
| **MTP Support** | Unknown |
| **DSpark Support** | ✅ Yes |
| **NVFP4 Support** | ✅ True 4-bit KV cache |
| **RTX 5060 Ti Compatible** | ⚠️ Targeted at RTX PRO 6000/SM120 |
| **Notes** | True 4-bit (NVFP4/E2M1) KV cache for DeepSeek-V4 |

---

## brandonmmusic-max/deepspark

| Property | Value |
|----------|-------|
| **Repository** | https://github.com/brandonmmmusic-max/deepspark |
| **Stars** | 1 |
| **GGUF Support** | Unknown |
| **MTP Support** | Unknown |
| **DSpark Support** | ✅ Yes |
| **RTX 5060 Ti Compatible** | ⚠️ Targeted at SM120 (RTX PRO 6000 Blackwell) |
| **Notes** | DeepSeek-V4-Flash + DSpark on b12x vLLM fork |

---

## DeepSeek-ai/DeepSpec

| Property | Value |
|----------|-------|
| **Repository** | https://github.com/deepseek-ai/DeepSpec |
| **GGUF Support** | ❌ Training codebase |
| **MTP Support** | ✅ (training) |
| **DSpark Support** | ✅ (training + evaluation) |
| **RTX 5060 Ti Compatible** | ⚠️ Multi-GPU by default |
| **Notes** | Full-stack for training draft models. Implements DSpark, DFlash, EAGLE3. Default 8-GPU, can reduce via CUDA_VISIBLE_DEVICES |

---

## xInfer (Rust, NOT vLLM fork)

| Property | Value |
|----------|-------|
| **Repository** | https://github.com/guoqingbao/xinfer |
| **Language** | Pure Rust |
| **GGUF Support** | ✅ Full |
| **MTP Support** | ✅ Via `--mtp` flag |
| **DSpark Support** | ❌ Not implemented |
| **KV Compression** | ✅ TurboQuant (fp8, turbo4, turbo3) |
| **RTX 5060 Ti Compatible** | ✅ (sm_120 binary available) |
| **Installation** | `curl -sSL https://guoqingbao.github.io/xinfer/install.sh | bash` |
| **Binary** | ✅ Downloaded at `/tmp/xinfer` |
| **Notes** | No Python/PyTorch needed, but requires NCCL for multi-GPU |

---

## Analysis Summary

### For RTX 5060 Ti 16GB (single GPU)

| Fork | Recommendation | Notes |
|------|---------------|-------|
| **vLLM mainline + GGUF plugin** | ✅ **Recommended** | Works, MTP supported, most stable |
| **aliasfoxkde vllm-gguf-plugin** | ✅ **Best for Qwen3.6 REAP** | Native MTP, best for our models |
| **xInfer** | 🔶 Future option | No PyTorch, needs NCCL |
| **DSpark forks (fraserprice, danielwoz)** | ❌ Not recommended | Targeted at 96GB GPUs |

### Key Finding
**DSpark forks are specifically designed for RTX PRO 6000 (96GB) and require multi-GPU setups (TP=2 or TP=4). They are NOT suitable for RTX 5060 Ti 16GB.**

---

## Recommendations for RTX 5060 Ti 16GB

1. **For MTP testing**: Use `aliasfoxkde/vllm-gguf-plugin` with `--speculative-config '{"method":"mtp","num_speculative_tokens":1}'`

2. **For future DSpark**: Monitor when DSpark implementations become available for consumer GPUs (16GB)

3. **For xInfer**: Install NCCL separately if interested in trying this Rust-based solution

---

---

## EAGLE-3 Support

### vLLM EAGLE-3 Documentation
- **URL**: https://docs.vllm.ai/en/latest/features/speculative_decoding/eagle/

### EAGLE-3 Draft Models (HuggingFace)

| Model | Format | Size | Notes |
|-------|--------|------|-------|
| **BLR2/Qwen3.5-9B-Eagle3-ShareGPT** | Safetensors | 763MB | Downloaded, NOT GGUF |
| **Ex0bit/Qwen3.6-27B-PRISM-EAGLE3** | GGUF likely | - | Not tested |
| **SafeAILab/EAGLE** | Multiple | - | Official implementation |

### llama.cpp EAGLE-3 Support
- llama.cpp supports EAGLE-3 via `--spec-type draft-eagle3`
- Requires GGUF format draft model (not safetensors)
- Downloaded model is safetensors - **NOT compatible**

### Testing Status
- ❌ EAGLE-3 safetensors model cannot be used directly with llama.cpp (needs GGUF)
- ⚠️ vLLM GGUF plugin has transformers compatibility issue

---

## Environment Status

| Component | Status | Version |
|----------|--------|---------|
| vLLM | ✅ Installed | 0.26.0 |
| vllm-gguf-plugin | ✅ Installed | 0.0.4 |
| Flashinfer | ⚠️ Version mismatch | 0.6.13 (vLLM wants 0.6.14) |
| xInfer | ❌ Removed | Had NCCL dependency |
| Transformers | ⚠️ Version conflict | 5.14.1 (too new for plugin) |

---

## Benchmark Results Summary

### llama.cpp MTP (RTX 5060 Ti, 128K CTX, KV q4_1)

| Config | Peak TPS | vs Baseline |
|--------|----------|-------------|
| Baseline (no spec) | 118.5 | - |
| MTP n_max=3 | **165.1** | **+39%** |

### Key Findings
1. **MTP provides 30-50% improvement** at concurrency ≥2
2. **DSpark requires vLLM Avesed fork** - not available for 16GB GPUs
3. **vLLM GGUF plugin has compatibility issues** with current transformers
4. **xinfer requires NCCL** - not suitable for single-GPU

---

## Recommendations for RTX 5060 Ti 16GB

### Best Option: llama.cpp with MTP
```bash
./llama-server -m Qwen3.6-35B-A3B-UD-Q3_K_M-REAP.gguf \
  -c 131072 -ctk q4_1 -ctv q4_1 -fa on -ngl 99 \
  --spec-type draft-mtp --spec-draft-n-max 3 \
  -tb 512 -ub 256
```
Expected: ~165 TPS peak (+39% over baseline)

### Next Steps
1. Fix vLLM/transformers compatibility for GGUF plugin
2. Convert EAGLE-3 safetensors to GGUF for testing
3. Monitor DSpark forks for 16GB GPU support
4. Consider xinfer when NCCL available
