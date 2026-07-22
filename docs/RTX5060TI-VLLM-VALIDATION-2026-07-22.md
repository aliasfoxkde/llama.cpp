# RTX 5060 Ti 16GB — vLLM Validation Report

**Date**: 2026-07-22
**Hardware**: NVIDIA RTX 5060 Ti 16GB (Blackwell GB206), Driver 595.80, CUDA 13.3
**Python**: 3.14.6
**vLLM**: 0.22.1
**Status**: ❌ BLOCKED — Python toolchain issue

---

## Executive Summary

| Component | Status | Details |
|-----------|--------|---------|
| NVIDIA Driver | ✅ Working | 595.80 |
| CUDA Toolkit | ✅ Working | 13.3 with gcc-15 |
| PyTorch CUDA | ✅ Working | 2.11.0+cu130 |
| FlashInfer | ✅ Working | 0.6.11.post2 |
| vLLM | ❌ BLOCKED | Triton JIT compilation fails |
| GGUF Support | ❌ Not supported | vLLM does not support GGUF natively |

**Root Cause**: vLLM's Triton-based sampler requires Python development headers (`Python.h`) which are not installed for Python 3.14.

---

## Phase 1 — Environment Validation Results

### CUDA Environment

```
nvidia-smi: CUDA Version 13.2, Driver 595.80, RTX 5060 Ti 16GB
nvcc: V13.3.73 (CUDA 13.3)
CUDA_HOME: /usr/local/cuda-13.3
NVCC_CCBIN: /usr/bin/gcc-15
```

### Python/PyTorch Environment

```
Python: 3.14.6
PyTorch: 2.11.0+cu130
CUDA (PyTorch): 13.0
GPU: NVIDIA GeForce RTX 5060 Ti
CUDA Available: True
FlashInfer: 0.6.11.post2
vLLM: 0.22.1
```

### GPU Memory

```
Total: 16311 MiB (~16 GB)
Free: ~14993 MiB (before model loading)
```

---

## Phase 4 — Model Compatibility Analysis

### Qwen3.6-35B-A3B MoE Model

**Local HF Format**: `/home/mkinney/Models/Qwen3.6-35B-A3B-HF/`
- 67GB total (26 safetensor shards)
- Architecture: `Qwen3_5MoeForConditionalGeneration`
- Num experts: 256, Active per token: 8
- Hidden size: 2048, Layers: 40
- Max position: 262144 (256K context)
- Vocab size: 248320

**VRAM Requirements**:
| Precision | Estimated VRAM | Fits in 16GB? |
|-----------|---------------|---------------|
| BF16/FP16 | ~70GB | ❌ No |
| INT8 | ~35GB | ❌ No |
| INT4 (AWQ/GPTQ) | ~17.5GB | ⚠️ Tight |
| Q3_K_M (GGUF) | ~12GB | ✅ Yes |

### vLLM Format Support

```
✅ HuggingFace safetensors (.safetensors)
✅ PyTorch bins (.bin)
✅ AWQ (.awq)
✅ GPTQ (.gptq)
❌ GGUF (not supported)
```

### Available GGUF Models (llama.cpp compatible)

| Model | Size | Quantization |
|-------|------|--------------|
| Qwen3.6-35B-A3B-UD-Q3_K_M-REAP-RangerX.gguf | 12GB | Q3_K_M |
| Qwen3.6-35B-A3B-UD-Q3_K_XL-REAP.gguf | 13GB | Q3_K_XL |
| Qwen3.6-35B-A3B-UD-IQ3_XXS-REAP.gguf | 11GB | IQ3_XXS |

---

## Phase 5 — vLLM Initialization Test

### Test: Qwen2.5-3B (Small Model)

**Goal**: Validate vLLM engine initialization with a small model

**Result**: ❌ FAILED

**Error**:
```
/tmp/tmpdl8ahmic/cuda_utils.c:7:10: fatal error: Python.h: No such file or directory
    7 | #include <Python.h>
      |          ^~~~~~~~~~
compilation terminated.
```

**Root Cause Analysis**:
1. vLLM uses Triton for JIT compilation of CUDA kernels
2. Triton compiles `cuda_utils.c` which requires `Python.h`
3. Python 3.14 headers are not installed (`/usr/include/python3.14/` only has `pyconfig-64.h`)
4. The system has Python 3.12 headers at `/usr/include/python3.12/Python.h`
5. Cannot install Python 3.14 headers without sudo/root access

**Attempted Workarounds**:
- `enforce_eager=True` (disables CUDA graphs, but Triton still required)
- `enable_flashinfer_autotune=False` (does not disable Triton)
- `CPATH=/usr/include/python3.12` (Triton ignores this)
- `Triton_CUDA_INCLUDE` environment variable (not respected)

---

## Issue: Triton Python Header Problem

Triton v3.6.0 is bundled with vLLM 0.22.1. It attempts to compile CUDA utilities at runtime:

```python
# Triton backend initialization path:
triton.runtime.driver.active.get_current_device()
  → _create_driver()
  → CudaUtils()
  → compile_module_from_src(cuda_utils.c)
  → subprocess.check_call([gcc, ..., -I/usr/include/python3.14])
```

The include path is hardcoded to Python 3.14's include directory, which lacks `Python.h`.

### System Headers Available

```
/usr/include/python3.12/Python.h    ✅ exists
/usr/include/python3.14/Python.h    ❌ missing
/usr/include/python3.14/pyconfig-64.h ✅ exists
```

---

## vLLM vs llama.cpp Comparison

### llama.cpp Status

| Feature | Status |
|---------|--------|
| CUDA compilation | ✅ Working |
| Model loading | ✅ Working |
| MTP (speculative decoding) | ✅ Working (n-max=3) |
| Concurrent inference | ✅ Working |
| GGUF support | ✅ Native |
| Concurrent throughput | ✅ 148 t/s per stream |

**Benchmark (existing)**:
- Q3_K_M RangerX + MTP n-max=3: **147-152 t/s** per stream
- Q3_K_XL + MTP n-max=3: **130-150 t/s** per stream

### vLLM Status

| Feature | Status |
|---------|--------|
| Python environment | ⚠️ Incomplete (missing headers) |
| CUDA compilation | ✅ Working (PyTorch verified) |
| Model loading (HF format) | ⚠️ Model loads, engine fails |
| GGUF support | ❌ Not supported |
| Triton JIT compilation | ❌ Fails (Python.h missing) |

---

## Recommendations

### For Immediate llama.cpp Use

```bash
# Best single-stream performance:
./build/bin/llama-server \
  -m Qwen3.6-35B-A3B-REAP-RangerX.gguf \
  -ngl 99 -c 4096 \
  --spec-type draft-mtp --spec-draft-n-max 3

# Expected: ~148 t/s per stream
```

### For vLLM Deployment

**Option 1: Install Python 3.14 Development Headers** (requires root)
```bash
sudo dnf install python3.14-devel
# Then restart vLLM
```

**Option 2: Use Python 3.12 Environment**
```bash
# Create conda/mamba environment
mamba create -n vllm312 python=3.12 -y
mamba activate vllm312
pip install vllm torch --index-url https://download.pytorch.org/whl/cu130
```

**Option 3: Use Containerized vLLM**
```bash
# NVIDIA container runtime
docker run --gpus all \
  -v /home/mkinney/Models:/models \
  nvcr.io/nvidia/vllm:latest \
  vllm serve /models/Qwen3.6-35B-A3B-HF
```

**Option 4: Convert GGUF → AWQ for vLLM**
```bash
# Install AWQ and convert
pip install autoawq
# Convert requires: 35GB+ RAM + GPU for calibration
```

---

## Model Compatibility Summary

| Model | Format | llama.cpp | vLLM | Notes |
|-------|--------|-----------|------|-------|
| Qwen3.6-35B-A3B | GGUF Q3_K_M | ✅ Works | ❌ Not supported | Best for llama.cpp |
| Qwen3.6-35B-A3B | HF safetensors | N/A | ⚠️ Can't initialize | Python headers missing |
| Qwen3.6-35B-A3B | AWQ INT4 | N/A | ⚠️ Would need download | Not locally available |
| Qwen2.5-3B | HF safetensors | N/A | ❌ Engine fails | Python headers missing |

---

## Bottleneck Analysis

### Current System Bottlenecks

1. **llama.cpp**: GPU compute (MTP provides ~50% speedup)
2. **vLLM**: Python toolchain (not a CUDA issue)

### Why vLLM Cannot Initialize

```
PyTorch CUDA:     ✅ Working (simple matmul succeeds)
FlashInfer:      ✅ Working (loads successfully)
Triton:          ❌ Fails to compile (missing Python.h)
vLLM Sampler:    ❌ Uses Triton (engine init fails)
vLLM Engine:     ❌ Cannot start due to sampler failure
```

---

## Next Steps

1. **llama.cpp is production-ready** for this hardware
   - Use MTP n-max=3 for best performance
   - Consider concurrent instances for multi-user

2. **To enable vLLM**:
   - Option A: Install `python3.14-devel` (root required)
   - Option B: Use containerized vLLM deployment
   - Option C: Set up Python 3.12 environment with conda/mamba

3. **For second GPU deployment**:
   - Same Python header issue will persist
   - Container runtime is recommended
   - Consider NVIDIA NGC vLLM containers

---

## System Information

```
GPU: NVIDIA GeForce RTX 5060 Ti 16GB
Driver: 595.80
CUDA: 13.3
gcc: 15.2.0
Python: 3.14.6
PyTorch: 2.11.0+cu130
FlashInfer: 0.6.11.post2
vLLM: 0.22.1
Triton: 3.6.0

Memory:
- GPU VRAM: 16311 MiB total
- System RAM: ~23 GiB available
- Disk: 996 GiB available

OS: Fedora 44
Kernel: Linux 7.1.3-200.fc44.x86_64
```

---

*Report generated: 2026-07-22*
