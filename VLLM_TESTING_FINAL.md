# vLLM Testing - Final Results

## Test Date: 2026-07-26

## Hardware Configuration

### Host Machine
- **GPU**: NVIDIA GeForce RTX 5060 Ti 16GB (Blackwell architecture)
- **CUDA**: 13.3
- **OS**: Fedora (Linux)

### Virtual Machine (QEMU/KVM with VFIO)
- **GPU**: Tesla V100-SXM2-16GB (Volta architecture)
- **CUDA**: 13.0 (driver), 13.1/13.3 (toolkit)
- **OS**: Debian 13 (Trixie)
- **CPU**: 2 cores
- **RAM**: 8GB

## Software Versions

| Component | Host | VM |
|-----------|------|-----|
| Python | 3.14 | 3.13.5 |
| vLLM | 0.22.1 | 0.26.0 (broken) |
| PyTorch | 2.11.0 | 2.11.0 (broken) |
| CUDA | 13.3 | 13.1/13.3 |

## Benchmark Results: RTX 5060 Ti (Host)

Model: Qwen3-4B-Instruct (Qwen/Qwen3-4B, 7.6GB safetensors)
Prompt: "Explain the concept of recursion in programming in exactly 2 sentences."
Max Tokens: 100 per request

| Concurrency | Tokens | Time(s) | Throughput (tok/s) |
|------------|--------|---------|---------------------|
| 1 | 100 | 2.16 | ~46 |
| 2 | 200 | 2.23 | ~90 |
| 4 | 400 | 2.27 | ~176 |
| 8 | 800 | 2.37 | ~338 |
| 12 | 1200 | 2.44 | ~492 |
| 16 | 1600 | 2.55 | ~628 |
| 24 | 2400 | 2.79 | ~859 |

**Peak Throughput: ~859 tok/s @ 24 concurrent requests**

## VM vLLM Status: FAILED

### Error Analysis
The VM has fundamental CUDA/Python compatibility issues:

1. **Python 3.13 incompatibility**: PyTorch and numpy have import errors
   - Error: `ImportError: cannot load module more than once per process`
   - Root cause: Python 3.13 is too new for most ML packages

2. **CUDA architecture mismatch**: V100 (compute_70) not supported
   - CUDA 13.x doesn't support Volta's compute_70
   - Would need CUDA 11.x for V100 support

3. **Package conflicts**: Mixed CUDA versions (11.x and 12.x)

### Resolution Steps (Not Completed)

1. Install Python 3.11 or 3.12 (not available in Debian 13)
2. Build PyTorch from source with CUDA 11.x support
3. Rebuild vLLM for the correct CUDA architecture

## llama.cpp Status

### Host (RTX 5060 Ti)
- Pre-built CUDA binaries available
- Located: `/home/mkinney/Repos/llama.cpp/build-cuda/`
- Working with GGUF models

### VM (V100)
- llama.cpp cloned to `/home/mkinney/llama.cpp`
- CPU-only build successful
- CUDA build fails due to compute_70 not supported
- Model downloaded: `/home/mkinney/Models/Qwen3-4B-Q4_K_M.gguf` (2.5GB)

## Quick Test Commands

### Host vLLM Test
```bash
# Check if running
curl -s http://localhost:8000/v1/models | grep Qwen

# Quick inference
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"/tmp/hf-cache/models--Qwen--Qwen3-4B/snapshots/...","messages":[{"role":"user","content":"Hello!"}],"max_tokens":50}'
```

### VM llama.cpp Test (CPU only - slow)
```bash
ssh -p 2222 mkinney@127.0.0.1
cd ~/Models
/home/mkinney/llama.cpp/build-cpu/bin/llama-cli -m Qwen3-4B-Q4_K_M.gguf -p "Hello" -n 50
```

## Files Created

- `benchmark.sh` - Full concurrency benchmark script
- `vllm_benchmark_results.md` - Detailed results
- `vllm_testing_summary.md` - Initial summary
- `VLLM_TESTING_FINAL.md` - This document

## Next Steps for VM Fix

1. **Option A**: Rebuild VM with Ubuntu 22.04 or CentOS 7 (better CUDA support)
2. **Option B**: Install Python 3.11 via pyenv/source
3. **Option C**: Use container (Docker) with CUDA 11.x inside VM
4. **Option D**: Use pre-built vLLM container from NVIDIA NGC

## Conclusion

The RTX 5060 Ti (Blackwell) achieved excellent vLLM performance with proper CUDA 13.x support. The Tesla V100 (Volta) in the VM cannot run modern vLLM due to:
1. Python 3.13 package incompatibilities
2. CUDA architecture gap (V100 needs CUDA 11.x)

The host system is fully operational for LLM inference at ~859 tok/s peak.
