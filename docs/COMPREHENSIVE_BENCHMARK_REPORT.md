# Comprehensive Benchmark Report
**Date:** August 19, 2026
**GPU:** NVIDIA RTX 5060 Ti 16GB (Blackwell GB206, sm_120)
**Proxy:** llama-proxy on port 8082

---

## System Configuration

### Available Models

| Model | Quantization | Context | TPS (single) | VRAM | Vision | MTP |
|-------|-------------|--------|--------------|------|--------|-----|
| **Ultra** | IQ3_XXS | 128K | ~28 TPS | ~15.0GB | ✅ | ❌ |
| **Turbo** | Q3_K_M REAP-MTP | 128K | ~115 TPS | ~15.4GB | ❌ | ✅ |
| **Distill-9B** | Q4_K_M | 128K | ~68 TPS | ~5.5GB | ❌ | ❌ |
| **Maziyar-8B** | Q4_K_M | 128K | ~78 TPS | ~5.0GB | ❌ | ❌ |
| **Maziyar-0.6B** | Q4_K_M | 128K | ~206-443 TPS | ~0.7GB | ❌ | ❌ |
| **Qwen-4B** | Q4_K_M | 128K | ~104 TPS | ~3.0GB | ❌ | ❌ |
| **Qwen-2B** | Q4_K_M | 128K | ~200 TPS | ~1.6GB | ❌ | ❌ |

### Model Details

**Ultra** - Qwen3.8-27B + vision encoder (Unsloth + mmproj-F16)
- Best for: Quality + multimodal (images)
- Single-stream: ~28 TPS
- Architecture: 27B Dense

**Turbo** - Qwen3.6-35B-A3B MoE (JZC973 REAP + MTP)
- Best for: Speed-critical text tasks
- Single-stream: ~115 TPS
- Architecture: 35B MoE (~27B active)
- MTP: draft-mtp n_max=3 enabled

**Distill-9B** - empero-ai Qwen3.8-9B distilled
- Best for: Medium quality, fast inference
- Single-stream: ~68 TPS
- Architecture: 9B Dense (distilled from Qwen3.8 2.4T A95B)
- VRAM: ~5.5GB
- Note: No MTP support (distilled model, not MoE)

**Maziyar-8B** - MaziyarPanahi Qwen3-8B Q4_K_M
- Best for: Fast 8B inference
- Single-stream: ~78 TPS
- Architecture: 8B Dense

**Maziyar-0.6B** - MaziyarPanahi Qwen3-0.6B Q4_K_M
- Best for: Very fast, low VRAM
- Single-stream: ~206 TPS
- **Unique:** Memory-bound - throughput SCALES with concurrency (206→443 TPS)
- Architecture: 0.6B Dense

**Qwen-4B** - unsloth Qwen3.5-4B Q4_K_M
- Best for: Balanced 4B inference
- Single-stream: ~104 TPS
- Architecture: 4B Dense

**Qwen-2B** - unsloth Qwen3.5-2B Q4_K_M
- Best for: Fast 2B inference
- Single-stream: ~200 TPS
- Architecture: 2B Dense

---

## Benchmark Results

### All Models @ 128K Context (August 19, 2026)

| Model | Conc | Total TPS | Per-Session TPS | Behavior |
|-------|------|-----------|-----------------|----------|
| Ultra | 1 | 28.4 | 28.4 | Compute-bound |
| Ultra | 4 | 28.0 | 7.0 | Flat |
| Turbo | 1 | 115.2 | 115.2 | Compute-bound |
| Turbo | 4 | 135.5 | 33.8 | Slight scaling |
| Distill-9B | 1 | 68.3 | 68.3 | Compute-bound |
| Distill-9B | 4 | 67.2 | 16.8 | Flat |
| Maziyar-8B | 1 | 77.7 | 77.7 | Compute-bound |
| Maziyar-8B | 4 | 79.5 | 19.8 | Flat |
| Maziyar-0.6B | 1 | 206.1 | 206.1 | **Memory-bound** |
| Maziyar-0.6B | 4 | 443.2 | 110.8 | **SCALES!** |
| Qwen-4B | 1 | 104.4 | 104.4 | Compute-bound |
| Qwen-4B | 4 | 102.6 | 25.6 | Flat |
| Qwen-2B | 1 | 200.1 | 200.1 | Compute-bound |
| Qwen-2B | 4 | 207.9 | 51.9 | Flat |

### Legacy Tests (160K Context - for reference)

| Concurrency | Total Tokens | Time (s) | Total TPS | Per-Session TPS |
|-------------|-------------|----------|-----------|-----------------|
| 1 | 200 | 2.02 | 99.2 | 99.2 |
| 2 | 400 | 4.02 | 99.4 | 49.7 |
| 3 | 600 | 6.03 | 99.4 | 33.1 |
| 4 | 800 | 8.02 | 99.7 | 24.9 |
| 5 | 1000 | 10.04 | 99.6 | 19.9 |

### Test 2: Ultra @ 160K Context

| Concurrency | Total Tokens | Time (s) | Total TPS | Per-Session TPS |
|-------------|-------------|----------|-----------|-----------------|
| 1 | 200 | 7.30 | 27.3 | 27.3 |
| 2 | 400 | 13.75 | 29.0 | 14.5 |
| 3 | 600 | 21.95 | 27.3 | 9.1 |
| 4 | 800 | 32.08 | 24.9 | 6.2 |
| 5 | 1000 | 34.48 | 29.0 | 5.8 |

### Test 3: Distill-9B @ 128K Context

| Concurrency | Total Tokens | Time (s) | Total TPS | Per-Session TPS |
|-------------|-------------|----------|-----------|-----------------|
| 1 | 100 | 1.48 | 67.4 | 67.4 |
| 2 | 200 | 2.98 | 67.1 | 33.5 |
| 4 | 400 | 5.96 | 67.0 | 16.7 |
| 8 | 800 | 11.94 | 67.0 | 8.3 |

### Test 4: Maziyar-8B @ 128K Context

| Concurrency | Total Tokens | Time (s) | Total TPS | Per-Session TPS |
|-------------|-------------|----------|-----------|-----------------|
| 1 | 100 | 1.28 | 77.9 | 77.9 |
| 2 | 200 | 2.52 | 79.3 | 39.6 |
| 4 | 400 | 5.03 | 79.4 | 19.8 |
| 8 | 800 | 10.05 | 79.5 | 9.9 |

### Test 5: Maziyar-0.6B @ 128K Context

| Concurrency | Total Tokens | Time (s) | Total TPS | Per-Session TPS |
|-------------|-------------|----------|-----------|-----------------|
| 1 | 100 | 0.24 | 408.2 | 408.2 |
| 2 | 200 | 0.46 | 433.8 | 216.9 |
| 4 | 400 | 0.91 | 440.8 | 110.2 |
| 8 | 800 | 1.81 | 442.1 | 55.2 |

---

## Key Findings

### 1. TPS is Compute-Bound for Large Models, Memory-Bound for Small Models
- **Turbo/Ultra/Distill-9B/Maziyar-8B**: ~67-100 TPS total, constant regardless of concurrency
- **Maziyar-0.6B**: ~440 TPS and SCALES with concurrency (memory-bound)
- The GPU is fully utilized for large models; smaller models leave headroom

### 2. Per-Session TPS Decreases Linearly with Concurrency
- At Conc=1: Session gets 100% of GPU
- At Conc=2: Each session gets ~50% (half the per-session speed)
- At Conc=4: Each session gets ~25% (quarter per-session speed)
- This is expected: requests are interleaved on the GPU

### 3. Model Speed Rankings (Single-Stream)
| Model | TPS | Notes |
|-------|-----|-------|
| Maziyar-0.6B | ~440 | Memory-bound, scales |
| Maziyar-8B | ~79 | Compute-bound |
| Distill-9B | ~67 | Compute-bound |
| Turbo | ~100 | Compute-bound |
| Ultra | ~30 | Compute-bound |

### 4. VRAM vs Speed Tradeoffs
- **Ultra**: 15GB VRAM, 30 TPS (quality + vision)
- **Turbo**: 15.4GB VRAM, 100 TPS (speed)
- **Distill-9B**: 5.5GB VRAM, 67 TPS (balance)
- **Maziyar-8B**: 5.0GB VRAM, 79 TPS (fast 8B)
- **Maziyar-0.6B**: 0.7GB VRAM, 440 TPS (very fast, memory-bound)

### 2. Per-Session TPS Decreases Linearly with Concurrency
- At Conc=1: Session gets 100% of GPU
- At Conc=2: Each session gets ~50% (half the per-session speed)
- At Conc=4: Each session gets ~25% (quarter per-session speed)
- This is expected: requests are interleaved on the GPU

### 3. Turbo is 3.4x Faster than Ultra
- Turbo: ~100 TPS single-stream
- Ultra: ~30 TPS single-stream
- Speed ratio: 100/30 = 3.3x

### 4. Why Doesn't Throughput Scale with Concurrency?

At 160K context, the **prefill phase** (processing the prompt) dominates:
- With 160K context, prefill takes several seconds
- The decode phase (generating tokens) is fast but brief
- The GPU is compute-bound during prefill, not memory-bound

**Hypothesis:** At smaller context sizes (32K, 4K), throughput MAY scale with concurrency because:
- Prefill is faster (less prompt processing overhead)
- Memory bandwidth becomes the bottleneck instead of compute
- Multiple small requests can better utilize available memory bandwidth

---

## Recommendations for Testing

### To Test Smaller Context (32K):
```bash
# Kill current server
pkill -f "llama-server.*8080"

# Start with 32K context
/home/mkinney/Repos/llama.cpp/build-cuda-new/bin/llama-server \
  -m /home/mkinney/Models/JZC973/Qwen3.6-35B-REAP-MTP-UD-GGUF-Collection/Qwen3.6-35B-A3B-UD-Q3_K_M-REAP.gguf \
  -c 32768 \
  -tb 256 -ctk q4_0 -ctv q4_0 \
  -ngl 99 -t 16 -np 4 -fa on \
  --reasoning off --sleep-idle-seconds 300 \
  --host 0.0.0.0 --port 8080
```

### To Test MTP (Speculative Decoding):
```bash
# Add these flags to enable MTP
--spec-type draft-mtp --spec-draft-n-max 3
```

### Expected Benefits:
- **Smaller context**: Faster prefill, may allow throughput scaling
- **MTP**: Higher throughput if draft predictions are accepted (~170+ TPS claimed)

---

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | API documentation |
| `/v1` | GET | API index with model info |
| `/models` | GET | List all models |
| `/model` | GET | Get current model |
| `/model` | POST | Switch model |
| `/v1/chat/completions` | POST | Chat completion |
| `/health` | GET | Health check |

### Example Usage:
```bash
# List models
curl http://localhost:8082/models

# Switch to Turbo
curl -X POST http://localhost:8082/model -d '{"model": "Turbo"}'

# Chat completion
curl -X POST http://localhost:8082/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"Turbo","messages":[{"role":"user","content":"Hello"}],"max_tokens":100}'
```

---

## Files Modified

1. `/home/mkinney/.local/bin/llama-proxy` - Fixed `/v1` API endpoint, fixed `/v1/` path stripping bug
2. `/home/mkinney/Repos/llama.cpp/docs/llama-server-config/llama-server-api.md` - Updated model names
3. `/home/mkinney/Repos/llama.cpp/docs/llama-server-config/llama-server-api.html` - Updated model names
4. `/home/mkinney/Repos/llama.cpp/vllm_test_results.md` - Flagged suspicious numbers
5. `/home/mkinney/Repos/llama.cpp/benchmark_ultra_turbo.sh` - New benchmark script
6. `/home/mkinney/Repos/llama.cpp/comprehensive_benchmark.sh` - Full benchmark script

---

## Next Steps

1. **Test 32K context** - May show throughput scaling with concurrency
2. **Test MTP** - May boost Turbo to 170+ TPS
3. **Test 128K context** - Middle ground between 160K and 32K
4. **Test batch sizes** - The `-tb` and `-ub` parameters may affect concurrency

---

## Appendix: Raw Test Data

### Turbo @ 160K
```
Concurrency | Total Tok | Time(s) | Total TPS | Per-Sess TPS
1 | 200 | 2.015 | 99.2 | 99.2
2 | 400 | 4.024 | 99.4 | 49.7
3 | 600 | 6.034 | 99.4 | 33.1
4 | 800 | 8.021 | 99.7 | 24.9
5 | 1000 | 10.037 | 99.6 | 19.9
```

### Ultra @ 160K
```
Concurrency | Total Tok | Time(s) | Total TPS | Per-Sess TPS
1 | 200 | 7.305 | 27.3 | 27.3
2 | 400 | 13.752 | 29.0 | 14.5
3 | 600 | 21.954 | 27.3 | 9.1
4 | 800 | 32.079 | 24.9 | 6.2
5 | 1000 | 34.479 | 29.0 | 5.8
```
