#!/usr/bin/env python3
import pickle, sys

if len(sys.argv) < 2:
    print("Usage: verify_pkl.py <file.pkl>")
    sys.exit(1)

with open(sys.argv[1], "rb") as f:
    data = pickle.load(f)

print(f"Loaded {len(data)} records from {sys.argv[1]}")

if len(data) > 0:
    times = [t for t, _ in data]
    duration = times[-1] - times[0]
    print(f"Duration: {duration:.2f} s, mean rate: {len(data)/duration:.1f} Hz")
    print("First record:", data[0])
    print("Last record:", data[-1])
