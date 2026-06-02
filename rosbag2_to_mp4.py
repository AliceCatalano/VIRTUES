#!/usr/bin/env python3
"""
Batch-convert rosbag (.mcap) files to MP4 for all levels and repetitions.

Expected structure:
BASE_DIR/
  level_L1/
    ...
  level_L5/
    rep_01/
    ...
    rep_10/
      video_bag/        ← bag folder (passed to SequentialReader)
        video_bag_0.mcap

Output MP4 is written one level up, inside the rep folder:
BASE_DIR/level_L1/rep_01/endoscope.mp4

Requirements (ROS2 environment must be sourced before running):
source /opt/ros/<distro>/setup.bash
pip install opencv-python
"""

import os
import glob
import cv2

from rosbag2_py import SequentialReader, StorageOptions, ConverterOptions
from rosidl_runtime_py.utilities import get_message
from rclpy.serialization import deserialize_message
from cv_bridge import CvBridge


# ============================================================
# CONFIG — edit these as needed
# ============================================================

BASE_DIR = "/run/user/1002/gvfs/smb-share:server=synkjk02.local,share=user%20study/subject_s48N/Baseline2/Level1"
IMAGE_TOPIC = "/endoscope/right/image_raw"
FPS = 30
OVERWRITE = False  # set True to re-convert already existing MP4s

# ============================================================

bridge = CvBridge()


def convert_bag(bag_dir: str, out_path: str) -> str:
    """
    Convert a single bag folder to an MP4.
    Returns: 'ok', 'skipped', or 'failed'.
    """

    if os.path.exists(out_path) and not OVERWRITE:
        print(f" [SKIP] already exists: {out_path}")
        return "skipped"

    # ── Open bag ─────────────────────────────────────────────
    reader = SequentialReader()
    try:
        reader.open(
            StorageOptions(uri=bag_dir, storage_id="mcap"),
            ConverterOptions("cdr", "cdr"),
        )
    except Exception as e:
        print(f" [ERROR] Could not open bag: {e}")
        return "failed"

    # ── Check topic exists ───────────────────────────────────
    topic_types = {t.name: t.type for t in reader.get_all_topics_and_types()}

    if IMAGE_TOPIC not in topic_types:
        print(f" [ERROR] Topic '{IMAGE_TOPIC}' not found.")
        print(f" Available topics: {list(topic_types.keys())}")
        return "failed"

    msg_type = get_message(topic_types[IMAGE_TOPIC])

    # ── Read frames and write MP4 ────────────────────────────
    video_writer = None
    frame_count = 0

    while reader.has_next():
        topic, data, _timestamp = reader.read_next()

        if topic != IMAGE_TOPIC:
            continue

        try:
            msg = deserialize_message(data, msg_type)
            frame = bridge.imgmsg_to_cv2(msg, desired_encoding="bgr8")
        except Exception as e:
            print(f" [WARN] Could not decode frame: {e}")
            continue

        if video_writer is None:
            h, w = frame.shape[:2]
            video_writer = cv2.VideoWriter(
                out_path,
                cv2.VideoWriter_fourcc(*"mp4v"),
                FPS,
                (w, h),
            )

            if not video_writer.isOpened():
                print(f" [ERROR] Could not open VideoWriter for {out_path}")
                return "failed"

        video_writer.write(frame)
        frame_count += 1

    if video_writer:
        video_writer.release()

    if frame_count == 0:
        print(" [ERROR] No frames decoded — check IMAGE_TOPIC.")
        if os.path.exists(out_path):
            os.remove(out_path)
        return "failed"

    print(f" [OK] {frame_count} frames → {out_path}")
    return "ok"


def main():
    # NEW structure: Baseline / Level* / video_bag
    pattern = os.path.join(BASE_DIR, "video_bag")
    bag_dirs = sorted(glob.glob(pattern))

    if not bag_dirs:
        print(f"No video_bag folders found under:\n {pattern}")
        return

    print(f"Found {len(bag_dirs)} bag(s) under {BASE_DIR}\n")

    success = 0
    skipped = 0
    failed = 0

    for bag_dir in bag_dirs:
        level_folder = os.path.basename(os.path.dirname(bag_dir))  # e.g. "Level1"
        level_num = level_folder.replace("Level", "")              # e.g. "1"

        out_name = f"video_Level{level_num}.mp4"
        out_path = os.path.join(os.path.dirname(bag_dir), out_name)

        rel = os.path.relpath(bag_dir, BASE_DIR)
        print(f"[{rel}]")

        result = convert_bag(bag_dir, out_path)

        if result == "ok":
            success += 1
        elif result == "skipped":
            skipped += 1
        else:
            failed += 1

        print()

    print("=" * 55)
    print(f"Done. Converted: {success} Skipped: {skipped} Failed: {failed}")


if __name__ == "__main__":
    main()