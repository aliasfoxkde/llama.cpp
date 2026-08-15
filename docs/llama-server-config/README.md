# Llama Server Configuration

Systemd-managed llama.cpp server for Qwen3.8-27B and Qwen3.6-35B REAP models.

## Structure

```
llama-server-config/
├── README.md              # This file
├── llama-server-start.sh  # Primary model (IQ3_XXS) startup script
├── llama-server-reap.sh   # REAP MTP model startup script
├── llama-server-api.md    # API reference (Markdown)
├── llama-server-api.html  # API reference (HTML, interactive)
├── systemd/
│   ├── llama-server.service       # API server systemd service
│   └── llama-docs-server.service  # Docs server systemd service
├── bin/
│   ├── llama-server       # Convenience wrapper (start/stop/switch)
│   └── llama-docs-server # Docs server control script
└── model-symlink/
    └── current-model.txt # Current model path (symlink target)
```

## Setup

1. Copy `systemd/*.service` to `~/.config/systemd/user/`
2. Copy `bin/*` to `~/.local/bin/` and ensure it's in PATH
3. Create model symlink: `mkdir -p ~/.llama-server && ln -sf <model-path> ~/.llama-server/model.gguf`

## Usage

```bash
llama-server start     # Start API server (port 8080)
llama-server stop      # Stop
llama-server restart   # Restart
llama-server status    # Status
llama-server switch    # List available models
llama-server switch qwen3.6-reap  # Switch to REAP model

llama-docs-server start   # Start docs server (port 8081)
llama-docs-server stop     # Stop
```

## Endpoints

- **API:** `http://host:8080/v1/completion`
- **Health:** `http://host:8080/v1/health`
- **Docs:** `http://host:8081/`

## Models

| Alias | Model | Load Time |
|-------|-------|-----------|
| qwen3.8-27b-iq3 | Qwen3.8-27B UD-IQ3_XXS | ~2.3s |
| qwen3.6-reap | Qwen3.6-35B REAP-MTP | ~9.6s |

## Timing

- Service stop: ~2s
- Model load: 2.3s (IQ3_XXS) / 9.6s (REAP)
- Total switch: ~4-12s
