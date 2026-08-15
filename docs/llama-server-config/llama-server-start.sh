#!/bin/bash
# llama.cpp server startup script for Qwen3.8-27B (IQ3_XXS)
# Model: Unsloth IQ3_XXS, 128K CTX, KV Cache Q4_0/Q4_0
# Optimal config for RTX 5060 Ti 16GB

MODEL_PATH="/home/mkinney/Models/unsloth/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-IQ3_XXS.gguf"

# Server configuration
PORT=8080
CTX_SIZE=131072
KV_CACHE_K=q4_0
KV_CACHE_V=q4_0
THREADS=16
NGPUS=99  # Load all layers to GPU

# Idle resource management - sleep after 5 minutes of idle
SLEEP_IDLE=300

# Multiple slots for concurrent requests
NP_PARALLEL=4

# Flash attention for better performance
FLASH_ATTN="on"

# Optional: Set CUDA_VISIBLE_DEVICES if needed
# export CUDA_VISIBLE_DEVICES=0

/home/mkinney/Repos/llama.cpp/build-cuda-new/bin/llama-server \
  -m "$MODEL_PATH" \
  -c $CTX_SIZE \
  -ctk $KV_CACHE_K \
  -ctv $KV_CACHE_V \
  -ngl $NGPUS \
  -t $THREADS \
  -np $NP_PARALLEL \
  -fa $FLASH_ATTN \
  --sleep-idle-seconds $SLEEP_IDLE \
  --host 0.0.0.0 \
  --port $PORT
