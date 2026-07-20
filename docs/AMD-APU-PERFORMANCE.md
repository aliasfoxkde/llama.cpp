# AMD APU Performance Guide

> A practical guide to understanding and maximizing llama.cpp throughput on AMD APUs.

## Hardware Overview

| Machine | APU | Architecture | Vulkan | Typical Throughput |
|---------|-----|-------------|--------|-------------------|
| 5700U MiniPC | AMD Ryzen 7 5700U (Lucienne) | GCN 5 / Vega | RADV RENOIR (works) | ~11 tok/s @ 128K context |
| 5700G / 5600G | AMD Ryzen (Cezanne/Renoir) | GCN 5 / Vega | RADV (varies) | ~8-15 tok/s |
| Strix Halo | AMD Ryzen AI Max (gfx1151) | RDNA 3.5 | Vulkan recommended | ~50-100+ tok/s |
| 5060 Ti 16GB | NVIDIA GeForce RTX 5060 Ti | Ada Lovelace | N/A (CUDA) | ~95-160 tok/s |

## Why the 5700U is Slow

The 5700U APU runs at ~11 tok/s due to **architectural constraints**, not missing software support:

1. **Integrated GPU (iGPU)** — Lucienne uses GCN 5 architecture (RADEON RX 590 era). Compute shaders are present but the GPU has no dedicated VRAM.
2. **DDR4 Bandwidth Bottleneck** — The iGPU shares system RAM via DDR4-3200. Peak bandwidth is ~51 GB/s (dual-channel). A discrete GPU like the RTX 5060 Ti has 256-512 GB/s via GDDR7/X.
3. **No Hardware Tensor Cores** — The 5700U iGPU lacks matrix/FFT hardware acceleration units.
4. **Software Fallback** — Most compute kernels fall back to CPU or LLVMpipe.

Vulkan **is available** and recognized (`RADV RENOIR`), but the GPU's compute capability is very limited.

## Current Performance (llama.cpp on 5700U)

| Model | Quant | Context | Throughput | Notes |
|-------|-------|---------|------------|-------|
| Qwen3.6-35B-REAP | Q3_K_XL | 128K | ~11 tok/s | KV cache optimizations enabled |
| Qwen3.6-35B-REAP | Q4_K_XL | 128K | ~8-10 tok/s | More accurate, slower |
| Qwen3.6-28B-REAP | Q3_K_M | 128K | ~15 tok/s | Smaller model fits better |

## Concurrency / Parallelism Support

llama.cpp **does support concurrent requests** via:

### Server-Side Options

```bash
./llama-server -m model.gguf -ngl 99 \
    --n-parallel 4 \        # decode 4 sequences in parallel
    --cont-batching         # dynamic batching (default: enabled)
```

```bash
# Example: benchmark with 4 concurrent sequences
./llama-server -m Qwen3.6-35B-REAP-RangerX-Q3_K_XL.gguf \
    -ngl 99 --n-parallel 4 --cont-batching -c 131072
```

### Parallel Example

```bash
# Dedicated throughput benchmark tool
./parallel -m Qwen3.6-35B-REAP-RangerX-Q3_K_XL.gguf \
    --n-parallel 4 --cont-batching -c 131072
```

### Key Parameters

| Flag | Default | Description |
|------|---------|-------------|
| `--n-parallel` | auto (-1) | Number of parallel sequences to decode |
| `--cont-batching` | enabled | Insert new sequences mid-generation (dynamic batching) |
| `--n-seqs` | 1 | Number of sequences per client request |

### Expected Concurrency Gains on 5700U

> **Warning:** The 5700U is bandwidth-bound. Gains from parallelism are modest.

| Parallel Sequences | Estimated Total Throughput | Per-Request Latency |
|-------------------|---------------------------|---------------------|
| 1 (baseline) | ~11 tok/s | 1x |
| 2 | ~16-18 tok/s | ~1.3x slower per request |
| 4 | ~22-26 tok/s | ~2x slower per request |
| 8 | ~28-32 tok/s | ~4x slower per request |

**Why the diminishing returns?** The iGPU is starved for memory bandwidth. Adding more sequences means more KV cache data per token, but the DDR4 bus can't feed them all faster.

## ROCmFPX — Does It Help?

[ROCmFPX](https://github.com/ciru-ai/ROCmFPX) provides FP4/FP6/FP8 GGUF weight formats with HIP and Vulkan kernels for AMD GPUs.

### Supported Hardware

| Architecture | Codename | Example | Supported |
|-------------|----------|---------|-----------|
| RDNA 4 | gfx1200 | RX 9070 series | Yes |
| RDNA 3.5 | gfx1151 | Strix Halo | Yes (Vulkan recommended) |
| RDNA 3 | gfx1100 | RX 7900 XTX | Yes |
| RDNA 2 | gfx1030 | RX 6700 XT | Yes |
| GCN 5 | gfx900 | Vega 56/64, 5700U | **No** |

**The 5700U (Lucienne / gfx900) is NOT supported by ROCmFPX.** It requires RDNA2 or newer.

## Optimization Path for 5700U

### Current Best Settings

```bash
# Vulkan with CPU assist for compute-heavy ops
./llama-server -m model.gguf \
    -ngl 99 \          # offload all layers to GPU
    -c 131072 \        # 128K context
    -tb 1024 \         # prompt processing batch
    -ub 2048 \         # generation batch
    --threads 8        # CPU threads for pre/post processing
    --mlock            # lock model in RAM
```

### What Actually Helps

1. **Smaller context** — 128K context is the primary bottleneck. At 4K context, you might see 30-50 tok/s.
2. **Smaller models** — Qwen3-4B at 4K context runs much faster.
3. **CPU fallback for compute** — The Vulkan path on GCN5 is slow for matmuls; the CPU backend can be faster for compute.
4. **Quantization** — Q3_K_XL is the sweet spot. Q2_K is faster but less accurate.

## The Real Path to 1000 tok/s

To hit 1000+ tok/s throughput, you need:

### Option 1: NVIDIA dGPU with vLLM (Recommended)

| Machine | GPU | vLLM Throughput |
|---------|-----|----------------|
| Dev machine | RTX 5060 Ti 16GB | ~500-1000 tok/s (with batching) |
| Future upgrade | RTX 5090 / RTX 5080 | ~1500-3000 tok/s |

See [docs/VLLM-RTX5060TI-SETUP.md](VLLM-RTX5060TI-SETUP.md) for setup instructions.

### Option 2: AMD Strix Halo APUs

The next generation of AMD APUs (Strix Halo, gfx1151) have:
- RDNA 3.5 GPU with hardware tensor cores
- Up to 128GB unified memory (CPU + GPU share)
- **ROCmFPX support with Vulkan acceleration**
- Expected ~100-200 tok/s single-stream, much higher with batching

### Option 3: Multi-GPU Linux Workstation

For llama.cpp:
```bash
# 2x RX 7900 XTX with pipeline parallelism
./llama-server -m model.gguf -ngl 99 -pp 2
```

## ROCmFPX Build for Supported Hardware

If you have RDNA2+ AMD hardware, build ROCmFPX:

```bash
# Clone ROCmFPX
git clone https://github.com/ciru-ai/ROCmFPX.git
cd ROCmFPX && git checkout main

# Build for your GPU
# RDNA2 (gfx1030):
env JOBS=16 scripts/build-radeon-rocmfp4-mtp.sh

# RDNA3 (gfx1100):
env JOBS=16 scripts/build-radeon-rocmfp4-mtp.sh

# Strix Halo (gfx1151):
env JOBS=16 scripts/build-strix-rocmfp4-mtp.sh
```

## Troubleshooting

### "No Vulkan device found" / GPU not enumerated

1. Check Vulkan detection:
   ```bash
   vulkaninfo --summary
   # or
   vulkaninfo --json | python3 -c "import sys,json; [print(d['deviceName']) for d in json.load(sys.stdin).get('devices',[])]"
   ```

2. Verify ICD is loaded:
   ```bash
   cat /usr/share/vulkan/icd.d/radeon_icd.json
   ls /usr/lib/x86_64-linux-gnu/libvulkan_radeon.so
   ```

3. Try with LLVMpipe (CPU Vulkan, slow but works):
   ```bash
   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json ./llama-cli -m model.gguf
   ```

### Low throughput despite GPU detection

- The APU iGPU may be detected but not actually running compute shaders well.
- Try CPU backend comparison:
  ```bash
  cmake -B build -DGGML_VULKAN=OFF -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS
  ```
- Check with `rocm-smi` if using HIP on a supported AMD dGPU.

## Summary

| Goal | 5700U Reality | Recommendation |
|------|-------------|----------------|
| Interactive use (low latency) | 11 tok/s is usable for small models | Use 4-8B models at 4K context |
| High throughput (batch/inference server) | 20-30 tok/s max | Use RTX 5060 Ti + vLLM |
| Future upgrade path | Limited by DDR4 bandwidth | Strix Halo or discrete GPU |
| ROCmFPX on this APU | Not supported | Not applicable |
| Concurrency (multiple users) | Marginal gains (bandwidth-bound) | Best used for OoO scheduling, not throughput |
