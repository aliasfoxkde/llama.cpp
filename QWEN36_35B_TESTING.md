# Qwen3.6-35B GGUF Testing - 2026-07-26

## Model
- **File**: `/home/mkinney/Models/JZC973/Qwen3.6-35B-REAP-MTP-UD-GGUF-Collection/Qwen3.6-35B-A3B-UD-Q3_K_XL-REAP.gguf`
- **Size**: 13.5GB (Q3_K_XL quantization)
- **Architecture**: Qwen3.5 MoE (qwen35moe)
- **CTX Size**: 4096

## llama.cpp Benchmark Results (RTX 5060 Ti)

| Concurrency | Throughput (tok/s) |
|------------|---------------------|
| 2 | ~152 |
| 4 | **~208** |
| 8 | ~197 |
| 12 | ~196 |

**Peak: ~208 tok/s @ 4 concurrent**

### KV Cache Q4_0 Results
Same performance - KV quantization doesn't significantly improve MoE throughput.

## vLLM GGUF Status
- **vLLM 0.22.1 + GGUF plugin**: Cannot load qwen35moe GGUF
  - Error: `ValueError: GGUF model with architecture qwen35moe is not supported yet.`
  - transformers library checks architecture before plugin can patch
- **localweights vllm-gguf-plugin**: Same issue - plugin doesn't intercept early enough
- **llama.cpp**: Working natively

## llama-server Command
```bash
cd /home/mkinney && ./Repos/llama.cpp/build-cuda-new/bin/llama-server \
  -m "/home/mkinney/Models/JZC973/Qwen3.6-35B-REAP-MTP-UD-GGUF-Collection/Qwen3.6-35B-A3B-UD-Q3_K_XL-REAP.gguf" \
  -c 4096 \
  -ngl 99 \
  -ctk q4_0 \
  -ctv q4_0 \
  --host 0.0.0.0 --port 8080
```

## Comparison

| Model | Tool | GPU | Peak Performance |
|-------|------|-----|------------------|
| Qwen3-4B | vLLM | RTX 5060 Ti | ~1006 tok/s |
| Qwen3.6-35B Q3_K_XL | llama.cpp | RTX 5060 Ti | ~208 tok/s |

Note: 35B MoE is much slower due to Mixture of Experts architecture overhead.
