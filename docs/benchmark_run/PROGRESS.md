# Qwen3.8-27B Benchmark Progress

## Hardware
- **GPU**: NVIDIA GeForce RTX 5060 Ti (16GB VRAM, Blackwell)
- **Driver**: 610.57.04 / CUDA 13.3
- **CPU**: Intel i5-13600K (14 cores) / **RAM**: 31GB
- **Idle VRAM**: ~15.6GB available

---

## Phase 0: Environment Characterization [✅ COMPLETE]
- [x] GPU info → `environment/gpu.txt`
- [x] Software env → `environment/software.txt`

## Phase 1: llama.cpp DFlash2 Baseline [✅ COMPLETE]
- [x] Baseline models tested (IQ2_XXS, IQ3_XXS, Q3_K_XL)
- [x] DFlash n-max sweep 2-7
- [x] **KEY FINDING: n_max=4 gives 61% speedup (37.5 → 60.5 tok/s)**

### DFlash Results Summary
| n_max | tok/s | Speedup | Acceptance |
|-------|-------|---------|------------|
| 0 | 37.5 | baseline | — |
| 2 | 52.0 | +39% | 62% |
| 3 | 54.1 | +44% | 58% |
| **4** | **60.5** | **+61%** | **56%** |
| 5 | 39.4 | +5% | 27% |
| 6 | 44.1 | +18% | 33% |
| 7 | OOM | — | — |

## Phase 2: Escha SGLang [⚠️ INCOMPLETE]
- [x] Downloaded Escha W2 model (10.15GB)
- [x] Installed Escha runtime wheel
- [x] Model loading started
- [ ] Server crashed - Blackwell compatibility issue

## Phase 3-5: Escha-based Testing [⚠️ SKIPPED]
- [x] Skipped - requires working Escha SGLang

## Phase 6: vLLM + W8 DFlash2 [⚠️ INCOMPLETE]
- [x] Downloaded W8A16 DFlash2 drafter (2.02GB)
- [x] vLLM requires safetensors target model
- [ ] Requires downloading large target model

## Phase 7: Quality Validation [❌ NOT STARTED]
- [ ] Greedy equivalence tests
- [ ] Quality benchmark suite

## Phase 8-12: Analysis [❌ NOT STARTED]
- [ ] Cross-engine comparison
- [ ] Pareto frontier
- [ ] Break-even analysis

---

## Key Findings

1. **llama.cpp DFlash2 works excellently** on RTX 5060 Ti
2. **n_max=4 is optimal** - higher causes VRAM pressure and lower acceptance
3. **IQ2_XXS is fastest** despite smallest - compute-bound at decode
4. **Escha SGLang** has Blackwell compatibility issues
5. **vLLM** needs safetensors target for DFlash2

---

## Missing Models/Downloads Needed
- [ ] Qwen3.8-27B-DFlash2-Q4_K_M.gguf (official DFlash2 drafter for llama.cpp)
- [ ] Safetensors target model for vLLM DFlash2 testing
- [ ] Escha SGLang debugging (Blackwell issue)

---

## Artifacts
- `RESULTS.md` - Complete results
- `benchmark_harness.sh` - Automation script
- `environment/` - HW/SW capture
- `prompts/` - Test prompts
