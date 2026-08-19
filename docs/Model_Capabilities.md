# Model Capabilities Configuration

**Date:** Wed Aug 19 2026
**Updated:** Added Fast tier with IQ2_XXS + DSpark

---

## Model Capability Tiers

| Capability | Model | Quant | CTX | TPS | Vision | Runtime | VRAM |
|------------|-------|-------|-----|-----|--------|---------|------|
| **Pro** | Qwen3.8-27B | IQ3_XXS | 160K | ~31 | ❌ | Stock | 14.1GB |
| **Vision** | Qwen3.8-27B + mmproj | IQ3_XXS | 128K | ~31 | ✅ | Stock | 15.4GB |
| **Turbo** | Qwen3.6-35B-A3B (MoE) | Q3_K_M | 160K | ~107 | ❌ | Stock | 14.5GB |
| **Fast** | Qwen3.8-27B + DSpark | IQ2_XXS | 96K | ~77 | ❌ | TQ3 fork | ~11.5GB |

---

## Detailed Model Specs

### Pro - Maximum Context Text
- **Model:** Unsloth Qwen3.8-27B
- **Quantization:** IQ3_XXS (~12GB on disk)
- **Max CTX:** 160K (192K crashes)
- **Speed:** ~31 TPS
- **Runtime:** Stock llama.cpp
- **Best for:** Long documents, code, complex reasoning
- **Notes:** Largest CTX available, no speculative decoding

### Vision - Multimodal
- **Model:** Unsloth Qwen3.8-27B + mmproj-F16.gguf
- **Quantization:** IQ3_XXS
- **Max CTX:** 128K (mmproj takes ~1GB VRAM)
- **Speed:** ~31 TPS
- **Runtime:** Stock llama.cpp
- **Best for:** Image understanding, documents with figures
- **Notes:** Only model with vision support

### Turbo - Maximum Speed
- **Model:** JZC973 Qwen3.6-35B-A3B REAP MTP (MoE)
- **Quantization:** Q3_K_M REAP (~13.4GB on disk)
- **Max CTX:** 160K
- **Speed:** ~107 TPS (3.4x faster than Pro)
- **Runtime:** Stock llama.cpp
- **Best for:** Fast responses, high-volume inference
- **Notes:** MoE architecture, built-in MTP available but unused
- **Concurrency:** ~215 TPS @ 4 concurrent requests

### Fast - High Speed Alternative
- **Model:** Unsloth Qwen3.8-27B + DSpark Q8_0 draft
- **Quantization:** IQ2_XXS (9GB) + DSpark Q8_0 (1.4GB)
- **Max CTX:** 96K
- **Speed:** ~77 TPS (2.5x faster than Pro)
- **Runtime:** TQ3 fork (turbo-tan)
- **Best for:** Speed-critical text tasks
- **Notes:** Requires TQ3 fork build, no vision
- **Status:** TQ3 fork not yet built locally

---

## Model Details

### Pro - Maximum Context Text
- **Base Model:** Unsloth Qwen3.8-27B
- **Quantization:** IQ3_XXS (~12GB on disk)
- **Max CTX:** 160K (192K crashes on 16GB VRAM)
- **Speed:** ~31 TPS
- **Best for:** Long documents, code analysis, complex reasoning

### Vision - Multimodal
- **Base Model:** Unsloth Qwen3.8-27B + mmproj-F16.gguf
- **Quantization:** IQ3_XXS
- **Max CTX:** 128K (vision takes ~1GB VRAM)
- **Speed:** ~31 TPS
- **Best for:** Image understanding, documents with figures

### Turbo - Maximum Speed
- **Base Model:** JZC973 Qwen3.6-35B-A3B REAP MTP (MoE)
- **Quantization:** Q3_K_M REAP (~13.4GB on disk)
- **Max CTX:** 160K (192K crashes)
- **Speed:** ~107 TPS (3.4x faster than Pro)
- **Best for:** Fast responses, high-volume inference

---

## VRAM Usage (RTX 5060 Ti 16GB)

| Config | Est. VRAM | Status |
|--------|-----------|--------|
| Pro 160K | 14.1 GB | ✅ |
| Vision 128K | 15.4 GB | ✅ |
| Turbo 160K | 14.5 GB | ✅ |
| Vision 160K | ~16.5 GB | ❌ OOM |
| Turbo + MTP 96K | ~15.8 GB | ❌ OOM |

---

## llama-proxy Model Switching

The proxy at `/home/mkinney/.local/bin/llama-proxy` maps these capabilities:

```python
MODEL_ALIASES = {
    "Pro": "/path/to/Qwen3.8-27B-UD-IQ3_XXS.gguf",
    "Vision": "/path/to/Qwen3.8-27B-UD-IQ3_XXS.gguf",
    "Turbo": "/path/to/Qwen3.6-35B-A3B-UD-Q3_K_M-REAP.gguf",
}
```

### API Endpoints

```bash
# List all capabilities
curl http://localhost:8082/models

# Get current model info
curl http://localhost:8082/model

# Switch capability
curl -X POST http://localhost:8082/model \
  -H "Content-Type: application/json" \
  -d '{"model": "Vision"}'
```

### API Response with Metadata

```json
{
  "id": "Vision",
  "object": "model",
  "description": "Qwen3.8-27B + vision encoder - 128K CTX with images",
  "quantization": "IQ3_XXS",
  "ctx": 131072,
  "tps": "~31 TPS",
  "vision": true,
  "mtp": false
}
```

---

## Speed Ranking

| Rank | Capability | TPS | CTX | Use Case |
|------|------------|-----|-----|----------|
| 🥇 | **Turbo** | ~107 | 160K | Speed-critical tasks |
| 🥈 | **Fast** | ~77 | 96K | Speed + context (requires TQ3) |
| 🥉 | **Pro** | ~31 | 160K | Best quality + max CTX |
| 🖼️ | **Vision** | ~31 | 128K | Image input |

---

## Key Findings

1. **Turbo is fastest** - 3.4x faster than Pro (~107 vs ~31 TPS)
2. **Fast is 2.5x Pro** - IQ2_XXS + DSpark at 77 TPS (needs TQ3 build)
3. **Vision caps at 128K** - mmproj takes ~1GB VRAM
4. **192K+ unstable** - crashes on 16GB VRAM
5. **MTP + Vision OOM** - can't combine speculative decoding with vision
6. **MoE advantage** - Qwen3.6's architecture enables 3x speed

---

## TQ3 Fork Requirements

Fast mode requires building the TQ3 fork:

```bash
git clone https://github.com/turbo-tan/llama.cpp.git /home/mkinney/Repos/llama.cpp-tq3
cd /home/mkinney/Repos/llama.cpp-tq3
mkdir build && cd build
cmake .. -GNinja -DLLAMA_CUDA=ON -DCMAKE_BUILD_TYPE=Release
ninja
```

**DSpark draft model:** Already downloaded at `/home/mkinney/Models/magnitudedev/Qwen3.8-27B-DSpark-GGUF/Qwen3.8-27B-DSpark-Q8_0.gguf` (1.4GB)

---

## llama-server Commands

```bash
# Pro (160K, no vision)
llama-server -m Qwen3.8-27B-UD-IQ3_XXS.gguf \
  -c 163840 -ngl 99 -ctk q4_0 -ctv q4_0 --port 8080

# Vision (128K + mmproj)
llama-server -m Qwen3.8-27B-UD-IQ3_XXS.gguf \
  --mmproj mmproj-F16.gguf \
  -c 131072 -ngl 99 -ctk q4_0 -ctv q4_0 --port 8080

# Turbo (160K, no vision)
llama-server -m Qwen3.6-35B-A3B-UD-Q3_K_M-REAP.gguf \
  -c 163840 -ngl 99 -ctk q4_0 -ctv q4_0 --port 8080
```

---

## Concurrency Notes

- All configs run with `-np 4` (4 parallel slots)
- KV cache quantization (`-ctk q4_0 -ctv q4_0`) essential for large CTX
- Flash attention (`-fa on`) improves throughput
