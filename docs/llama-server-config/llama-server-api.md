# Llama Server — API Reference & Orchestration Guide

## Overview

Systemd-managed llama.cpp server with model switching proxy running on RTX 5060 Ti 16GB (Fedora).

**Proxy Endpoint:** `http://localhost:8082`

---

## Available Models

### Model Specifications

| Property | Ultra | Turbo | Distill-9B | Maziyar-8B | Maziyar-0.6B |
|----------|--------|--------|------------|-------------|---------------|
| **Model** | Qwen3.8-27B + vision | Qwen3.6-35B-A3B MoE | Qwen3.8-9B distilled | Qwen3-8B | Qwen3-0.6B |
| **Quantization** | IQ3_XXS | Q3_K_M REAP-MTP | Q4_K_M | Q4_K_M | Q4_K_M |
| **Context** | 128K | 128K | 128K | 128K | 128K |
| **Parameters** | 27B Dense | 35B MoE (~27B active) | 9B Dense | 8B Dense | 0.6B Dense |
| **VRAM** | ~15.0GB | ~15.4GB | ~5.5GB | ~5.0GB | ~0.7GB |
| **Vision** | ✅ Yes | ❌ No | ❌ No | ❌ No | ❌ No |
| **MTP** | ❌ No | ✅ Yes (n_max=3) | ❌ No | ❌ No | ❌ No |
| **Single-stream TPS** | ~30 TPS | ~100 TPS | ~67 TPS | ~79 TPS | ~440 TPS |

### Model Details

**Ultra** - Unsloth Qwen3.8-27B + mmproj-F16 vision encoder
- Best for: Quality + multimodal (images)
- Single-stream: ~30 TPS
- Architecture: 27B Dense

**Turbo** - JZC973 Qwen3.6-35B-A3B with REAP + MTP
- Best for: Speed-critical text tasks
- Single-stream: ~100 TPS
- Architecture: 35B MoE (~27B active)
- MTP: draft-mtp n_max=3 enabled

**Distill-9B** - empero-ai Qwen3.8-9B distilled GGUF
- Best for: Medium quality, fast inference
- Single-stream: ~67 TPS
- Architecture: 9B Dense

**Maziyar-8B** - MaziyarPanahi Qwen3-8B Q4_K_M
- Best for: Fast 8B inference
- Single-stream: ~79 TPS
- Architecture: 8B Dense

**Maziyar-0.6B** - MaziyarPanahi Qwen3-0.6B Q4_K_M
- Best for: Very fast, low VRAM (scales with concurrency)
- Single-stream: ~440 TPS
- Architecture: 0.6B Dense

---

## API Endpoints

### GET /v1 - API Index
```bash
curl http://localhost:8082/v1
# Returns: API info, endpoints, model details, backend status
```

### GET /models - List All Models
```bash
curl http://localhost:8082/models
# Returns: Array of models with full metadata
```

### GET /model - Current Model Info
```bash
curl http://localhost:8082/model
# Returns: Current model details including backend_status
```

### POST /model - Switch Model
```bash
curl -X POST http://localhost:8082/model \
  -H "Content-Type: application/json" \
  -d '{"model": "Turbo"}'
```

### POST /v1/chat/completions - Chat Completion
```bash
curl -X POST http://localhost:8082/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Turbo",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 100
  }'
```

### GET /health - Health Check
```bash
curl http://localhost:8082/health
# Response: {"status":"ok"}
```

---

## Model API Response Format

```json
{
  "id": "Ultra",
  "object": "model",
  "owned_by": "local",
  "description": "Qwen3.8-27B + vision encoder - Best quality, 128K CTX, multimodal",
  "quantization": "IQ3_XXS",
  "ctx": 131072,
  "ctx_display": "128K",
  "tps": "~30 TPS",
  "vision": true,
  "mtp": false,
  "parameters": "27B Dense",
  "architecture": "Dense",
  "vram": "~15.0GB",
  "details": "Unsloth Qwen3.8-27B + mmproj-F16 vision encoder",
  "is_current": true,
  "backend_status": "online"
}
```

---

## Benchmark Results

### Throughput vs Context Size (Turbo)

| Context | Scaling Behavior | Peak TPS |
|---------|-----------------|----------|
| 160K | **Flat** (~100 TPS, no scaling) | 100 |
| 128K | Scales 2.3x | 232 |
| 96K | Scales 2.4x | 237 |
| 32K | Scales 2.4x | 237 |

**Key Finding:** 128K provides best balance of context size and throughput scaling.

### Concurrency Performance (128K Context)

**Turbo @ 128K:**
| Concurrency | Total TPS | Per-Session TPS |
|-------------|-----------|-----------------|
| 1 | ~100 | ~100 |
| 4 | ~230 | ~57 |
| 8 | ~236 | ~30 |
| 16 | ~230 | ~14 |

**Ultra @ 128K:**
| Concurrency | Total TPS | Per-Session TPS |
|-------------|-----------|-----------------|
| 1 | ~30 | ~30 |
| 4 | ~74 | ~18 |
| 8 | ~76 | ~9 |

**Maziyar-0.6B @ 128K (Memory-Bound - Scales!):**
| Concurrency | Total TPS | Per-Session TPS |
|-------------|-----------|-----------------|
| 1 | ~408 | ~408 |
| 2 | ~434 | ~217 |
| 4 | ~441 | ~110 |
| 8 | ~442 | ~55 |

**Key Finding:** Maziyar-0.6B is memory-bound and throughput SCALES with concurrency (unique behavior).

---

## Service Management

```bash
# Via systemctl
systemctl --user start llama-proxy
systemctl --user stop llama-proxy
systemctl --user restart llama-proxy
systemctl --user status llama-proxy

# Check logs
journalctl --user -u llama-proxy -n 50 --no-pager
```

---

## Python Example

```python
import requests

API = "http://localhost:8082"

def wait_ready(timeout=30):
    start = time.time()
    while time.time() - start < timeout:
        try:
            if requests.get(f"{API}/health").status_code == 200:
                return True
        except:
            pass
        time.sleep(0.5)
    return False

def chat(model, message, max_tokens=100):
    resp = requests.post(f"{API}/v1/chat/completions", json={
        "model": model,
        "messages": [{"role": "user", "content": message}],
        "max_tokens": max_tokens
    })
    return resp.json()

# Usage
if wait_ready():
    result = chat("Turbo", "Explain recursion")
    print(result["choices"][0]["message"]["content"])
```

---

## Troubleshooting

### Server shows "offline"
```bash
# Check proxy status
systemctl --user status llama-proxy

# Restart proxy
systemctl --user restart llama-proxy
```

### OOM errors
- Reduce context size
- Switch to Turbo (uses less VRAM)
- Check GPU memory: `nvidia-smi`

### Model switch fails
```bash
curl -X POST http://localhost:8082/model -d '{"model": "Ultra"}'
```

---

## Files

- `/home/mkinney/.local/bin/llama-proxy` - Model switching proxy
- `/home/mkinney/.config/systemd/user/llama-proxy.service` - Systemd service
