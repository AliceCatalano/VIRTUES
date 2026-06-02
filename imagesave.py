#!/usr/bin/env python3
"""
Save one frame from each endoscope topic to disk.

Usage:
    python3 save_endoscope_images.py --level 1 --rep 1

This will save:
    /home/acatalano/acat_ws/src/hi_decklink_ros2/Examples/Level1Rep1_left.png
    /home/acatalano/acat_ws/src/hi_decklink_ros2/Examples/Level1Rep1_right.png
"""

import rclpy
from rclpy.node import Node
from sensor_msgs.msg import Image
from cv_bridge import CvBridge
import cv2
import os
import argparse
import sys


SAVE_DIR = "/home/acatalano/acat_ws/src/hi_decklink_ros2/Examples"
TOPIC_LEFT  = "/endoscope/left/image_raw"
TOPIC_RIGHT = "/endoscope/right/image_raw"


class EndoscopeImageSaver(Node):

    def __init__(self, level: int, rep: int):
        super().__init__("endoscope_image_saver")

        self.bridge = CvBridge()
        self.level  = level
        self.rep    = rep

        self.saved_left  = False
        self.saved_right = False

        os.makedirs(SAVE_DIR, exist_ok=True)

        self.path_left  = os.path.join(SAVE_DIR, f"Level{level}Rep{rep}_left.png")
        self.path_right = os.path.join(SAVE_DIR, f"Level{level}Rep{rep}_right.png")

        self.sub_left = self.create_subscription(
            Image, TOPIC_LEFT, self._cb_left, 1
        )
        self.sub_right = self.create_subscription(
            Image, TOPIC_RIGHT, self._cb_right, 1
        )

        self.get_logger().info(
            f"Waiting for one frame on:\n"
            f"  {TOPIC_LEFT}\n"
            f"  {TOPIC_RIGHT}"
        )

    # ------------------------------------------------------------------
    def _save(self, msg: Image, path: str, side: str) -> bool:
        try:
            cv_img = self.bridge.imgmsg_to_cv2(msg, desired_encoding="bgra8")
            cv2.imwrite(path, cv_img)
            self.get_logger().info(f"[{side}] Saved → {path}  ({cv_img.shape[1]}x{cv_img.shape[0]})")
            return True
        except Exception as e:
            self.get_logger().error(f"[{side}] Failed to save: {e}")
            return False

    def _cb_left(self, msg: Image):
        if not self.saved_left:
            self.saved_left = self._save(msg, self.path_left, "LEFT")
            self._check_done()

    def _cb_right(self, msg: Image):
        if not self.saved_right:
            self.saved_right = self._save(msg, self.path_right, "RIGHT")
            self._check_done()

    def _check_done(self):
        if self.saved_left and self.saved_right:
            self.get_logger().info("Both images saved. Shutting down.")
            raise SystemExit   # cleanly exit spin()


# ----------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Save one frame from each endoscope topic."
    )
    parser.add_argument("--level", type=int, default=1, help="Level number (default: 1)")
    parser.add_argument("--rep",   type=int, default=1, help="Rep number   (default: 1)")

    # argparse and rclpy both consume sys.argv — split them
    args, ros_args = parser.parse_known_args()

    rclpy.init(args=ros_args if ros_args else None)

    node = EndoscopeImageSaver(level=args.level, rep=args.rep)

    try:
        rclpy.spin(node)
    except SystemExit:
        pass
    except KeyboardInterrupt:
        node.get_logger().info("Interrupted by user.")
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()