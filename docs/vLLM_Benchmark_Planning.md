# vLLM CUDA Validation, Repair, and Benchmark Plan

## Objective

Set up and validate vLLM on this Fedora 44 RTX 5060 Ti system, resolve any CUDA/toolchain issues, then benchmark vLLM against the existing llama.cpp baseline.

The goal is **maximum concurrent inference throughput**, not single-request latency.

Target workload:

* Qwen3.6 35B A3B MoE
* Long context (up to 128K)
* Multiple concurrent agents
* Tool calls
* Parallel sessions
* High aggregate tokens/sec

Current known-good baseline:

* RTX 5060 Ti 16GB
* NVIDIA Driver 595.80
* CUDA Toolkit 13.3
* PyTorch CUDA working
* FlashInfer 0.6.11.post2 working
* llama.cpp CUDA backend compiling
* CUDA host compiler:

  * `/usr/bin/g++-15`

---

# Phase 1 — Environment Validation

Run and record:

```bash
nvidia-smi

nvcc --version

echo $CUDA_HOME

which nvcc

python -c "import torch; print(torch.cuda.is_available()); print(torch.version.cuda); print(torch.cuda.get_device_name(0))"

python -c "import flashinfer; print(flashinfer.__version__)"

python -c "import vllm; print(vllm.__version__)"
```

Expected:

* CUDA available = True
* GPU detected
* FlashInfer imports
* vLLM imports

Do not continue until these are clean.

---

# Phase 2 — Verify vLLM Installation

Check:

```bash
pip show vllm
pip show flashinfer-python
pip show torch
```

Verify versions are compatible.

If vLLM is broken:

* Do not randomly reinstall CUDA.
* Preserve the working CUDA environment.
* Reinstall only Python packages.

---

# Phase 3 — Verify CUDA Compiler Environment

Ensure:

```bash
echo $NVCC_CCBIN
```

returns:

```
/usr/bin/g++-15
```

Ensure:

```bash
echo $CUDA_HOME
```

returns:

```
/usr/local/cuda-13.3
```

Test:

```bash
nvcc --version
```

Do not use GCC 16.

---

# Phase 4 — Determine Model Compatibility

Important:

The current llama.cpp model is GGUF.

vLLM primarily expects:

* Hugging Face format
* safetensors
* supported quantization formats

Do NOT assume the GGUF model will work.

Determine:

1. Does the exact Qwen3.6 35B A3B model have HF weights?
2. Does vLLM support the model architecture?
3. Does vLLM support the quantization format?

Report:

```
Model:
Architecture:
Quantization:
vLLM support:
FlashInfer support:
```

---

# Phase 5 — Start Simple vLLM Test

Do NOT immediately use 128K context.

Start:

```bash
vllm serve MODEL \
--gpu-memory-utilization 0.90 \
--max-model-len 8192
```

Verify:

* model loads
* CUDA kernels compile
* no OOM
* API responds

Test:

```bash
curl http://localhost:8000/v1/models
```

---

# Phase 6 — Increase Context

Test:

```
8K
32K
64K
128K
```

Record:

* VRAM usage
* load time
* generation speed
* failures

Monitor:

```bash
watch -n1 nvidia-smi
```

---

# Phase 7 — Benchmark Concurrency

Do not benchmark only one request.

Create workloads:

## Test A

1 concurrent request

Measure:

* prompt tok/s
* generation tok/s

## Test B

4 concurrent requests

## Test C

8 concurrent requests

## Test D

16 concurrent requests

## Test E

32 concurrent requests if possible

Record:

| Concurrency | Total tok/s | Avg latency | P95 latency | VRAM |
| ----------- | ----------: | ----------: | ----------: | ---: |
| 1           |             |             |             |      |
| 4           |             |             |             |      |
| 8           |             |             |             |      |
| 16          |             |             |             |      |
| 32          |             |             |             |      |

The important metric:

```
aggregate generated tokens/sec
```

---

# Phase 8 — Tune vLLM Parameters

Test combinations:

## Scheduler

```bash
--max-num-seqs
```

Values:

```
4
8
16
32
```

---

## Batch tokens

Test:

```bash
--max-num-batched-tokens
```

Values:

```
4096
8192
16384
32768
```

---

## Memory

Test:

```bash
--gpu-memory-utilization
```

Values:

```
0.85
0.90
0.95
0.98
```

---

# Phase 9 — Compare Against llama.cpp

Use identical:

* prompts
* context lengths
* concurrency

Compare:

## llama.cpp

Record:

* single stream tok/s
* concurrent total tok/s

## vLLM

Record:

* single stream tok/s
* concurrent total tok/s

Do not declare a winner based on one request.

---

# Phase 10 — Agent Simulation Benchmark

Create a realistic workload:

Each agent:

* 32K context
* reasoning prompt
* tool call
* response generation
* follow-up message

Run:

```
4 agents
8 agents
16 agents
32 agents
```

Measure:

* total completed tasks/minute
* tokens/sec
* GPU utilization
* latency

---

# Phase 11 — Investigate Speculative Decoding

After baseline:

Investigate:

* MTP
* Draft model
* DSpark support
* speculative decoding

Do not assume published speedups apply.

Benchmark:

```
normal decoding
vs
MTP/speculative decoding
```

using the same workload.

---

# Success Criteria

The goal is not:

"highest tokens/sec on one prompt."

The goal:

"maximum useful AI agent throughput."

A successful result would show:

* CUDA vLLM exceeds llama.cpp at concurrency
* GPU utilization remains high
* multiple agents can run efficiently
* long context does not destroy throughput

---

# Final deliverable

Produce:

1. Environment report
2. vLLM version/configuration
3. Model compatibility report
4. Benchmark tables
5. Best parameter configuration
6. llama.cpp vs vLLM comparison
7. Bottleneck analysis
8. Recommendations for second GPU deployment

