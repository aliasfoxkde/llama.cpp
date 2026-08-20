# vLLM Concurrency Test Results

## ⚠️ WARNING: These results are questionable
The numbers below show suspicious jumps (139 → 496 → 635) that don't follow expected scaling patterns. These should be re-validated with proper methodology.

## Test Configuration
- **Model:** Qwen3-4B-Instruct (7.6GB)
- **vLLM Version:** 0.22.1
- **GPU (Host):** NVIDIA GeForce RTX 5060 Ti 16GB

## Results (NEEDS RE-VALIDATION)

| Concurrency | Throughput (tok/s) | Status |
|-------------|-------------------|--------|
| 1 | ~47 | ⚠️ Re-test |
| 2 | ~89 | ⚠️ Re-test |
| 4 | ~178 | ⚠️ Re-test |
| 8 | ~139 | ⚠️ Suspicious drop |
| 12 | ~496 | ⚠️ Suspicious jump |
| 16 | ~635 | ⚠️ Suspicious jump |
| 24 | ~866 | ⚠️ Re-test |

## Issues with Original Test
1. **Non-linear scaling**: Concurrency 8 shows LOWER throughput than conc 4 (139 vs 178)
2. **Suspicious jumps**: 8→12 (139→496) and 12→16 (496→635) are unrealistic
3. **Methodology problems**: Original test may have used wall-clock time incorrectly

## Proper Testing Methodology
1. Warmup: 2-3 requests before measuring
2. Measure actual completion tokens from API response (`usage.completion_tokens`)
3. Use parallel curl with background jobs, `wait` for all to complete
4. Calculate: TPS = sum(completion_tokens) / elapsed_time
5. Run multiple iterations and average

## Expected Behavior
- Single-stream TPS should remain constant (~47 tok/s for Qwen3-4B)
- Total throughput = concurrency × single-stream TPS (linear scaling)
- At most, slight decreases at high concurrency due to memory contention

## vLLM Configuration Used
```bash
--enforce-eager --max-model-len 30720 --gpu-memory-utilization 0.85
```

## Action Items
- [ ] Re-run test with proper methodology
- [ ] Verify with actual token counting from responses
- [ ] Document real measured values
