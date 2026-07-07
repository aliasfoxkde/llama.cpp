#!/usr/bin/env python3
"""Test embedding models: ONNX vs GGUF comparison."""

import time
import json
import sys

def load_onnx_model(model_path):
    """Load ONNX model with ONNX Runtime."""
    import onnxruntime as ort

    print(f"Loading ONNX model: {model_path}")
    start = time.time()

    # Create session with optimal settings for CPU
    sess_options = ort.SessionOptions()
    sess_options.intra_op_num_threads = 12
    sess_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL

    session = ort.InferenceSession(model_path, sess_options)

    load_time = time.time() - start
    print(f"ONNX model loaded in {load_time:.2f}s")

    return session, load_time


def get_onnx_input_name(session):
    """Get the input name for the ONNX model."""
    inputs = session.get_inputs()
    if inputs:
        return inputs[0].name
    return "input_ids"


def run_onnx_inference(session, texts, run_times=5):
    """Run ONNX inference and measure time."""
    import numpy as np

    # Get input name
    input_name = get_onnx_input_name(session)
    inputs = session.get_inputs()

    print(f"\nRunning ONNX inference ({run_times} runs)...")

    times = []
    for i in range(run_times):
        start = time.time()

        # Run inference - input format depends on model
        if "input_ids" in input_name.lower() or len(inputs) == 1:
            # Tokenize manually (simple approximation)
            encoded = np.array([[ord(c) % 50000 for c in text[:512]]] for text in texts)
            session.run(None, {input_name: encoded.astype(np.int64)})
        else:
            session.run(None, {input_name: np.array(texts)})

        elapsed = time.time() - start
        times.append(elapsed)
        print(f"  Run {i+1}: {elapsed*1000:.2f}ms")

    avg_time = sum(times) / len(times)
    print(f"Average inference time: {avg_time*1000:.2f}ms")

    return times, avg_time


def run_gguf_inference(model_path, texts, run_times=5):
    """Run GGUF inference using llama-server CLI."""
    import subprocess

    print(f"\nRunning GGUF inference ({run_times} runs)...")
    times = []

    for i in range(run_times):
        start = time.time()

        # Run a quick embedding extraction
        cmd = [
            "./llama-server",
            "-m", model_path,
            "-fa",  # flash attention
            "-p", texts[0][:100],
            "-n", "1",
            "--log-disable"
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        elapsed = time.time() - start
        times.append(elapsed)
        print(f"  Run {i+1}: {elapsed*1000:.2f}ms")

    avg_time = sum(times) / len(times)
    print(f"Average inference time: {avg_time*1000:.2f}ms")

    return times, avg_time


def main():
    import sys

    models_dir = "/nas/Temp/repos/llama.cpp/models"

    # Test texts
    test_texts = [
        "The quick brown fox jumps over the lazy dog",
        "Machine learning is a subset of artificial intelligence",
        "Hello world, this is a test of embedding models"
    ]

    results = {}

    # Test ONNX model
    onnx_model = f"{models_dir}/model_q4f16.onnx"
    try:
        session, load_time = load_onnx_model(onnx_model)
        onnx_times, onnx_avg = run_onnx_inference(session, test_texts, run_times=5)
        results["onnx"] = {
            "load_time": load_time,
            "times": onnx_times,
            "avg_time": onnx_avg
        }
    except Exception as e:
        print(f"Error testing ONNX model: {e}")
        results["onnx"] = {"error": str(e)}

    # Test GGUF model if available
    gguf_models = [
        f"{models_dir}/nomic-embed-text-v1.5-Q4_K_M.gguf",
    ]

    for gguf_model in gguf_models:
        try:
            import os
            if os.path.exists(gguf_model):
                gguf_times, gguf_avg = run_gguf_inference(gguf_model, test_texts, run_times=3)
                results["gguf"] = {
                    "model": gguf_model,
                    "times": gguf_times,
                    "avg_time": gguf_avg
                }
            else:
                print(f"GGUF model not found: {gguf_model}")
        except Exception as e:
            print(f"Error testing GGUF model: {e}")
            results["gguf"] = {"error": str(e)}

    print("\n" + "="*60)
    print("RESULTS SUMMARY")
    print("="*60)
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
