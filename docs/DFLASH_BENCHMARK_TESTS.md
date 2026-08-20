Yes. Given the new information on the DFlash2 W8 repo and the current state of the three runtimes, I would change the plan somewhat.

The key finding is:

> **Do not assume the Q4_K_M GGUF DFlash2 drafter can be loaded by SGLang.** The Q4_K_M drafter is currently demonstrated in the llama.cpp ecosystem. SGLang's DFLASH interface expects a DFlash draft checkpoint, and the `lued/Qwen3.8-27B-DFlash2-W8` repository is specifically a **Safetensors W8A16 DFlash2 checkpoint intended for vLLM's DFlash implementation**, not a GGUF. ([Hugging Face][1])

That actually makes your proposed three-engine experiment **much more interesting**, because we can separate:

1. **llama.cpp:** Q4_K_M DFlash2 + GGUF target
2. **SGLang:** Escha W2 + DFlash2, if we can get the appropriate DFlash checkpoint into the Escha fork
3. **vLLM:** conventional quantized target + W8A16 DFlash2

And we should absolutely test **draft lengths 2–7**, rather than assuming 4 or 7 is optimal.

Recent real-world testing already shows that DFlash2's optimum is workload-dependent. One 4090 test found `n-max=4` better than 7 in some configurations, while another test found significant gains from DFlash2 over MTP. ([vramcalculator.com][2])

---

# First: what I think about the three DFlash2 options

## 1. Q4_K_M DFlash2 GGUF

**Yes — this is the one I would use first with llama.cpp.**

Recent testing is specifically using:

```text
Qwen3.8-27B-DFlash2-Q4_K_M.gguf
```

with:

```text
--spec-type draft-dflash
--spec-draft-n-max 7
```

on the llama.cpp DFlash2 branch. ([Reddit][3])

There is even a recent report using:

```text
Qwen3.8-27B-Q5_K_L
+
Qwen3.8-27B-DFlash2-Q4_K_M
```

with DFlash2 and getting substantially higher decode performance than ordinary decoding. ([Reddit][3])

For your **16 GB card**, however, I would *not* copy their Q5 target. We should specifically test the smaller target quants.

---

# 2. `lued/Qwen3.8-27B-DFlash2-W8`

This repository is very interesting.

It is:

```text
DFlash2
5-layer block-diffusion drafter
W8A16
2.02 GiB
```

versus:

```text
BF16 DFlash2
3.58 GiB
```

The author reports essentially equal drafting acceptance between W8 and BF16 in their test: 2.65 vs 2.72 accepted tokens/draft. ([Hugging Face][1])

But there is an important distinction:

### This is not a generic "DFlash2 W8 model"

The model card explicitly says:

> Serve it as the DFlash2 drafter of the matching quantized target.

and gives a vLLM-specific configuration using the vendored DFlash PR. ([Hugging Face][1])

So:

| Runtime           | DFlash2-W8                         |
| ----------------- | ---------------------------------- |
| **vLLM**          | **Yes — this is the intended use** |
| **SGLang**        | Not established                    |
| **llama.cpp**     | No — use GGUF DFlash2              |
| Escha SGLang fork | **Unknown / requires integration** |

That's actually useful for our experiment.

---

# 3. SGLang is the wildcard

Current upstream SGLang has DFLASH support and exposes:

```text
--speculative-algorithm DFLASH
--speculative-draft-model-path ...
--speculative-num-draft-tokens ...
```

and the DFlash documentation describes the draft as a dedicated DFlash checkpoint. ([GitHub][4])

However, the **Escha runtime is a custom SGLang fork**, and its documented supported model is the Escha W2 model. The runtime is tightly coupled to the Escha kernels. ([Hugging Face][5])

Therefore our first SGLang objective shouldn't be:

> "Make TurboQuant + DFlash2 work."

It should be:

> **Can the Escha SGLang runtime run DFlash2 at all?**

Then:

```text
Escha
  ↓
Escha + DFlash2
  ↓
Escha + TurboQuant
  ↓
Escha + TurboQuant + DFlash2
```

That sequencing will save a huge amount of debugging time.

---

# The testing architecture I recommend

I would organize the entire experiment as a **four-layer investigation**:

```text
PHASE 0
Hardware / environment characterization
        │
        ▼
PHASE 1
llama.cpp
        │
        ├── baseline
        ├── quantization
        ├── KV
        ├── DFlash
        └── n-max 2–7
        │
        ▼
PHASE 2
Escha SGLang
        │
        ├── baseline
        ├── context
        ├── KV
        ├── DFlash
        └── combined
        │
        ▼
PHASE 3
vLLM
        │
        ├── baseline
        ├── DFlash W8
        ├── n-max 2–7
        └── KV variants
        │
        ▼
PHASE 4
Cross-engine analysis
        │
        ├── speed
        ├── VRAM
        ├── acceptance
        ├── context
        ├── quality
        └── stability
```

The important part is that **every phase produces a clean artifact before moving to the next**.

---

# PHASE 0 — Establish the machine

Before touching any model, create a reproducible environment record.

## 0.1 Hardware

Record:

```bash
nvidia-smi
nvidia-smi -q
```

Capture:

* GPU model
* VRAM
* driver version
* CUDA version reported by driver
* PCIe information
* power limit
* clocks
* temperature
* utilization

Also:

```bash
lscpu
free -h
uname -a
```

And:

```bash
python --version
gcc --version
g++ --version
nvcc --version
```

if CUDA toolkit exists.

---

# 0.2 Establish idle VRAM

Record:

```bash
nvidia-smi --query-gpu=memory.total,memory.used,memory.free --format=csv
```

Do this immediately after boot/reboot.

This gives us:

```text
usable_VRAM =
16 GB - OS/driver/background allocation
```

Do **not** assume the marketing 16 GB is the available 16 GB.

---

# 0.3 Freeze the software environment

Every engine needs:

```text
engine
version
git commit
CUDA version
driver
PyTorch version
Python version
model revision
draft model revision
launch command
environment variables
```

For Git repositories:

```bash
git rev-parse HEAD
git status --short
git diff
```

The test harness should automatically collect these.

This is particularly important because DFlash2 is currently in a rapidly changing state. The llama.cpp DFlash2 implementation is still an open PR, and SGLang's DFlash implementation is also evolving. ([vramcalculator.com][2])

---

# PHASE 1 — llama.cpp first

I agree with your proposed order.

**llama.cpp is currently the lowest-friction way to determine whether DFlash2 is actually useful on this 16 GB card.**

And because we can test multiple GGUF target quantizations and the Q4_K_M drafter, it gives us a very good empirical baseline.

---

## 1.1 Build a known-good llama.cpp

Use a dedicated branch/worktree for DFlash2.

Do not mix your existing llama.cpp build with this experiment.

Record:

```text
commit
compiler
CUDA
CMake configuration
GPU architecture
```

Build with CUDA enabled.

Verify:

```bash
llama-cli --version
llama-server --version
```

---

# 1.2 First test: ordinary Qwen3.8

Before DFlash2:

```text
Qwen3.8-27B
```

Run:

```text
no speculative decoding
```

This is the **control group**.

Do not change:

* temperature
* sampling
* context
* batch
* GPU offload
* KV
* prompt

after establishing this baseline.

---

# 1.3 Target quantization matrix

On a 16 GB GPU, test the smallest useful set first.

I recommend:

| Target              |                   Priority |
| ------------------- | -------------------------: |
| Q3_K_M / equivalent |                       High |
| Q4_K_M              |              **Very high** |
| Q5_K_M              |            High if it fits |
| Escha W2            | Separate SGLang experiment |

The purpose isn't to benchmark every GGUF ever created.

We want to answer:

> **How much target-model quantization can we afford before the model becomes memory/compute constrained?**

---

# 1.4 KV cache matrix

For llama.cpp, establish:

```text
F16
Q8_0
Q4_0
```

if supported by the chosen build/model.

Recent DFlash2 testing is already using quantized KV in llama.cpp; one 5090 test used Q8 KV, while another Strix Halo test used F16 target KV and Q8 draft KV. ([Reddit][3])

For your 16 GB:

### First priority

```text
Q8_0
```

### Then

```text
Q4_0
```

The objective is to determine whether Q4 KV causes a meaningful performance/quality issue.

---

# 1.5 Establish context ceiling WITHOUT DFlash

For each viable target quant:

```text
8K
16K
32K
64K
128K
```

Stop when:

* OOM
* allocation failure
* catastrophic slowdown
* instability

Record:

```text
context
VRAM
prefill tok/s
decode tok/s
TTFT
```

This establishes the **KV memory curve**.

---

# 1.6 Now DFlash2

Use:

```text
Qwen3.8-27B-DFlash2-Q4_K_M.gguf
```

as the first draft.

Do not start at 7.

Run:

```text
n-max = 2
n-max = 3
n-max = 4
n-max = 5
n-max = 6
n-max = 7
```

This is one of the most important experiments in the entire project.

---

# 1.7 Why 2–7 matters

DFlash2 isn't simply:

```text
more draft tokens = faster
```

There are three competing effects:

```text
n-max ↑
    │
    ├── potential accepted tokens ↑
    │
    ├── draft work ↑
    │
    ├── draft memory ↑
    │
    └── verification work ↑
```

So there will be an optimum.

Recent testing demonstrates exactly this behavior: a 4090 experiment found `n-max=4` gave better VRAM/throughput behavior than 7, while another workload benefited from larger draft windows. ([vramcalculator.com][2])

Your 5060 Ti could have a **different optimum**.

---

# 1.8 Measure acceptance, not just tok/s

Every DFlash test should record:

```text
n-max
accepted tokens
acceptance rate
mean acceptance length
draft tokens
verification calls
decode tok/s
```

The most important derived metric is:

```text
speedup =
DFlash decode tok/s
-------------------
baseline decode tok/s
```

But also:

```text
accepted_tokens_per_draft
```

because that tells us **why** the speed changed.

---

# 1.9 Workload matrix

Do not use one prompt.

Use at least:

### A. Code

```text
Rust/Python/JS implementation task
```

### B. Reasoning

```text
multi-step mathematics
```

### C. General prose

```text
long-form explanation
```

### D. Structured output

```json
```

### E. Agentic/code-edit workload

```text
inspect requirements
produce implementation
```

### F. Long-context

```text
16K+
```

This matters because DFlash2 acceptance is strongly workload-shaped. The W8 drafter repository itself reports materially different acceptance envelopes for math versus long prose. ([Hugging Face][1])

---

# 1.10 llama.cpp success criteria

We should call llama.cpp DFlash2 successful if:

### Minimum

```text
stable
correct
fits 16 GB
DFlash2 > baseline
```

### Good

```text
≥1.25× decode improvement
```

### Excellent

```text
≥1.5×
```

### Exceptional

```text
≥2×
```

But **do not use those as hard scientific thresholds**. They are engineering classifications.

The recent Qwen3.8 DFlash2 reports span very large ranges depending on workload, which reinforces the need for workload-specific results. ([Reddit][6])

---

# PHASE 2 — Escha SGLang baseline

Now move to SGLang.

This is the most important phase for your particular hardware.

The Escha model is only **10.15 GB**, and the custom runtime is explicitly designed around its special quantization format. The runtime also explicitly says RTX 50-series requires the Triton attention backend. ([Hugging Face][7])

---

# 2.1 Do NOT introduce DFlash yet

First get:

```text
Escha W2
+
custom SGLang
+
RTX 5060 Ti
```

working.

That gives us:

```text
Escha baseline
```

---

# 2.2 Start with the documented 16 GB configuration

The model card says 16 GB should fit at reduced context but explicitly says that tier is **not physically tested**. ([Hugging Face][7])

Use the cookbook's 16-GB-derived configuration as the initial experiment.

Critically:

```text
ATTN_BACKEND=triton
```

because the runtime explicitly requires Triton on consumer Blackwell / sm_120. ([Hugging Face][7])

---

# 2.3 Determine actual Escha memory breakdown

Record:

```text
weights
KV pool
Mamba/recurrent pool
CUDA graph allocations
temporary allocations
total
```

We want an actual memory model:

```text
VRAM =
W
+
KV
+
M
+
graphs
+
runtime
```

This is more valuable than simply saying:

> "It fits."

---

# 2.4 Context sweep

Run:

```text
4K
8K
16K
24K
32K
48K
64K
```

until failure.

Because the model card says 24 GB can fit 64K, but 16 GB is untested, this experiment gives us the first actual empirical answer for the 5060 Ti. ([Hugging Face][7])

---

# 2.5 Determine baseline Escha decode

Measure:

```text
prompt = 512
prompt = 2K
prompt = 8K
prompt = 16K
```

with:

```text
output = 512–2048 tokens
```

This establishes how much long-context degradation occurs.

---

# PHASE 3 — TurboQuant KV

Only after Escha baseline is stable.

Then introduce:

```text
TurboQuant Dynamic 4-bit KV
```

Do **not** simultaneously introduce DFlash2.

We need to answer:

> What does TurboQuant itself do?

Test:

```text
Escha W2 + native/default KV
Escha W2 + TurboQuant 4-bit
```

at:

```text
8K
16K
32K
64K
```

Record:

```text
VRAM
decode
prefill
TTFT
quality
stability
```

---

# 3.1 TurboQuant success criteria

The important metric isn't merely:

```text
VRAM reduction
```

It is:

```text
VRAM reduction
+
decode impact
+
long-context degradation
```

For example:

```text
TurboQuant:
- saves 1.5 GB
- costs 3% decode
- enables 64K instead of 24K
```

would be a huge success.

Whereas:

```text
TurboQuant:
- saves 1.5 GB
- costs 20% decode
- enables no additional useful context
```

would be questionable.

---

# PHASE 4 — DFlash2 + normal Escha

Now test:

```text
Escha W2
+
DFlash2
```

**without TurboQuant first.**

This isolates DFlash.

---

# 4.1 Which DFlash2 checkpoint?

This is where we experiment.

### Candidate A

Original:

```text
z-lab/incoai Qwen3.8-27B-DFlash2
```

### Candidate B

```text
lued/Qwen3.8-27B-DFlash2-W8
```

The W8 model is attractive because it is only ~2.02 GiB and its author reports essentially equivalent acceptance to BF16 in their test. ([Hugging Face][1])

### Candidate C

Any SGLang-compatible converted DFlash2 checkpoint we can produce.

---

# 4.2 Do not convert blindly

If SGLang rejects the W8 checkpoint:

**stop.**

Do not immediately start rewriting the model loader.

First determine:

```text
What checkpoint format does current SGLang DFLASH expect?
What does Qwen3.8 DFlash2's config declare?
What tensors are expected?
What tensor names differ?
What quantization backend is required?
```

Then decide whether conversion is:

```text
trivial
moderate
substantial
```

This prevents wasting time debugging a format mismatch as though it were a CUDA issue.

---

# 4.3 DFlash n-max sweep

Run:

```text
2
3
4
5
6
7
```

again.

But also record:

```text
DFlash model VRAM
total VRAM
acceptance
speed
```

This lets us compare:

```text
llama.cpp n-max curve
SGLang n-max curve
vLLM n-max curve
```

---

# PHASE 5 — Combined Escha + TurboQuant + DFlash2

**This is the main experiment.**

Only attempt it after the previous three independently work.

Target:

```text
Escha W2
+
TurboQuant Dynamic Q4 KV
+
DFlash2
```

Start:

```text
context = 8K
n-max = 2
batch = 1
```

Then:

```text
n-max 2
3
4
5
6
7
```

Then repeat the best two configurations at:

```text
16K
32K
64K
```

---

# 5.1 The key output from this phase

We want a table like:

| Context | n-max | VRAM | Acceptance | Decode | Speedup |
| ------: | ----: | ---: | ---------: | -----: | ------: |
|      8K |     2 |      |            |        |         |
|      8K |     3 |      |            |        |         |
|      8K |     4 |      |            |        |         |
|      8K |     5 |      |            |        |         |
|      8K |     6 |      |            |        |         |
|      8K |     7 |      |            |        |         |
|     16K |     2 |      |            |        |         |
|     ... |       |      |            |        |         |

That becomes the core SGLang result.

---

# PHASE 6 — vLLM

Now we have a reason to test vLLM.

The `lued` W8A16 DFlash2 checkpoint is specifically interesting here.

The repository states:

```text
BF16 drafter = 3.58 GiB
W8A16 drafter = 2.02 GiB
```

and provides a DFlash configuration using 7 speculative tokens. ([Hugging Face][1])

---

# 6.1 vLLM baseline

Do **not** immediately enable DFlash.

Run:

```text
target
+
best target quantization that fits
```

and establish:

```text
decode
prefill
VRAM
context
```

---

# 6.2 vLLM + W8 DFlash2

Then:

```text
target
+
lued W8A16 DFlash2
```

Test:

```text
n=2
3
4
5
6
7
```

assuming the patched vLLM implementation permits those values.

---

# 6.3 Why vLLM is useful even if it loses

vLLM becomes our **reference DFlash implementation**.

If:

```text
vLLM DFlash works
SGLang DFlash fails
```

we know the problem probably isn't:

```text
DFlash2 model
```

It is probably:

```text
SGLang integration
```

Likewise, if:

```text
vLLM W8 DFlash
```

uses 4+ GB more than the llama.cpp version, that's valuable information about runtime overhead.

---

# PHASE 7 — Quality validation

This needs to be separate from performance.

Do not decide:

> "DFlash is correct because it generated plausible text."

Instead establish a deterministic baseline.

---

# 7.1 Greedy equivalence

For:

```text
temperature = 0
```

run:

```text
baseline
DFlash n=2
DFlash n=3
...
DFlash n=7
```

using exactly the same prompts.

Compare:

```text
output token sequence
```

where the runtime guarantees exact speculative decoding semantics.

DFlash is supposed to be lossless because the target verifies the draft; recent reports explicitly describe it this way. ([vramcalculator.com][2])

If outputs differ:

**flag it immediately.**

Do not continue performance benchmarking until the discrepancy is explained.

---

# 7.2 Quality benchmark

Use a small fixed suite:

```text
10 coding
10 math
10 reasoning
10 knowledge
10 structured JSON
10 long-context
```

This isn't meant to produce publishable benchmark scores.

It is a **regression detector**.

---

# PHASE 8 — Performance methodology

This part is critical.

Never compare:

```text
llama.cpp:
Q4
16K
batch 2048

versus

SGLang:
W2
32K
batch 1
```

and call the result meaningful.

Every comparison needs controlled variables.

---

# Core benchmark variables

Keep constant:

```text
GPU
driver
model
prompt
output length
temperature
sampling
context
batch
KV
```

Change only:

```text
engine
quantization
speculative decoding
```

---

# Metrics

Capture at minimum:

### Latency

```text
TTFT
TPOT
inter-token latency
```

### Throughput

```text
prompt tok/s
decode tok/s
total tok/s
```

### Speculation

```text
draft tokens
accepted tokens
acceptance rate
mean acceptance length
```

### Memory

```text
peak VRAM
steady-state VRAM
weights
KV
draft
temporary
```

### System

```text
GPU utilization
GPU power
GPU temperature
clock
```

### Reliability

```text
startup success
OOM
CUDA errors
crashes
timeouts
corrupted output
```

---

# PHASE 9 — Long-context stress testing

This is particularly important for your intended TurboQuant use.

Run:

```text
8K
16K
32K
64K
128K
```

where possible.

At each:

```text
prefill  →  decode 500
```

Then:

```text
prefill → decode 2K
```

We want to see whether DFlash2 remains beneficial when the target is already heavily attention/KV-bound.

---

# PHASE 10 — Agentic workload

This should be its own benchmark.

Since you are interested in Codex/CLI-style workloads, use a realistic sequence:

```text
prompt
↓
inspect code
↓
reason
↓
generate code
↓
inspect result
↓
modify
↓
test
↓
fix
```

Record the entire session.

Why?

Because raw:

```text
tokens/sec
```

doesn't necessarily translate into:

```text
agent task completion time
```

DFlash can increase decode speed but add draft computation and prefill cost.

The SGLang community has already observed cases where DFlash **reduced** throughput despite reasonable acceptance, so we absolutely need end-to-end measurements rather than assuming speculative decoding helps. ([GitHub][8])

---

# PHASE 11 — Find the Pareto frontier

Once everything is measured, don't simply select:

> fastest configuration.

Build a Pareto frontier using:

```text
decode speed
VRAM
context
quality
```

For example:

```text
Configuration A
35 tok/s
14.5 GB
32K
excellent quality

Configuration B
42 tok/s
15.8 GB
16K
excellent quality

Configuration C
38 tok/s
14.2 GB
64K
excellent quality
```

Depending on your use case, **C may actually be the best configuration**.

---

# PHASE 12 — Cross-engine comparison

Eventually produce one master table:

| Engine    | Target | Draft | KV | Context | n-max | VRAM | Decode | Acceptance | Speedup |
| --------- | ------ | ----- | -- | ------: | ----: | ---: | -----: | ---------: | ------: |
| llama.cpp |        |       |    |         |       |      |        |            |         |
| SGLang    |        |       |    |         |       |      |        |            |         |
| vLLM      |        |       |    |         |       |      |        |            |         |

And another:

| Engine    | Startup | TTFT | 8K | 16K | 32K | 64K |
| --------- | ------: | ---: | -: | --: | --: | --: |
| llama.cpp |         |      |    |     |     |     |
| SGLang    |         |      |    |     |     |     |
| vLLM      |         |      |    |     |     |     |

---

# PHASE 13 — Determine *why* one engine wins

This is the part I would explicitly tell the implementing AI **not to skip**.

If SGLang wins, determine why.

Potential explanation:

```text
Escha W2
+
custom GEMV
+
Triton attention
+
TurboQuant
```

If llama.cpp wins:

```text
GGUF kernel maturity
+
lower runtime overhead
+
Q4 DFlash drafter
```

If vLLM wins:

```text
better DFlash integration
+
W8 drafter
+
optimized verification
```

Don't stop at:

> "SGLang is 18% faster."

We want:

> "SGLang is 18% faster because target decode is memory-bandwidth bound and Escha's W2 GEMV reduces target weight traffic by X, while the other engines spend Y GB/s more."

That is the useful engineering conclusion.

---

# PHASE 14 — Failure taxonomy

Every failure should be categorized.

## Category A — Installation

```text
pip
CUDA
ABI
dependency
```

## Category B — Model loading

```text
unsupported architecture
tensor mismatch
quantization mismatch
```

## Category C — VRAM

```text
weight allocation
KV allocation
draft allocation
CUDA graph capture
```

## Category D — Kernel

```text
Triton
CUDA
FlashInfer
Escha kernel
DFlash kernel
```

## Category E — Runtime

```text
scheduler
speculative decoder
batching
KV cache
```

## Category F — Quality

```text
wrong output
template
reasoning
sampling
```

## Category G — Performance

```text
slow draft
low acceptance
verification overhead
memory bandwidth
```

This makes debugging dramatically easier.

---

# PHASE 15 — Automatically capture everything

I would have the AI create a benchmark harness rather than manually running commands.

Something like:

```text
qwen38-bench/
│
├── README.md
├── PLAN.md
├── RESULTS.md
├── FINDINGS.md
├── CONCLUSIONS.md
│
├── environment/
│   ├── gpu.txt
│   ├── driver.txt
│   ├── cuda.txt
│   └── software.txt
│
├── configs/
│   ├── llama/
│   ├── sglang/
│   └── vllm/
│
├── prompts/
│   ├── code/
│   ├── math/
│   ├── reasoning/
│   ├── prose/
│   ├── json/
│   └── long_context/
│
├── runs/
│   ├── llama/
│   ├── sglang/
│   └── vllm/
│
├── logs/
│
├── metrics/
│
└── analysis/
```

Every run gets a unique ID:

```text
2026-08-20_llama_q4km_q8kv_dflash_n4_16k
```

---

# PHASE 16 — Machine-readable results

Have the benchmark produce JSON for every run.

Something approximately like:

```text
run_id
timestamp
engine
engine_commit
target_model
target_revision
target_quant
draft_model
draft_revision
draft_quant
kv_type
context_length
batch_size
n_max

gpu
driver
cuda
torch

startup_time
peak_vram_mb
prompt_tokens
output_tokens
prefill_tps
decode_tps
ttft_ms
tpot_ms

draft_tokens
accepted_tokens
acceptance_rate
mean_accept_length

temperature
top_p
top_k
seed

exit_code
errors
warnings
```

Then generate Markdown reports from the JSON.

That gives you **reproducibility instead of screenshots and manually copied numbers**.

---

# PHASE 17 — Reflection after every phase

After each phase, require the AI to produce:

## Observations

What actually happened?

## Surprises

What differed from expectations?

## Hypotheses

Why?

## Evidence

What measurements support the hypothesis?

## Next experiments

What is the smallest experiment that can distinguish competing explanations?

## Dead ends

What should **not** be attempted again?

That last one is particularly useful.

---

# PHASE 18 — Adaptive experimentation

Don't blindly execute a 200-run matrix.

Use staged expansion.

For example:

```text
             Baseline
                │
         Does model fit?
           /          \
         NO            YES
         │              │
      stop/fix       measure
                        │
                 DFlash available?
                    /        \
                  NO          YES
                  │            │
              investigate    n=4
                               │
                       positive speedup?
                         /          \
                       NO            YES
                       │              │
                    n=2/3          n=2–7
                       │              │
                       └──────┬───────┘
                              │
                         best n-max
                              │
                       add TurboQuant
                              │
                       context sweep
```

This is much more efficient than brute force.

---

# The specific order I would use

## Stage 1 — llama.cpp

### Target

```text
Qwen3.8-27B Q4_K_M
```

### KV

```text
Q8_0
```

### Baseline

```text
no DFlash
```

Then:

```text
DFlash2 Q4_K_M
n=2,3,4,5,6,7
```

Then:

```text
best n
+
Q4 KV
```

Then:

```text
context sweep
```

Then optionally:

```text
Q3/Q5 target
```

---

# Stage 2 — SGLang / Escha

### Baseline

```text
Escha W2
Triton
INT8 head
no DFlash
no TurboQuant
```

Then:

```text
context sweep
```

Then:

```text
TurboQuant 4-bit
```

Then:

```text
DFlash2
```

Then:

```text
TurboQuant + DFlash2
```

Then:

```text
n=2–7
```

Then:

```text
context × n-max
```

---

# Stage 3 — vLLM

Baseline:

```text
best target quant that fits
```

Then:

```text
lued/Qwen3.8-27B-DFlash2-W8
```

Then:

```text
n=2–7
```

Then:

```text
KV variants
```

Then:

```text
context sweep
```

---

# Stage 4 — final A/B

Take the **best configuration from each engine**.

Then run exactly the same workload suite:

```text
10 code
10 math
10 reasoning
10 prose
10 JSON
10 long-context
10 agentic
```

No more tuning.

This becomes the final comparison.

---

# One thing I would specifically add: "break-even analysis"

For every DFlash configuration calculate:

```text
baseline_time_per_token
draft_overhead
verification_overhead
accepted_tokens
```

Then derive:

```text
minimum acceptance length required
for DFlash to beat baseline
```

This is much more useful than simply reporting acceptance.

For example:

```text
baseline = 40 tok/s

DFlash n=2
accept = 1.7
→ -4%

DFlash n=3
accept = 2.3
→ +11%

DFlash n=4
accept = 2.8
→ +24%

DFlash n=5
accept = 2.9
→ +20%
```

Then we learn:

> **The optimal n-max is 4, because n=5 doesn't produce enough additional accepted tokens to pay for its additional drafting cost.**

That's an actual engineering conclusion.

---

# What I expect we'll discover

My current hypothesis is:

### llama.cpp

Likely easiest path to DFlash2.

```text
Q4_K_M target
+
Q4_K_M DFlash2
+
Q8/Q4 KV
```

should establish whether DFlash2 itself is worthwhile on 16 GB.

---

### vLLM

Likely easiest path to the **W8A16 DFlash2 drafter** because that repository explicitly targets the vLLM implementation. ([Hugging Face][1])

But I expect memory pressure to be significant.

---

### SGLang

Potentially the most interesting.

Because:

```text
Escha W2 = 10.15 GB
```

is dramatically smaller than conventional Q4/Q5 target weights. ([Hugging Face][7])

That leaves room for:

```text
DFlash2
+
TurboQuant
+
large KV
```

that the other engines may not have.

But **this is also the least certain integration path**, because the Escha runtime is a custom SGLang fork and its documented configuration does not currently establish DFlash2/TurboQuant interoperability. ([Hugging Face][5])

---

# The experiment's actual research question

I would frame the entire project as:

> **Can an RTX 5060 Ti 16 GB run Qwen3.8-27B at useful interactive/agentic speed by combining ultra-low-bit target weights, quantized KV cache, and DFlash2 speculative decoding—and which inference engine provides the best memory/performance tradeoff?**

Then the subquestions become:

1. What is the fastest **plain** Qwen3.8-27B configuration?
2. What target quantization gives the best speed/quality/VRAM balance?
3. What KV quantization gives the best memory/latency tradeoff?
4. What DFlash2 `n-max` is optimal on 16 GB?
5. Does DFlash2 actually improve **end-to-end** latency?
6. Does DFlash2 remain useful at long context?
7. Can SGLang's Escha W2 reduce enough target-model memory to make the complete stack viable?
8. Can TurboQuant turn that remaining memory into useful context?
9. Does SGLang's custom Escha kernel offset its DFlash integration complexity?
10. Which engine gives the best **tokens/sec per GB of VRAM**?
11. Which gives the best **agent-task completion time**, rather than merely raw decode speed?

That last metric is probably the one I'd ultimately care about most for your intended Codex/agent workloads.

## Most important immediate action

I would **start with llama.cpp exactly as you suggested**, because the DFlash2 Q4_K_M path is already being actively tested there. Current reports show Qwen3.8-27B + Q4_K_M DFlash2 working, while the upstream llama.cpp implementation is still evolving. ([Reddit][3])

Then we use those results to decide how aggressively to pursue SGLang.

And I would **not download the 2.02-GiB W8 drafter for llama.cpp**. That's primarily useful for the vLLM experiment. For llama.cpp, use the **Q4_K_M GGUF DFlash2**. For SGLang, first determine the exact DFLASH checkpoint format expected by the Escha fork before attempting conversion. For vLLM, use the `lued` W8A16 checkpoint as the first serious DFlash2 candidate. ([Hugging Face][1])

That gives us a very clean experimental split:

```text
                    Qwen3.8-27B
                         │
        ┌────────────────┼────────────────┐
        │                │                │
    llama.cpp          SGLang           vLLM
        │                │                │
   GGUF DFlash2      Escha W2         W8A16 DFlash2
      Q4_K_M             │                │
        │          TurboQuant KV          │
        │                │                │
        └───────────────┬┴────────────────┘
                        │
                 same benchmark
                        │
             ┌──────────┴──────────┐
             │                     │
       raw performance       agent performance
             │                     │
             └──────────┬──────────┘
                        │
                  final winner
```

This is the approach I'd hand to an implementation agent rather than giving it one giant "benchmark everything" task. It creates a sequence of **small, independently verifiable experiments**, and each result determines the next experiment.

[1]: https://huggingface.co/lued/Qwen3.8-27B-DFlash2-W8 "lued/Qwen3.8-27B-DFlash2-W8 · Hugging Face"
[2]: https://vramcalculator.com/dflash-2-speculative-decoding/?utm_source=chatgpt.com "DFlash 2 Doubles Qwen 3.8 27B Again: The VRAM Cost"
[3]: https://www.reddit.com/r/LocalLLaMA/comments/1vs43av/i_tested_dflash2_for_qwen38_27b_on_a_5090/?utm_source=chatgpt.com "I tested DFlash2 for Qwen3.8 27B on a 5090"
[4]: https://github.com/sgl-project/sglang/blob/main/docs_new/docs/advanced_features/speculative_decoding.mdx?utm_source=chatgpt.com "sglang/docs_new/docs/advanced_features/speculative_decoding.mdx at main · sgl-project/sglang · GitHub"
[5]: https://huggingface.co/EschaLabs/escha-runtime-qwen3dense "EschaLabs/escha-runtime-qwen3dense · Hugging Face"
[6]: https://www.reddit.com/r/LocalLLaMA/comments/1vsuaoj/dflash2_speeds_qwen_38_27b_up_to_4_times/?utm_source=chatgpt.com "DFlash2 speeds Qwen 3.8 27B up to 4 times"
[7]: https://huggingface.co/EschaLabs/Qwen3.8-27B-Escha-W2 "EschaLabs/Qwen3.8-27B-Escha-W2 · Hugging Face"
[8]: https://github.com/sgl-project/sglang/issues/29244?utm_source=chatgpt.com "[DFlash][Performance] Speculative Decoding (DFlash) slowing down inference on Qwen3-30B-A3B (A800, BS=1) · Issue #29244 · sgl-project/sglang · GitHub"
