# T5500 On-Demand Inference Plan

**Status:** planning only. The T5500 is off and has a reported startup fan fault. Do not automate power-on or serve model requests from it until that fault is repaired and verified.

**Updated:** 2026-11-20

This plan describes a cold-standby provider that accepts queued requests while powered off, starts only when work is eligible, and shuts down after a measured idle period. Its power target is at least 95% less energy than leaving the host on continuously, measured over a representative period. This is a goal, not a guarantee.

## Safety and readiness gate

The fan fault blocks unattended startup. Before enabling any on-demand action:

1. Identify the exact host, motherboard/firmware, GPU(s), fan(s), and existing fan-control method.
2. Diagnose and repair the fan fault. Confirm the machine completes multiple cold boots without the fault.
3. Observe GPU and CPU temperatures and fan behavior under sustained load and after shutdown/restart.
4. Document the supported remote power-on and graceful power-off methods, credentials, timeout, and recovery behavior.
5. Keep automatic power control disabled until a human signs off on the hardware check.

Do not use a smart plug or hard power cut to stop a running host. Prefer a documented out-of-band controller, Wake-on-LAN, or managed PDU for power-on only if the exact hardware supports it. Use an authenticated OS shutdown for normal power-off. Retain a manual recovery path.

## Always-on request queue

The queue must live on an always-on system such as the router/orchestrator, not on the T5500. A request should include:

- Unique request ID and idempotency key.
- Explicit provider/model profile and capability requirements.
- Creation time, expiration time, maximum queue time, and cancellation state.
- Priority/fairness class and bounded token/output limits.
- A protected request payload reference; logs should store metadata, not prompt contents or credentials.

The API should tell clients whether work is `queued`, `starting`, `ready`, `running`, `completed`, `expired`, `cancelled`, or `failed`. Queue depth, oldest age, and an estimated wait should be visible. Bound the queue and payload retention. Do not silently hold work indefinitely while the host is off.

When a valid request arrives and the T5500 is off, the controller should:

1. Confirm that the profile is eligible and the queue has capacity.
2. Coalesce simultaneous wake requests into one start operation.
3. Start the T5500 through the verified control path.
4. Wait for OS, network, GPU, fan/thermal, and model-service readiness checks.
5. Dispatch queued work only after the expected model ID and health checks pass.
6. Route elsewhere or fail clearly if startup fails or the request expires.

The route decision is deterministic: explicit model ID, capability, queue policy, power state, and readiness determine dispatch. No model chooses whether the host should power on.

## Power state machine

Use one controller with a single state per host:

```text
OFF -> STARTING -> VERIFYING -> READY -> BUSY -> DRAINING -> STOPPING -> OFF
                    |             |             |
                    +----------> FAULTED <-------+
```

- `OFF`: accept eligible work into the queue; do not dispatch.
- `STARTING`: one power-on operation is in progress; concurrent requests join the same wait.
- `VERIFYING`: wait for network, GPU, temperatures, fans, filesystem, and model health.
- `READY`: admit work according to the provider's concurrency limit.
- `BUSY`: one or more admitted requests are active; prevent shutdown.
- `DRAINING`: stop new admission while existing generations finish.
- `STOPPING`: request graceful OS shutdown, then confirm the host is actually off.
- `FAULTED`: block automatic starts, preserve queue status, alert the operator, and use configured fallback/expiry behavior.

Every transition needs a timeout and an observable reason. Restart attempts must be bounded with a cooldown. A failed fan/thermal check immediately enters `FAULTED`; it must not loop through repeated boots.

## Queue and power policy

Tune these values from observed use rather than hard-coding guesses:

- Maximum queue length and queue TTL.
- Maximum wait before using another qualified provider or returning an error.
- Priority and fairness between users/services.
- Startup timeout and health-check timeout.
- Minimum on-time after the final request to avoid rapid power cycling.
- Idle grace period before draining and shutdown.
- Maximum continuous run time and an operator override.
- Cooldown after shutdown and after a failed start.

Batch requests that arrive during startup. Keep the host on while any request is active or any stream is open. When the queue is empty, start the idle timer; cancel it if new work arrives. Do not repeatedly turn the host on and off for a bursty queue: use a measured minimum-on interval and hysteresis, while honoring request TTLs.

When the T5500 is unavailable, use a documented fallback order such as another qualified provider, Fedora Lite, or a clear unavailable response. Do not route to Fedora Turbo/Ultra/Pro without checking its own queue and resource state.

## Measuring the 95% energy goal

Compare controlled operation with the always-on baseline over the same representative period:

```text
always_on_energy = measured_average_always_on_watts * observation_hours
controlled_energy = off_energy + startup_energy + ready_idle_energy + inference_energy
savings_fraction = 1 - (controlled_energy / always_on_energy)
```

Measure wall power with a plug meter, UPS telemetry, or PDU; GPU board power alone is not whole-system power. Include boot and shutdown energy, idle time while ready, inference work, and time spent starting or recovering from faults. Report request latency and queue expirations alongside energy so the power target does not hide unusable wait times.

Collect at least a representative weekday/weekend sample before changing idle timers. If the host is off 95% of the time, that does not automatically mean 95% energy savings: startup, loaded power, and ready-idle duration still count.

## Qualification gates

Enable unattended T5500 use only after all gates pass:

1. Fan fault repaired; repeated cold starts and sustained thermal checks pass.
2. Manual power-on, health validation, inference, graceful shutdown, and restart pass.
3. Queue survives orchestrator restart without duplicate execution or lost status.
4. Duplicate wake requests create one boot; expired and cancelled work is not dispatched.
5. Fan, GPU, network, or model readiness failure enters `FAULTED` and does not retry in a loop.
6. Requests are dispatched only after the expected model identity is verified.
7. The idle shutdown timer never stops an active request or stream.
8. Measured energy and wait-time results meet the agreed target for a representative usage period.

## Rollout

1. Keep the host off and prepare queue/status logic on the always-on orchestrator without triggering power control.
2. Repair and manually validate the fan and thermal fault.
3. Run power-on and shutdown checks manually, recording boot time, service readiness time, idle draw, inference draw, and shutdown time.
4. Enable controller dry-run mode: compute intended actions but do not power the host.
5. Run supervised on-demand trials with short queue TTLs and a human watching startup/thermal status.
6. Enable unattended starts only after all gates pass; retain a one-command disable and manual override.

Until the fan issue is fixed, requests for T5500-only capability should queue only for a short, explicit TTL or fail over. They must not trigger a power-on attempt.
