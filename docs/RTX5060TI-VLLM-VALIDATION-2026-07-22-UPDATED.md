# RTX 5060 Ti 16GB — vLLM Validation Status

**Date**: 2026-07-22
**Last Updated**: 2026-07-22
**Status**: Blocked by LM Studio GPU usage

---

## Summary of Findings

### ✅ Working Components
- NVIDIA Driver 595.80, CUDA 13.3
- PyTorch 2.11.0+cu130 CUDA compilation
- FlashInfer 0.6.11.post2
- Triton JIT compilation (Python.h issue resolved)
- vLLM 0.22.1 engine initialization

### ❌ Blocking Issues

**Issue 1**: GGUF architecture `qwen35moe` not supported
- vLLM/transformers GGUF loader expects `qwen3_moe`
- Our GGUF files use `qwen35moe` architecture name
- This is a naming mismatch, not a fundamental incompatibility

**Issue 2**: GPU memory occupied by LM Studio
- LM Studio using 13.6 GiB of 15.5 GiB available
- Only ~1.1 GiB free, insufficient for model loading
- **Need to close LM Studio to continue testing**

### Available Models

| Model | Format | Size | vLLM Status |
|-------|--------|------|-------------|
| Qwen3.6-35B-A3B-HF | HF safetensors | 67GB BF16 | ❌ OOM (doesn't fit 16GB) |
| cyankiwi/Qwen3.6-35B-A3B-AWQ-4bit | AWQ | ~22GB | ⏳ Awaiting GPU memory |
| Qwen2.5-3B | HF safetensors | ~6GB | ⏳ Awaiting GPU memory |
| Qwen3.6-35B-A3B GGUF (various) | GGUF | 11-13GB | ❌ Architecture mismatch |

---

## Next Steps

1. **Close LM Studio** to free GPU memory
2. Test AWQ quantized model (cyankiwi/Qwen3.6-35B-A3B-AWQ-4bit)
3. If AWQ works, run full benchmark suite
4. Compare against llama.cpp baseline

---

*Status updated: 2026-07-22*
