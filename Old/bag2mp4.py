import os
import cv2
import numpy as np
from rosbags.rosbag2 import Reader
from rosbags.typesys import Stores, get_typestore

bag_dir = "/home/acatalano/Desktop/Virtues_Data/subject_io/videos/Test1/video_bag_20261019_152742"
output  = os.path.join(bag_dir, "video.mp4")

typestore = get_typestore(Stores.ROS2_HUMBLE)

with Reader(bag_dir) as reader:
    print("Topics:")
    for conn in reader.connections:
        print(f"  {conn.topic}  [{conn.msgtype}]")

    image_conns = [c for c in reader.connections if 'image' in c.topic.lower()]
    if not image_conns:
        image_conns = list(reader.connections)
    print(f"\nUsing topic: {image_conns[0].topic}")

    writer      = None
    fps         = 30
    frame_count = 0

    for conn, ts, rawdata in reader.messages(connections=image_conns):
        msg = typestore.deserialize_cdr(rawdata, conn.msgtype)

        arr = np.frombuffer(msg.data, dtype=np.uint8)
        enc = msg.encoding

        if enc in ('rgb8',):
            frame = cv2.cvtColor(arr.reshape((msg.height, msg.width, 3)), cv2.COLOR_RGB2BGR)
        elif enc in ('bgr8',):
            frame = arr.reshape((msg.height, msg.width, 3))
        elif enc in ('mono8',):
            frame = cv2.cvtColor(arr.reshape((msg.height, msg.width)), cv2.COLOR_GRAY2BGR)
        elif enc in ('jpeg', 'compressed'):
            frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        else:
            frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
            if frame is None:
                frame = arr.reshape((msg.height, msg.width, -1))

        if frame is None:
            continue

        if writer is None:
            h, w = frame.shape[:2]
            fourcc = cv2.VideoWriter_fourcc(*'mp4v')
            writer = cv2.VideoWriter(output, fourcc, fps, (w, h))
            print(f"Writing {w}x{h}  enc={enc}")

        writer.write(frame)
        frame_count += 1
        if frame_count % 100 == 0:
            print(f"  {frame_count} frames...")

if writer:
    writer.release()
    print(f"\nSaved: {output}  ({frame_count} frames)")
else:
    print("No frames written")
