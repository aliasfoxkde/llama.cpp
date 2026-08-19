# Model Capabilities Configuration

**Date:** Wed Aug 19 2026

---

## Model Tiers

| Capability | Model | Quant | CTX | TPS | Vision | Parameters | Architecture |
|------------|-------|-------|-----|-----|--------|------------|--------------|
| **Ultra** | Qwen3.8-27B | IQ3_XXS | 160K | ~31 | ✅ | 27B | Dense |
| **Turbo** | Qwen3.6-35B-A3B | Q3_K_M | 160K | ~107 | ❌ | 35B MoE | MoE |

---

## Ultra - Best Quality Multimodal
- **Model:** Unsloth Qwen3.8-27B + mmproj-F16.gguf
- **Quantization:** IQ3_XXS (~12GB on disk)
- **Max CTX:** 160K
- **Speed:** ~36 TPS (measured)
- **Vision:** ✅ Multimodal with images
- **Parameters:** 27B Dense
- **Runtime:** Stock llama.cpp (with --reasoning off)
- **VRAM:** ~15.7GB
- **Best for:** Complex reasoning, image understanding, code, long documents

## Turbo - Maximum Speed
- **Model:** JZC973 Qwen3.6-35B-A3B REAP MTP
- **Quantization:** Q3_K_M REAP (~13.4GB on disk)
- **Max CTX:** 160K
- **Speed:** ~118 TPS single, ~192 TPS @ concurrency 4 (peak 220)
- **Vision:** ❌ Text only
- **Parameters:** 35B MoE (~27B active)
- **Runtime:** Stock llama.cpp (with --reasoning off)
- **VRAM:** ~14.5GB
- **Best for:** High-volume inference, fast responses

---

## Speed Ranking

| Rank | Model | TPS | CTX | Concurrency | Use Case |
|------|-------|-----|-----|-------------|----------|
| 🥇 | **Turbo** | ~118 | 160K | ~192 @ 4 (peak 220) | Speed-critical tasks |
| 🥈 | **Ultra** | ~36 | 160K | ~157 @ 4 | Quality + vision |

---

## VRAM Usage (RTX 5060 Ti 16GB)

| Config | VRAM | Status |
|--------|------|--------|
| Ultra 160K + vision | 15.7GB | ✅ |
| Turbo 160K | 14.5GB | ✅ |

---

## API Endpoints

```bash
# List all models
curl http://localhost:8082/models

# Get current model info
curl http://localhost:8082/model

# Switch model
curl -X POST http://localhost:8082/model \
  -H "Content-Type: application/json" \
  -d '{"model": "Turbo"}'
```

### API Response

```json
{
  "id": "Ultra",
  "object": "model",
  "description": "Qwen3.8-27B + vision encoder - Best quality, 160K CTX, multimodal",
  "quantization": "IQ3_XXS",
  "ctx": 163840,
  "tps": "~31 TPS",
  "vision": true,
  "mtp": false,
  "parameters": "27B",
  "architecture": "Dense"
}
```

---

## llama-server Commands

```bash
# Ultra (160K + vision)
llama-server -m Qwen3.8-27B-UD-IQ3_XXS.gguf \
  --mmproj mmproj-F16.gguf \
  -c 163840 -ngl 99 -ctk q4_0 -ctv q4_0 --port 8080

# Turbo (160K, no vision)
llama-server -m Qwen3.6-35B-A3B-UD-Q3_K_M-REAP.gguf \
  -c 163840 -ngl 99 -ctk q4_0 -ctv q4_0 --port 8080
```

---

## Key Findings

1. **Turbo is 3.3x faster single-stream** - ~118 vs ~36 TPS
2. **Concurrency TPS is GPU-limited** - both hit ~267 TPS peak at conc 4
3. **Both support 160K CTX** - max context on 16GB VRAM
4. **Ultra has vision** - only model with multimodal support
5. **MoE architecture** - Turbo uses fewer active parameters for single-stream speed
6. **IQ3_XXS quality** - good balance of size and capability
7. **Both pass quality tests** - math, logic, code, factual recall all correct
8. **10/10 reliability** - no failures in sequential request testing

## Concurrency Scaling

Single-stream TPS differs significantly, but under concurrent load both models reach similar peak throughput (~267 TPS at concurrency 4) because the GPU is the bottleneck.

## Validation Results (Aug 19 2026)

| Test | Ultra | Turbo |
|------|-------|-------|
| TPS @ 160K | ~36 | ~118 |
| Concurrency 2 | ~160 | ~160 |
| Concurrency 4 | **~267 (peak)** | **~267 (peak)** |
| Concurrency 6 | ~200 | ~218 |
| Concurrency 8 | ~246 | ~246 |
| Math (15*23) | ✅ 345 | ✅ 345 |
| Logic syllogism | ✅ Correct | ✅ Correct |
| Code generation | ✅ Works | ✅ Works |
| Factual recall | ✅ Neil Armstrong | ✅ |
| VRAM | 15.7GB | 14.5GB |
| Sequential reliability | 10/10 | 10/10 |
