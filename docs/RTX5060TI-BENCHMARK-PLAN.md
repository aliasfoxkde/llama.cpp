# RTX 5060 Ti 16GB Benchmark Plan

**Date**: 2026-07-21
**Hardware**: NVIDIA RTX 5060 Ti 16GB (Blackwell GB206), CUDA 12.9+, Driver 570+
**Model**: Qwen3.6-35B-A3B-REAP-MTP (GGUF Q3_K_M)
**Goal**: Systematic throughput/latency characterization — find the sweet spot

---

## Hardware Details

| Specification | Value |
|---|---|
| GPU | NVIDIA RTX 5060 Ti 16GB |
| Architecture | Blackwell (GB206) |
| VRAM | 16GB GDDR7 |
| Memory Bus | 128-bit |
| CUDA | 12.9+ for Blackwell |
| Driver | 570+ |

---

## Executive Summary of Research

### DSpark on llama.cpp
**DSpark is NOT available in llama.cpp.** It is a DeepSeek framework requiring the Avesed vLLM fork. llama.cpp supports: MTP, EAGLE-3, DFlash, and n-gram methods.

### Draft Model Compatibility for Qwen3.6 MoE

| Draft Type | Compatible? | Notes |
|---|---|---|
| **MTP** (native) | ✅ Perfect | Built into REAP-MTP model, zero overhead |
| **EAGLE-3 (Qwen3 MoE)** | ⚠️ Uncertain | Trained for standard Qwen3 MoE, Qwen3.6 has gated attention (attn_output_gate, swish) — mismatch will reduce acceptance |
| **DFlash (Qwen3 dense)** | ❌ Poor expected | No MoE DFlash drafts known; dense-on-MoE will have low acceptance |
| **n-gram methods** | ✅ Yes | No external model needed; works on pattern matching |

### NVFP4 Analysis
NVFP4 is weight-only quantization (4-bit weights, FP16 compute). It reduces **weight storage** but NOT activation memory. At 128K context, activation/KV cache dominates VRAM. NVFP4 does NOT free enough VRAM for DSpark on 16GB.

**GGUF Q3_K_M (13.4GB) + KV q4_1 is the sweet spot** — already validated at 95-155 t/s.

### VRAM Budget on RTX 5060 Ti 16GB

| Component | Memory |
|---|---|
| Model (Q3_K_M) | ~13.4 GB |
| KV cache (32K, q4_1) | ~1.5 GB |
| Activations + overhead | ~0.5 GB |
| **Total at 32K ctx** | **~15.4 GB** |
| **Headroom** | **~0.6 GB** |

At 128K ctx, KV cache alone is ~6GB. VRAM is the binding constraint.

---

## Test Philosophy

Test in this order — each phase answers a specific question:

1. **Phase 0**: What draft models can we even get?
2. **Phase 1**: What is the per-stream ceiling? (single request, best t/s)
3. **Phase 2**: What is the total system throughput? (12 concurrent requests)
4. **Phase 3**: Is there a ctx/speed tradeoff? (sweep ctx sizes)
5. **Phase 4**: Does draft model + Qwen3.6 work? (acceptance rate measurement)
6. **Phase 5**: What is the adaptive sweet spot? (ctx selection logic)

---

## Phase 0: Draft Model Inventory

Objective: Get all available draft models converted and catalogued.

### Draft Models to Obtain

```bash
# EAGLE-3 MoE draft (for Qwen3.6 MoE target)
# Trained on Qwen3-30B MoE — may have acceptance issues due to gated attention
huggingface-cli download AngelSlim/Qwen3-30B_moe_eagle3 --local-dir ./draft-models/Qwen3-30B_moe_eagle3
huggingface-cli download Tengyunw/qwen3_30b_moe_eagle3 --local-dir ./draft-models/qwen3_30b_moe_eagle3

# EAGLE-3 dense drafts (for comparison — will have poor MoE acceptance)
huggingface-cli download AngelSlim/Qwen3-14B_eagle3 --local-dir ./draft-models/Qwen3-14B_eagle3
huggingface-cli download AngelSlim/Qwen3-8B_eagle3 --local-dir ./draft-models/Qwen3-8B_eagle3
```

### Convert for llama.cpp

```bash
# EAGLE-3 MoE (Qwen3-30B MoE on Qwen3-35B target)
python convert_hf_to_gguf.py ./draft-models/Qwen3-30B_moe_eagle3 \
    --target-model-dir Qwen/Qwen3-35B-A3B \
    --outtype bf16 --outfile ./draft-models/Qwen3-30B_moe_eagle3.gguf

# EAGLE-3 dense (8B dense on 35B MoE target — will have mismatch)
python convert_hf_to_gguf.py ./draft-models/Qwen3-8B_eagle3 \
    --target-model-dir Qwen/Qwen3-35B-A3B \
    --outtype bf16 --outfile ./draft-models/Qwen3-8B_eagle3.gguf
```

### Script to Run
```bash
./scripts/benchmarks/rtx5060ti-draft-convert.sh
```

---

## Phase 1: Per-Stream Throughput Sweep

Objective: Establish per-stream t/s ceiling for each config.

### Variables

| Variable | Values |
|---|---|
| Context size | 4K, 8K, 16K, 32K, 64K, 96K, 128K |
| MTP n-max | 0, 3, 5, 7 |
| KV quant | q4_0, q4_1, q5_0 |
| Batch (tb/ub) | 256/128, 512/256, 1024/512 |

### Fixed

| Parameter | Value |
|---|---|
| Model | Qwen3.6-35B-A3B-UD-Q3_K_XL-REAP.gguf |
| NGL | 99 (all) |
| Temperature | 0 |
| Draft | MTP (native) |

### Expected Output
`results/rtx5060ti/llama-per-stream-${TIMESTAMP}.csv`

### Key Question
**What ctx size + MTP n-max gives the best per-stream t/s?**

Likely answer: Smaller ctx + higher MTP n-max wins for per-stream.

---

## Phase 2: Acceptance Rate Measurement

Objective: Measure draft acceptance rate for each speculative method.

### What to Measure

For each config, capture from server stats:
- `draft acceptance rate = accepted / generated`
- `#gen drafts`, `#acc drafts`
- `#gen tokens`, `#acc tokens`
- `dur(b,g,a)` — begin, generation, accumulation times

### Methods to Test

| Method | Config |
|---|---|
| MTP | `--spec-type draft-mtp --spec-draft-n-max 3` |
| MTP | `--spec-type draft-mtp --spec-draft-n-max 5` |
| MTP | `--spec-type draft-mtp --spec-draft-n-max 7` |
| n-gram-mod | `--spec-type ngram-mod` |
| n-gram-simple | `--spec-type ngram-simple` |
| EAGLE-3 (if converted) | `--spec-type draft-eagle3 -md <path>` |

### Key Questions
1. Does MTP acceptance drop significantly at larger ctx?
2. Does EAGLE-3 (Qwen3 MoE draft) have acceptable acceptance on Qwen3.6 MoE target?
3. Is n-gram-mod better than MTP at certain ctx sizes?

---

## Phase 3: Concurrent System Throughput

Objective: Measure total t/s under realistic load (12 concurrent sessions).

### The Real-World Metric

Per-stream t/s doesn't matter for a busy server. What matters is:
- Total tokens generated per second across all concurrent requests
- Latency per request under load
- How the system degrades as concurrency increases

### Sweep

| Concurrency | 4 | 8 | 12 | 16 |
|---|---|---|---|---|
| Best per-stream config | t/s | t/s | t/s | t/s |
| MTP off | t/s | t/s | t/s | t/s |
| MTP n-max=3 | t/s | t/s | t/s | t/s |
| n-gram-mod | t/s | t/s | t/s | t/s |

### Key Question
**At what concurrency does MTP overhead stop paying off?**

If MTP adds 20% overhead but only improves acceptance by 10%, at high concurrency the overhead dominates.

---

## Phase 4: Draft Model Comparison

Objective: Does EAGLE-3 (Qwen3 MoE) work acceptably on Qwen3.6 MoE?

### Test Matrix

| Target | Draft | Acceptance | t/s | Notes |
|---|---|---|---|---|
| Qwen3.6-35B-MoE | MTP (native) | ~65% | ~8 t/s | Baseline |
| Qwen3.6-35B-MoE | EAGLE-3 Qwen3-30B MoE | ? | ? | Gated attention mismatch |
| Qwen3.6-35B-MoE | EAGLE-3 Qwen3-8B dense | ? | ? | Dense-on-MoE, expect poor |
| Qwen3.6-35B-MoE | n-gram-mod | ? | ? | Pattern-based |
| Qwen3.6-35B-MoE | none | N/A | ~7 t/s | No speculative |

### Key Question
**Is the EAGLE-3 MoE draft better than MTP despite the architectural mismatch?**

---

## Phase 5: Adaptive Context Selector

Objective: Build a smarter server that selects ctx dynamically.

### The Idea

For each request, estimate the optimal ctx based on:
- Prompt length
- Requested max_tokens
- Available VRAM
- Current load

### Strategy

| Scenario | Optimal ctx | MTP n-max | Reason |
|---|---|---|---|
| Short prompt + short response | 4K | 7 | Fast, MTP helps |
| Long prompt + short response | 96K | 3 | Need ctx for prompt, minimal MTP |
| Short prompt + long response | 4K | 7 | MTP helps generation |
| Long prompt + long response | 128K | 3 | Context dominates, MTP overhead not worth it |
| High concurrency | 32K | 0 | Maximize throughput, no speculative overhead |

### Script
```bash
./scripts/benchmarks/rtx5060ti-adaptive-bench.sh
```

---

## Scripts

| Script | Purpose |
|---|---|
| `rtx5060ti-draft-convert.sh` | Phase 0: Download and convert EAGLE-3 draft models |
| `rtx5060ti-llama-bench.sh` | Phases 1-4: llama.cpp sweep (all config combos) |
| `rtx5060ti-acceptance-bench.sh` | Phase 2: Acceptance rate measurement |
| `rtx5060ti-concurrent-bench.sh` | Phase 3: Concurrent throughput sweep |
| `rtx5060ti-adaptive-bench.sh` | Phase 5: Adaptive context selector |
| `rtx5060ti-vllm-bench.sh` | vLLM: Avesed fork DSpark, upstream comparison |
| `run-all-benchmarks.sh` | Master runner |

---

## Implementation Steps

1. Pull latest `feature/apu-benchmarks-2026` branch
2. Run Phase 0: Download and convert EAGLE-3 drafts
3. Run Phase 1: Per-stream sweep
4. Run Phase 2: Acceptance rate measurement
5. Run Phase 3: Concurrent throughput
6. Run Phase 4: Draft model comparison
7. Run Phase 5: Adaptive context
8. Run vLLM benchmarks (Avesed DSpark vs upstream)
9. Compile results into `docs/RTX5060TI-BENCHMARKS.md`
10. Commit and push

---

## Notes

- Run each config at least 3 times — MTP has stochastic elements
- Monitor VRAM: `nvidia-smi` during each run — watch for OOM at high concurrency
- Acceptance rate is the key metric for draft quality, not raw t/s
- The "best" config depends on your use case: interactive vs batch vs mixed
