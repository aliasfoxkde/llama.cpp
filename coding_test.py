#!/usr/bin/env python3
import requests
import json
import time

API = "http://localhost:8082"

TESTS = [
    ("Longest Palindromic Substring", "Write a Python function to find the longest palindromic substring in a given string. Include both expand-around-center and dynamic programming approaches."),
    ("Binary Tree Level Order", "Write a Python function to perform level order traversal of a binary tree. Include both BFS and DFS recursive approaches with proper docstrings and type hints."),
    ("LRU Cache", "Implement an LRU (Least Recently Used) cache in Python with O(1) get and put operations. Include proper type hints and a usage example."),
    ("Merge Intervals", "Write a Python function that takes a list of intervals and merges all overlapping intervals. Example: [[1,3],[2,6],[8,10],[15,18]] -> [[1,6],[8,10],[15,18]]"),
    ("Trie Data Structure", "Implement a Trie (prefix tree) in Python with insert, search, and startsWith methods. Include proper docstrings."),
    ("Concurrent Worker Pool", "Write a Python thread pool executor that processes tasks concurrently with a maximum number of workers. Include error handling and result collection."),
]

def run_test(name, prompt):
    print(f"\n{'='*60}")
    print(f"TEST: {name}")
    print(f"{'='*60}")

    start = time.time()
    resp = requests.post(f"{API}/v1/chat/completions", json={
        "model": "current",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 600
    })
    elapsed = time.time() - start

    if resp.status_code == 200:
        data = resp.json()
        content = data['choices'][0]['message']['content']
        tokens = data['usage']['total_tokens']
        print(f"Response ({elapsed:.1f}s, {tokens} tokens):")
        print("-" * 40)
        print(content[:2000])
        if len(content) > 2000:
            print("...(truncated)")
        print(f"\n[OK] {tokens} tokens in {elapsed:.1f}s = {tokens/elapsed:.1f} TPS")
    else:
        print(f"ERROR: {resp.status_code} - {resp.text}")

# Warmup
print("Warming up...")
requests.post(f"{API}/v1/chat/completions", json={
    "model": "current",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 50
})
time.sleep(1)

# Run all tests
for name, prompt in TESTS:
    run_test(name, prompt)
    time.sleep(1)

print("\n" + "="*60)
print("ALL TESTS COMPLETE")
print("="*60)
