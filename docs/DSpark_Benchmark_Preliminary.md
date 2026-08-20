# DSpark/Speculative Decoding Benchmark - Preliminary Results
**Date**: 2026-07-30
**GPU**: NVIDIA RTX 5060 Ti 16GB (Blackwell GB206, sm_120)
**Driver**: 610.43.02
**Settings**: CTX=128K, KV=q4_1, Flash Attention=ON

## Models Tested
1. **Qwen3.6-35B-A3B-UD-Q3_K_M-REAP** (Q3_K_M-REAP-MTP) - has MTP
2. **Qwen3.6-35B-A3B-UD-Q3_K_M-REAP-RangerX** (Q3_K_M-RangerX-MTP) - has MTP
3. **Qwen3.6-35B-A3B-REAP-48-Q3K-mixed** (REAP-48-Q3K) - no MTP

## Preliminary Results

### Q3_K_M-REAP-MTP Model

| Config | Conc | TPS | Notes |
|--------|------|-----|-------|
| **Baseline** | 1 | 80.5 | No speculative |
| **Baseline** | 2 | 74.4 | |
| **Baseline** | 4 | **118.5** | Peak |
| **Baseline** | 8 | 115.1 | |
| **Baseline** | 12 | 114.9 | |
| **Baseline** | 16 | 110.6 | |
| **Baseline** | 20 | 110.1 | |
| **Baseline** | 24 | 111.8 | |
| **MTP n_max=3** | 1 | 73.2 | Slower at conc=1 |
| **MTP n_max=3** | 2 | 118.7 | +59% vs baseline |
| **MTP n_max=3** | 4 | **165.1** | +39% vs baseline |
| **MTP n_max=3** | 8 | 156.3 | +36% vs baseline |
| **MTP n_max=3** | 12 | 161.1 | +40% vs baseline |
| **MTP n_max=3** | 16 | 164.4 | +49% vs baseline |
| **MTP n_max=3** | 20 | 150.5 | +37% vs baseline |
| **MTP n_max=3** | 24 | 155.5 | +39% vs baseline |

### Key Findings
1. **MTP benefits emerge at concurrency >= 2**: Single-stream is slightly slower with MTP overhead
2. **MTP n_max=3 provides 30-50% improvement** at higher concurrency
3. **Draft acceptance rate**: ~65-75% at n_max=3
4. **No early stopping triggered**: TPS remained consistent (didn't decrease 2x in a row)

## DSpark Model (External Draft)
- Model: `dspark_qwen3_8b_block7.q4_k_m.gguf` (1.53 GB)
- **Issue**: llama.cpp architecture "dspark" not recognized
- DSpark requires vLLM Avesed fork - not available in vanilla llama.cpp

## Comparison to Prior Benchmarks (from 2026-07-21)
- Previous RTX 5060 Ti MTP tests: ~147-152 tok/s @ 4K ctx
- Current 128K ctx tests: ~165 tok/s peak at conc=4
- Note: Different models, but MTP still provides significant speedup

## Next Steps
1. Complete benchmark (MTP n_max=5, RangerX, REAP-48 models)
2. Test vLLM with GGUF plugin (MTP support)
3. Evaluate xinfer with proper setup
4. Test DSpark in vLLM Avesed fork if available

## Environment Notes
- vLLM 0.26.0 installed with GGUF plugin
- Flashinfer version conflicts (0.6.13 vs 0.6.14 required)
- xinfer 0.3.2 installed but has transformers compatibility issue
- Need to resolve environment conflicts between vLLM and xinfer
