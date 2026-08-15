# Llama Server Configuration

Systemd-managed llama.cpp server with proxy for model switching.

## Architecture

- **Proxy (port 8082):** Handles API requests, model switching, forwards to llama-server
- **llama-server (port 8080):** Actual inference server
- **Docs server (port 8081):** API documentation

## Structure

```
llama-server-config/
├── README.md              # This file
├── llama-server-start.sh  # Startup script reference
├── llama-server-reap.sh   # REAP model startup reference
├── llama-server-api.md    # API reference
├── llama-server-api.html  # Interactive API docs
├── llama-proxy           # Model-switching proxy script
├── systemd/
│   ├── llama-server.service
│   ├── llama-docs-server.service
│   └── llama-proxy.service
└── bin/
    ├── llama-server       # Convenience wrapper
    └── llama-docs-server
```

## Setup

1. Copy `systemd/*.service` to `~/.config/systemd/user/`
2. Copy `bin/*` and `llama-proxy` to `~/.local/bin/`
3. Run `llama-proxy &` to start everything

## Usage

```bash
# API (through proxy on port 8082)
curl http://localhost:8082/completion -d '{"prompt":"test","n_predict":32}'
curl http://localhost:8082/health
curl http://localhost:8082/model  # Get current model

# Switch model (via proxy API)
curl -X POST http://localhost:8082/model/switch \
  -H "Content-Type: application/json" \
  -d '{"alias": "Qwen3.6-35B-A3B-REAP-MTP"}'

# Or use wrapper
llama-server switch Qwen3.6-35B-A3B-REAP-MTP
```

## Models

| Alias | Model | Load Time |
|-------|-------|-----------|
| Qwen3.8-27B | Qwen3.8-27B UD-IQ3_XXS | ~2.3s |
| Qwen3.6-35B-A3B-REAP-MTP | Qwen3.6-35B REAP-MTP | ~9.6s |

## Endpoints

- **API:** `http://host:8082/completion`
- **Health:** `http://host:8082/health`
- **Model info:** `http://host:8082/model`
- **Docs:** `http://host:8081/`

## Timing

- Service stop: ~2s
- Model load: 2.3s (IQ3_XXS) / 9.6s (REAP)
- Total switch: ~4-12s
