# save as ~/recover_video.py
from mcap.reader import make_reader
from mcap_ros2.decoder import DecoderFactory
import cv2, numpy as np

MCAP_FILE = "/home/acatalano/video_bag_test/video_bag_0.mcap"
OUT_FILE  = "/home/acatalano/video_bag_test/recovered_video.mp4"
TOPIC     = "/endoscope/right/image_raw/compressed"

with open(MCAP_FILE, "rb") as f:
    reader = make_reader(f, decoder_factories=[DecoderFactory()])
    writer = None
    count = 0
    try:
        for schema, channel, message, decoded in reader.iter_decoded_messages(topics=[TOPIC]):
            try:
                np_arr = np.frombuffer(decoded.data, np.uint8)
                frame = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
                if frame is None:
                    continue
                if writer is None:
                    h, w = frame.shape[:2]
                    writer = cv2.VideoWriter(OUT_FILE, cv2.VideoWriter_fourcc(*"mp4v"), 30, (w, h))
                    print(f"First frame: {w}x{h}")
                writer.write(frame)
                count += 1
                if count % 100 == 0:
                    print(f"  {count} frames...")
            except Exception as e:
                print(f"  [WARN] frame skip: {e}")
                continue
    except Exception as e:
        print(f"  [EOF/corrupt] stopped at frame {count}: {e}")

if writer:
    writer.release()
print(f"Done. Recovered {count} frames → {OUT_FILE}")