#!/usr/bin/env python3
"""
Batch inspect and convert .mcap.zstd rosbags to MP4.

For each bag that has a metadata.yaml:
  1. Decompress to local temp dir
  2. Patch metadata (remove zstd references)
  3. Inspect: count frames and compute actual FPS
  4. If frames > MIN_FRAMES: convert to MP4 at actual FPS
  5. Clean up temp files

Usage:
    source /opt/ros/jazzy/setup.bash
    /home/acatalano/VIRTUES/venv_converter/bin/python batch_convert_all.py
"""

import os
import re
import glob
import shutil
import subprocess
import tempfile

import cv2
import numpy as np
from rosbag2_py import SequentialReader, StorageOptions, ConverterOptions, StorageFilter
from rosidl_runtime_py.utilities import get_message
from rclpy.serialization import deserialize_message

# ============================================================
#  CONFIG
# ============================================================
SMB_BASE    = "/run/user/1002/gvfs/smb-share:server=synkjk02.local,share=user%20study"
IMAGE_TOPIC = "/endoscope/right/image_raw/compressed"
MIN_FRAMES  = 300        # skip bags with fewer frames than this
OVERWRITE   = False      # set True to re-convert already existing MP4s
TEMP_BASE   = "/tmp"     # needs ~6-8 GB free per bag (cleaned up after each)

# Where to write MP4s:
#   None  → writes next to the original bag folder on the NAS
#   path  → all MP4s go into this local directory, named by their relative path
OUTPUT_BASE = "/home/acatalano/video_bag_test"
# ============================================================


def find_eligible_bags(smb_base):
    """Find all video_bag dirs that have both metadata.yaml and a .mcap.zstd file. Skip #recycle."""
    pattern = os.path.join(smb_base, "**", "video_bag", "metadata.yaml")
    meta_files = sorted(glob.glob(pattern, recursive=True))

    bags = []
    for meta_path in meta_files:
        bag_dir = os.path.dirname(meta_path)
        if "#recycle" in bag_dir:
            continue
        zstd_files = glob.glob(os.path.join(bag_dir, "*.mcap.zstd"))
        if not zstd_files:
            continue
        bags.append((bag_dir, zstd_files[0], meta_path))
    return bags


def get_output_path(bag_dir, smb_base, output_base):
    """Build output MP4 path from the bag's relative path."""
    rel   = os.path.relpath(bag_dir, smb_base)
    parts = [p for p in rel.split(os.sep) if p not in ("videos", "video_bag")]
    name  = "_".join(parts) + ".mp4"
    if output_base:
        os.makedirs(output_base, exist_ok=True)
        return os.path.join(output_base, name)
    else:
        return os.path.join(os.path.dirname(bag_dir), name)


def patch_metadata(meta_path):
    """Replace .mcap.zstd references with .mcap and clear compression fields."""
    with open(meta_path, "r") as f:
        content = f.read()
    content = content.replace(".mcap.zstd", ".mcap")
    content = re.sub(r"compression_format:.*", "compression_format: ''", content)
    content = re.sub(r"compression_mode:.*",   "compression_mode: ''",   content)
    with open(meta_path, "w") as f:
        f.write(content)


def decompress(zstd_path, tmp_mcap):
    """Decompress zstd to tmp_mcap. Returns size in bytes."""
    with open(tmp_mcap, "wb") as fout:
        subprocess.run(["zstdcat", zstd_path], stdout=fout, stderr=subprocess.PIPE)
    return os.path.getsize(tmp_mcap) if os.path.exists(tmp_mcap) else 0


def inspect(tmp_bag_dir, image_topic):
    """
    Read all messages, return (timestamps_list, topic_type_str).
    timestamps_list contains only image topic timestamps.
    """
    reader = SequentialReader()
    reader.open(
        StorageOptions(uri=tmp_bag_dir, storage_id="mcap"),
        ConverterOptions("cdr", "cdr"),
    )

    topic_types = {t.name: t.type for t in reader.get_all_topics_and_types()}
    type_str = topic_types.get(image_topic, "")

    timestamps = []
    while reader.has_next():
        topic, _, ts = reader.read_next()
        if topic == image_topic:
            timestamps.append(ts)

    return timestamps, type_str


def decode_frame(msg, is_compressed):
    """Decode a ROS image message to a BGR cv2 frame."""
    if is_compressed:
        arr = np.frombuffer(msg.data, np.uint8)
        return cv2.imdecode(arr, cv2.IMREAD_COLOR)

    arr = np.frombuffer(msg.data, np.uint8)
    enc = msg.encoding.lower()

    if enc in ("bgr8", "8uc3"):
        return arr.reshape((msg.height, msg.width, 3))
    elif enc == "rgb8":
        return cv2.cvtColor(arr.reshape((msg.height, msg.width, 3)), cv2.COLOR_RGB2BGR)
    elif enc == "mono8":
        return cv2.cvtColor(arr.reshape((msg.height, msg.width)), cv2.COLOR_GRAY2BGR)
    elif enc in ("yuv422", "yuv422_yuy2", "yuyv"):
        return cv2.cvtColor(arr.reshape((msg.height, msg.width, 2)), cv2.COLOR_YUV2BGR_YUY2)
    elif enc == "bayer_rggb8":
        return cv2.cvtColor(arr.reshape((msg.height, msg.width)), cv2.COLOR_BayerRG2BGR)
    else:
        channels = len(arr) // (msg.height * msg.width)
        return arr.reshape((msg.height, msg.width, channels))[..., :3]


def convert_to_mp4(tmp_bag_dir, out_mp4, image_topic, fps, type_str):
    """Read bag and write frames to MP4. Returns frame count."""
    is_compressed = "CompressedImage" in type_str
    msg_type      = get_message(type_str)

    reader = SequentialReader()
    reader.open(
        StorageOptions(uri=tmp_bag_dir, storage_id="mcap"),
        ConverterOptions("cdr", "cdr"),
    )
    reader.set_filter(StorageFilter(topics=[image_topic]))

    video_writer = None
    frame_count  = 0

    while reader.has_next():
        topic, data, _ = reader.read_next()
        if topic != image_topic:
            continue
        try:
            msg   = deserialize_message(data, msg_type)
            frame = decode_frame(msg, is_compressed)
            if frame is None or frame.size == 0:
                continue
        except Exception as e:
            print(f"    [WARN] frame decode error: {e}")
            continue

        if video_writer is None:
            h, w = frame.shape[:2]
            os.makedirs(os.path.dirname(out_mp4), exist_ok=True)
            video_writer = cv2.VideoWriter(
                out_mp4,
                cv2.VideoWriter_fourcc(*"mp4v"),
                fps, (w, h)
            )
            if not video_writer.isOpened():
                print(f"    [ERROR] Could not open VideoWriter")
                return 0
            print(f"    Resolution : {w}x{h}, FPS: {fps}")

        video_writer.write(frame)
        frame_count += 1
        if frame_count % 500 == 0:
            print(f"    {frame_count} frames written...")

    if video_writer:
        video_writer.release()

    return frame_count


def process_bag(bag_dir, zstd_path, meta_path, out_mp4):
    """Full pipeline for one bag. Returns 'converted', 'skipped', 'too_short', or 'failed'."""
    if os.path.exists(out_mp4) and not OVERWRITE:
        print(f"  [SKIP] MP4 already exists")
        return "skipped"

    # Check zstd integrity
    result = subprocess.run(["zstd", "-t", zstd_path], capture_output=True)
    if result.returncode != 0:
        print(f"  [WARN] Truncated zstd stream — attempting partial recovery")

    tmp_dir     = tempfile.mkdtemp(prefix="bag_convert_", dir=TEMP_BASE)
    tmp_bag_dir = os.path.join(tmp_dir, "video_bag")
    os.makedirs(tmp_bag_dir)
    tmp_mcap    = os.path.join(tmp_bag_dir, "video_bag_0.mcap")

    try:
        # Decompress
        print(f"  Decompressing...")
        size = decompress(zstd_path, tmp_mcap)
        if size < 1_000_000:
            print(f"  [ERROR] Only {size} bytes recovered")
            return "failed"
        print(f"  Decompressed : {size / 1e9:.2f} GB")

        # Patch metadata
        dst_meta = os.path.join(tmp_bag_dir, "metadata.yaml")
        shutil.copy2(meta_path, dst_meta)
        patch_metadata(dst_meta)

        # Inspect
        print(f"  Inspecting...")
        timestamps, type_str = inspect(tmp_bag_dir, IMAGE_TOPIC)
        n_frames = len(timestamps)

        if n_frames < 2:
            print(f"  [TOO SHORT] Only {n_frames} frame(s) found")
            return "too_short"

        duration   = (timestamps[-1] - timestamps[0]) / 1e9
        actual_fps = round((n_frames - 1) / duration, 1)
        fps_int    = max(1, round(actual_fps))

        print(f"  Frames   : {n_frames}")
        print(f"  Duration : {duration:.1f} s  ({duration/60:.1f} min)")
        print(f"  FPS      : {actual_fps} → using {fps_int}")

        if n_frames < MIN_FRAMES:
            print(f"  [TOO SHORT] {n_frames} frames < threshold {MIN_FRAMES} — skipping conversion")
            return "too_short"

        if not type_str:
            print(f"  [ERROR] Image topic not found in bag")
            return "failed"

        # Convert
        print(f"  Converting to MP4...")
        count = convert_to_mp4(tmp_bag_dir, out_mp4, IMAGE_TOPIC, fps_int, type_str)

        if count == 0:
            print(f"  [ERROR] No frames written")
            if os.path.exists(out_mp4):
                os.remove(out_mp4)
            return "failed"

        print(f"  [OK] {count} frames → {out_mp4}")
        return "converted"

    except Exception as e:
        print(f"  [ERROR] Unexpected error: {e}")
        return "failed"

    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def main():
    print(f"Scanning for eligible bags under:\n  {SMB_BASE}\n")
    bags = find_eligible_bags(SMB_BASE)

    if not bags:
        print("No eligible bags found (need both metadata.yaml and .mcap.zstd).")
        return

    print(f"Found {len(bags)} eligible bag(s)\n{'=' * 60}\n")

    converted = skipped = too_short = failed = 0
    failed_list = []

    for i, (bag_dir, zstd_path, meta_path) in enumerate(bags, 1):
        rel    = os.path.relpath(bag_dir, SMB_BASE)
        out_mp4 = get_output_path(bag_dir, SMB_BASE, OUTPUT_BASE)

        print(f"[{i}/{len(bags)}] {rel}")

        result = process_bag(bag_dir, zstd_path, meta_path, out_mp4)

        if result == "converted":
            converted += 1
        elif result == "skipped":
            skipped += 1
        elif result == "too_short":
            too_short += 1
        else:
            failed += 1
            failed_list.append(rel)
        print()

    print("=" * 60)
    print(f"Converted : {converted}")
    print(f"Skipped   : {skipped}  (MP4 already existed)")
    print(f"Too short : {too_short}  (fewer than {MIN_FRAMES} frames)")
    print(f"Failed    : {failed}")
    if failed_list:
        print("\nFailed bags:")
        for f in failed_list:
            print(f"  {f}")


if __name__ == "__main__":
    main()