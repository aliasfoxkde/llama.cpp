#!/bin/bash
# vLLM Concurrency Test - Qwen3-4B-Instruct on RTX 5060 Ti

VLLM_URL="http://localhost:8000/v1/chat/completions"
MODEL="/tmp/hf-cache/models--Qwen--Qwen3-4B/snapshots/1cfa9a7208912126459214e8b04321603b3df60c"
PROMPT="Explain what recursion is in programming in exactly 2 sentences."

run_test() {
    local concurrency=$1
    local total_tokens=0
    local start=$(date +%s.%N)
    
    for i in $(seq 1 $concurrency); do
        curl -s -X POST "$VLLM_URL" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":100,\"temperature\":0.7}" > /tmp/vllm_resp_$i.json &
    done
    wait
    
    for i in $(seq 1 $concurrency); do
        tokens=$(python3 -c "import json; print(json.load(open('/tmp/vllm_resp_$i.json'))['usage']['completion_tokens'])" 2>/dev/null)
        total_tokens=$((total_tokens + tokens))
        rm -f /tmp/vllm_resp_$i.json
    done
    
    local end=$(date +%s.%N)
    local elapsed=$(echo "$end - $start" | bc)
    local tps=$(echo "scale=1; $total_tokens / $elapsed" | bc)
    
    echo "Concurrency: $concurrency | Tokens: $total_tokens | Time: ${elapsed}s | ~$tps tok/s"
}

echo "=== vLLM Qwen3-4B-Instruct Concurrency Test ==="
echo "GPU: RTX 5060 Ti 16GB | Model: Qwen3-4B-Instruct (7.6GB)"
echo ""

for conc in 1 2 4 8 12 16 24; do
    run_test $conc
    sleep 2
done

echo ""
echo "Test complete"
