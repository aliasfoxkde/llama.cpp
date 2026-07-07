# llama.cpp Benchmark Report - AMD 5700U APU
**Date**: July 6, 2026  
**System**: AMD Ryzen 7 5700U (8C/16T) + Radeon Graphics (Lucienne) APU  
**RAM**: 32GB DDR4 | **Vulkan**: RADV RENOIR  
**Build**: llama.cpp b9878-2da668617 + Vulkan backend

---

## Key Findings

### CRITICAL: GPU Layers SLOW Down Inference on This APU

The AMD 5700U APU has **unified shared memory** between CPU and GPU. This means:
- GPU offloading incurs **memory transfer overhead** that often exceeds the compute benefit
- **CPU-only is almost always faster** for these workloads
- Exception: models large enough that GPU compute helps but data still fits in unified memory

### Performance Rankings (Verified July 2026)

| Rank | Model | Size | Config | Gen t/s | Notes |
|------|-------|------|--------|---------|-------|
| 🥇 | MiniCPM-1B | 657MB | CPU-12t | **43.2** | ✅ Optimal params |
| 🥈 | MiniCPM-V-4.6 | 505MB | CPU-12t | **33.0** | Vision model |
| 🥉 | LFM2.5-8B MoE | 5GB | CPU-8t | **14.8** | Best coding |
| 4 | Qwen3.6-28B-MoE Q3_K_M | 13GB | CPU-12t ctx4096 | **11.4** | ✅ Best 28B result |
| 5 | Qwen3.6-28B MoE A3B | 17GB | CPU-12t | **9.5** | Q4_K_M quant |
| 6 | Qwen3.5-4B | 2.8GB | CPU-12t | **8.5** | 2.4x faster than 8t |
| 7 | Qwen3.6-35B-A3B MoE | 21GB | CPU-12t | **3.6** | Memory pressure |
| 8 | Qwen3.6-27B Dense | 16GB | CPU-12t | **1.6** | ❌ Too large for 32GB RAM |

### New Models Tested (July 6 2026)

| Model | Size | Best Speed | Notes |
|-------|------|-----------|-------|
| Qwen3.6-28B-REAP20-A3B-Q3_K_M | 13GB | **11.4 t/s** | ctx4096, 12 threads |
| Qwen3.6-28B-REAP.i1-Q3_K_M | 13GB | **8.0 t/s** | REAP-i1 variant |
| Ornith-1.0-9B-heretic-MTP-Q6_K | 7.1GB | **4.7 t/s** | |
| Ornith-1.0-9B-MTP-Q5_K_M | 6.2GB | **4.7 t/s** | |

### Critical Model Issues

| Model | Issue |
|-------|-------|
| Qwen3.6-35B-REAP-RangerX | **GARBLED OUTPUT** - tokenizer/embedding failure |
| Qwen3.6-27B Dense | ❌ 16GB model too large for 32GB RAM - memory pressure causes 1.6 t/s |

---

## Detailed Results

### MiniCPM5-1B-Q4_K_M (657MB)
**BEST FOR: Maximum speed text generation**

| Config | Load Time | Wall Time | Gen t/s | Notes |
|--------|-----------|----------|---------|-------|
| CPU-12t | ~9s | ~3.4s | **43.2** | ✅ Optimal (5 runs avg) |

Run breakdown:
- Run 1: 49.3 t/s
- Run 2: 42.2 t/s
- Run 3: 44.6 t/s
- Run 4: 36.2 t/s
- Run 5: 43.9 t/s

### MiniCPM-V-4.6-Q4_K_M (505MB)
**BEST FOR: Vision + text, multimodal**

| Config | Load Time | Wall Time | Gen t/s | Notes |
|--------|-----------|----------|---------|-------|
| CPU-12t | ~24s | ~1.3s | **33.0** | ✅ Text-only test |

### Qwen3.5-4B-Q4_K_M (2.8GB)

| Config | Load Time | Wall Time | Gen t/s | Notes |
|--------|-----------|----------|---------|-------|
| CPU-12t | ~12s | ~17.9s | **8.5** | ✅ 2.4x faster than 8t |
| CPU-8t | ~21s | ~17.9s | **3.6** | Old baseline |

### Qwen3.6-28B-REAP-MTP-A3B-Q4_K_M (17GB MoE A3B)

| Config | Load Time | Wall Time | Gen t/s | Notes |
|--------|-----------|----------|---------|-------|
| CPU-12t | ~3min | ~10s | **9.5** | ✅ With optimal params |

Run breakdown:
- Run 1: 8.64 t/s
- Run 2: 10.08 t/s
- Run 3: 8.74 t/s
- Run 4: 10.20 t/s
- Run 5: 10.10 t/s
- **Avg: 9.5 t/s**

### Qwen3.6-35B-A3B-UD-Q4_K_M (21GB MoE A3B)
**NOTE**: Model too large for 32GB RAM without heavy swap pressure

| Config | Load Time | Wall Time | Gen t/s | Notes |
|--------|-----------|----------|---------|-------|
| CPU-12t | ~4min | ~20s | **3.6** | Memory pressure |

### Qwen3.6-27B-Q4_K_M (16GB Dense)
**STATUS: TOO LARGE** - 16GB model causes memory pressure on 32GB RAM system

| Config | Load Time | Wall Time | Gen t/s | Notes |
|--------|-----------|----------|---------|-------|
| CPU-12t | ~5min | ~50s | **1.6** | ❌ Swap thrashing |

### LFM2.5-8B-A1B-Q4_K_XL (5GB MoE 8B/1B)
**BEST FOR: General coding tasks**

| Config | Load Time | Wall Time | Gen t/s | Notes |
|--------|-----------|----------|---------|-------|
| CPU-8t | ~76s | 5288ms | **14.8** | ✅ Fastest overall |
| GPU-40l | ~7s | 5338ms | **12.9** | GPU overhead hurts |

---

## AMD 5700U Optimization

### OPTIMAL Parameters (from sweep script analysis):
```bash
GGML_BACKEND=CPU llama-server \
  -m <model> \
  -t 12 -tb 12 \
  --ctx-size 4096 -b 256 -ub 128
```

### For This Hardware (Unified Memory APU):
1. **Always use CPU-only**: `GGML_BACKEND=CPU` or `--n-gpu-layers 0`
2. **12 threads is optimal**: Using all available threads (not just 8)
3. **Batch sizes matter**: `-b 256 -ub 128` improves throughput significantly
4. **Avoid GPU layers**: Transfer overhead > compute benefit for models <10GB
5. **Model size matters**: Models > 16GB cause memory pressure and slow inference

### General:
1. **Use MoE models**: LFM2.5-8B (14.8 t/s) >> dense 4B (8.5 t/s)
2. **Smaller models win**: 657MB MiniCPM at 43 t/s beats larger models
3. **Avoid large dense models**: 35B/28B too slow on this APU

---

## Storage I/O Findings

### NAS Performance:
- **NAS read speed**: ~383 MB/s (via btrfs on /dev/sda1)
- **tmpfs (RAM)**: Available at /tmp with 16GB capacity
- Models on NAS load without significant I/O bottleneck

### Impact on Inference:
- Model loading from NAS: One-time cost, acceptable for large models
- Inference speed: **NOT I/O bound** once model is in memory
- **Memory pressure is the real bottleneck** for large models (>16GB on 32GB RAM)

### Recommendation:
- Keep models on NAS (sufficient I/O)
- Ensure adequate free RAM for model + KV cache
- Use tmpfs only for small models if needed

---

## Missing / Needed

### Models (DOWNLOADED July 6 2026):
- ✅ **Qwen3.6-35B-A3B MoE**: `/nas/AI/Models/gguf/Qwen3.6-35B-A3B-MoE/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf` (21GB)
- ✅ **Qwen3.6-27B Dense**: `/nas/AI/Models/gguf/Qwen3.6-27B-Dense/Qwen3.6-27B-Q4_K_M.gguf` (16GB)
- ✅ **Qwen3.6-28B-REAP20-A3B-Q3_K_M**: `/nas/AI/Models/gguf/Qwen3.6-28B-REAP20-A3B/Qwen3.6-28B-REAP20-A3B-Q3_K_M.gguf` (13GB)
- ✅ **Qwen3.6-28B-REAP.i1-Q3_K_M**: `/nas/AI/Models/gguf/Qwen3.6-28B-REAP-i1/Qwen3.6-28B-REAP.i1-Q3_K_M.gguf` (13GB)
- ✅ **Ornith-1.0-9B-heretic-MTP-Q6_K**: `/nas/AI/Models/gguf/Ornith-1.0-9B-heretic-MTP/Ornith-1.0-9B-heretic-MTP-Q6_K.gguf` (7.1GB)
- ✅ **Ornith-1.0-9B-MTP-Q5_K_M**: `/nas/AI/Models/gguf/Ornith-1.0-9B-MTP/Ornith-1.0-9B-MTP-Q5_K_M.gguf` (6.2GB)

---

## Optimization Attempts (20+ t/s Goal)

### Tests Performed:
1. **Rebuild with -march=znver2**: Build failed due to -ffast-math conflict
2. **Flash Attention**: Crashes on this build
3. **KV Cache Quantization (q4_0)**: Build crashes when using -ctk q4_0
4. **Context size**: ctx 2048 slightly slower than ctx 4096 (10.4 vs 11.4 t/s)
5. **Thread counts**: Results variable, 12 threads most stable

### Findings:
- **System load affects results significantly** (0.6-12 t/s for same config)
- **Best achievable on 5700U**: ~11.4 t/s for 13GB MoE model
- **To achieve 20+ t/s** would require:
  - Properly optimized build with `-march=znver2`
  - Or different model (smaller MoE like LFM2.5-8B at 14.8 t/s)
  - Or more powerful hardware

### Recommendations:
1. **For speed**: Use LFM2.5-8B-MoE (14.8 t/s) or MiniCPM-1B (43 t/s)
2. **For quality with decent speed**: Qwen3.6-28B-MoE at 11.4 t/s is best balance
3. **Hardware upgrade needed**: For 20+ t/s with 13GB model, consider desktop AMD (Zen 4+) or Intel with more cores
- **BeeLlama.cpp fork**: TCQ is CUDA-only (no AMD), DFlash needs conversion

---

## Recommended Configs

### Maximum Speed (MiniCPM-1B):
```bash
GGML_BACKEND=CPU llama-server \
  -m /nas/AI/Models/benchmarks/minicpm5/minicpm5-1b-Q4_K_M.gguf \
  -t 12 -tb 12 --ctx-size 4096 -b 256 -ub 128
# ~43 t/s
```

### Vision + Text (MiniCPM-V-4.6):
```bash
GGML_BACKEND=CPU llama-server \
  -m /nas/AI/Local/models/MiniCPM-V-4.6/model.gguf \
  --mmproj /nas/AI/Local/models/MiniCPM-V-4.6/mmproj.gguf \
  -t 12 -tb 12 --ctx-size 4096 -b 256 -ub 128 --jinja
# ~33 t/s
```

### Fast Coding (LFM2.5-8B MoE):
```bash
GGML_BACKEND=CPU llama-server \
  -m /nas/AI/models/LFM2.5-8B-A1B-Q4_K_XL.gguf \
  -t 12 -tb 12 --ctx-size 4096 -b 256 -ub 128
# ~15 t/s
```

### Quality (Qwen3.5-4B):
```bash
GGML_BACKEND=CPU llama-server \
  -m /nas/AI/Models/benchmarks/qwen35-mtp/Qwen3.5-4B-Q4_K_M.gguf \
  -t 12 -tb 12 --ctx-size 4096 -b 256 -ub 128
# ~8.5 t/s
```

---

## Next Steps

1. **Download Qwen3.6 35B A3B MoE** - likely much faster than 28B MoE
2. **Test MTP speculative decoding** with stable server
3. **Fix 35B garbled output** - may need different quantization
4. **Try BeeLlama.cpp** DFlash if converted model available

