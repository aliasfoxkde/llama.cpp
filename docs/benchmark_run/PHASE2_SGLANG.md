# Phase 2: Escha SGLang Results

## Status: BLOCKED - Blackwell Architecture Compatibility

### Error
```
AssertionError: capture_bs=[0]
```
CUDA graph capture fails on Blackwell (sm_120) GPU.

### Details
- Model: EschaLabs/Qwen3.8-27B-Escha-W2 (10.15GB, 2-bit escha quantization)
- Runtime: escha-runtime-qwen3dense (custom SGLang fork)
- Required flags discovered: `--attention-backend triton`
- Model loads successfully but fails during CUDA graph capture initialization
- This is a Blackwell-specific kernel compatibility issue

### Workaround Attempts
1. Tried various --mem-fraction-static values (0.95, 0.90, 0.85)
2. Tried --disable-cuda-graph flag
3. Tried --attention-backend triton

### Conclusion
**Escha SGLang is not compatible with RTX 5060 Ti (Blackwell sm_120)** at this time.
The escha runtime requires CUDA graph support that is broken on Blackwell architecture.

### Models Available
- Escha W2: 10.15GB safetensors (2-bit escha quantization)
- lued W8A16 DFlash2: 2.02GB safetensors (for vLLM)
