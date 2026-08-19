# Comprehensive Benchmark Report
**Date:** August 19, 2026
**GPU:** NVIDIA RTX 5060 Ti 16GB (Blackwell GB206, sm_120)
**Proxy:** llama-proxy on port 8082

---

## System Configuration

### Available Models

| Model | Quantization | Context | TPS (single) | VRAM | Vision | MTP |
|-------|-------------|--------|--------------|------|--------|-----|
| **Ultra** | IQ3_XXS | 128K | ~30 TPS | ~15.0GB | ✅ | ❌ |
| **Turbo** | Q3_K_M REAP-MTP | 128K | ~100 TPS | ~15.4GB | ❌ | ✅ |

### Model Details

**Ultra** - Qwen3.8-27B + vision encoder (Unsloth + mmproj-F16)
- Best for: Quality + multimodal (images)
- Single-stream: ~30 TPS
- Architecture: 27B Dense

**Turbo** - Qwen3.6-35B-A3B MoE (JZC973 REAP + MTP)
- Best for: Speed-critical text tasks
- Single-stream: ~100 TPS
- Architecture: 35B MoE (~27B active)
- MTP: draft-mtp n_max=3 enabled

---

## Benchmark Results

### Test 1: Turbo @ 160K Context

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

---

## Key Findings

### 1. TPS is Compute-Bound (Constant Regardless of Concurrency)
- **Turbo**: ~100 TPS total at all concurrency levels
- **Ultra**: ~29 TPS total at all concurrency levels
- The GPU is fully utilized; adding more requests doesn't increase total throughput

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
