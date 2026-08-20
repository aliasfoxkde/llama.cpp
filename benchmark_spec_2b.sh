#!/bin/bash
# Systematic Speculative Decoding Benchmark for Qwen3.8-2B-Distill
# Tests: baseline, hetero-spec (Qwen3.5-0.8B draft), ngram-simple

set -e

LLAMA_SERVER="/home/mkinney/Repos/llama.cpp/build-cuda-new/bin/llama-server"
BACKEND_URL="http://localhost:8083"
PROMPT="Explain the concept of recursion in programming in exactly 2 sentences."
MAX_TOKENS=100
WARMUP=2
RUNS=3

# Target: Lite (Qwen3.8-2B-Distill)
TARGET_MODEL="/home/mkinney/Models/empero-ai/Qwen3.8-2B-Q4_K_M.gguf"

# Draft models to test
# NOTE: Qwen3-0.6B is incompatible (vocab type mismatch with Qwen3.8-2B-Distill)
declare -A DRAFT_MODELS=(
    ["Qwen3.5-0.8B"]="/home/mkinney/Models/Qwen3.5-0.8B-Q4_K_M.gguf"
)

N_MAX_VALUES=(1 2 3 4 5 8)
CONCURRENCY_LEVELS=(1 2 4 8)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================"
echo "  Speculative Decoding Benchmark: Qwen3.8-2B-Distill"
echo "============================================================"
echo ""
echo "Target: $TARGET_MODEL"
echo "Draft models: ${!DRAFT_MODELS[@]}"
echo ""

# Check target exists
if [ ! -f "$TARGET_MODEL" ]; then
    echo -e "${RED}ERROR: Target model not found: $TARGET_MODEL${NC}"
    exit 1
fi

# Check draft models exist
for name in "${!DRAFT_MODELS[@]}"; do
    path="${DRAFT_MODELS[$name]}"
    if [ ! -f "$path" ]; then
        echo -e "${YELLOW}WARNING: Draft model not found: $path ($name) - will skip${NC}"
        unset DRAFT_MODELS[$name]
    else
        echo -e "${GREEN}OK${NC}: $name @ $path"
    fi
done

echo ""

# ============================================================
# Helper: start_server
# Kills existing server, starts new one with given args
# ============================================================
start_server() {
    local target="$1"
    local draft="$2"       # empty = no draft
    local spec_type="$3"    # none, draft-simple, ngram-simple
    local n_max="$4"        # spec-draft-n-max value

    pkill -f "llama-server.*8080" 2>/dev/null || true
    sleep 2

    local cmd=(
        "$LLAMA_SERVER"
        "-m" "$target"
        "-c" "131072"
        "-ngl" "99"
        "-t" "16"
        "-np" "4"
        "--host" "0.0.0.0"
        "--port" "8080"
        "--reasoning" "off"
        "--sleep-idle-seconds" "300"
        "-fa" "on"
    )

    if [ -n "$draft" ] && [ "$spec_type" != "none" ]; then
        cmd+=("--spec-type" "$spec_type")
        if [ "$spec_type" == "draft-simple" ]; then
            cmd+=("--spec-draft-model" "$draft")
            cmd+=("--spec-draft-n-max" "$n_max")
            cmd+=("--ngld" "99")
        elif [[ "$spec_type" == ngram-* ]]; then
            cmd+=("--spec-draft-n-max" "$n_max")
        fi
    fi

    eval "setsid ${cmd[*]} > /tmp/llama_spec2b.log 2>&1 &"
    sleep 6

    # Wait for health
    for i in $(seq 1 30); do
        if curl -s "$BACKEND_URL/health" 2>/dev/null | grep -q "ok"; then
            return 0
        fi
        sleep 1
    done
    echo -e "${RED}FAILED${NC}: Server did not start"
    cat /tmp/llama_spec2b.log | tail -10
    return 1
}

# ============================================================
# Helper: verify_model
# Confirms backend reports correct target model
# ============================================================
verify_model() {
    local expected_path="$TARGET_MODEL"
    local actual
    actual=$(curl -s "$BACKEND_URL/v1/models" 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data'][0].get('id',d['data'][0].get('model','?')))" 2>/dev/null)
    if [[ "$actual" == *"$expected_path"* ]]; then
        return 0
    else
        echo -e "${RED}MISMATCH${NC}: expected path containing '$expected_path', got '$actual'"
        return 1
    fi
}

# ============================================================
# Helper: run_benchmark
# Fires concurrency N requests, returns: total_tokens elapsed accept_rate
# ============================================================
run_benchmark() {
    local conc=$1

    local start end total_tokens
    start=$(date +%s.%N)

    declare -a pids
    declare -a output_files

    for i in $(seq 1 $conc); do
        local out="/tmp/bench_spec2b_${conc}_${i}.json"
        output_files+=("$out")
        curl -s -X POST "$BACKEND_URL/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"test\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":$MAX_TOKENS}" \
            > "$out" &
        pids+=($!)
    done

    for pid in "${pids[@]}"; do
        wait $pid 2>/dev/null || true
    done

    end=$(date +%s.%N)

    total_tokens=0
    for out in "${output_files[@]}"; do
        if [ -f "$out" ]; then
            local t
            t=$(python3 -c "import json; print(json.load(open('$out'))['usage']['completion_tokens'])" 2>/dev/null || echo "0")
            total_tokens=$((total_tokens + t))
            rm -f "$out"
        fi
    done

    elapsed=$(echo "$end - $start" | bc)
    tps=$(echo "scale=2; $total_tokens / $elapsed" | bc)

    echo "$total_tokens $elapsed $tps"
}

# ============================================================
# Helper: get_acceptance_rate
# Parses server log for last draft acceptance rate
# ============================================================
get_acceptance_rate() {
    # Look for "draft acceptance = X.XXXXX" in log
    local rate
    rate=$(grep "draft acceptance =" /tmp/llama_spec2b.log 2>/dev/null | tail -1 | sed 's/.*draft acceptance = \([0-9.]*\).*/\1/')
    if [ -z "$rate" ]; then
        echo "N/A"
    else
        echo "$rate"
    fi
}

# ============================================================
# Section: Check vocab compatibility for hetero-spec
# ============================================================
echo -e "${BLUE}=== Phase 1: Vocab Compatibility Check ===${NC}"
echo ""

echo -e "${BLUE}=== Phase 1: Vocab Compatibility Check ===${NC}"
echo ""

# Pre-checked compatibility (confirmed via manual test):
# - Qwen3.5-0.8B + Qwen3.8-2B-Distill: ✅ COMPATIBLE (~86% acceptance at n_max=2)
# - Qwen3-0.6B + Qwen3.8-2B-Distill: ❌ INCOMPATIBLE (vocab type mismatch)
echo -e "${GREEN}Confirmed compatible drafts:${NC}"
for name in "${!DRAFT_MODELS[@]}"; do
    echo "  - $name"
done
echo ""
echo -e "${YELLOW}Excluded (incompatible):${NC}"
echo "  - Qwen3-0.6B (vocab type mismatch with Qwen3.8-2B-Distill)"
echo ""

# Quick runtime verification: start server with spec, send one request
echo -n "Verifying spec initialization... "
pkill -f "llama-server.*8083" 2>/dev/null || true
sleep 1

"$LLAMA_SERVER" \
    -m "$TARGET_MODEL" \
    --spec-type draft-simple \
    --spec-draft-model "${DRAFT_MODELS[*]}" \
    --spec-draft-n-max 2 \
    -ngl 99 -t 4 --host 0.0.0.0 --port 8083 \
    > /tmp/llama_vocab_verify.log 2>&1 &
sleep 8

if curl -s http://localhost:8083/health 2>/dev/null | grep -q "ok"; then
    # Send test request to trigger spec init
    curl -s -X POST http://localhost:8083/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{"model":"test","messages":[{"role":"user","content":"hi"}],"max_tokens":5}' \
        > /dev/null 2>&1
    sleep 1

    if grep -q "vocab type must match\|failed to initialize" /tmp/llama_vocab_verify.log 2>/dev/null; then
        echo -e "${RED}FAILED${NC} - spec initialization error"
        cat /tmp/llama_vocab_verify.log | grep -i "vocab\|error\|failed" | head -5
        echo -e "${RED}No compatible drafts. Exiting.${NC}"
        exit 1
    else
        echo -e "${GREEN}OK${NC} - spec initialized successfully"
    fi
else
    echo -e "${RED}FAILED${NC} - server did not start"
    cat /tmp/llama_vocab_verify.log | tail -10
    exit 1
fi

pkill -f "llama-server.*8083" 2>/dev/null || true
sleep 2

# ============================================================
# Phase 2: Baseline (no speculative decoding)
# ============================================================
echo -e "${BLUE}=== Phase 2: Baseline (no spec) ===${NC}"
echo ""

start_server "$TARGET_MODEL" "" "none" ""
verify_model || echo "Warning: model verification failed"

# Warmup
for i in $(seq 1 $WARMUP); do
    curl -s -X POST "$BACKEND_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"test\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":$MAX_TOKENS}" \
        > /dev/null
done
sleep 2

# Measure baseline at each concurrency
declare -A baseline_tps
echo "Concurrency | TPS (avg of $RUNS runs)"
echo "------------|---------------------------"
for conc in "${CONCURRENCY_LEVELS[@]}"; do
    local sum=0
    local count=0
    for run in $(seq 1 $RUNS); do
        local result
        result=$(run_benchmark $conc)
        local tps
        tps=$(echo "$result" | cut -d' ' -f3)
        sum=$(echo "$sum + $tps" | bc)
        count=$((count + 1))
        sleep 1
    done
    local avg
    avg=$(echo "scale=1; $sum / $count" | bc)
    baseline_tps[$conc]=$avg
    echo "$conc | $avg"
done
echo ""

# ============================================================
# Phase 3: Hetero-spec (draft-simple with each draft model)
# ============================================================
for draft_name in "${!DRAFT_MODELS[@]}"; do
    draft_path="${DRAFT_MODELS[$draft_name]}"
    echo -e "${BLUE}=== Phase 3: Hetero-spec ($draft_name) ===${NC}"
    echo ""

    echo "| Conc | n_max | TPS | Accept | Speedup |"
    echo "|------|-------|-----|--------|---------|"

    for n_max in "${N_MAX_VALUES[@]}"; do
        for conc in "${CONCURRENCY_LEVELS[@]}"; do
            start_server "$TARGET_MODEL" "$draft_path" "draft-simple" "$n_max"
            verify_model || continue

            # Warmup
            for i in $(seq 1 $WARMUP); do
                curl -s -X POST "$BACKEND_URL/v1/chat/completions" \
                    -H "Content-Type: application/json" \
                    -d "{\"model\":\"test\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":$MAX_TOKENS}" \
                    > /dev/null
                sleep 1
            done

            # Run benchmark
            local sum_tps=0 sum_accept=0 count=0
            for run in $(seq 1 $RUNS); do
                local result
                result=$(run_benchmark $conc)
                local tps accept
                tps=$(echo "$result" | cut -d' ' -f3)
                accept=$(get_acceptance_rate)
                sum_tps=$(echo "$sum_tps + $tps" | bc)
                if [ "$accept" != "N/A" ]; then
                    sum_accept=$(echo "$sum_accept + $accept" | bc)
                fi
                count=$((count + 1))
                sleep 1
            done

            local avg_tps avg_accept speedup
            avg_tps=$(echo "scale=1; $sum_tps / $count" | bc)
            if [ "$accept" != "N/A" ]; then
                avg_accept=$(echo "scale=2; $sum_accept / $count" | bc)
                speedup=$(echo "scale=2; $avg_tps / ${baseline_tps[$conc]}" | bc)
                printf "| %4d | %5d | %s | %s | %sx |\n" "$conc" "$n_max" "$avg_tps" "$avg_accept" "$speedup"
            else
                printf "| %4d | %5d | %s | N/A | N/A |\n" "$conc" "$n_max" "$avg_tps"
            fi
        done
    done
    echo ""
done

# ============================================================
# Phase 4: ngram-simple (no draft model needed)
# ============================================================
echo -e "${BLUE}=== Phase 4: ngram-simple ===${NC}"
echo ""

echo "| Conc | n_max | TPS | Speedup |"
echo "|------|-------|-----|---------|"

for n_max in 1 2 3 5; do
    for conc in "${CONCURRENCY_LEVELS[@]}"; do
        start_server "$TARGET_MODEL" "" "ngram-simple" "$n_max"
        verify_model || continue

        # Warmup
        for i in $(seq 1 $WARMUP); do
            curl -s -X POST "$BACKEND_URL/v1/chat/completions" \
                -H "Content-Type: application/json" \
                -d "{\"model\":\"test\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":$MAX_TOKENS}" \
                > /dev/null
            sleep 1
        done

        # Run benchmark
        local sum_tps=0 count=0
        for run in $(seq 1 $RUNS); do
            local result
            result=$(run_benchmark $conc)
            local tps
            tps=$(echo "$result" | cut -d' ' -f3)
            sum_tps=$(echo "$sum_tps + $tps" | bc)
            count=$((count + 1))
            sleep 1
        done

        local avg_tps speedup
        avg_tps=$(echo "scale=1; $sum_tps / $count" | bc)
        speedup=$(echo "scale=2; $avg_tps / ${baseline_tps[$conc]}" | bc)
        printf "| %4d | %5d | %s | %sx |\n" "$conc" "$n_max" "$avg_tps" "$speedup"
    done
done
echo ""

# Cleanup
pkill -f "llama-server.*8080" 2>/dev/null || true

echo "============================================================"
echo "Benchmark complete. Results in /tmp/llama_spec2b.log"
echo "============================================================"
