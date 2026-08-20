# vLLM Benchmark Results

## Test Configuration
- **Model:** Qwen3-4B-Instruct (Qwen/Qwen3-4B, 7.6GB safetensors)
- **Prompt:** "Explain the concept of recursion in programming in exactly 2 sentences."
- **Max Tokens:** 100 per request

---

## GPU Comparison

| Spec | RTX 5060 Ti | Tesla V100-SXM2-16GB |
|------|--------------|----------------------|
| Architecture | Blackwell (CUDA 13.x) | Volta (CUDA 13.x) |
| Memory | 16GB GDDR7 | 16GB HBM2 |
| Bandwidth | ~896 GB/s | ~900 GB/s |
| vLLM Status | Working | Binary incompatibility |

---

## RTX 5060 Ti (Host) - vLLM 0.22.1

| Concurrency | Tokens | Time(s) | Throughput (tok/s) |
|------------|--------|---------|---------------------|
| 1 | 100 | 2.21 | ~45 |
| 2 | 200 | 2.20 | ~91 |
| 4 | 400 | 2.25 | ~178 |
| 8 | 800 | 2.34 | ~342 |
| 12 | 1200 | 2.42 | ~496 |
| 16 | 1600 | 2.52 | ~636 |
| 24 | 2400 | 2.77 | ~867 |

**Peak Throughput: ~867 tok/s @ 24 concurrent**

---

## Tesla V100 (VM) - Pending

vLLM binary crashes on V100 due to CUDA architecture mismatch.
The installed vLLM was built for newer GPU architectures.

**Options to fix:**
1. Build vLLM from source on VM
2. Use llama.cpp with CPU backend (slow)
3. Use different vLLM binary

---

## llama.cpp Build Status

### Host (RTX 5060 Ti)
- Pre-built in `/home/mkinney/Repos/llama.cpp/build-cuda/`
- CUDA support via libggml-cuda.so

### VM (V100)
- llama.cpp cloned to `/home/mkinney/llama.cpp`
- CUDA 13.3 installed
- Build fails: `Unsupported gpu architecture 'compute_70'`
- CPU-only build exists: `/home/mkinney/llama.cpp/build-cpu/`

---

## Quick Test Commands

```bash
# Host vLLM (RTX 5060 Ti)
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"/tmp/hf-cache/models--Qwen--Qwen3-4B/snapshots/...","messages":[{"role":"user","content":"Hello"}],"max_tokens":50}'

# Run benchmark
./benchmark.sh
```
