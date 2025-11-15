import subprocess

# Path to the correct Python inside your conda env
neon_python = "/home/acatalano/miniforge3/envs/NeonEnv3_13/bin/python"
pink_code = "/home/acatalano/pink_code/Neon/NeonGeneralCode/NeonRecordingRawData.py"

# Shimmer script can use system python3
shimmer_code = "/home/acatalano/pyshimmer/examples/shimmer_Bt.py"

processes = []

try:
    # launch Neon inside its environment
    p1 = subprocess.Popen([neon_python, pink_code])
    processes.append(p1)

    # launch Shimmer
    p2 = subprocess.Popen(["python3", shimmer_code])
    processes.append(p2)

    print("Both processes started. Press Ctrl+C to stop.")

    for p in processes:
        p.wait()

except KeyboardInterrupt:
    print("Stopping both processes...")
    for p in processes:
        p.terminate()
