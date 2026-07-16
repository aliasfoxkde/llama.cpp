# AMD Ryzen 7 5700U (Radeon Graphics) — Vulkan Benchmark

## System info

```bash
# Hardware
CPU: AMD Ryzen 7 5700U with Radeon Graphics (8-core, 16-thread) @ 1.8GHz base
GPU: AMD Radeon Graphics (RADV RENOIR) — integrated Vega in 5700U APU
GPU Memory: 16 GB total (shared with CPU via DDR4)
GPU VRAM available: ~9.7 GB

# OS / Software
OS: Debian 13 (Trixie) x86_64
Kernel: 6.12.57+deb13-amd64
amdgpu driver: loaded (14MB kernel module)
Vulkan driver: RADV (open-source Mesa)
ROCm: 6.1.2 installed (broken on this APU — see below)

# Storage
NVME (local SSD, root "/"): 444GB, ~38GB free
NAS mount (/nas, USB/HDD/JBOD): 15TB, slow
Model location: /nas/AI/Models/gguf/
```

## Binary

Build: `prism-b9591-62061f9` (llama.cpp)
Binary: `llama-server` (Vulkan backend)
Path: `/home/mkinney/Bonsai-demo/bin/vulkan/llama-server`

```bash
llama-server --version
# version: 9591 (62061f910)
# built with GNU 11.4.0 for Linux x86_64
```

## Bonsai Model Variants

Repository: https://huggingface.co/prism-ml/Ternary-Bonsai-27B-gguf and https://huggingface.co/prism-ml/Bonsai-27B-gguf

### Available GGUF files

| Model | File | Size | Bits | Vision | Location |
|-------|------|------|------|--------|----------|
| Bonsai-27B (1-bit) | Bonsai-27B-Q1_0.gguf | 3.6 GB | 1.125 | No | /nas/AI/Models/gguf/Bonsai-27B-1bit/ |
| Ternary-Bonsai-27B | Ternary-Bonsai-27B-Q2_0.gguf | 6.7 GB | 1.71 | Yes | /nas/AI/Models/gguf/27B/ |
| Ternary-Bonsai-27B | Ternary-Bonsai-27B-Q2_g64.gguf | 7.6 GB | 1.71 | Yes | Untested |
| Ternary-Bonsai-27B | Ternary-Bonsai-27B-PQ2_0.gguf | 7.2 GB | 1.71 | Yes | Untested |
| Bonsai-8B (1-bit) | Bonsai-8B-Q1_0.gguf | 1.1 GB | 1.125 | No | /nas/AI/Models/gguf/Bonsai-8B/ |
| Ternary-Bonsai-27B mmproj | Ternary-Bonsai-27B-mmproj-Q8_0.gguf | 601 MB | — | Req'd | /nas/AI/Models/gguf/27B/ |
| Ternary-Bonsai-27B mmproj | Ternary-Bonsai-27B-mmproj-BF16.gguf | 931 MB | — | Req'd | Untested |
| Ternary-Bonsai-27B drafter | Ternary-Bonsai-27B-dspark-Q4_1.gguf | 1.9 GB | — | — | Speculative decoding only |
| Bonsai-27B drafter | Bonsai-27B-dspark-Q4_1.gguf | 1.8 GB | — | — | Speculative decoding only |

All models support up to **262K context** and include thinking/reasoning by default.

## Benchmark Results

### Bonsai-27B Variants

| Model | Size | Backend | t/s (cold) | t/s (warm) | Notes |
|-------|------|---------|-----------|-----------|-------|
| Q1_0 (1-bit) | 3.6 GB | Vulkan | 0.88 | 0.76–0.79 | |
| Q2_0 (ternary) | 6.7 GB | Vulkan | 0.98 | 0.57–0.64 | |
| Q2_0 + mmproj-Q8_0 | 7.3 GB | Vulkan | 1.05 | — | Vision inference |
| Q1_0 (1-bit) | 3.6 GB | CPU 12t | 0.36 | 0.18–0.92 | Prompt cache helps |

### Bonsai-8B Variants

| Model | Size | Backend | t/s (cold) | t/s (warm) | Notes |
|-------|------|---------|-----------|-----------|-------|
| **Q1_0 (1-bit)** | **1.1 GB** | **Vulkan** | **2.62** | **6.61–6.88** | **★ Best Bonsai speed** |
| Q1_0 (1-bit) | 1.1 GB | CPU 12t | 1.57 | 5.28–6.44 | |

### Recommended server configs

```bash
# Best speed: Bonsai-8B-Q1_0 Vulkan
LD_LIBRARY_PATH=/home/mkinney/Bonsai-demo/bin/vulkan \
  llama-server -m /nas/AI/Models/gguf/Bonsai-8B/Bonsai-8B-Q1_0.gguf \
  -ngl 99 -t 4 --port 8089 -c 512

# Best 27B: Ternary-Q2_0 Vulkan
LD_LIBRARY_PATH=/home/mkinney/Bonsai-demo/bin/vulkan \
  llama-server -m /nas/AI/Models/gguf/27B/Ternary-Bonsai-27B-Q2_0.gguf \
  -ngl 99 -t 4 --port 8089 -c 512

# Vision: Ternary-Q2_0 + mmproj
LD_LIBRARY_PATH=/home/mkinney/Bonsai-demo/bin/vulkan \
  llama-server -m /nas/AI/Models/gguf/27B/Ternary-Bonsai-27B-Q2_0.gguf \
  --mmproj /nas/AI/Models/gguf/27B/Ternary-Bonsai-27B-mmproj-Q8_0.gguf \
  -ngl 99 -t 4 --port 8089 -c 512
```

### Model load time

| Storage | Cold load | Notes |
|---------|-----------|-------|
| NAS (USB/HDD) | 55–70s | 27B models |
| NAS (USB/HDD) | 10s | 8B model |

### Backend comparison (27B Q2_0)

| Backend | t/s | Notes |
|---------|------|-------|
| Vulkan (RADV) | **0.6–1.2** | **Best — works out of box** |
| CPU only | 0.2 | Baseline |
| ROCm HIP | 0.15 | Broken on this APU |

## ROCm status

ROCm 6.1.2 is installed (`rocminfo` works, `rocm-smi` works) but the HIP backend produces extremely poor throughput (0.15 t/s vs Vulkan's 0.6-1.2 t/s). The GPU is detected correctly:

```
Agent 2:
  Name:                    gfx90c
  Marketing Name:          AMD Radeon Graphics
  Device Type:             GPU
  Compute Unit:            8
  SIMDs per CU:            4
  Max Clock Freq. (MHz):  1900
```

The gfx90c (Renoir) architecture likely needs a newer ROCm version than 6.1.2, or the HIP runtime is misconfigured on Debian Trixie. Vulkan works out-of-the-box via the open-source RADV driver that is already loaded as the kernel module.

## Vision (Multimodal) — 27B only

Model: Ternary-Bonsai-27B-mmproj-Q8_0 (601 MB)
Path: `/nas/AI/Models/gguf/27B/Ternary-Bonsai-27B-mmproj-Q8_0.gguf`

Vision inference requires both the main model AND the mmproj projector:

```bash
llama-server -m Ternary-Bonsai-27B-Q2_0.gguf --mmproj Ternary-Bonsai-27B-mmproj-Q8_0.gguf -ngl 99
```

Test: 1×1 PNG with 256×256 grayscale texture, `Describe this image in one sentence.`

| Metric | Value |
|--------|-------|
| t/s | 1.05 |
| Image processed | Yes — correct description |
| VRAM used | ~7.8 GB (model 7.17 GB + mmproj 0.6 GB) |

The mmproj-Q8_0 is **not standalone** — it requires `--mmproj` flag pointing to the projector file, and must be used alongside the base model. Bonsai-8B does **not** have vision support.

## Key findings

1. **Vulkan is the best backend** for this APU — works out of the box with RADV
2. **Bonsai-8B-Q1_0 is the fastest** at 6.9 t/s (warm) — 7× faster than 27B variants
3. **1-bit vs ternary**: Q1_0 (1-bit) and Q2_0 (ternary) run at similar speeds despite size difference
4. **8B is text-only** — no mmproj available; 27B is required for vision
5. **Vision works** with Q2_0 + mmproj-Q8_0 on Vulkan at 1.05 t/s
6. **Prompt cache**: Dramatically improves repeat inference (2–4× speedup on warm runs)
7. **ROCm is broken** on this APU with current stack

## See also

- [GGML-Vulkan Backend](../backend/Vulkan.md)
- [GGML-VirtGPU Backend](../backend/VirtGPU.md)
