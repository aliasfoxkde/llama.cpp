# Task List - llama.cpp RTX 5060 Ti Benchmarks

**Version**: 2.0
**Last Updated**: 2026-07-21

---

## Task Status Legend

- [ ] Pending
- [~] In Progress
- [x] Completed
- [!] Blocked
- [-] Cancelled

---

## Phase 0: Draft Model Inventory

- [x] Create draft model compatibility analysis: `docs/DRAFT-MODEL-COMPATIBILITY.md`
- [x] Create download/convert script: `scripts/benchmarks/rtx5060ti-draft-convert.sh`
- [ ] Download EAGLE-3 MoE drafts (AngelSlim/Qwen3-30B_moe_eagle3)
- [ ] Download EAGLE-3 dense drafts (AngelSlim/Qwen3-8B_eagle3, etc.)
- [ ] Convert EAGLE-3 drafts for llama.cpp with Qwen3.6-35B as target
- [ ] Verify converted GGUF files load correctly in llama-server

---

## Phase 1: Per-Stream Throughput Sweep

- [x] Create script: `scripts/benchmarks/rtx5060ti-llama-bench.sh`
- [ ] Run context size sweep (4K, 8K, 16K, 32K, 64K, 96K, 128K)
- [ ] Run MTP n-max sweep (0, 3, 5, 7)
- [ ] Run KV cache quantization sweep (q4_0, q4_1, q5_0)
- [ ] Run batch size sweep
- [ ] Run NGL layer sweep
- [ ] Analyze results: find per-stream ceiling

---

## Phase 2: Acceptance Rate Measurement

- [x] Create script: `scripts/benchmarks/rtx5060ti-acceptance-bench.sh`
- [ ] Measure MTP acceptance rate vs context size
- [ ] Measure n-gram methods acceptance rate
- [ ] Measure EAGLE-3 acceptance (Qwen3 MoE draft on Qwen3.6 target)
- [ ] Compare acceptance vs per-stream t/s tradeoff
- [ ] Answer: Does MTP acceptance drop enough at large ctx to matter?

---

## Phase 3: Concurrent System Throughput

- [ ] Create script: `scripts/benchmarks/rtx5060ti-concurrent-bench.sh`
- [ ] Sweep concurrency levels (4, 8, 12, 16 parallel requests)
- [ ] Measure total t/s (aggregate, not per-stream)
- [ ] Test MTP on/off at high concurrency
- [ ] Identify concurrency sweet spot for RTX 5060 Ti 16GB
- [ ] Answer: At what concurrency does MTP overhead stop paying off?

---

## Phase 4: Draft Model Comparison

- [ ] Compare EAGLE-3 (Qwen3 MoE draft) vs MTP vs n-gram vs no-spec
- [ ] Measure acceptance rate for each method
- [ ] Measure per-stream t/s for each method
- [ ] Measure concurrent t/s for each method
- [ ] Calculate VRAM overhead per method
- [ ] Answer: Is EAGLE-3 MoE draft better than MTP despite mismatch?

---

## Phase 5: Adaptive Context Selector

- [x] Create script: `scripts/benchmarks/rtx5060ti-adaptive-bench.sh`
- [ ] Test 5 scenarios: short/long prompt x short/long response
- [ ] Test ctx sweep at 12 concurrent
- [ ] Test MTP n-max sweep at 12 concurrent
- [ ] Derive adaptive heuristic from data
- [ ] Document heuristic for production use

---

## Phase 6: Multi-GPU (RTX 5060 Ti + V100)

- [x] Create script: `scripts/benchmarks/rtx5060ti-multi-gpu-bench.sh`
- [ ] Install both GPUs physically (5060 Ti + V100)
- [ ] Verify both GPUs detected via `nvidia-smi`
- [ ] Phase 1: Single-GPU baselines (each card individually)
- [ ] Phase 2: Pipeline parallelism (`-pp 2`) across both cards
- [ ] Phase 3: Parallel instances (one server per GPU, aggregate throughput)
- [ ] Phase 4: GPU-to-GPU comparison summary
- [ ] Answer: Which GPU is faster per-stream? Which wins at concurrency?
- [ ] Answer: Does V100's HBM2 bandwidth beat 5060 Ti's GDDR7?

---

## Phase 7: vLLM Benchmarks

- [ ] Install vLLM (upstream): `pip install vllm>=0.8.0`
- [ ] Run vLLM basic throughput (FP16, matching configs to llama.cpp)
- [ ] Install Avesed fork (for Qwen3.6 MoE): `docker pull ghcr.io/avesed/vllm-ampere-optimized:0.3`
- [ ] Run Avesed vLLM with DSpark: `--speculative-config '{"method":"dspark","num_speculative_tokens":5}'`
- [ ] Test NVFP4 (Blackwell GB206): `--dtype fp4` or `--quantization fp4`
- [ ] Compare vLLM vs llama.cpp at matching configs
- [ ] Answer: Does vLLM + DSpark outperform llama.cpp + MTP on RTX 5060 Ti?

---

## Documentation

- [x] Benchmark plan: `docs/RTX5060TI-BENCHMARK-PLAN.md` (updated with systematic phases)
- [x] Draft compatibility: `docs/DRAFT-MODEL-COMPATIBILITY.md`
- [x] TASKS.md this file
- [ ] Final report: `docs/RTX5060TI-BENCHMARKS.md` (after running benchmarks)
- [ ] Update `docs/VLLM-RTX5060TI-SETUP.md` with actual findings

---

## Progress Summary

- **Phase 0**: 40% complete (docs/scripts done, download/convert pending)
- **Phase 1**: 10% complete (script done, execution pending)
- **Phase 2**: 10% complete (script done, execution pending)
- **Phase 3**: 10% complete (script done, execution pending)
- **Phase 4**: 0% complete
- **Phase 5**: 10% complete (script done, execution pending)
- **Phase 6**: 0% complete
- **Overall**: ~15%

---

## How to Run

```bash
# Full suite (all phases)
./scripts/benchmarks/run-all-benchmarks.sh

# Step by step
./scripts/benchmarks/run-all-benchmarks.sh --phase0  # download drafts
./scripts/benchmarks/run-all-benchmarks.sh --phase1  # per-stream
./scripts/benchmarks/run-all-benchmarks.sh --phase2  # acceptance
./scripts/benchmarks/run-all-benchmarks.sh --phase3  # concurrent
./scripts/benchmarks/run-all-benchmarks.sh --phase5  # adaptive

# Quick test (fewer runs)
./scripts/benchmarks/run-all-benchmarks.sh --quick

# Draft model download
./scripts/benchmarks/rtx5060ti-draft-convert.sh

# vLLM benchmarks (separate)
./scripts/benchmarks/run-all-benchmarks.sh --vllm
```