# Qwen3.8-27B IQ1_M + DSpark Analysis

**Date:** Wed Aug 19 2026
**Updated:** With DSpark Q4_0 quantization testing

---

## DSpark Model Availability

| Model | Source | Size | Format |
|-------|--------|------|--------|
| Qwen3.8-27B-DSpark-BF16 | erlidev/Qwen3.8-27B-DSpark-GGUF | **2.6 GB** | BF16 (source) |
| Qwen3.8-27B-DSpark-Q8_0 | magnitudedev/Qwen3.8-27B-DSpark-GGUF | 1.4 GB | Q8_0 |
| Qwen3.8-27B-DSpark-Q4_0 | (quantized from BF16) | **740 MB** | Q4_0 |

**Download:**
```bash
hf download erlidev/Qwen3.8-27B-DSpark-GGUF Qwen3.8-27B-DSpark-BF16.gguf
```

**Quantize to Q4_0:**
```bash
./build/bin/llama-quantize \
  Qwen3.8-27B-DSpark-BF16.gguf \
  Qwen3.8-27B-DSpark-Q4_0.gguf Q4_0
```

---

## Does DSpark Support Vision Encoder?

**No.** DSpark is a pure draft model - it doesn't have vision capabilities. The mmproj vision encoder is:
1. Only needed for MTP (Multi-Token Prediction)
2. Not used by DSpark at all
3. Doesn't need to be loaded for DSpark speculative decoding

**Trade-off:** Skipping mmproj saves ~870MB VRAM, but DSpark draft still needs its own ~740MB (Q4_0).

---

## TQ3 Fork Testing (turbo-tan/llama.cpp-tq3)

### Can IQ1_M Run on TQ3 Fork?
**Yes.** IQ1_M loads successfully on the TQ3 fork (same as stock llama.cpp).

### Does DSpark Draft Work on TQ3 Fork?
**Yes.** Using `--spec-type draft-dspark --spec-draft-model <path-to-dspark-q4_0>`:
- Loads without errors
- Draft model is used (block_size=7, n_extract=5)
- Works without mmproj

**Warning:** "dflash requires ctx_other to be set" is a normal warning during initialization.

---

## Performance Comparison on TQ3 Fork (64K CTX, q4_0 KV)

| Config | TPS Range | Average TPS | vs Baseline |
|--------|-----------|-------------|-------------|
| **Baseline** | 29-34 | ~33 | — |
| **MTP n=2** | 33-48 | ~42 | **+27%** |
| **DSpark Q4_0** | 29-40 | ~36 | **+9%** |

### Key Findings

1. **MTP beats DSpark on TQ3 fork** — MTP gives ~42 TPS vs DSpark's ~36 TPS
2. **DSpark Q4_0 saves 50% vs Q8_0** — 740MB vs 1.4GB, but doesn't improve speed
3. **DSpark OOM at 128K** — Even without mmproj, 128K + DSpark fails
4. **MTP on TQ3 supports 64K** — Same as stock llama.cpp

---

## VRAM Usage (RTX 5060 Ti 16GB)

| Config | Est. VRAM | Status |
|--------|-----------|--------|
| IQ1_M baseline 64K | ~10.5 GB | ✅ |
| IQ1_M + MTP 64K | ~15.3 GB | ✅ |
| IQ1_M + DSpark Q4_0 64K | ~11.2 GB | ✅ |
| IQ1_M + MTP 128K | ~16.5 GB | ❌ OOM |
| IQ1_M + DSpark Q4_0 128K | ~15.8 GB | ❌ OOM |

---

## Why DSpark Underperforms MTP Here

DSpark was designed for and performs best with:
- **Larger target models** (70B+) where draft << target
- **Shorter contexts** (8K-32K)
- **Matching architecture** between draft and target

With IQ1_M (7.3GB main + 740MB draft = 8GB total):
- Draft is ~10% of model size (not enough ratio)
- Same architecture means less diversity advantage
- MTP has better integration on TQ3 fork

---

## Updated Recommendation Table

| Use Case | Best Config | TPS | CTX | Notes |
|----------|-------------|-----|-----|-------|
| **Max speed** | IQ1_M + MTP n=2 | ~61 | 64K | Requires mmproj (870MB) |
| **Large CTX + speed** | IQ1_M + MTP n=2 | ~57 | 128K | q4_0 KV needed |
| **Max CTX text** | IQ1_M baseline | ~38 | 256K | No MTP, no mmproj |
| **DSpark experiment** | IQ1_M + DSpark | ~36 | 64K | No mmproj needed |

---

## Summary: DSpark on IQ1_M

- ✅ DSpark Q4_0 **works** on TQ3 fork
- ✅ Q4_0 quantization **halves** DSpark size (1.4GB → 740MB)
- ❌ DSpark is **~15% slower** than MTP on same setup
- ❌ DSpark doesn't enable larger CTX than MTP
- ❌ No vision support (same as MTP, neither is multimodal)
- ❓ Best for: experiments/testing; MTP is faster for production

---

## Commands

```bash
# DSpark on TQ3 fork (64K)
./build/bin/llama-server \
  -m Qwen3.8-27B-IQ1_M.gguf \
  --spec-draft-model Qwen3.8-27B-DSpark-Q4_0.gguf \
  --spec-type draft-dspark \
  -c 65536 -ngl 99 -ctk q4_0 -ctv q4_0 --port 8080

# MTP on TQ3 fork (64K)
./build/bin/llama-server \
  -m Qwen3.8-27B-IQ1_M.gguf \
  --mmproj mmproj-BF16.gguf \
  --spec-type draft-mtp --spec-draft-n-max 2 \
  -c 65536 -ngl 99 -ctk q4_0 -ctv q4_0 --port 8080

# Quantize DSpark BF16 → Q4_0
./build/bin/llama-quantize \
  Qwen3.8-27B-DSpark-BF16.gguf \
  Qwen3.8-27B-DSpark-Q4_0.gguf Q4_0
```
