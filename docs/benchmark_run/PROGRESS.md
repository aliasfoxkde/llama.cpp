# Qwen3.8-27B Benchmark Progress - RTX 5060 Ti 16GB

## Hardware
- **GPU**: NVIDIA GeForce RTX 5060 Ti (16GB VRAM, Blackwell/sm_120)
- **Driver**: 610.57.04 / CUDA 13.3
- **CPU**: Intel i5-13600K (14 cores) / **RAM**: 31GB

---

## Phase 0: Environment [DONE]

## Phase 1: llama.cpp DFlash2 [COMPLETE]
- Baseline: 37.5 tok/s
- DFlash2 n_max=4: **60.5 tok/s** (+61%)

---

## Phase 2: Escha SGLang [IN PROGRESS]

### Configuration That Works
```bash
VENV=/home/mkinney/Repos/llama.cpp/sglang_test_env
MODEL=/home/mkinney/Models/EschaLabs/Qwen3.8-27B-Escha-W2
ATTN_BACKEND=triton
MEM=0.90
CTXLEN=16384
CUDA_GRAPH_BS="1 2 4 8"
GRAPHS=1
THINK=0
bash /tmp/escha-runtime/sglang/serve.sh
```

### Baseline (Single User, 31 tok/s)
| Context | tok/s |
|---------|-------|
| 8K | 31.3 |
| 16K | 31.1 |

### Throughput Scaling (16K)
| Concurrent | Aggregate tok/s |
|------------|-----------------|
| 1 | 31 |
| 2 | 54 |
| 4 | 110 |
| 8 | 187 |
| 16 | 299 |

### Context Sweep (TO DO)
- 24K, 32K, 48K, 64K

### DFlash2 Status
- lued/Qwen3.8-27B-DFlash2-W8 is for **vLLM only**, NOT SGLang
- Escha SGLang fork does not support DFlash2

### Workload Matrix (TO DO)
- Code, Math, Reasoning, Prose, JSON

### Quality Validation (TO DO)

---

## Push Status
4 commits ready, push blocked by GitHub auth.
