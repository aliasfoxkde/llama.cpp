# Llama Server — API Reference & Orchestration Guide

## Overview

Systemd-managed llama.cpp server running on RTX 5060 Ti 16GB (Fedora).

**Endpoint:** `http://localhost:8082`

---

## Service Management

```bash
llama-server start     # Start the service
llama-server stop     # Stop the service
llama-server restart # Restart (reload model)
llama-server status  # Check if running
llama-server log     # Follow logs (Ctrl+C to exit)
```

---

## Model Switching

```bash
llama-server switch              # List available models
llama-server switch <alias>     # Switch model (auto-restarts)
```

### Available Models

| Alias | Model | Size | Load Time | Best For |
|-------|-------|------|-----------|----------|
| `Qwen3.8-27B` | Qwen3.8-27B UD-IQ3_XXS | 12GB | ~2.3s | Code/agent tasks, 128K ctx |
| `Qwen3.6-35B-A3B-REAP-MTP` | Qwen3.6-35B REAP-MTP | 13GB | ~9.6s | Fast small tasks, MTP |

### Model Specifications

#### Qwen3.8-27B (default)
- **Quantization:** IQ3_XXS (~3-bit)
- **Context:** 131072 tokens (128K)
- **KV Cache:** q4_0/q4_0
- **Throughput:** ~30 t/s concurrent, ~54 t/s peak
- **VRAM:** ~13.8GB

#### Qwen3.6-35B REAP-MTP
- **Quantization:** Q3_K_M
- **Context:** 131072 tokens (128K)
- **KV Cache:** q4_0/q4_0
- **MTP:** draft-mtp n=3
- **Throughput:** ~210 t/s for small tasks (claimed)
- **VRAM:** ~14.5GB

---

## API Endpoints

### Health Check
```bash
curl http://localhost:8082/health
# Response: {"status":"ok"}
```

### Completion (POST)
```bash
curl -X POST http://localhost:8082/completion \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Your prompt here",
    "n_predict": 128,
    "cache_type_k": "q4_0",
    "cache_type_v": "q4_0",
    "temperature": 0.7,
    "stop": ["</s>", "end"]
  }'
```

**Key fields:**
- `prompt` (string, required) — Input text
- `n_predict` (int) — Max tokens to generate
- `cache_type_k` / `cache_type_v` — Override KV cache quantization per-request
- `temperature` (float) — Sampling temperature (0.0-2.0)
- `top_p` (float) — Nucleus sampling threshold
- `stop` (array) — Stop sequences

### Infill (POST)
```bash
curl -X POST http://localhost:8082/infill \
  -H "Content-Type: application/json" \
  -d '{"prompt": "prefix", "suffix": "suffix", "n_predict": 64}'
```

---

## Per-Request KV Cache Override

You can override KV cache quantization per-request (server uses q4_0/q4_0):

```bash
# Use f16 KV for a specific request
curl -X POST http://localhost:8082/completion \
  -d '{"prompt":"test","n_predict":32,"cache_type_k":"f16","cache_type_v":"f16"}'

# Mix K and V types
curl -X POST http://localhost:8082/completion \
  -d '{"prompt":"test","n_predict":32,"cache_type_k":"q8_0","cache_type_v":"q4_0"}'
```

**Supported KV types:** `f16`, `q4_0`, `q4_1`, `q5_0`, `q5_1`, `q8_0`, `iq4_nl`, `f32`, `bf16`

**Note:** K != V makes zero measurable difference in throughput. Use symmetric q4_0/q4_0.

---

## Orchestration Timing

### Model Load Times
- **Qwen3.8-27B IQ3_XXS:** ~2.3 seconds
- **Qwen3.6-35B REAP-MTP:** ~9.6 seconds (MTP overhead)

### Health Polling
```bash
# Wait for server to be ready
while ! curl -s http://localhost:8082/health > /dev/null 2>&1; do sleep 0.5; done
echo "Server ready"
```

### Model Switch Sequence
1. Call `llama-server switch <alias>`
2. Server stops (~2s)
3. Symlink updates (~instant)
4. Server starts (model load time)
5. Server responds to health → ready

---

## Python Example

```python
import requests
import time

API = "http://localhost:8082"

def wait_ready(timeout=30):
    start = time.time()
    while time.time() - start < timeout:
        if requests.get(f"{API}/health").status_code == 200:
            return True
        time.sleep(0.5)
    return False

def complete(prompt, n_predict=128, **kwargs):
    payload = {"prompt": prompt, "n_predict": n_predict, **kwargs}
    resp = requests.post(f"{API}/completion", json=payload)
    resp.raise_for_status()
    return resp.json()

# Usage
if wait_ready():
    result = complete("Write a function", temperature=0.7)
    print(result["content"])
```

---

## Caching Behavior

The server maintains a KV cache. For repeated prompts:
- First request: full prompt evaluation
- Subsequent requests: cache hit for shared prefix (faster)

Cache is per-slot and shared across requests when using multiple slots (n_parallel=4).

---

## Troubleshooting

### Server won't start
```bash
llama-server log  # Check errors
journalctl --user -u llama-server -e  # Recent logs
```

### OOM errors
- Reduce context size
- Switch to smaller model
- Check GPU memory: `nvidia-smi`

### Model switch fails
```bash
llama-server switch Qwen3.8-27B  # Force default
```
