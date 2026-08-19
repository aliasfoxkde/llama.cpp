# Qwen3.8-27B-IQ1_M Benchmark (llama.cpp direct)

**Date:** Wed Aug 19 2026
**Model:** Qwen3.8-27B-IQ1_M (IQ1_M - 1.75 bpw, ~7.3GB on disk)
**mmproj:** mmproj-Qwen3.8-27B-BF16.gguf (~870MB) — required for MTP only
**GPU:** NVIDIA GeForce RTX 5060 Ti 16GB (VRAM: 16311 MB)
**llama.cpp build:** `/home/mkinney/Repos/llama.cpp/build/bin/llama-server`
**Prompt:** "What is machine learning? Answer in exactly 15 words." (15 tokens output)

---

## Summary Table

| CTX | KV Type | baseline TPS | MTP n_max=2 TPS | Speedup | Accept% | VRAM | Notes |
|------|---------|-------------|-----------------|---------|---------|------|-------|
| 32K | FP16 | 38.3 | 61.3 | **+60%** | 81% | ~11GB | |
| 64K | FP16 | 38.3 | 61.4 | **+60%** | 81% | ~15.3GB | |
| 96K | q4_0 | 38.1 | 57.9 | +52% | 74% | ~13.5GB | |
| 128K | q4_0 | 38.0 | 57.7 | +52% | 74% | ~14.4GB | |
| 160K | q4_0 | 38.0 | 56.4 | +48% | 70% | ~15.3GB | n_max=3/4 crash |
| 192K | q4_0 | 37.9 | (crash) | — | — | ~15.7GB+ | |
| 256K | q4_0 | 37.9 | FAILED | — | — | 15.4GB | |
| **256K no mmproj** | q4_0 | **37.9** | N/A | N/A | N/A | **14.3GB** | text-only |

**MTP n_max=2 is optimal across all working CTX sizes.**

---

## 32K CTX Full Results (5 runs)

| Mode | n_max | TPS | Draft Tot | Draft Acc | Accept% |
|------|-------|-----|-----------|-----------|---------|
| baseline | 0 | 38.3 | 0 | 0 | 0% |
| MTP | 2 | **61.3** | 37 | 30 | **81%** |
| MTP | 3 | 52.6 | 54 | 30 | 55% |
| MTP | 4 | 47.1 | 71 | 30 | 42% |
| MTP | 5 | 43.3 | 80 | 31 | 39% |
| DFlash | 2 | 42.0 | 51 | 22 | 43% |
| DFlash | 3 | 42.9 | 66 | 25 | 37% |
| DFlash | 4 | 41.4 | 83 | 26 | 31% |

**draft-eagle3 and ngram-simple:** Loaded but generated 0 drafts (require separate draft model files).

---

## Temperature Sweep (128K CTX, MTP n_max=2, q4_0 KV)

| Temperature | TPS | Draft Tot | Draft Acc | Accept% |
|-------------|-----|-----------|-----------|---------|
| **0.3** | **61.6** | 37 | 30 | **81%** |
| 0.0 | 57.8 | 39 | 29 | 74% |
| 0.7 | 55.9 | 40 | 28 | 70% |
| 1.0 | 57.6 | 39 | 28 | 71% |

**temp=0.3 is optimal** — highest TPS (61.6) and highest acceptance rate (81%).

---

## VRAM Breakdown (RTX 5060 Ti 16GB)

| Component | Size |
|-----------|------|
| Main model (IQ1_M) | ~7.3 GB |
| mmproj (BF16) | ~0.87 GB |
| MTP draft model | ~0.87 GB |
| KV cache FP16 @ 64K | ~8.6 GB |
| KV cache q4_0 @ 128K | ~6.4 GB |
| KV cache q4_0 @ 256K | ~12.8 GB |
| **VRAM budget** | **16.3 GB** |

---

## mmproj Quantization Attempt

**Goal:** Free VRAM by quantizing the mmproj (BF16 -> Q4_0 hybrid)

**Result: FAILED for MTP use case**

- Successfully quantized 86/334 tensors to Q4_0 (2D weights with dim % 32 == 0)
- 248 tensors must stay BF16 (1D bias/ln, or 2D with non-32-aligned dims like hidden_dim=1152)
- Output: mmproj-Qwen3.8-BF16-hybrid-Q4_0.gguf (694MB vs 889MB, **22% smaller**)
- **Problem:** The MTP draft model weights in the mmproj cannot be loaded from quantized format
- llama-server fails to load MTP from the quantized mmproj
- **Only works for:** text inference without MTP

**Key insight:** MTP draft model weights MUST be loadable in full precision (BF16/FP16). Quantizing the vision encoder portion is harmless but doesn't save enough to enable larger CTX.

---

## Key Findings

1. **MTP n_max=2 is optimal** — best TPS (+60% at 32K/64K, +52% at 96K/128K) with highest acceptance (81%)
2. **q4_0 KV cache is essential for large CTX** — reduces KV from ~20GB to ~6.4GB at 128K
3. **160K works with q4_0 KV** — MTP n_max=2 gives 56.4 TPS (+48%), n_max=3/4 crash
4. **192K MTP crashes** — borderline OOM at ~15.7GB VRAM
5. **256K baseline works without mmproj** — 37.9 TPS at 14.3GB (text-only, no MTP)
6. **Temperature 0.3 is ideal for MTP** — 61.6 TPS with 81% acceptance
7. **DFlash bootstrap draft works** — modest +10% gain, lower acceptance (43%)
8. **IQ1_M at 1.75 bpw is surprisingly capable** — coherent output, stable inference
9. **mmproj quantization won't help MTP** — MTP draft model needs full precision weights

---

## How to Run

```bash
# 32K MTP (optimal)
./build/bin/llama-server -m Qwen3.8-27B-IQ1_M.gguf --mmproj mmproj-BF16.gguf \
  -c 32768 -ngl 99 --spec-type draft-mtp --spec-draft-n-max 2 --port 8080

# 128K MTP (q4_0 KV needed)
./build/bin/llama-server -m Qwen3.8-27B-IQ1_M.gguf --mmproj mmproj-BF16.gguf \
  -c 131072 -ngl 99 --spec-type draft-mtp --spec-draft-n-max 2 \
  -ctk q4_0 -ctv q4_0 --port 8080

# 256K text-only (no MTP, no mmproj needed)
./build/bin/llama-server -m Qwen3.8-27B-IQ1_M.gguf \
  -c 262144 -ngl 99 -ctk q4_0 -ctv q4_0 --port 8080
```
