#!/usr/bin/env python3
"""
Inspect a single .mcap.zstd rosbag: prints frame count, duration, and actual FPS.
Does NOT convert to MP4 — read-only diagnostic tool.

Usage:
    source /opt/ros/jazzy/setup.bash
    /home/acatalano/VIRTUES/venv_converter/bin/python inspect_bag.py
"""

import os
import re
import shutil
import subprocess
import tempfile

from rosbag2_py import SequentialReader, StorageOptions, ConverterOptions

# ============================================================
#  CONFIG — change BAG_DIR to inspect a different bag
# ============================================================
BAG_DIR     = "/run/user/1002/gvfs/smb-share:server=synkjk02.local,share=user%20study/subject_s09N/videos/level_L1/rep_05_R/video_bag"
IMAGE_TOPIC = "/endoscope/right/image_raw/compressed"
TEMP_BASE   = "/tmp"
# ============================================================


def patch_metadata(meta_path):
    with open(meta_path, "r") as f:
        content = f.read()
    content = content.replace(".mcap.zstd", ".mcap")
    content = re.sub(r"compression_format:.*", "compression_format: ''", content)
    content = re.sub(r"compression_mode:.*",   "compression_mode: ''",   content)
    with open(meta_path, "w") as f:
        f.write(content)


def main():
    zstd_path = os.path.join(BAG_DIR, "video_bag_0.mcap.zstd")
    meta_path = os.path.join(BAG_DIR, "metadata.yaml")

    for f, label in [(zstd_path, "zstd file"), (meta_path, "metadata.yaml")]:
        if not os.path.exists(f):
            print(f"[ERROR] {label} not found: {f}")
            return

    print(f"Inspecting: {BAG_DIR}\n")

    tmp_dir     = tempfile.mkdtemp(prefix="bag_inspect_", dir=TEMP_BASE)
    tmp_bag_dir = os.path.join(tmp_dir, "video_bag")
    os.makedirs(tmp_bag_dir)
    tmp_mcap    = os.path.join(tmp_bag_dir, "video_bag_0.mcap")

    try:
        print("Decompressing (this may take a minute)...")
        with open(tmp_mcap, "wb") as fout:
            subprocess.run(
                ["zstdcat", zstd_path],
                stdout=fout, stderr=subprocess.PIPE
            )
        size = os.path.getsize(tmp_mcap)
        print(f"Decompressed size : {size / 1e9:.2f} GB\n")

        shutil.copy2(meta_path, os.path.join(tmp_bag_dir, "metadata.yaml"))
        patch_metadata(os.path.join(tmp_bag_dir, "metadata.yaml"))

        reader = SequentialReader()
        reader.open(
            StorageOptions(uri=tmp_bag_dir, storage_id="mcap"),
            ConverterOptions("cdr", "cdr"),
        )

        # Print all topics
        topics = reader.get_all_topics_and_types()
        print(f"Topics ({len(topics)}):")
        for t in topics:
            print(f"  {t.name}  [{t.type}]")
        print()

        # Collect timestamps for image topic
        timestamps = []
        topic_counts = {}
        while reader.has_next():
            topic, _, ts = reader.read_next()
            topic_counts[topic] = topic_counts.get(topic, 0) + 1
            if topic == IMAGE_TOPIC:
                timestamps.append(ts)

        print("Message counts per topic:")
        for topic, count in sorted(topic_counts.items()):
            print(f"  {topic}: {count} msgs")
        print()

        if len(timestamps) < 2:
            print(f"[WARN] Not enough image frames to compute FPS ({len(timestamps)} found)")
            return

        duration   = (timestamps[-1] - timestamps[0]) / 1e9
        actual_fps = (len(timestamps) - 1) / duration

        print("=" * 45)
        print(f"  Frames      : {len(timestamps)}")
        print(f"  Duration    : {duration:.2f} s  ({duration/60:.1f} min)")
        print(f"  Actual FPS  : {actual_fps:.1f}")
        print(f"  Use FPS={round(actual_fps)} in convert_single_bag.py")
        print("=" * 45)

    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        print("\nTemp files cleaned up")


if __name__ == "__main__":
    main()