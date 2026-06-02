import os
import sys
import cv2
import numpy as np
import zstandard as zstd
from mcap.reader import make_reader
from mcap_ros2.decoder import DecoderFactory
import tempfile

BASE = "/run/user/1003/gvfs/smb-share:server=synkjk02.local,share=user%20study"

subject = sys.argv[1]
section = sys.argv[2]
trial   = sys.argv[3]

folder = os.path.join(
    BASE,f"subject_{subject}",
    "videos",section,trial
)

zstd_file = os.path.join(folder, "video_bag", "video_bag_0.mcap.zstd")

if not os.path.isfile(zstd_file):
    raise FileNotFoundError(zstd_file)

print("Decompressing...")

tmp_mcap = tempfile.NamedTemporaryFile(suffix=".mcap", delete=False).name

with open(zstd_file, "rb") as compressed:
    dctx = zstd.ZstdDecompressor()
    with open(tmp_mcap, "wb") as out:
        dctx.copy_stream(compressed, out)

print("Reading MCAP...")

output_mp4 = os.path.join(folder, "video.mp4")

reader = make_reader(open(tmp_mcap, "rb"), decoder_factories=[DecoderFactory()])

writer = None
fps = 30

frame_count = 0

for schema, channel, message, ros_msg in reader.iter_decoded_messages():

    if channel.topic != "/endoscope/right/image_raw":
        continue

    img = ros_msg.data
    height = ros_msg.height
    width  = ros_msg.width

    frame = (
        cv2
        .imdecode(
            np.frombuffer(img, dtype=np.uint8),
            cv2.IMREAD_COLOR
        )
    )

    if writer is None:
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        writer = cv2.VideoWriter(
            output_mp4,
            fourcc,
            fps,
            (width, height)
        )

    writer.write(frame)
    frame_count += 1

if writer is not None:
    writer.release()

print(f"Saved: {output_mp4}")
print(f"Frames: {frame_count}")