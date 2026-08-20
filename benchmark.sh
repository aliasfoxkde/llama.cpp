#!/bin/bash
# vLLM Concurrency Benchmark
# Compares RTX 5060 Ti vs V100-SXM2-16GB

echo "=============================================="
echo "vLLM Benchmark: RTX 5060 Ti vs V100-SXM2-16GB"
echo "Model: Qwen3-4B-Instruct"
echo "=============================================="

run_benchmark() {
    local name=$1
    local url=$2
    local model=$3
    local max_conc=${4:-24}

    echo ""
    echo "--- $name ---"
    echo "URL: $url"
    echo "Model: $model"
    echo ""

    PROMPT="Explain the concept of recursion in programming in exactly 2 sentences."

    for conc in 1 2 4 8 12 16 24; do
        if [ $conc -gt $max_conc ]; then
            break
        fi

        total_tokens=0
        start=$(date +%s.%N)

        for i in $(seq 1 $conc); do
            curl -s -X POST "$url/v1/chat/completions" \
                -H "Content-Type: application/json" \
                -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":100,\"temperature\":0.7}" > /tmp/bench_$i.json &
        done
        wait

        for i in $(seq 1 $conc); do
            tokens=$(python3 -c "import json; print(json.load(open('/tmp/bench_$i.json'))['usage']['completion_tokens'])" 2>/dev/null)
            total_tokens=$((total_tokens + tokens))
            rm -f /tmp/bench_$i.json
        done

        end=$(date +%s.%N)
        elapsed=$(echo "$end - $start" | bc)
        tps=$(echo "scale=1; $total_tokens / $elapsed" | bc)

        echo "Concurrency: $conc | Tokens: $total_tokens | Time: ${elapsed}s | ~$tps tok/s"
        sleep 1
    done
}

# Run benchmarks
echo ""
echo ">>> RTX 5060 Ti (Host) <<<"
run_benchmark "RTX 5060 Ti (Host)" "http://localhost:8000" "/tmp/hf-cache/models--Qwen--Qwen3-4B/snapshots/1cfa9a7208912126459214e8b04321603b3df60c" 24

echo ""
echo ">>> V100-SXM2-16GB (VM) <<<"
run_benchmark "V100-SXM2-16GB (VM)" "http://localhost:8001" "/home/mkinney/Models/Qwen3-4B" 24

echo ""
echo "=============================================="
echo "Benchmark complete"
echo "=============================================="
