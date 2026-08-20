#!/bin/bash
# Benchmark llama-server with Qwen3.6-35B GGUF at various concurrency levels

MODEL="Qwen3.6-35B-A3B-UD-Q3_K_XL-REAP"
URL="http://localhost:8080/v1/chat/completions"
PROMPT="Explain the concept of recursion in programming in exactly 2 sentences."
MAX_TOKENS=100

echo "=== Qwen3.6-35B GGUF llama.cpp Benchmark ==="
echo "Model: $MODEL"
echo "Max tokens: $MAX_TOKENS"
echo ""

# Warmup
curl -s -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":$MAX_TOKENS}" \
  > /dev/null
sleep 1

for CONCURRENCY in 2 4 8 12; do
    echo -n "Concurrency $CONCURRENCY: "
    for run in {1..3}; do
        START=$(date +%s.%N)
        for i in $(seq 1 $CONCURRENCY); do
            curl -s -X POST "$URL" \
                -H "Content-Type: application/json" \
                -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":$MAX_TOKENS}" \
                > /dev/null &
        done
        wait
        END=$(date +%s.%N)
        ELAPSED=$(echo "$END - $START" | bc)
        TOTAL_TOKENS=$((CONCURRENCY * MAX_TOKENS))
        THROUGHPUT=$(echo "scale=1; $TOTAL_TOKENS / $ELAPSED" | bc)
        echo -n "${THROUGHPUT} "
        sleep 0.5
    done
    echo ""
done

echo ""
echo "=== Done ==="
