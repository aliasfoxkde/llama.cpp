# Local Inference Architecture Plan

**Status:** planning only. No service, routing, model, storage, or hardware changes are authorized by this document.

**Updated:** 2026-11-20

This plan describes a local inference service that can switch models deterministically, keep a small fallback path available, and expose qualified providers to agents through direct and routed APIs. It keeps model lifecycle control outside the language model.

## Goals

- Preserve a simple direct API path for diagnosis when a router is unavailable or misconfigured.
- Add explicit, named model profiles for Turbo, Ultra, Pro, Lite, and future models.
- Select and load profiles using ordinary service logic, never by asking a model which process to start.
- Respect the fact that Fedora has one 16 GiB GPU and cannot keep all large profiles resident at once.
- Keep the T5500 powered off until its startup fan fault is repaired and verified; later, support queued on-demand use with measured power savings.
- Keep the benchmark and route definitions portable enough to qualify the T5500 and future Qwen models.

## Current evidence and constraints

The Fedora audit on 2026-11-20 found Fedora 44, an RTX 5060 Ti with 16,311 MiB, 31 GiB system RAM, and the following services:

| Service | State in the audit | Notes |
|---|---|---|
| `llama-server` | Active on port 8080 | Serving Turbo from a `llama-mst` build; 15,454 MiB GPU use was attributed to this process. |
| `llama-proxy` | Active on port 8082 | Responded to health/model requests. Backend management is disabled; systemd owns the server. |
| Qwen embedding server | Active on port 8105 | Used 128 MiB of GPU memory in the snapshot. |

The GPU had 311 MiB free at the time. Recent proxy requests spent about 62-72 seconds waiting in the queue, while their post-admission inference times were only a few seconds. Treat these as a live snapshot, not a performance benchmark.

The NVMe volume holding `/home` had 76 GB free at 96% use. `/nas` had 8.9 TB free but is a rotational disk. The Gyro-S GGUF is a 58.5 GB download, with additional pack, draft, and optional vision files. Keep active model files on NVMe; inventory and free space before downloading. Existing measurements note 3-15 second model loads from NVMe versus 47-171 seconds from `/nas` in tested cases. See [RTX5060TI-RESULTS.md](RTX5060TI-RESULTS.md).

The T5500 is currently off and has a fan fault during startup. It is not a burst provider until the fault is repaired and a human verifies normal fan and thermal behavior. Its current out-of-band power controls and network state have not been audited in this planning pass.

## Proposed service roles

| Role | Responsibility | Availability model |
|---|---|---|
| API proxy | OpenAI-compatible HTTP handling, request validation, bounded output, telemetry, and forwarding to the currently active engine | Always on; remains simple and independent of Amortyx |
| Model supervisor | Allowlisted profile selection, request admission, drain, start/stop, readiness checks, rollback, and status | Always on; non-AI process controlled by systemd |
| Turbo | Fast Qwen3.6-35B-A3B MoE profile | Fedora GPU, exclusive with other large models |
| Ultra | Qwen3.8-27B profile | Fedora GPU, exclusive with other large models |
| Pro | Candidate Qwen3.8-Flash-Next Gyro-S on Strata | Fedora GPU, exclusive; enabled only after qualification |
| Lite | Small local assistant fallback | Prefer CPU or separate hardware if it must remain available while a large model occupies the GPU |
| Embedding | Text embedding API | Separate service; retain only if its measured resource cost remains acceptable |
| OpenCodifier | Fast decision substrate for supported rules and retrieval tasks | Separate service with explicit API/provider entry |
| TTS, STT, image/video generation | Media tasks | CPU, separate accelerator, or GPU scheduler jobs; do not assume they can overlap a large model |
| Amortyx | Optional policy, routing, telemetry, and failover front door | Separate named providers; direct route remains available |

The always-on orchestrator is the model supervisor, not Lite. Lite may be an always-available conversational fallback, but it does not own service lifecycle decisions. Large GPU models are mutually exclusive until additional accelerator capacity is proven.

## Named profiles

Each profile should define:

- Stable public model ID and profile version.
- Model file, projector, draft file, and SHA-256 hashes.
- Engine name, source commit, build options, CUDA/runtime version, and binary path.
- Context, slots, batch settings, KV formats, MTP/draft settings, reasoning setting, vision capability, and output cap.
- Expected host RAM, VRAM, free-space requirements, startup timeout, and health checks.
- Supported modalities and tool-call qualification status.
- Throughput measurements by prompt length, concurrency, and benchmark revision.

Pro remains a candidate profile, not a promise of higher quality or speed. Gyro-S is a Qwen3.8-Flash-Next quant with custom rotor weight types. Its model card lists Strata and AgentionAI's llama.cpp build as supported runtimes and says stock upstream llama.cpp cannot load the files. Its reported 221 tok/s is for an RTX 5090 with full VRAM residency and does not predict Fedora performance. See the [Gyro model card](https://huggingface.co/agentionai/Qwen3.8-Flash-Next-Gyro-GGUF) and [Strata Gyro guide](https://github.com/Niko1221/Strata/blob/main/docs/GYRO.md).

## Deterministic request and model lifecycle

The API client names a profile. The supervisor applies a fixed allowlist and policy:

1. If the requested profile is already ready, admit the request under that profile's concurrency limit.
2. If a different profile is active, place the request in the bounded queue and begin a serialized switch only when active generations can drain.
3. Stop the current engine through systemd and verify process exit and GPU memory release.
4. Start the selected profile with its pinned configuration.
5. Verify process identity, loaded model path, API model ID, health endpoint, and declared context before admitting work.
6. If startup or health validation fails, mark the target unavailable and restore the last known-good profile.

Requests must never be silently served by a different model than the requested profile. Queued requests need a request ID, model ID, bounded wait/TTL, cancellation, and visible state. Coalesce simultaneous wake/switch requests for the same target. Apply fairness so a stream of Turbo requests cannot starve Ultra or Pro indefinitely.

Protect the control API separately from the inference API. It should accept only profile IDs, not arbitrary command lines or model paths. Write one durable transition log for state changes, but never log prompt bodies or secrets. Expose active profile, readiness, queue depth, queue age, last switch result, and next action in a health/status endpoint.

## Routing topology

```text
Agent or service
  -> direct API proxy ---------------------> model supervisor -> active Fedora engine
  -> Amortyx named route (optional) -------> direct API proxy or qualified remote provider
  -> explicit T5500 provider (future) -----> queue/power controller -> T5500 engine

Always-on supporting services: model supervisor, proxy, embeddings, OpenCodifier where reachable,
and optionally Lite on CPU or separate hardware.
```

Keep direct and routed choices explicit, such as `Fedora-Turbo-Direct`, `Fedora-Ultra`, `Fedora-Pro`, and later `T5500-FlashNext`. Amortyx should use provider capacity and health metadata rather than guessing the loaded model. Set per-GPU concurrency to the measured profile capacity. Preserve the direct route to distinguish proxy/model failures from router failures.

The current Fedora proxy's backend-management setting is disabled and the live deployment is systemd-managed. The eventual supervisor may control systemd units; do not make Amortyx or an LLM responsible for process management.

## Rollout gates

1. Document and reproduce active Turbo and Ultra profiles.
2. Build the fast qualification probe before accepting engine or model changes.
3. Test Ultra optimizations and Strata/Gyro-S in a maintenance window with one GPU model loaded at a time.
4. Add the supervisor only after the profile files, startup behavior, and rollback path are understood.
5. Test direct API and proxy first; add Amortyx after direct results pass.
6. Add T5500 only after the fan fault is repaired, startup is reliable, and its off-state control path is verified.
7. Add multimodal and media services after explicit resource budgets and scheduling policy exist.

Do not bind profile policy to Qwen3.8 names or flags. Qwen4 should enter as a new catalog profile with its own compatibility and qualification record.
