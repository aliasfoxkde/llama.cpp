# Phase 2 Results: Escha SGLang

## Attempted: Escha Runtime (SGLang Fork) with Escha W2 Model

### Result: PARTIALLY WORKING - Installation Complex

The Escha runtime requires:
1. Python 3.12 with specific dependencies
2. Custom Escha wheel (`escha-1.1.0+qwen3dense-cp312-cp312-manylinux_2_28_x86_64.whl`)
3. Proper setup via `serve.sh`

### What Worked
- Successfully installed Escha wheel in Python 3.12 venv
- Model weights loaded (safetensors)
- Server started initializing

### Issue
- Server crashed during model initialization
- Possible OOM or Blackwell architecture compatibility issue

### Error Observed
The server loaded the escha shards but crashed before becoming ready. The log showed:
```
Loaded 1 escha shards (ref_gemm: NO, multi: YES, prefill: fused, ref-free: YES)
```
repeated many times, then process terminated.

### Documentation
- Escha model: `/home/mkinney/Models/EschaLabs/Qwen3.8-27B-Escha-W2/`
- Model size: ~10.15GB (2-bit quantization)
- Requires: RTX 50-series support (sm_120)

### Decision
**Deferred** - Requires further debugging of Blackwell/sm_120 compatibility.
