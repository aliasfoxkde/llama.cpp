#!/bin/bash
# vLLM Concurrency Test Script
# Tests Qwen3-4B-Instruct on RTX 5060 Ti with varying concurrency levels

VLLM_URL="http://localhost:8000/v1/chat/completions"
MODEL="Qwen/Qwen3-4B-Instruct"

PROMPT="Explain the concept of recursion in programming in 3 sentences."

run_test() {
    local num_requests=$1
    local start_time=$(date +%s.%N)

    # Run concurrent requests
    for i in $(seq 1 $num_requests); do
        curl -s -X POST "$VLLM_URL" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":100,\"temperature\":0.7}" &
    done

    # Wait for all to complete
    wait

    local end_time=$(date +%s.%N)
    local elapsed=$(echo "$end_time - $start_time" | bc)

    echo "Concurrency: $num_requests | Time: ${elapsed}s | ~$(echo "scale=1; 300/$elapsed" | bc) tok/s"
}

echo "=== vLLM Qwen3-4B-Instruct Concurrency Test ==="
echo "Prompt: $PROMPT"
echo ""

for concurrency in 1 2 4 8 12 16; do
    run_test $concurrency
    sleep 2
done

echo ""
echo "Test complete"
