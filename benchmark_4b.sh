#!/bin/bash
# Benchmark vLLM with Qwen3-4B at various concurrency levels

MODEL="/tmp/hf-cache/models--Qwen--Qwen3-4B/snapshots/1cfa9a7208912126459214e8b04321603b3df60c"
URL="http://localhost:8000/v1/chat/completions"
PROMPT="Explain the concept of recursion in programming in exactly 2 sentences."
MAX_TOKENS=100

echo "=== Qwen3-4B vLLM Benchmark ==="
echo "Max tokens: $MAX_TOKENS"
echo ""

for CONCURRENCY in 2 4 8 12; do
    echo "--- Concurrency: $CONCURRENCY ---"

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
    THROUGHPUT=$(echo "scale=2; $TOTAL_TOKENS / $ELAPSED" | bc)

    echo "Tokens: $TOTAL_TOKENS, Time: ${ELAPSED}s, Throughput: ${THROUGHPUT} tok/s"
    echo ""
done

echo "=== Done ==="
