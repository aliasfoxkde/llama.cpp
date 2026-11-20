# Local Model Qualification Plan

**Status:** planning only. No GPU tests or runtime changes have been made for this plan.

**Updated:** 2026-11-20

This plan qualifies serving profiles for speed, concurrency, tool use, and quality. It extends the existing [RTX 5060 Ti benchmark results](RTX5060TI-RESULTS.md) and [benchmark plan](RTX5060TI-BENCHMARK-PLAN.md), which primarily cover Qwen3.6-35B-A3B performance and do not establish agentic tool-loop quality.

## Questions to answer

1. Can the Fedora Ultra profile exceed its current roughly 28 tok/s report on the exact Qwen3.8-27B IQ3_S-MTP GGUF?
2. Can a faster configuration preserve tool-call correctness and the current quality band?
3. Does Gyro-S on Strata provide enough task-quality benefit to justify its memory, storage, and speed tradeoffs?
4. Which serving profiles improve per-request latency, aggregate throughput, and queue delay separately?
5. Which speed switches alter answers, and are any gains worth those changes?

## Validate the 57.2 tok/s report

The user-submitted RTX 5060 Ti report lists 57.2 tok/s for Qwen3.8-27B 3-bit using Ignis and compares it with Gyro-S. It also gives 5,828 generated tokens and 110.79 seconds; if that is the same timing interval, the quotient is about 52.6 tok/s. Preserve the original timing definition if available. Do not treat it as the Fedora target until the GGUF hash, engine, draft configuration, context, prompt mix, output length, and timing boundaries match or are explicitly accounted for. See [the report](https://llamaperf.com/?gpu=70).

## Benchmark profiles

The main model families under test are:

- **Turbo:** current Qwen3.6-35B-A3B REAP/MTP profile on the Fedora `llama-mst` build.
- **Ultra:** Qwen3.8-27B IQ3_S-MTP, using the exact local GGUF and its matching projector where required.
- **Pro candidate:** Qwen3.8-Flash-Next Gyro-S using a pinned Strata engine and the supported Gyro files.
- **Lite:** Qwen3.8-2B profile as a fallback candidate, preferably tested on CPU or separate resources if it must remain available while another model uses the GPU.

Do not test Project Maya as part of this qualification plan. Strata is the selected runtime for the Gyro-S experiment. Other llama.cpp forks remain candidates only when the measured bottleneck matches their optimization.

## Short regression probe

Build a fixed 12-task suite intended to finish in a few minutes on a warm model:

| Group | Tasks | Required evidence |
|---|---:|---|
| Known-answer/document retrieval | 3 | Exact answer keys or required facts |
| Tool use | 4 | Correct tool choice, schema-valid arguments, multi-tool completion, and failure recovery |
| Code/file changes | 3 | Expected diff, successful command/test, and no unrelated edits |
| Multi-turn/context | 2 | Facts persist across turns and are retrieved correctly |

Keep prompts, tool schemas, expected outputs, sampling, output limits, and input sizes versioned. Grade with deterministic checks wherever possible. Do not use another model as the only grader. Add a small vision sub-suite only when a vision-capable profile is being evaluated.

Use the existing 52-task arithmetic/code probe as a second gate. It is useful for those tasks but is not a substitute for tool loops, file edits, multi-turn behavior, or long-context work.

## Test method

For each profile, pin:

- Model and auxiliary-file SHA-256 hashes.
- Engine source commit, build flags, CUDA/runtime and driver versions.
- Context, slots, batch settings, KV formats, offload settings, sampling, reasoning, MTP/draft settings, and environment variables.
- Exact prompt and output token counts, tool schema, concurrency, warm/cold state, and benchmark commit.

Use temperature zero for reproducible speed/correctness checks unless the task specifically evaluates sampling. Run at least five paired, interleaved A/B rounds for speed candidates. Do not change multiple variables between arms. Keep the GPU otherwise idle and load only one large model at a time. Do not run these experiments while Fedora is serving production requests.

Measure separate workload shapes:

| Shape | Inputs | Main outputs |
|---|---|---|
| Short response | 20-100 tokens | TTFT, decode tok/s, small-task correctness |
| Typical agent turn | 1K-8K tokens | End-to-end latency, tool-loop completion, tokens/turn |
| Long context | 32K and 128K where profile allows | Prefill rate, TTFT, decode after context fill, memory |
| Concurrency | 1, 2, 4, 8 clients as memory permits | Aggregate tok/s, per-client rate, p50/p95 queue and response delay |
| Reload | Model/profile switch | Drain time, startup time, readiness, correct loaded identity, rollback |

Track quality/task pass rate, malformed tool calls, repeated or no-op tool calls, correct file diff, turns and tokens to completion, TTFT, prefill/decode rate, aggregate throughput, queue wait, wall time, RAM, swap, VRAM, temperature, GPU power, and failures. Wall power is not available from the current Fedora audit; use a plug meter or UPS/PDU telemetry if whole-system energy is required.

## Ultra optimization order

Use the exact Ultra file and current `llama-mst` configuration as the control. First reproduce the current result. Then test one variable at a time:

1. MTP off and on, then a small MTP window sweep; record draft acceptance as well as speed.
2. Context and KV format at realistic operating points; include the vision projector when evaluating the vision profile.
3. Batch and slot counts; compare latency and aggregate throughput separately.
4. Compatible 27B quant variants that fit the actual memory budget; record exact hashes.
5. Matching upstream llama.cpp build versus `llama-mst` only after the production build is reproducible.

The Codacus fork's expert cache, asynchronous prefetch, and pinned host-memory optimizations are relevant to Turbo only if measurements show experts are being served from CPU/RAM. Do not expect those optimizations to double a dense 27B Ultra profile. Test the fork in an isolated build directory and only after confirming it supports the exact model and required MTP behavior. Its published Qwen3.8 gains are from different hardware and workloads. See [the fork](https://github.com/thecodacus/llama.cpp) and [upstream discussion](https://github.com/ggml-org/llama.cpp/discussions/24528).

## Gyro-S and Strata experiment

The Gyro model card reports 27.64 GiB full weights, 28.8 GiB total at 64K context, and a 58.5 GB download. The custom weight format is supported by Strata and selected other specialized builds, not stock upstream llama.cpp. Use a pinned Strata release and verify every downloaded artifact. See the [model card](https://huggingface.co/agentionai/Qwen3.8-Flash-Next-Gyro-GGUF) and [Strata Gyro guide](https://github.com/Niko1221/Strata/blob/main/docs/GYRO.md).

Initial arm:

- Strata 0.2.17 / engine 0.1.63 or a later explicitly pinned release.
- Text-only, modest context, one generation at a time.
- Full expert routing, `STRATA_ROUTE_TAIL_SKIP=0`.
- Record the effective Blackwell-specific settings at startup.

Then evaluate each answer-changing speed switch separately. Strata 0.2.17 turns route-tail skip off by default after reports of quality loss. Rank 7 is an opt-in speed arm, not the baseline. The same release enables `STRATA_ADAPT_FETCH=2` by default on one RTX 50 GPU of 16 GB or less; test it against `=0`. Also pin/test its Blackwell short-read behavior. The release reports different gains by request type and some output differences, so record both speed and task outcomes. See [Strata 0.2.17 release notes](https://www.stratat.com/es/releases/v0.2.17).

Gyro-S is not accepted as a free intelligence upgrade based on model-card KLD or an outside speed report. Compare it directly against Ultra and Turbo on the same agentic suite. The model card's 98% of Q4 MMLU-Pro claim is for Gyro-M, not Gyro-S.

## Fork and switch decision rules

- Use `llama-mst` as the production control for existing Turbo and Ultra profiles.
- Use Strata for the Gyro-S/Pro profile.
- Test the Codacus fork only when a CPU/RAM expert-offload bottleneck exists and only for compatible model formats.
- Test no fork only because a headline tok/s number is larger. Every candidate must load the exact model, use the intended API/tool path, pass the probe, and show a paired speed benefit.
- Treat a switch as safe only if outputs are expected to remain the same and the probe confirms it. For answer-changing approximations, require no critical task regression, disclose the approximation in the profile, and keep a one-setting rollback.

## Initial acceptance gates

These thresholds are starting points to be reviewed after the control runs:

- 100% of required tool arguments are schema-valid; no crash, hang, or OOM.
- All critical file-edit checks pass with no unrelated changes.
- The 12-task smoke suite has no regression on critical tasks and no more than one total task regression versus the control; investigate every changed failure.
- A performance claim requires at least 5% median improvement across paired runs and a spread that is not explained by run-to-run noise.
- Report per-request latency, aggregate throughput, and queue delay separately. Never promote a profile based on aggregate tok/s alone if its per-request context or latency is unsuitable.
- A switched profile must report the requested and actually loaded model IDs identically, pass health checks, and restore the previous profile after a forced startup failure.

After the short suite passes, run the full 52-task probe and a larger agentic qualification set before changing any production default.
