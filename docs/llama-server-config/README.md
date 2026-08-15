# Llama Server Configuration

Single proxy (port 8082) handles API, model switching, and serves docs.

## Endpoints (port 8082)

| Path | Method | Description |
|------|--------|-------------|
| `/` | GET | API documentation |
| `/models` | GET | List available models |
| `/model` | GET | Get current model info |
| `/model` | POST | Switch model |
| `/completion` | POST | Run inference |

## Usage

```bash
# List models
curl http://localhost:8082/models

# Get current model
curl http://localhost:8082/model

# Switch model
curl -X POST http://localhost:8082/model -d '{"id":"Qwen3.6-35B-A3B-REAP-MTP"}'

# Run inference
curl -X POST http://localhost:8082/completion \
  -d '{"prompt":"Hello","n_predict":32}'
```

## Models

| ID | File | Load Time |
|----|------|-----------|
| Qwen3.8-27B | IQ3_XXS, 12GB | ~2.3s |
| Qwen3.6-35B-A3B-REAP-MTP | Q3_K_M, 13GB | ~9.6s |
