#!/usr/bin/env python3
"""Benchmark ONNX embedding models."""

import time
import json
import os
import numpy as np

def load_onnx_model(model_path):
    """Load ONNX model with ONNX Runtime."""
    import onnxruntime as ort

    print(f"\n{'='*60}")
    print(f"Loading: {os.path.basename(model_path)} ({os.path.getsize(model_path)/1024/1024:.1f} MB)")
    start = time.time()

    sess_options = ort.SessionOptions()
    sess_options.intra_op_num_threads = 12
    sess_options.inter_op_num_threads = 1
    sess_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL

    session = ort.InferenceSession(model_path, sess_options)
    load_time = time.time() - start

    inputs = session.get_inputs()
    outputs = session.get_outputs()
    print(f"Load time: {load_time:.2f}s")
    print(f"Inputs: {[(i.name, i.shape, i.type) for i in inputs]}")
    print(f"Outputs: {[(o.name, o.shape, o.type) for o in outputs]}")

    return session, load_time

def bert_tokenize(texts, max_len=512):
    """Simple BERT-style tokenization using tokenizer.json if available."""
    import json

    # Try to load tokenizer from HuggingFace format
    tokenizer_path = None
    for base in texts if isinstance(texts, str) else [texts]:
        break

    # Simple whitespace tokenization + padding
    words = texts[0].split() if isinstance(texts, list) else texts.split()
    tokens = [ord(c) % 30522 for word in words for c in word][:max_len-2]
    tokens = [101] + tokens + [102]  # [CLS] ... [SEP]
    tokens = tokens + [0] * (max_len - len(tokens))  # padding

    return np.array([[tokens]], dtype=np.int64)

def run_benchmark(session, model_name, texts, runs=10):
    """Run benchmark on ONNX model."""
    import onnxruntime as ort

    input_name = session.get_inputs()[0].name

    # Check what inputs are needed
    inputs = session.get_inputs()
    input_names = [i.name for i in inputs]
    has_token_type_ids = 'token_type_ids' in input_names
    has_attention_mask = 'attention_mask' in input_names

    # Prepare inputs
    tokens = bert_tokenize(texts)
    seq_len = tokens.shape[-1]

    feed = {'input_ids': tokens}
    if has_token_type_ids:
        feed['token_type_ids'] = np.zeros_like(tokens)
    if has_attention_mask:
        feed['attention_mask'] = np.ones_like(tokens)

    print(f"\n{model_name} - {runs} runs, seq_len={seq_len}:")

    # Warmup
    for _ in range(3):
        session.run(None, feed)

    # Benchmark
    times = []
    for i in range(runs):
        start = time.time()
        out = session.run(None, feed)
        elapsed = time.time() - start
        times.append(elapsed)
        print(f"  Run {i+1}: {elapsed*1000:.2f}ms")

    avg = sum(times) / len(times)
    print(f"  Average: {avg*1000:.2f}ms")

    return {
        "model": model_name,
        "times": times,
        "avg_ms": avg * 1000,
        "embedding_dim": out[0].shape[-1] if out else None
    }

def main():
    models_dir = "/nas/Temp/repos/llama.cpp/models"

    test_texts = [
        "The quick brown fox jumps over the lazy dog",
        "Machine learning is a subset of artificial intelligence"
    ]

    results = []

    # BGE-small ONNX (127MB)
    bge_path = f"{models_dir}/bge-small-en-v1.5-model.onnx"
    if os.path.exists(bge_path):
        try:
            sess, load_time = load_onnx_model(bge_path)
            r = run_benchmark(sess, "BGE-small-en-v1.5-ONNX", test_texts)
            r["load_time"] = load_time
            results.append(r)
        except Exception as e:
            print(f"Error: {e}")
    else:
        print(f"BGE model not found: {bge_path}")

    # nomic ONNX (521MB)
    nomic_path = f"{models_dir}/model.onnx"
    if os.path.exists(nomic_path):
        try:
            sess, load_time = load_onnx_model(nomic_path)
            r = run_benchmark(sess, "Nomic-embed-text-v1.5-ONNX", test_texts)
            r["load_time"] = load_time
            results.append(r)
        except Exception as e:
            print(f"Error: {e}")

    print("\n" + "="*60)
    print("EMBEDDING BENCHMARK RESULTS")
    print("="*60)
    for res in results:
        print(f"\n{res['model']}:")
        print(f"  Size: {os.path.getsize(models_dir + '/' + res['model'].split('-')[0] + '.onnx') / 1024 / 1024:.1f} MB")
        print(f"  Load: {res['load_time']:.2f}s")
        print(f"  Speed: {res['avg_ms']:.2f}ms/inference")
        print(f"  Embedding dim: {res['embedding_dim']}")

    print("\n" + "="*60)
    print(json.dumps(results, indent=2))

if __name__ == "__main__":
    main()
