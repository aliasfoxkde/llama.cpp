# Model Capabilities Configuration

**Date:** Wed Aug 19 2026
**Updated:** With capability-based model naming

---

## Model Capability Tiers

| Capability | Model | Quant | CTX | TPS | Vision | MTP | VRAM |
|------------|-------|-------|-----|-----|--------|-----|------|
| **Pro** | Qwen3.8-27B | IQ3_XXS | 160K | ~31 | ❌ | ❌ | 14.1GB |
| **Vision** | Qwen3.8-27B + mmproj | IQ3_XXS | 128K | ~31 | ✅ | ❌ | 15.4GB |
| **Turbo** | Qwen3.6-35B-A3B (MoE) | Q3_K_M | 160K | ~107 | ❌ | ❌* | 14.5GB |

*MTP available but not used when VRAM-constrained (vision OOMs with MTP at any CTX)

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

## Key Findings

1. **Turbo is 3.4x faster** than Pro/Vision (~107 vs ~31 TPS)
2. **Vision caps at 128K** due to mmproj VRAM overhead (~1GB)
3. **192K unstable** on 16GB VRAM - crashes on load
4. **MTP + Vision OOM** - can't use MTP speculative decoding with vision
5. **MoE advantage** - Qwen3.6's architecture enables 3x speed despite similar VRAM

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
