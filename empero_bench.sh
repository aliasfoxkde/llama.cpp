#!/bin/bash
# Benchmark empero-ai Qwen3.8-{2,4,9}B-Distill models
# Tests concurrency 1-24, stops when throughput plateaus

BACKEND="http://localhost:8080"
SERVER="/home/mkinney/Repos/llama.cpp/build-cuda-new/bin/llama-server"
PROMPT="Explain recursion in programming."

MODELS=(
    "/home/mkinney/Models/empero-ai/Qwen3.8-9B-Q4_K_M.gguf:empero-9B:Q4_K_M"
    "/home/mkinney/Models/empero-ai/Qwen3.8-4B-Q4_K_M.gguf:empero-4B:Q4_K_M"
    "/home/mkinney/Models/empero-ai/Qwen3.8-2B-Q4_K_M.gguf:empero-2B:Q4_K_M"
)

pkill -f "llama-server.*8080" 2>/dev/null
sleep 2

for entry in "${MODELS[@]}"; do
    IFS=':' read -r path name quant <<< "$entry"
    if [ ! -f "$path" ]; then
        echo "SKIP: $name - not found at $path"
        continue
    fi

    SIZE=$(du -h "$path" | cut -f1)
    echo ""
    echo "=========================================="
    echo "MODEL: $name ($quant) - $SIZE"
    echo "=========================================="

    for spec in "base" "ngram"; do
        if [ "$spec" = "base" ]; then
            echo "--- Base (no speculative decoding) ---"
            $SERVER -m "$path" -c 131072 -ngl 99 -t 16 -np 24 --host 0.0.0.0 --port 8080 &
        else
            echo "--- With ngram-simple speculative decoding ---"
            $SERVER -m "$path" -c 131072 -ngl 99 -t 16 -np 24 --host 0.0.0.0 --port 8080 --spec-type ngram-simple &
        fi
        sleep 10

        echo "Testing concurrency 1->24, stopping when TPS drops..."
        prev_tps=0
        conc=1
        while [ $conc -le 24 ]; do
            start=$(date +%s.%N)
            for i in $(seq 1 $conc); do
                curl -s -X POST $BACKEND/v1/chat/completions \
                    -H "Content-Type: application/json" \
                    -d "{\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":100}" > /tmp/b${conc}_${i}.json &
            done
            wait
            end=$(date +%s.%N)

            total=0
            for i in $(seq 1 $conc); do
                t=$(python3 -c "import json; print(json.load(open('/tmp/b${conc}_$i.json'))['usage']['completion_tokens'])" 2>/dev/null || echo 0)
                total=$((total + t))
            done

            elapsed=$(echo "$end - $start" | bc)
            tps=$(echo "scale=1; $total / $elapsed" | bc)

            # Stop if TPS dropped significantly (more than 5% below previous)
            if [ $(echo "$tps < $prev_tps * 0.95" | bc) -eq 1 ] && [ $conc -gt 4 ]; then
                echo "C$conc: TPS=$tps (DROPPED - stopping)"
                break
            fi

            echo "C$conc: TPS=$tps (total=$total tok in ${elapsed}s)"
            prev_tps=$tps
            conc=$((conc + 1))
        done

        pkill -f "llama-server.*8080" 2>/dev/null
        sleep 2
    done
done

echo ""
echo "=========================================="
echo "BENCHMARK COMPLETE"
echo "=========================================="
echo ""
echo "To restart your normal proxy:"
echo "  /home/mkinney/.local/bin/llama-proxy &"
