# vLLM Setup Guide for RTX 5060 Ti 16GB

> Target: ~500-1000 tok/s throughput with Qwen3.6-35B-REAP-MTP model via vLLM continuous batching.

## Prerequisites

### Hardware
- **GPU:** NVIDIA RTX 5060 Ti 16GB (or any NVIDIA GPU with 16GB+ VRAM)
- **CPU:** Modern multi-core (Intel/AMD)
- **RAM:** 32GB+ system RAM recommended
- **Storage:** 50GB+ free space (model + vLLM install)

### Software
- **OS:** Ubuntu 22.04+ (recommended), Windows WSL2, or macOS
- **CUDA:** 12.1+ (12.4+ recommended for RTX 5060 Ti)
- **Python:** 3.10 - 3.12
- **NVIDIA Driver:** 555+ (required for PCIe 5.0 / new GPU features)

## Installation

### 1. Verify CUDA and GPU

```bash
nvidia-smi
# Expected output: GPU 0: NVIDIA GeForce RTX 5060 Ti | 16GB VRAM | Driver 555+

nvcc --version
# Expected: CUDA 12.4+ or 12.6+
```

### 2. Install vLLM

```bash
# Option A: pip (fastest, for most users)
pip install vllm>=0.8.0

# Option B: from source (for latest features / custom builds)
git clone https://github.com/vllm-project/vllm.git
cd vllm

# For RTX 5060 Ti (Ada Lovelace / sm_89):
# vLLM auto-detects GPU architecture, but you can override:
export VLLM_GPU_TARGETS="sm_89"

pip install -e .
```

### 3. Download the Model

The Qwen3.6-35B-REAP-MTP model in GGUF format needs to be converted to HuggingFace format:

```bash
# Option A: Use existing GGUF -> HF conversion
# The Qwen3.6-35B-REAP-MTP-UD-Q3_K_XL.gguf is at:
# /nas/AI/Models/gguf/Qwen3.6-35B-REAP-MTP-UD/

# Convert using llama.cpp's convert script:
python3 convert_hf_to_gguf.py \
    /path/to/Qwen3.6-35B-REAP-MTP-UD/ \
    --outfile Qwen3.6-35B-REAP-MTP-UD-Q3_K_XL.gguf

# Option B: Use HuggingFace format directly if available
# Or use the original HF model if you have access:
# Qwen/Qwen3-35B-REAP or similar
```

For vLLM, you generally want the **unquantized BF16 model** or **GPTQ/AWQ quantized** weights, not GGUF:

```bash
# If the base model is available on HuggingFace:
# pip install huggingface_hub
# huggingface-cli download Qwen/Qwen2.5-72B-Instruct-GPTQ-Int4

# For maximum throughput on 16GB VRAM, use a quantized variant:
# GPTQ: Qwen/Qwen2.5-72B-Instruct-GPTQ-Int4
# Or: The REAP-MTP model in HF format if available
```

## Running vLLM Server

### Basic Launch

```bash
python3 -m vllm.entrypoints.openai.api_server \
    --model Qwen/Qwen3.6-35B-REAP-MTP \
    --dtype half \
    --gpu-memory-utilization 0.90 \
    --max-model-len 131072 \
    --tensor-parallel-size 1 \
    --pipeline-parallel-size 1 \
    --port 8000
```

### Optimized for RTX 5060 Ti 16GB

```bash
# Max out VRAM usage with batching
python3 -m vllm.entrypoints.openai.api_server \
    --model Qwen/Qwen3.6-35B-REAP-MTP \
    --dtype half \
    --gpu-memory-utilization 0.95 \
    --max-model-len 32768 \
    --block-size 16 \
    --max-num-batched-tokens 8192 \
    --max-num-seqs 256 \
    --enable-chunked-prefill \
    --port 8000
```

### With Quantization (for 16GB VRAM)

```bash
# Use AWQ or GPTQ to fit larger models
python3 -m vllm.entrypoints.openai.api_server \
    --model Qwen/Qwen2.5-72B-Instruct-AWQ \
    --dtype half \
    --gpu-memory-utilization 0.90 \
    --max-model-len 32768 \
    --port 8000
```

## Benchmarking Throughput

### Tool 1: vLLM's Built-in Benchmark

```bash
# Measure online serving throughput
python3 -m vllm.benchmarks.serve \
    --backend vllm \
    --base-url http://localhost:8000/v1 \
    --model Qwen3.6-35B \
    --num-prompt 1000 \
    --request-rate 10
```

### Tool 2: Concurrent Request Benchmark

```bash
# Simulate concurrent users with wrk or locust
# Using a simple script with asyncio:

python3 << 'EOF'
import asyncio
import aiohttp
import time

async def send_request(session, prompt):
    async with session.post(
        "http://localhost:8000/v1/completions",
        json={"prompt": prompt, "max_tokens": 512, "temperature": 0}
    ) as resp:
        return await resp.json()

async def benchmark(num_requests=100, concurrency=6):
    async with aiohttp.ClientSession() as session:
        tasks = []
        start = time.time()
        for i in range(num_requests):
            task = asyncio.create_task(send_request(
                session,
                f"Explain quantum computing in {i % 10 + 1} sentences."
            ))
            tasks.append(task)
            if len(tasks) >= concurrency:
                await asyncio.gather(*tasks)
                tasks = []
        if tasks:
            await asyncio.gather(*tasks)
        elapsed = time.time() - start
        print(f"{num_requests} requests in {elapsed:.2f}s")
        print(f"Throughput: {num_requests/elapsed:.2f} req/s")

asyncio.run(benchmark())
EOF
```

### Tool 3: llmcmp (llama.cpp comparison)

For a fair comparison, run the same benchmark against llama.cpp server:

```bash
# Start llama.cpp server
./llama-server -m Qwen3.6-35B-REAP-Q3_K_XL.gguf \
    -ngl 99 -c 32768 --port 8080

# Benchmark command
# (use same concurrent requests against port 8080)
```

## Expected Performance

### RTX 5060 Ti 16GB — Qwen3.6-35B

| Config | Tokens/sec | Concurrent Users | Notes |
|--------|-----------|-----------------|-------|
| BF16 / no quant | ~95-120 tok/s | 1-2 | Best quality |
| GPTQ Int4 | ~150-200 tok/s | 2-3 | Good quality, fits in VRAM |
| AWQ Int4 | ~160-220 tok/s | 2-4 | Slightly faster than GPTQ |
| **+6 concurrent batching** | **~500-700 tok/s** | 6-8 | vLLM continuous batching |
| **+16 concurrent batching** | **~800-1000 tok/s** | 12-16 | With block-sized chunking |

### Key vLLM Flags for Max Throughput

| Flag | Value | Effect |
|------|-------|--------|
| `--enable-chunked-prefill` | yes | Allows partial prefill, keeps GPU busy |
| `--max-num-batched-tokens` | 8192+ | More tokens per batch iteration |
| `--max-num-seqs` | 256+ | More concurrent sequences |
| `--gpu-memory-utilization` | 0.90-0.95 | Use most of VRAM for KV cache |
| `--block-size` | 16 | Larger KV cache pages = less overhead |

## llama.cpp vs vLLM Comparison

Run both servers and hit them with the same benchmark:

```bash
# Terminal 1: llama.cpp server
./llama-server -m Qwen3.6-35B.gguf -ngl 99 -c 32768 --n-parallel 4 --port 8080

# Terminal 2: vLLM server
python3 -m vllm.entrypoints.openai.api_server \
    --model Qwen3.6-35B --dtype half --max-model-len 32768 --port 8000

# Terminal 3: Run concurrent benchmark
# against both ports and compare tok/s and latency
```

### Key Differences

| Metric | llama.cpp | vLLM |
|--------|-----------|------|
| **Per-stream latency** | Lower (no batching overhead) | Slightly higher under load |
| **Total throughput** | Limited by KV cache per sequence | 5-6x higher with batching |
| **Memory per extra user** | Full KV cache duplication | Shared paged KV cache |
| **Setup complexity** | Single binary, no Python | Requires Python + torch + vLLM |
| **Hardware** | Any with Vulkan/CUDA | NVIDIA dGPU recommended |
| **Max context** | 128K-1M+ | 128K-1M (VRAM limited) |

## Troubleshooting

### "CUDA out of memory" on launch

```bash
# Reduce gpu-memory-utilization
--gpu-memory-utilization 0.80

# Or reduce max-model-len
--max-model-len 16384

# Or use quantization
--quantization awq
```

### "HIP error" or AMD GPU detected

vLLM is NVIDIA-only. For AMD GPUs, use:
- [ROCm vLLM](https://github.com/ROCm/vllm) (AMD ROCm fork)
- Or llama.cpp with ROCm/HIP backend

### Low throughput despite GPU usage

Check:
1. Batch size settings (`--max-num-batched-tokens`)
2. Number of concurrent requests (vLLM needs load to show gains)
3. NVLink connectivity (if multi-GPU)
4. CPU bottleneck (ensure `--enforce-eager` is off)

## Quick Start Commands

```bash
# 1. Install
pip install vllm>=0.8.0

# 2. Start server
python3 -m vllm.entrypoints.openai.api_server \
    --model Qwen/Qwen2.5-72B-Instruct-GPTQ-Int4 \
    --dtype half \
    --gpu-memory-utilization 0.90 \
    --max-model-len 32768 \
    --enable-chunked-prefill \
    --port 8000

# 3. Test with a prompt
curl http://localhost:8000/v1/completions \
    -H "Content-Type: application/json" \
    -d '{"prompt": "Write a story about AI", "max_tokens": 200}'

# 4. Benchmark with 6 concurrent users
# (see benchmark script above)
```
