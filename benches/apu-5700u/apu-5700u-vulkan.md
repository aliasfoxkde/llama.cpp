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
Model location (NVME): /home/mkinney/models/ternary-gguf/27B/
```

## Model: Ternary-Bonsai-27B-Q2_0

Repository: https://huggingface.co/prism-ml/Ternary-Bonsai-27B-gguf

- Size: 7.17 GB
- Quantization: Q2_0 (ternary/2-bit)
- Context: 8192
- Vision: Yes (27B has vision + tool calling)
- Model location: `/home/mkinney/models/ternary-gguf/27B/Ternary-Bonsai-27B-Q2_0.gguf`

## Binary

Build: `prism-b9591-62061f9` (llama.cpp)
Binary: `llama-server` (Vulkan backend)
Path: `/nas/Temp/repos/Bonsai-demo/bin/vulkan/llama-server`

```bash
llama-server --version
# version: 9591 (62061f910)
# built with GNU 11.4.0 for Linux x86_64
```

## Results

### llama-server (API inference)

Test: `curl /v1/completions` with `max_tokens=32`, 3 prompts

| Prompt | t/s | prompt_ms | predicted_n | Notes |
|--------|------|-----------|-------------|-------|
| "Three farmers have 3 chickens..." | 0.98 | 6835 | 64 | Cold KV cache |
| "What is the derivative of x^3?" | 0.64 | 6699 | 64 | Warm KV |
| "Explain quicksort in one sentence." | 0.57 | 8036 | 64 | Warm KV |

- **GPU layers**: 99 (full offload)
- **Threads**: 4
- **Context**: 512

### Model load time

| Storage | Cold load | Notes |
|---------|-----------|-------|
| NVME (local SSD) | **25s** | Fast |
| NAS (USB/HDD) | 70-90s | Slow |

### Backend comparison (same model, same conditions)

| Backend | t/s | Notes |
|---------|------|-------|
| Vulkan (RADV) | **0.6–1.2** | **Works — best option** |
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

## Vision (Multimodal)

Model: Ternary-Bonsai-27B-mmproj-Q8_0 (601 MB)
Path: `/home/mkinney/models/ternary-gguf/27B/Ternary-Bonsai-27B-mmproj-Q8_0.gguf`

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

The mmproj-Q8_0 is **not standalone** — it requires `--mmproj` flag pointing to the projector file, and must be used alongside the base model.

## Key findings

1. **Vulkan is the best backend** for this APU — works out of the box with RADV
2. **Integrated GPU is bandwidth-limited** — shared DDR4 memory means throughput is modest (~1 t/s)
3. **NVME storage matters for iteration speed** — 25s cold load vs 70-90s on NAS
4. **ROCm is broken** on this APU with current stack
5. **Vision works** with Q2_0 + mmproj-Q8_0 on Vulkan at 1.05 t/s

## See also

- [GGML-Vulkan Backend](../backend/Vulkan.md)
- [GGML-VirtGPU Backend](../backend/VirtGPU.md)
