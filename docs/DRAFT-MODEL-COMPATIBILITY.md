# Draft Model Compatibility Analysis — Qwen3.6-35B MoE

**Date**: 2026-07-21
**Target Model**: Qwen3.6-35B-A3B-MoE (REAP, MTP, gated attention)
**Goal**: Find the best speculative decoding strategy for RTX 5060 Ti 16GB

---

## First Principles

A draft model works by proposing tokens that the target model then verifies. The key compatibility constraints are:

### 1. Tokenizer Must Match

The draft model's `lm_head` outputs logits over its own vocabulary. A `d2t` (draft-to-target) table maps draft tokens to target tokens. If vocabularies differ significantly, the `d2t` table degrades. Qwen3.6 uses the Qwen3 tokenizer — so drafts trained on Qwen3 tokenizer should be compatible.

### 2. Draft Must Read Target Hidden States Correctly

**EAGLE-3**: Reads hidden states from specific layer indices of the target model. It assumes a standard transformer architecture.

**DFlash**: Injects target model's K/V cache into the draft attention. Also assumes standard architecture.

**Qwen3.6's gated attention** (`attn_output_gate` + `swish`) creates hidden states that differ from standard Qwen3. A draft trained on standard Qwen3 will read "wrong" hidden states when attached to Qwen3.6. This doesn't mean zero acceptance — but acceptance will be lower than a matched pair.

### 3. Draft Must Be Trained for the Target

EAGLE-3 and DFlash drafts are **trained** against a specific target model. The training minimizes the divergence between draft and target predictions. A draft not trained for Qwen3.6 will have lower acceptance than one that was.

### 4. MTP Is Different

MTP heads are trained **into** the target model during pre-training. They are specifically aligned with Qwen3.6's architecture. No `d2t` mapping, no hidden state mismatch. MTP is the most compatible draft mechanism for Qwen3.6 by design.

---

## Available Draft Models

### MTP (draft-mtp) — RECOMMENDED

- **Source**: Built into Qwen3.6-35B-A3B-REAP-MTP model
- **Compatibility**: Perfect (native to model)
- **VRAM overhead**: Zero (heads already in model)
- **Acceptance rate**: ~64-68% at 96K ctx (from your benchmarks)
- **How to use**: `--spec-type draft-mtp --spec-draft-n-max 3`

No external draft model needed. Already validated at 7.9-8.1 t/s at 96K ctx.

---

### EAGLE-3 Draft Models

EAGLE-3 drafts are trained to predict the next token by reading hidden states from a target model. The key question is whether a draft trained on standard Qwen3 MoE works with Qwen3.6 MoE.

| Draft Model | Target Trained For | MoE? | Expected Compatibility |
|---|---|---|---|
| `AngelSlim/Qwen3-30B_moe_eagle3` | Qwen3-30B MoE (standard) | Yes | ⚠️ Uncertain — Qwen3.6 has gated attention |
| `Tengyunw/qwen3_30b_moe_eagle3` | Qwen3-30B MoE | Yes | ⚠️ Same issue |
| `AngelSlim/Qwen3-14B_eagle3` | Qwen3-14B dense | No | ❌ Different architecture (dense vs MoE) |
| `AngelSlim/Qwen3-8B_eagle3` | Qwen3-8B dense | No | ❌ Dense vs MoE mismatch |
| `AngelSlim/Qwen3-4B_eagle3` | Qwen3-4B dense | No | ❌ Dense vs MoE mismatch |

**The MoE EAGLE-3 drafts exist for Qwen3.6** (Qwen3-30B_moe_eagle3), but they are trained against standard Qwen3 MoE, not Qwen3.6 MoE. The architectural difference (gated attention) will reduce acceptance rates vs a matched pair.

**To convert for llama.cpp**:
```bash
python convert_hf_to_gguf.py AngelSlim/Qwen3-30B_moe_eagle3 \
    --target-model-dir Qwen/Qwen3-35B-A3B \
    --outtype bf16 --outfile qwen3-30b-moeeagle3.gguf
```

Then use: `--spec-type draft-eagle3 -md qwen3-30b-moeeagle3.gguf`

### DFlash Draft Models

DFlash produces a block of draft tokens in one forward pass, using target hidden states. Same compatibility concern as EAGLE-3.

| Draft Model | Target Trained For | Notes |
|---|---|---|
| `z-lab/Qwen3-4B-DFlash` | Qwen3-4B dense | ❌ Dense, will have poor acceptance on MoE |
| ? | Qwen3 MoE | ⚠️ No known Qwen3 MoE DFlash draft |

**The DFlash situation is worse**: we don't know of a DFlash draft trained for Qwen3 MoE, let alone Qwen3.6 MoE. A dense Qwen3-4B DFlash draft on a MoE target will likely have very poor acceptance.

### n-gram Methods — No External Model Needed

These methods use statistical patterns from already-generated text. They have **zero model compatibility concerns** because they don't use a separate model.

| Method | Draft Source | VRAM Overhead | Acceptance | Notes |
|---|---|---|---|---|
| `ngram-simple` | History | ~0 | Low-moderate | Best for repetitive tasks |
| `ngram-map-k` | History (hash map) | ~16MB | Moderate | Better than simple |
| `ngram-map-k4v` | History (4-value) | ~20MB | Moderate-high | More memory, better tracking |
| `ngram-mod` | Shared hash pool | ~16MB | Moderate | Shared across all slots |

n-gram methods work by finding matching n-gram patterns in the already-generated token history and using the tokens that followed those patterns as drafts. They require patterns to have already appeared.

---

## Systematic Testing Framework

### Phase 0: Draft Model Inventory

Before running throughput tests, catalog what's available and convert what's needed.

### Phase 1: Acceptance Rate Baseline

Measure acceptance rate (not just t/s) to understand draft quality:
- Draft acceptance rate = accepted / generated
- Per-token acceptance breakdown
- How acceptance changes with context length

### Phase 2: Per-Stream Throughput

Measure tokens-per-second for single-sequence generation.

### Phase 3: Total System Throughput

Measure aggregate throughput under concurrent load.

---

## Expected Outcomes (First Principles)

| Method | Acceptance | Per-Stream t/s | Total t/s (12x concurrent) | VRAM Overhead |
|---|---|---|---|---|
| MTP n-max=3 | ~65% | ~8-9 t/s @ 96K | ~96-108 t/s | 0 |
| MTP n-max=5 | ~50% | ~10-12 t/s @ 32K | ~120-144 t/s | 0 |
| EAGLE-3 (Qwen3 MoE) | ~40-55% (est.) | ~7-9 t/s | ~84-108 t/s | ~4-6GB |
| DFlash (Qwen3 dense) | ~20-30% (est.) | ~5-7 t/s | ~60-84 t/s | ~3-5GB |
| n-gram-mod | Varies | ~7-8 t/s | ~84-96 t/s | ~16MB |
| MTP + n-gram-mod | ~65% + ngram | ~8-10 t/s | ~96-120 t/s | ~16MB |

**Key insight**: MTP with higher n-max at smaller context may beat MTP at large context. The sweet spot depends on your use case.

---

## Smart Test Order

1. **MTP acceptance rate sweep** — establish the ceiling
2. **n-gram-mod sweep** — no external model needed
3. **EAGLE-3 MoE draft** — convert AngelSlim/Qwen3-30B_moe_eagle3, test
4. **EAGLE-3 vs MTP comparison** — does the larger draft compensate for architectural mismatch?
5. **Concurrent throughput** — the real-world metric
6. **Adaptive context** — dynamically select ctx based on request

---

## Notes

- **DSpark via llama.cpp**: Not implemented. DSpark requires the Avesed vLLM fork, not llama.cpp.
- **Qwen3.6 MoE + EAGLE-3**: The architectural mismatch (gated attention) means EAGLE-3 acceptance will be lower than the theoretical maximum. Empirical testing is the only way to know.
- **DFlash situation**: Worse than EAGLE-3 — no known MoE-compatible DFlash draft, and dense DFlash on MoE target will likely perform poorly.
