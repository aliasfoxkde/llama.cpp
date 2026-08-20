# vLLM Testing Summary

## Status: PARTIAL SUCCESS

### Working
- **Host vLLM** (RTX 5060 Ti 16GB): ✅ Fully operational
- **Model**: Qwen3-4B-Instruct (Qwen/Qwen3-4B)
- **vLLM Version**: 0.22.1
- **Peak throughput**: ~867 tok/s @ 24 concurrent

### Not Working
- **VM vLLM** (Tesla V100-SXM2-16GB): ❌ Binary incompatibility
  - Exit code 135 (Bus error) - CUDA architecture mismatch
  - Torch import fails with Python 3.13.5

## Benchmark Results: RTX 5060 Ti

| Concurrency | Throughput (tok/s) |
|------------|-------------------|
| 1 | ~45 |
| 2 | ~91 |
| 4 | ~178 |
| 8 | ~342 |
| 12 | ~496 |
| 16 | ~636 |
| 24 | ~867 |

## Quick Test Commands

```bash
# Test vLLM
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"/tmp/hf-cache/models--Qwen--Qwen3-4B/snapshots/1cfa9a7208912126459214e8b04321603b3df60c","messages":[{"role":"user","content":"Hello!"}],"max_tokens":50}'

# Run full benchmark
./benchmark.sh
```

## VM Issues to Fix

1. **Python 3.13 incompatibility**: Most ML packages (torch, numpy, vllm) don't fully support Python 3.13
   - Fix: Install Python 3.11 or 3.12 in VM

2. **CUDA architecture mismatch**: V100 (compute_70) not supported by newer CUDA toolkits
   - Fix: Build torch/vllm from source with CUDA 11.x

## Files Created

- `benchmark.sh` - Concurrency benchmark script
- `vllm_test_results.md` - Test results
- `vllm_testing_summary.md` - This summary
