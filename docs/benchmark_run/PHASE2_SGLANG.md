# Phase 2: Escha SGLang Results

## Status: ✅ WORKING on RTX 5060 Ti 16GB Blackwell

### Configuration That Works
```bash
VENV=/home/mkinney/Repos/llama.cpp/sglang_test_env \
MODEL=/home/mkinney/Models/EschaLabs/Qwen3.8-27B-Escha-W2 \
ATTN_BACKEND=triton \
MEM=0.90 \
CTXLEN=16384 \
CUDA_GRAPH_BS="1 2 4 8" \
GRAPHS=1 \
THINK=1 \
PORT=30000 \
HOST=0.0.0.0 \
bash /tmp/escha-runtime/sglang/serve.sh
```

### Key Success Factors
1. **VENV must point to clean cp312 venv** - system Python 3.14 causes module errors
2. **ATTN_BACKEND=triton** - required on Blackwell (sm_120)
3. **MEM=0.90, CTXLEN=16384** - conservative settings for 16GB
4. **CUDA_GRAPH_BS="1 2 4 8"** - small batch sizes for CUDA graph capture
5. **PyTorch 2.9+cu128** - required version

### Baseline Results (Escha W2)

| Metric | Value |
|--------|-------|
| **Decode Speed** | 31 tok/s |
| **VRAM Used** | 14.7 GB / 16 GB |
| **Context Length** | 16K |
| **Max Concurrent** | 4 streams |

### Comparison to llama.cpp

| Engine | Model | tok/s | VRAM |
|--------|-------|-------|------|
| llama.cpp DFlash2 n=4 | IQ2_XXS | 60.5 | 14.4GB |
| Escha SGLang | W2 (2-bit) | 31 | 14.7GB |

Note: Escha W2 is a different quantization (escha 2-bit) vs IQ2_XXS. Quality should be better.

### Next Steps
1. Test Escha with DFlash2 drafter
2. Test TurboQuant KV
3. Test combined Escha + TurboQuant + DFlash2
