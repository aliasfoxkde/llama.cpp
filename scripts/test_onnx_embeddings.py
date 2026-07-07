#!/usr/bin/env python3
"""Test ONNX embedding model with ONNX Runtime."""

import time
import json
import sys
import os

def load_onnx_model(model_path):
    """Load ONNX model with ONNX Runtime."""
    import onnxruntime as ort

    print(f"Loading ONNX model: {model_path}")
    print(f"File size: {os.path.getsize(model_path) / 1024 / 1024:.1f} MB")
    start = time.time()

    # Create session with optimal settings for CPU
    sess_options = ort.SessionOptions()
    sess_options.intra_op_num_threads = 12
    sess_options.inter_op_num_threads = 1
    sess_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL

    session = ort.InferenceSession(model_path, sess_options)

    load_time = time.time() - start
    print(f"ONNX model loaded in {load_time:.2f}s")

    # Print model info
    inputs = session.get_inputs()
    outputs = session.get_outputs()
    print(f"Inputs: {[(i.name, i.shape, i.type) for i in inputs]}")
    print(f"Outputs: {[(o.name, o.shape, o.type) for o in outputs]}")

    return session, load_time


def simple_tokenize(text, max_length=512):
    """Simple character-based tokenization for testing."""
    # Map characters to token IDs (simplified)
    vocab_size = 30522  # BERT vocab size approximation
    tokens = [ord(c) % vocab_size for c in text[:max_length]]
    return tokens


def run_onnx_inference(session, texts, run_times=5):
    """Run ONNX inference and measure time."""
    import numpy as np

    # Get input name
    input_name = session.get_inputs()[0].name
    print(f"\nRunning ONNX inference ({run_times} runs) on {len(texts)} texts...")

    times = []
    for i in range(run_times):
        start = time.time()

        # Tokenize
        tokens = simple_tokenize(texts[0], max_length=512)
        input_ids = np.array([tokens], dtype=np.int64)

        # Run inference
        embeddings = session.run(None, {input_name: input_ids})

        elapsed = time.time() - start
        times.append(elapsed)
        print(f"  Run {i+1}: {elapsed*1000:.2f}ms")

    avg_time = sum(times) / len(times)
    print(f"Average inference time: {avg_time*1000:.2f}ms")
    print(f"Embedding shape: {embeddings[0].shape}")

    return times, avg_time, embeddings[0]


def main():
    models_dir = "/nas/Temp/repos/llama.cpp/models"

    # Test ONNX model
    onnx_model = f"{models_dir}/model_q4f16.onnx"

    if not os.path.exists(onnx_model):
        print(f"ONNX model not found: {onnx_model}")
        sys.exit(1)

    # Test texts
    test_texts = [
        "The quick brown fox jumps over the lazy dog",
        "Machine learning is a subset of artificial intelligence",
        "Hello world, this is a test of embedding models"
    ]

    results = {}

    try:
        session, load_time = load_onnx_model(onnx_model)
        onnx_times, onnx_avg, embeddings = run_onnx_inference(session, test_texts, run_times=5)
        results["onnx"] = {
            "model": onnx_model,
            "load_time": load_time,
            "times": onnx_times,
            "avg_time": onnx_avg,
            "embedding_shape": embeddings.shape.tolist()
        }
    except Exception as e:
        import traceback
        print(f"Error testing ONNX model: {e}")
        traceback.print_exc()
        results["onnx"] = {"error": str(e)}

    print("\n" + "="*60)
    print("RESULTS SUMMARY")
    print("="*60)
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
