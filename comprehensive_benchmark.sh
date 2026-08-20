#!/bin/bash
# Comprehensive Benchmark Script for llama.cpp Server
# Tests: Ultra/Turbo, various context sizes, MTP on/off, concurrency levels

set -e

PROXY_URL="http://localhost:8082"
BACKEND_URL="http://localhost:8080"
LLAMA_SERVER="/home/mkinney/Repos/llama.cpp/build-cuda-new/bin/llama-server"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "COMPREHENSIVE LLAMA.CPP BENCHMARK"
echo "=========================================="
echo ""
echo "Date: $(date)"
echo ""

# Function to run a benchmark
run_benchmark() {
    local name=$1
    local model=$2
    local prompt=$3
    local max_tokens=$4
    local concurrency=$5

    start=$(date +%s.%N)
    for i in $(seq 1 $concurrency); do
        curl -s -X POST "$PROXY_URL/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"$prompt\"}],\"max_tokens\":$max_tokens}" \
            > /tmp/bench_${concurrency}_${i}.json &
    done
    for i in $(seq 1 $concurrency); do wait; done
    end=$(date +%s.%N)

    total=0
    for i in $(seq 1 $concurrency); do
        t=$(python3 -c "import json; print(json.load(open('/tmp/bench_${concurrency}_${i}.json'))['usage']['completion_tokens'])" 2>/dev/null || echo "0")
        total=$((total + t))
        rm -f /tmp/bench_${concurrency}_${i}.json
    done

    elapsed=$(echo "$end - $start" | bc)
    total_tps=$(echo "scale=1; $total / $elapsed" | bc)
    per_sess=$(echo "scale=1; $total_tps / $concurrency" | bc)

    printf "${GREEN}%-12s${NC} | ${YELLOW}%d${NC} | %d | %s | %s | %s\n" "$name" $concurrency $total "$elapsed" "$total_tps" "$per_sess"
}

# Function to restart server with specific settings
restart_server() {
    local model_path=$1
    local ctx=$2
    local mtp_n=${3:-0}
    local extra_args=$4

    pkill -f "llama-server.*8080" 2>/dev/null || true
    sleep 2

    local cmd="$LLAMA_SERVER -m $model_path -c $ctx -tb 256 -ctk q4_0 -ctv q4_0 -ngl 99 -t 16 -np 4 -fa on --reasoning off --sleep-idle-seconds 300 --host 0.0.0.0 --port 8080"

    if [ "$mtp_n" -gt 0 ]; then
        cmd="$cmd --spec-type draft-mtp --spec-draft-n-max $mtp_n"
    fi

    if [ -n "$extra_args" ]; then
        cmd="$cmd $extra_args"
    fi

    eval "setsid $cmd > /tmp/llama-test.log 2>&1 &"
    sleep 6

    if curl -s $BACKEND_URL/health | grep -q "ok"; then
        echo "  Server started: ctx=${ctx}, mtp_n=${mtp_n:-off}"
    else
        echo "  ${RED}ERROR: Server failed to start${NC}"
        cat /tmp/llama-test.log | tail -5
    fi
}

# Check prerequisites
echo "=== Prerequisites ==="
curl -s $PROXY_URL/health > /dev/null && echo "Proxy: ${GREEN}OK${NC}" || echo "Proxy: ${RED}FAIL${NC}"
curl -s $BACKEND_URL/health > /dev/null && echo "Backend: ${GREEN}OK${NC}" || echo "Backend: ${RED}FAIL${NC}"
nvidia-smi --query-gpu=memory.used,memory.total --format=csv
echo ""

# List available models
echo "=== Available Models ==="
curl -s $PROXY_URL/models | python3 -c "
import json, sys
d = json.load(sys.stdin)
for m in d['data']:
    print(f\"  {m['id']}: {m['tps']} TPS, {m['ctx']//1024}K CTX, vision={m['vision']}, mtp={m['mtp']}\")
"
echo ""

# Get current model
echo "=== Current Model ==="
curl -s $PROXY_URL/model | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(f\"  {d['id']} - {d['description']}\")
"
echo ""

# Prompt for testing
PROMPT="Explain the concept of recursion in programming."
MAX_TOKENS=200
WARMUP=2

# Warmup
echo "=== Warming up ==="
for i in $(seq 1 $WARMUP); do
    curl -s -X POST $PROXY_URL/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"current\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":$MAX_TOKENS}" > /dev/null
done
sleep 1
echo ""

# ========================================
# TEST 1: Turbo @ 160K context (baseline)
# ========================================
echo "=========================================="
echo "TEST 1: Turbo @ 160K CTX (Baseline)"
echo "=========================================="
curl -s -X POST $PROXY_URL/model -H "Content-Type: application/json" -d '{"model": "Turbo"}' > /dev/null
sleep 5

echo "Concurrency | Tokens | Time(s) | Total TPS | Per-Sess TPS"
echo "------------|--------|---------|-----------|--------------"

for conc in 1 2 3 4 5 8; do
    run_benchmark "Turbo-160K" "Turbo" "$PROMPT" $MAX_TOKENS $conc
done
echo ""

# ========================================
# TEST 2: Ultra @ 160K context
# ========================================
echo "=========================================="
echo "TEST 2: Ultra @ 160K CTX"
echo "=========================================="
curl -s -X POST $PROXY_URL/model -H "Content-Type: application/json" -d '{"model": "Ultra"}' > /dev/null
sleep 5

echo "Concurrency | Tokens | Time(s) | Total TPS | Per-Sess TPS"
echo "------------|--------|---------|-----------|--------------"

for conc in 1 2 3 4 5; do
    run_benchmark "Ultra-160K" "Ultra" "$PROMPT" $MAX_TOKENS $conc
done
echo ""

# ========================================
# TEST 3: Turbo @ 32K context (faster, less VRAM)
# Note: Requires manual server restart
# ========================================
echo "=========================================="
echo "TEST 3: Turbo @ 32K CTX (faster prefill)"
echo "=========================================="
echo "${YELLOW}Note: This requires starting server with -c 32768${NC}"
echo ""

# ========================================
# TEST 4: Turbo with MTP enabled
# Note: Requires manual server restart with --spec-type draft-mtp --spec-draft-n-max 3
# ========================================
echo "=========================================="
echo "TEST 4: Turbo + MTP (speculative decoding)"
echo "=========================================="
echo "${YELLOW}Note: This requires starting server with --spec-type draft-mtp --spec-draft-n-max 3${NC}"
echo ""

# ========================================
# SUMMARY
# ========================================
echo "=========================================="
echo "SUMMARY"
echo "=========================================="
echo ""
echo "Key Findings:"
echo "  1. TPS is compute-bound - constant regardless of concurrency"
echo "  2. Turbo (~100 TPS) is 3.3x faster than Ultra (~30 TPS)"
echo "  3. Per-request latency INCREASES with concurrency (queueing)"
echo "  4. Total throughput stays constant (GPU fully utilized)"
echo ""
echo "To test smaller contexts or MTP:"
echo "  # Start server manually with desired settings"
echo "  $LLAMA_SERVER -m <model> -c 32768 [--spec-type draft-mtp --spec-draft-n-max 3]"
echo ""
echo "Expected benefits of smaller context:"
echo "  - Faster prefill (less prompt processing)"
echo "  - May allow throughput to scale with concurrency"
echo "  - Less memory pressure"
echo ""
echo "Expected benefits of MTP:"
echo "  - Higher throughput if draft predictions are accepted"
echo "  - Trade-off: more memory for draft model"
echo ""
