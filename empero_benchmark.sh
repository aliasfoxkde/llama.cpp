#!/bin/bash
# Standalone benchmark script for empero-ai Distill models
# Does NOT modify proxy or system settings

set -e

BACKEND_URL="http://localhost:8080"
LLAMA_SERVER="/home/mkinney/Repos/llama.cpp/build-cuda-new/bin/llama-server"
PROMPT="Explain the concept of recursion in programming."

# Models to test (empero-ai Qwen3.8-{2,4,9}B-Distill-GGUF)
declare -A MODELS=(
    ["empero-ai/Qwen3.8-9B-Distill"]="/home/mkinney/Models/empero-ai/Qwen3.8-9B-Q4_K_M.gguf"
    ["empero-ai/Qwen3.8-4B-Distill"]="/home/mkinney/Models/empero-ai/Qwen3.8-4B-Q4_K_M.gguf"
    ["empero-ai/Qwen3.8-2B-Distill"]="/home/mkinney/Models/empero-ai/Qwen3.8-2B-Q4_K_M.gguf"
)

run_benchmark() {
    local name=$1
    local model_path=$2
    local ctx=${3:-131072}  # 128K default
    local mtp_opts=$4  # optional MTP flags

    echo "=========================================="
    echo "Testing: $name @ ${ctx}K context"
    if [ -n "$mtp_opts" ]; then
        echo "MTP flags: $mtp_opts"
    fi
    echo "=========================================="

    # Kill any existing server
    pkill -f "llama-server.*8080" 2>/dev/null || true
    sleep 2

    # Start server
    CMD="$LLAMA_SERVER -m $model_path -c $ctx -ngl 99 -t 16 -np 4 --host 0.0.0.0 --port 8080 --reasoning off --sleep-idle-seconds 300"
    if [ -n "$mtp_opts" ]; then
        CMD="$CMD $mtp_opts"
    fi

    $CMD > /tmp/llama-test.log 2>&1 &
    SERVER_PID=$!

    # Wait for server to be ready
    echo -n "Waiting for server..."
    for i in $(seq 1 30); do
        if curl -s $BACKEND_URL/health 2>/dev/null | grep -q "ok"; then
            echo " Ready!"
            break
        fi
        sleep 1
        echo -n "."
    done

    if ! curl -s $BACKEND_URL/health 2>/dev/null | grep -q "ok"; then
        echo " FAILED TO START"
        cat /tmp/llama-test.log | tail -20
        kill $SERVER_PID 2>/dev/null || true
        return 1
    fi

    # Benchmark at different concurrency levels
    echo ""
    echo "Concurrency | Total Tok | Time(s) | Total TPS | Per-Sess TPS"
    echo "------------|-----------|---------|-----------|--------------"

    for conc in 1 2 4 8; do
        start=$(date +%s.%N)
        for i in $(seq 1 $conc); do
            curl -s -X POST $BACKEND_URL/v1/chat/completions \
                -H "Content-Type: application/json" \
                -d "{\"model\":\"$name\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":100}" \
                > /tmp/bench_${conc}_${i}.json &
        done
        for i in $(seq 1 $conc); do wait; done
        end=$(date +%s.%N)

        total=0
        for i in $(seq 1 $conc); do
            t=$(python3 -c "import json; print(json.load(open('/tmp/bench_${conc}_${i}.json'))['usage']['completion_tokens'])" 2>/dev/null || echo "0")
            total=$((total + t))
        done

        elapsed=$(echo "$end - $start" | bc)
        total_tps=$(echo "scale=1; $total / $elapsed" | bc)
        per_sess=$(echo "scale=1; $total_tps / $conc" | bc)
        echo "$conc | $total | ${elapsed}s | $total_tps | $per_sess"
    done

    echo ""

    # Cleanup
    kill $SERVER_PID 2>/dev/null || true
    pkill -f "llama-server.*8080" 2>/dev/null || true
    sleep 2
}

# Check prerequisites
echo "=== Prerequisites ==="
nvidia-smi --query-gpu=memory.used,memory.total --format=csv
echo ""

# Run benchmarks
for name in "${!MODELS[@]}"; do
    path="${MODELS[$name]}"

    if [ ! -f "$path" ]; then
        echo "SKIP: $name - file not found: $path"
        continue
    fi

    # Test base speed @ 128K
    run_benchmark "$name" "$path" 131072

    # Try with ngram speculative decoding (no draft model needed)
    echo ""
    echo ">>> Testing with ngram-simple speculative decoding..."
    run_benchmark "$name" "$path" 131072 "--spec-type ngram-simple"

done

echo "=========================================="
echo "BENCHMARK COMPLETE"
echo "=========================================="
echo ""
echo "Results saved to /tmp/llama-test.log"
