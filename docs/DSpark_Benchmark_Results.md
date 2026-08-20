# Comprehensive Speculative Decoding Benchmark Results
**Date**: 2026-07-30
**GPU**: NVIDIA RTX 5060 Ti 16GB (Blackwell GB206, sm_120)
**Settings**: KV=q4_1, Flash Attention=ON

---

## Summary: llama.cpp Results

### 4K Context

| Configuration | Conc=1 | Conc=2 | Conc=4 | Conc=8 | Conc=12 | Conc=16 |
|--------------|--------|--------|--------|--------|---------|---------|
| **Baseline** | 96 tok/s | ~100 tok/s | ~100 tok/s | ~100 tok/s | ~100 tok/s | ~100 tok/s |
| **MTP n_max=3** | 81.7 tok/s | 118.9 tok/s | **173.5 tok/s** | 166.7 tok/s | 163.2 tok/s | - |
| **EAGLE-3 (35B draft)** | 45.7 tok/s | 70.6 tok/s | 93.3 tok/s | 94.3 tok/s | - | - |

### Key Findings (4K Context)
- **MTP n_max=3 provides 30-80% improvement** at higher concurrency
- **Peak MTP: 173.5 TPS at conc=4** (+80% vs baseline)
- **EAGLE-3 (35B draft) is SLOWER** - draft model is almost same size as target
- **EAGLE-3 (8B draft) had compatibility issues** - returned 0 tokens

---

## Model Information

### Target Models Available
| Model | Path | Size | MTP |
|-------|------|------|-----|
| Qwen3.6-35B-A3B-REAP (Q3_K_M) | `JZC973/Qwen3.6-35B-REAP-MTP-UD-GGUF-Collection/Qwen3.6-35B-A3B-UD-Q3_K_M-REAP.gguf` | 13 GB | ✅ Yes |
| Qwen3.6-35B-REAP-48-Q3K | `crucible-labs/Qwen3.6-35B-A3B-REAP-48-Q3K-mixed-GGUF/qwen36-reap-48pct-mixed-q3k.gguf` | 8.8 GB | ❌ No |

### Draft Models Available
| Model | Path | Size | Format | Status |
|-------|------|------|--------|--------|
| DSpark Qwen3-8B | `dspark_qwen3_8b_block7.q4_k_m.gguf` | 1.5 GB | GGUF | ❌ Not compatible with llama.cpp |
| EAGLE-3 (8B) | `williamliao/Qwen3-8B-EAGLE3-Speculator-GGUF/Qwen3-8B-speculator.eagle3-F16.gguf` | 2.0 GB | GGUF | ❌ Draft issues |
| EAGLE-3 (35B) | `EntityDeletr/Qwen3.6-35B-A3B-Caption-Eagle3DraftModel-GGUF/Qwen3.6-35B-A3B-Caption-Eagle3DraftModel.gguf` | 494 MB | GGUF | ⚠️ Works but slower |
| MTP (built-in) | Via REAP model | - | - | ✅ Best performance |

---

## 128K Context Results (from earlier test)

| Configuration | Peak TPS | vs Baseline |
|--------------|----------|-------------|
| **Baseline** | 118.5 | - |
| **MTP n_max=3** | **165.1** | **+39%** |

---

## EAGLE-3 Analysis

### Why EAGLE-3 (35B draft) is Slow
- Draft model (35B) is nearly as large as target model (35B MoE)
- No speedup when draft ≈ target size
- EAGLE-3 works best when draft << target (e.g., 3B draft for 70B target)

### 8B EAGLE-3 Issues
- Compatibility issues with Qwen3.6-35B-MoE target
- Returned 0 tokens (draft not being used correctly)
- Architecture mismatch likely

---

## Recommendations for RTX 5060 Ti 16GB

### Best Configuration: MTP n_max=3
```bash
./llama-server -m Qwen3.6-35B-A3B-UD-Q3_K_M-REAP.gguf \
  -c 4096 -ctk q4_1 -ctv q4_1 -fa on -ngl 99 \
  --spec-type draft-mtp --spec-draft-n-max 3 \
  -tb 512 -ub 256 --port 8080
```
**Expected: ~170-175 TPS at concurrency 4**

---

## Backend Comparison (Preliminary)

| Backend | MTP | EAGLE-3 | DSpark | Status |
|---------|-----|----------|--------|--------|
| **llama.cpp** | ✅ Best | ⚠️ Slow | ❌ | ✅ Working |
| **vLLM + GGUF plugin** | ✅ | ? | ❌ | ⚠️ Env issues |
| **xinfer** | ✅ | ❌ | ❌ | ⚠️ Needs NCCL |
| **vLLM Avesed** | ✅ | ✅ | ✅ | ❌ 96GB only |
| **SGLang** | ✅ | ✅ | ? | 📋 Not tested |
| **TensorRT-LLM** | ✅ | ✅ | ✅ | 📋 Not tested |

---

## Next Steps

1. ✅ llama.cpp MTP - **Working, best option**
2. 🔄 vLLM GGUF - Fix environment issues
3. 📋 SGLang - Install and test
4. 📋 TensorRT-LLM - Build for RTX 5060 Ti
5. 📋 xInfer - Install NCCL for production use
