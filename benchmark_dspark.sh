#!/bin/bash
# DSpark/MTO/REAP Benchmark for RTX 5060 Ti
# Concurrency 1-24 with early stop on 2x TPS decrease
# CTX: 128K, KV: q4_1

set -e

PORT=8080
LLAMA_SERVER="/home/mkinney/Repos/llama.cpp/build/bin/llama-server"
PROMPT="Explain the concept of machine learning in exactly 2 sentences."
MAX_TOKENS=100

# Models to test: path:name:hasMTP
MODELS=(
  "/home/mkinney/Models/JZC973/Qwen3.6-35B-REAP-MTP-UD-GGUF-Collection/Qwen3.6-35B-A3B-UD-Q3_K_M-REAP.gguf:Q3_K_M-REAP-MTP:yes"
  "/home/mkinney/Models/JZC973/Qwen3.6-35B-REAP-MTP-UD-GGUF-Collection/Qwen3.6-35B-A3B-UD-Q3_K_M-REAP-RangerX.gguf:Q3_K_M-RangerX-MTP:yes"
  "/home/mkinney/Models/crucible-labs/Qwen3.6-35B-A3B-REAP-48-Q3K-mixed-GGUF/qwen36-reap-48pct-mixed-q3k.gguf:REAP-48-Q3K:no"
)

RESULTS_FILE="/home/mkinney/Repos/llama.cpp/docs/DSpark_Benchmark_Results.md"

echo "# DSpark/Speculative Decoding Benchmark Results" > "$RESULTS_FILE"
echo "Date: $(date)" >> "$RESULTS_FILE"
echo "GPU: RTX 5060 Ti 16GB" >> "$RESULTS_FILE"
echo "CTX: 128K, KV: q4_1" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

for model_info in "${MODELS[@]}"; do
  IFS=':' read -r MODEL_PATH MODEL_NAME HAS_MTP <<< "$model_info"

  if [ ! -f "$MODEL_PATH" ]; then
    echo "SKIP: $MODEL_NAME - file not found"
    continue
  fi

  echo "=============================================="
  echo "Testing: $MODEL_NAME"
  echo "=============================================="

  echo "## $MODEL_NAME" >> "$RESULTS_FILE"
  echo "" >> "$RESULTS_FILE"
  echo "| Config | Concurrency | TPS | Accepted/Total |" >> "$RESULTS_FILE"
  echo "|--------|-------------|-----|----------------|" >> "$RESULTS_FILE"

  # Baseline (no speculative)
  echo "Testing baseline (no MTP)..."
  pkill -f "llama-server.*$PORT" 2>/dev/null || true
  sleep 2

  $LLAMA_SERVER -m "$MODEL_PATH" -c 131072 -ctk q4_1 -ctv q4_1 -fa on -ngl 99 -tb 512 -ub 256 --port $PORT 2>&1 &
  sleep 10

  for conc in 1 2 4 8 12 16 20 24; do
    total=0; accepted=0; generated=0; start=$(date +%s.%N)
    declare -a pids

    for i in $(seq 1 $conc); do
      curl -s -X POST "http://localhost:$PORT/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"main\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":$MAX_TOKENS,\"temperature\":0.7}" > /tmp/b${conc}_${i}.json &
      pids+=($!)
    done

    for pid in "${pids[@]}"; do wait $pid 2>/dev/null; done
    end=$(date +%s.%N); elapsed=$(echo "$end - $start" | bc)

    for i in $(seq 1 $conc); do
      tokens=$(python3 -c "import json; print(json.load(open('/tmp/b${conc}_${i}.json')).get('usage',{}).get('completion_tokens',0))" 2>/dev/null || echo "0")
      total=$((total + tokens))
      rm -f /tmp/b${conc}_${i}.json
    done

    tps=$(echo "scale=1; ($total) / $elapsed" | bc)
    echo "| baseline | $conc | $tps | N/A |" >> "$RESULTS_FILE"
    echo "  Conc $conc: ${elapsed}s, ~$tps tok/s (total=$total)"
    sleep 1
  done

  # MTP if available
  if [ "$HAS_MTP" = "yes" ]; then
    for NMAX in 3 5; do
      echo "Testing MTP n_max=$NMAX..."
      pkill -f "llama-server.*$PORT" 2>/dev/null || true
      sleep 2

      $LLAMA_SERVER -m "$MODEL_PATH" -c 131072 -ctk q4_1 -ctv q4_1 -fa on -ngl 99 \
        --spec-type draft-mtp --spec-draft-n-max $NMAX \
        -tb 512 -ub 256 --port $PORT 2>&1 &
      sleep 10

      prev_tps=0; decrease_count=0

      for conc in 1 2 4 8 12 16 20 24; do
        total=0; accepted=0; generated=0; start=$(date +%s.%N)
        declare -a pids

        for i in $(seq 1 $conc); do
          curl -s -X POST "http://localhost:$PORT/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"main\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":$MAX_TOKENS,\"temperature\":0.7}" > /tmp/b${conc}_${i}.json &
          pids+=($!)
        done

        for pid in "${pids[@]}"; do wait $pid 2>/dev/null; done
        end=$(date +%s.%N); elapsed=$(echo "$end - $start" | bc)

        for i in $(seq 1 $conc); do
          tokens=$(python3 -c "import json; print(json.load(open('/tmp/b${conc}_${i}.json')).get('usage',{}).get('completion_tokens',0))" 2>/dev/null || echo "0")
          total=$((total + tokens))
          rm -f /tmp/b${conc}_${i}.json
        done

        tps=$(echo "scale=1; ($total) / $elapsed" | bc)
        echo "| MTP n_max=$NMAX | $conc | $tps | N/A |" >> "$RESULTS_FILE"
        echo "  Conc $conc: ${elapsed}s, ~$tps tok/s (total=$total)"

        # Early stop check
        if [ ! -z "$prev_tps" ] && [ ! -z "$tps" ]; then
          if (( $(echo "$tps < $prev_tps" | bc -l) )); then
            decrease_count=$((decrease_count + 1))
            if [ $decrease_count -ge 2 ]; then
              echo "  Early stop at concurrency $conc"
              break
            fi
          else
            decrease_count=0
          fi
        fi
        prev_tps=$tps

        sleep 1
      done
    done
  fi

  pkill -f "llama-server.*$PORT" 2>/dev/null || true
  sleep 2
done

echo ""
echo "=============================================="
echo "Results saved to: $RESULTS_FILE"
echo "=============================================="
cat "$RESULTS_FILE"
