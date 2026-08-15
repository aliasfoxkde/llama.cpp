#!/bin/bash
# llama.cpp server startup script for Qwen3.6-35B REAP MTP
# Model: JZC973 UD-Q3_K_M-REAP (13GB), 128K CTX, KV Cache Q4_0/Q4_0
# Best for: fast small tasks at ~210 tok/s per request, C4 concurrent
# Hardware: RTX 5060 Ti 16GB

MODEL_PATH="/home/mkinney/Models/JZC973/Qwen3.6-35B-REAP-MTP-UD-GGUF-Collection/Qwen3.6-35B-A3B-UD-Q3_K_M-REAP.gguf"

# Server configuration
PORT=8080
CTX_SIZE=131072
KV_CACHE_K=q4_0
KV_CACHE_V=q4_0
THREADS=16
NGPUS=99  # Load all layers to GPU

# Idle resource management - sleep after 5 minutes of idle
SLEEP_IDLE=300

# Multiple slots for concurrent requests (REAP MTP shines at C4)
NP_PARALLEL=4

# Flash attention for better performance
FLASH_ATTN="on"

# MTP speculative decoding (REAP has MTP built-in)
SPEC_TYPE=draft-mtp
SPEC_DRAFT_N_MAX=3

/home/mkinney/Repos/llama.cpp/build-cuda-new/bin/llama-server \
  -m "$MODEL_PATH" \
  -c $CTX_SIZE \
  -ctk $KV_CACHE_K \
  -ctv $KV_CACHE_V \
  -ngl $NGPUS \
  -t $THREADS \
  -np $NP_PARALLEL \
  -fa $FLASH_ATTN \
  --spec-type $SPEC_TYPE \
  --spec-draft-n-max $SPEC_DRAFT_N_MAX \
  --sleep-idle-seconds $SLEEP_IDLE \
  --host 0.0.0.0 \
  --port $PORT
