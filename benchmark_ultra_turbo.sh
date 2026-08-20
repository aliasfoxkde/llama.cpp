#!/bin/bash
# Benchmark Ultra and Turbo models via llama-proxy
# Tests actual tokens generated, proper warmup, and accurate TPS measurement

set -e

PROXY_URL="http://localhost:8082"
PROMPT="Explain the concept of recursion in programming in exactly 2 sentences."
MAX_TOKENS=100
WARMUP_REQUESTS=2

echo "=============================================="
echo "Ultra/Turbo Benchmark via llama-proxy"
echo "=============================================="
echo ""

# Function to run benchmark for a model
run_benchmark() {
    local model_name=$1
    local model_id=$2
    
    echo "--- Testing $model_name ---"
    echo "Model ID: $model_id"
    
    # Switch to the model
    echo "Switching to $model_name..."
    curl -s -X POST "$PROXY_URL/model" -H "Content-Type: application/json" -d "{\"model\": \"$model_id\"}" > /dev/null
    sleep 3  # Wait for model to load
    
    # Warmup
    echo "Warming up..."
    for i in $(seq 1 $WARMUP_REQUESTS); do
        curl -s -X POST "$PROXY_URL/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"$model_id\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":$MAX_TOKENS}" \
            > /dev/null
    done
    sleep 1
    
    # Run benchmarks at different concurrency levels
    echo ""
    echo "Concurrency | Total Tokens | Time (s) | TPS |"
    echo "------------|--------------|----------|-----|"
    
    for conc in 1 2 4 8 12 16 24; do
        total_tokens=0
        declare -a pids
        declare -a output_files
        start=$(date +%s.%N)
        
        # Launch concurrent requests
        for i in $(seq 1 $conc); do
            output_file="/tmp/bench_${model_name}_${conc}_${i}.json"
            output_files+=("$output_file")
            curl -s -X POST "$PROXY_URL/v1/chat/completions" \
                -H "Content-Type: application/json" \
                -d "{\"model\":\"$model_id\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":$MAX_TOKENS}" \
                > "$output_file" &
            pids+=($!)
        done
        
        # Wait for all to complete
        for pid in "${pids[@]}"; do
            wait $pid 2>/dev/null || true
        done
        
        end=$(date +%s.%N)
        
        # Parse actual tokens from responses
        for output_file in "${output_files[@]}"; do
            if [ -f "$output_file" ]; then
                tokens=$(python3 -c "import json; print(json.load(open('$output_file'))['usage']['completion_tokens'])" 2>/dev/null || echo "0")
                total_tokens=$((total_tokens + tokens))
                rm -f "$output_file"
            fi
        done
        
        elapsed=$(echo "$end - $start" | bc)
        if [ "$(echo "$elapsed > 0" | bc)" -eq 1 ]; then
            tps=$(echo "scale=1; $total_tokens / $elapsed" | bc)
        else
            tps="0"
        fi
        
        echo "$conc | $total_tokens | ${elapsed}s | $tps |"
        sleep 1
    done
    echo ""
}

# Get available models
echo "Available models from proxy:"
curl -s "$PROXY_URL/models" | python3 -c "import json,sys; d=json.load(sys.stdin); [print(f'  - {m[\"id\"]}: {m[\"description\"]}') for m in d['data']]" 2>/dev/null || echo "  (could not fetch)"
echo ""

# Benchmark Ultra
run_benchmark "Ultra" "Ultra"

echo ""

# Benchmark Turbo
run_benchmark "Turbo" "Turbo"

echo "=============================================="
echo "Benchmark complete"
echo "=============================================="
