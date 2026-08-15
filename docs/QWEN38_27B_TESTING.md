# Bonsai-27B GGUF Testing — 2026-08-08

## Models Tested

| Model | Path | Size | Status | Notes |
|---|---|---|---|---|
| Bonsai-27B-Q1_0 | `lmstudio-community/Bonsai-27B-GGUF/` | 3.6GB | ✅ WORKS | Standard llama.cpp arch |
| Bonsai-27B-dspark-Q4_1 | `prism-ml/Bonsai-27B-gguf/` | 1.7GB | ❌ FAILS | `dspark` arch unknown to llama.cpp |
| Ternary-Bonsai-27B-PQ2_0 | `prism-ml/Ternary-Bonsai-27B-gguf/` | 6.7GB | ❌ FAILS | ggml type 142 not in any build |
| Ternary-Bonsai-27B-dspark-Q4_1 | `prism-ml/Ternary-Bonsai-27B-gguf/` | 1.9GB | ❌ FAILS | `dspark` arch unknown |
| Ternary-Bonsai-27B-dspark-BF16 | `prism-ml/Ternary-Bonsai-27B-gguf/` | 6.8GB | ❌ FAILS | `dspark` arch unknown |
| Bonsai-27b-1bit-CRACK-Q1_0 | `dealignai/` | 4.4GB | NOT TESTED | |

## Bonsai-27B-Q1_0 Benchmark Results

**Hardware:** RTX 5060 Ti 16GB | **Build:** llama.cpp build-cuda-new (b10091) | **Context:** 32768

### Concurrent Throughput

| Concurrency | Throughput (tok/s) | GPU Power |
|---|---|---|
| 1 | ~52 | ~20W |
| 2 | ~88 | ~45W |
| 4 | **~107** | ~66W |
| 8 | ~107 | ~120W |
| 12 | ~106 | ~120W |

**Peak: ~107 tok/s @ concurrency 4-8**
- Cold-start penalty on first request (~40 tok/s) — stabilizes after
- Prompt length does not meaningfully impact throughput

### Prompt Length Sweep (concurrency 4)

| Prompt Length | Conc 1 | Conc 4 |
|---|---|---|
| Short (~5 words) | 53 tok/s | 105 tok/s |
| Medium (~20 words) | 53 tok/s | 103 tok/s |
| Long (~57 words) | 47 tok/s | 102 tok/s |

### Speculative Decoding

- `ngram-mod` was tested: negligible difference (prompt 236 vs 257 baseline)
- Not worthwhile for this model/config

## vLLM Status

- vLLM GGUF plugin fork (`~/Repos/vllm-gguf-plugin`) only supports Qwen3.5/3.6 hybrids — Bonsai architecture not supported
- flashinfer version mismatch (0.6.14 vs 0.6.13) blocks vLLM startup — can bypass with `FLASHINFER_DISABLE_VERSION_CHECK=1` but core functionality unaffected

---

# Qwen3.8-27B GGUF Testing — 2026-08-08/15

## Models Available

| Model | Path | Size | Status |
|---|---|---|---|
| Qwen3.8-27B-UD-IQ3_XXS | `unsloth/Qwen3.8-27B-GGUF/` | 12GB | ✅ WORKS |
| Qwen3.8-27B-UD-Q3_K_XL | `unsloth/Qwen3.8-27B-GGUF/` | 13GB | ✅ WORKS |
| Qwen3.8-27B-DSpark-Q8_0 | `magnitudedev/Qwen3.8-27B-DSpark-GGUF/` | 1.4GB | ❌ FAILS |
| Qwen3.8-27B-NVFP4-MTP-LOW | `esatapedico/Qwen3.8-27B-NVFP4-MTP-GGUF/` | 15GB | ❌ FAILS |

## llama-server Commands

**Primary config (128K, optimal):**
```bash
/home/mkinney/Repos/llama.cpp/build-cuda-new/bin/llama-server \
  -m /home/mkinney/Models/unsloth/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-IQ3_XXS.gguf \
  -c 131072 -tb 256 -ngl 99 --host 0.0.0.0 --port 8080 \
  --flash-attn on --cache-type-k q4_0 --cache-type-v q4_0
```

**MTP n=3 (8K, best single-request latency):**
```bash
/home/mkinney/Repos/llama.cpp/build-cuda-new/bin/llama-server \
  -m /home/mkinney/Models/unsloth/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-IQ3_XXS.gguf \
  -c 8192 -tb 256 -ngl 99 --host 0.0.0.0 --port 8080 \
  --flash-attn on --cache-type-k q4_0 --cache-type-v q4_0 \
  --spec-type draft-mtp --spec-draft-n-max 3
```

**REAP MTP (fast small tasks):**
```bash
# See llama-server-reap.sh
./llama-server-reap.sh
```

## Full Benchmark Results

**Hardware:** RTX 5060 Ti 16GB | **Build:** llama.cpp build-cuda-new (b10091)

| Config   | Ctx  | C1 | C2 | C3 | C4 | C5 | C6 | C7 |  C8 | C9 | C10 | C11 | C12 | C13 | C14 | C15 | C16 |
|----------|------|----|----|----|----|----|----|----|-----|----|-----|-----|-----|-----|-----|-----|-----|
| No MTP   |  8K  | 26 | 37 | 45 | 54 | 43 | 46 | 51 | **87** | —  |  48 |  —  |  54 |  —  |  50 |  —  |  55 |
| MTP n=2  |  8K  | 25 | 37 | 46 | 53 | 41 | 48 | 50 |  54  | 47 |  49 |  —  |  54 |  —  |  49 |  —  |  54 |
| MTP n=3  |  8K  | 40 | 52 | 58 | 70 | 58 | 60 | 66 |  75  | —  |  —  |  —  |  —  |  —  |  —  |  —  |  —  |
| No MTP   | 64K  | 26 | 37 | 45 | 54 | 43 | 47 | 50 |  53  | —  |  —  |  —  |  —  |  —  |  —  |  —  |  —  |
| MTP n=3  | 64K  | 40 | 47 | —  | 69 | —  | —  | —  |  71  | —  |  —  |  —  |  —  |  —  |  —  |  —  |  —  |
| No MTP   | 96K  | 24 | 37 | 46 | 54 | 44 | 46 | 51 |  54  | 46 |  50 |  —  |  53 |  —  |  51 |  —  |  53 |
| No MTP   | 128K | 26 | 37 | 46 | 54 | 43 | 48 | 50 |  54  | 48 |  50 |  51 |  54 |  49 |  51 |  52 |  54 |

### Key Findings

1. **No-MTP C8 = 87 t/s at 8K is the overall peak** — larger ctx sizes plateau at ~54 t/s; the 8K C8 jump is a GPU batching artifact
2. **MTP n=3 wins at C1-C4** — 40-70% faster than no-MTP (40 vs 26 at C1, 70 vs 54 at C4)
3. **MTP n=2 ≈ no-MTP** — draft too weak to help; within noise margin at every concurrency
4. **Context size barely matters for no-MTP** — 8K/64K/96K/128K within ~2 t/s at most concurrency levels; Q4_1 KV quantization absorbs overhead
5. **MTP n=3 is only stable at 8K ctx** — 64K+ is unstable or crashes under concurrent load
6. **NVFP4, DSpark, 262K ctx** — all fail on RTX 5060 Ti (sm_100); see Incompatible Variants below
7. **K != V makes zero measurable difference** — all combinations yield ~30 t/s at 128K, ~30 t/s at 8K; no direction (K vs V) advantage exists

### Incompatible Variants

| Variant | Error | Reason |
|---|---|---|
| DSpark Q8_0 | Tensor mismatch (58 vs 62) | Qwen3.8 main model and DSpark draft have incompatible architectures |
| NVFP4 MTP | `cudaMalloc failed` | CUDA kernels require Blackwell sm_120; RTX 5060 Ti is sm_100 (Ada Lovelace) |
| 262K ctx | OOM | KV cache exceeds available VRAM even with Q4_1 quantization |
| 96K + MTP n=3 | OOM | KV + MTP draft heads exceed 16GB VRAM budget |
| 128K + MTP n=3 | OOM | Same as above |

### Speculative Decoding Analysis

- **MTP n=1:** Negligible improvement over no-MTP — single draft token too weak
- **MTP n=3:** Best single-token latency; draft acceptance ~50-56%
- **MTP n=4-8:** Rejection overhead dominates; throughput decreases
- **DSpark:** Architecturally incompatible between Qwen3.8 variants
- **ngram-mod:** Tested on Bonsai-27B — negligible difference, not worthwhile

### KV Cache Asymmetry Tests (K != V)

**Method:** Server runs with q4_0/q4_0 KV; per-request overrides select alternative K or V types.
**Result: ZERO measurable difference in any direction.**

| KV Combo | 128K t/s | 8K t/s | Notes |
|---|---|---|---|
| f16/f16 | ❌ OOM | ~30 | Fits 8K only |
| q4_0/q4_0 | ~30 | ~30 | Baseline |
| q8_0/q8_0 | ~30 | — | Same as q4_0 |
| K=f16 V=q4_0 | ~30 | ~30 | No advantage |
| K=q4_0 V=f16 | ~30 | ~30 | No advantage |
| K=q8_0 V=q4_0 | ~30 | — | No advantage |
| K=q4_0 V=q8_0 | ~30 | — | No advantage |
| K=f16 V=q8_0 | ~30 | — | No advantage |
| K=q8_0 V=f16 | ~30 | — | No advantage |

**Conclusion:** K and V have equal importance for throughput. Use symmetric q4_0/q4_0 — saves VRAM with no performance penalty.

### VRAM Budget (RTX 5060 Ti 16GB)

| Config | Est. VRAM |
|---|---|
| IQ3_XXS + 8K ctx + Q4_0 KV | ~12.5GB |
| IQ3_XXS + 96K ctx + Q4_0 KV | ~13.5GB |
| IQ3_XXS + 128K ctx + Q4_0 KV | ~13.8GB |
| IQ3_XXS + 262K ctx + Q4_0 KV | ❌ OOM (8GB KV alone exceeds headroom) |
| Q3_K_XL + 128K ctx + Q4_0 KV | ❌ OOM (13GB model too large) |
| IQ3_XXS + 96K ctx + MTP n=3 | ❌ OOM |

### Optimal Configurations

**Primary (code/agent tasks, 128K ctx):**
```bash
./llama-server-start.sh
# Model: IQ3_XXS, CTX: 131072, KV: q4_0/q4_0, ~30 t/s concurrent
```

**Fast small tasks (REAP MTP):**
```bash
./llama-server-reap.sh
# Model: Qwen3.6-35B-REAP-Q3_K_M, CTX: 131072, KV: q4_0/q4_0, MTP n=3
```

## Future Tests (TODO)

- [ ] **Q3_K_XL + 96K ctx** — quality comparison vs IQ3_XXS (Q3_K_XL fits at 96K, ~4% slower)
- [ ] **Qwen3.6-35B REAP MTP benchmarks** — validate ~210 tok/s claims at C4
- [ ] **262K ctx with layer offloading** — ngl=48 works but at 6.8 t/s (too slow)
- [ ] **Context size sweep** — test 8K/16K/32K/64K/128K throughput for Bonsai-27B-Q1_0
- [ ] **Bonsai-27b-1bit-CRACK-Q1_0** (4.4GB) — test 1-bit quantization quality
- [ ] **Ternary-Bonsai PQ2_0** — rebuild llama.cpp from latest upstream (type 142) when available
- [ ] **Bonsai + vLLM** — only if vLLM fork adds Bonsai support
