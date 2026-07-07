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

## System-Level Optimizations (July 7 2026)

### Applied Optimizations:

```bash
# CPU Governor - Set to performance mode
sudo sh -c 'for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo "performance" > $cpu; done'

# Transparent Huge Pages - Enabled always
sudo sh -c 'echo always > /sys/kernel/mm/transparent_hugepage/enabled'
sudo sh -c 'echo always > /sys/kernel/mm/transparent_hugepage/defrag'

# Swappiness - Already optimized at 10
# NUMA balancing - Already disabled
```

### Verification:
```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
# Output: performance

cat /sys/kernel/mm/transparent_hugepage/enabled
# Output: [always] madvise never
```

### Impact:
- CPU Governor: Set from `powersave` to `performance`
- THP: Enabled for better memory management
- Combined with -march=znver2 build gives ~10-12 t/s stable

### Other Tunables (Not Applied - Require Root or Reboot):
- `vm.swappiness` - Already at 10 (low swap usage)
- `mlock()` / MAP_HUGETLB - Would require rebuild
- jemalloc - Would require rebuild
- CPU affinity pinning - Can be done per-run with `taskset`
- `madvise(MADV_HUGEPAGE)` - Already active with THP

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

## KV Cache Quantization + Extended Context Results (July 7 2026)

### Breakthrough: KV Cache q4_0 Now Works!

Using the optimized -march=znver2 build, KV cache quantization (`-ctk q4_0 -ctv q4_0`) now works reliably. This allows much larger context sizes without OOM.

### Context Size Sweep Results (Qwen3.6-28B-REAP20-A3B-Q3_K_M + KV q4_0)

| Context | Speed (t/s) | Status | Notes |
|---------|-------------|--------|-------|
| 40K | 10.76 | ✅ Stable | Baseline with KV quant |
| 52K | 11.52 | ✅ Stable | |
| 56K | 11.86 | ✅ Stable | |
| 60K | 11.54 | ✅ Stable | |
| 61K | 10.76 | ✅ Stable | |
| 62K | 11.14 | ✅ Stable | |
| 63K | 11.34 | ✅ Stable | |
| **64K** | **12.02** | ✅ Stable | **Peak performance** |
| **65K** | **12.29** | ✅ Stable | **Best overall** |
| 66K | 11.08 | ✅ Stable | |
| 68K | 11.25 | ✅ Stable | |
| 70K | 10.53 | ✅ Stable | |
| 72K | 10.95 | ✅ Stable | |
| 74K | 10.96 | ✅ Stable | |
| 76K | 11.40 | ✅ Stable | |
| 78K | 10.60 | ✅ Stable | |
| 80K | 11.26 | ✅ Stable | |
| 82K | 10.62 | ✅ Stable | |
| 84K | 11.31 | ✅ Stable | |
| 86K | 10.12 | ✅ Stable | |
| 88K | 10.47 | ✅ Stable | |
| 90K | 10.61 | ✅ Stable | |
| 92K | 10.73 | ✅ Stable | |
| 94K | 10.82 | ✅ Stable | |
| 96K | 10.88 | ✅ Stable | **96K Achieved!** |
| 100K | 11.10 | ✅ Stable | |
| 110K | 10.70 | ✅ Stable | |
| 120K | 10.94 | ✅ Stable | |
| 128K | 10.43 | ✅ Stable | **128K Achieved!** |
| 140K | 10.09 | ✅ Stable | **140K Achieved!** |

### Key Findings:
1. **96K-140K context now stable** with KV cache q4_0 quantization
2. **Peak speed at 64K-65K**: ~12.3 t/s
3. **Speed remains decent at 128K**: ~10.4 t/s (only ~15% slower than peak)
4. **Speed at 140K**: ~10.1 t/s - still usable!
5. **No OOM failures** up to 140K tested

### Optimal Configurations:

#### Maximum Speed (64K context):
```bash
GGML_BACKEND=CPU llama-server \
  -m /nas/AI/Models/gguf/Qwen3.6-28B-REAP20-A3B/Qwen3.6-28B-REAP20-A3B-Q3_K_M.gguf \
  -t 12 -tb 12 --ctx-size 65536 \
  -ctk q4_0 -ctv q4_0 --no-warmup
# ~12.3 t/s
```

#### Maximum Context (140K stable):
```bash
GGML_BACKEND=CPU llama-server \
  -m /nas/AI/Models/gguf/Qwen3.6-28B-REAP20-A3B/Qwen3.6-28B-REAP20-A3B-Q3_K_M.gguf \
  -t 12 -tb 12 --ctx-size 143360 \
  -ctk q4_0 -ctv q4_0 --no-warmup
# ~10.1 t/s at 140K context
```

#### Balanced (96K context - hits user goal):
```bash
GGML_BACKEND=CPU llama-server \
  -m /nas/AI/Models/gguf/Qwen3.6-28B-REAP20-A3B/Qwen3.6-28B-REAP20-A3B-Q3_K_M.gguf \
  -t 12 -tb 12 --ctx-size 98304 \
  -ctk q4_0 -ctv q4_0 --no-warmup
# ~10.9 t/s at 96K context
```

---

## Optimization Attempts (20+ t/s Goal)

### Tests Performed:
1. ✅ **KV Cache Quantization (q4_0)**: Now working with -march=znver2 build
2. ✅ **Context size sweep 40K-140K**: All stable, 96K-140K achievable
3. ⚠️ **-march=znver2 build**: Works but may need optimization flags tuned
4. ❌ **Flash Attention**: Crashes on this build
5. ❌ **-ffast-math**: Conflicts with existing build flags

### Extended Context Results (July 7 2026):

| Context | Speed (t/s) | Status | Notes |
|---------|-------------|--------|-------|
| 150K | 8-9.4 | ✅ Stable | Heavy memory pressure |
| 160K | 3.04 | ✅ Stable | Cache thrashing |
| 180K | 2.77 | ✅ Stable | Very slow |
| 200K | 4.01 | ✅ Stable | Slow but works |
| 224K | 6.96 | ✅ Stable | Better at 224K |
| **262K** | **8.94** | ✅ Stable | **MAX - Model native ctx!** |

### Final Findings (July 7 2026):
- **96K context: ACHIEVED** at ~10.9 t/s ✅
- **128K context: ACHIEVED** at ~10.4 t/s ✅
- **140K context: ACHIEVED** at ~10.1 t/s ✅
- **262K context: ACHIEVED** at ~8.9 t/s ✅ **MODEL MAX CONTEXT!**
- **Peak speed 12.3 t/s** at 64K context
- **20 t/s goal**: Still requires more RAM or different hardware
- **Memory ceiling**: 32GB RAM limits context scaling

### Why 20+ t/s Requires More Than 32GB RAM:
The AMD 5700U APU has 32GB unified memory. With a 13GB model + KV cache at large contexts:
- Model weights: ~13GB
- KV cache (128K context, q4_0): ~4-6GB
- System overhead + buffers: ~4-6GB
- Total: Approaches 24-26GB leaving little headroom

For 20+ t/s with large context, would need either:
1. More RAM (64GB+) for larger KV cache without quantization
2. Desktop CPU with AVX-512 (Intel/AMD Zen 4)
3. GPU with dedicated VRAM (RTX 4080+)

### Recommendations:
1. **For maximum context**: Use 140K with q4_0 KV (~10 t/s)
2. **For balanced**: Use 96K at ~11 t/s
3. **For speed**: Use 64K at ~12.3 t/s
4. **For 20+ t/s**: Hardware upgrade needed (or use smaller model like LFM2.5-8B)

---

## Recommended Configs

### Maximum Context (Qwen3.6-28B-MoE, 140K):
```bash
GGML_BACKEND=CPU llama-server \
  -m /nas/AI/Models/gguf/Qwen3.6-28B-REAP20-A3B/Qwen3.6-28B-REAP20-A3B-Q3_K_M.gguf \
  -t 12 -tb 12 --ctx-size 143360 \
  -ctk q4_0 -ctv q4_0 --no-warmup
# ~10.1 t/s at 140K context
```

### Balanced (Qwen3.6-28B-MoE, 96K):
```bash
GGML_BACKEND=CPU llama-server \
  -m /nas/AI/Models/gguf/Qwen3.6-28B-REAP20-A3B/Qwen3.6-28B-REAP20-A3B-Q3_K_M.gguf \
  -t 12 -tb 12 --ctx-size 98304 \
  -ctk q4_0 -ctv q4_0 --no-warmup
# ~10.9 t/s at 96K context
```

### Maximum Context (Qwen3.6-28B-MoE, 262K - Model Max!):
```bash
GGML_BACKEND=CPU llama-server \
  -m /nas/AI/Models/gguf/Qwen3.6-28B-REAP20-A3B/Qwen3.6-28B-REAP20-A3B-Q3_K_M.gguf \
  -t 12 -tb 12 --ctx-size 262144 \
  -ctk q4_0 -ctv q4_0 --no-warmup
# ~8.9 t/s at 262K context (MODEL MAX!)
```

### Maximum Speed (Qwen3.6-28B-MoE, 64K):
```bash
GGML_BACKEND=CPU llama-server \
  -m /nas/AI/Models/gguf/Qwen3.6-28B-REAP20-A3B/Qwen3.6-28B-REAP20-A3B-Q3_K_M.gguf \
  -t 12 -tb 12 --ctx-size 65536 \
  -ctk q4_0 -ctv q4_0 --no-warmup
# ~12.3 t/s at 64K context
```

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

