# Phase 6 Results: vLLM + W8 DFlash2

## Attempted: vLLM with DFlash2

### Goal
Test lued/Qwen3.8-27B-DFlash2-W8 drafter with vLLM

### Result: INCOMPLETE

**Issue:** vLLM requires a safetensors/half precision target model, but we only have GGUF models locally.

The W8A16 DFlash2 drafter is:
- Size: 2.02 GB (excellent for 16GB cards)
- Format: Safetensors W8A16
- Designed for vLLM's DFlash2 implementation

### What Would Be Needed
1. Download full BF16 or FP8 target model (Qwen3.8-27B base, ~54GB)
2. Or use a quantized safetensors target that fits alongside the drafter

### Decision
**Deferred** - requires downloading large target model not currently available.

## Alternative
llama.cpp DFlash2 is working excellently with local GGUF models.
