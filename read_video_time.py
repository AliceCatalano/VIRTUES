from mcap.reader import make_reader

bag_path = "/home/acatalano/VIRTUES/level_L1/rep_01/video_bag/video_bag_0.mcap"
topic_name = "/endoscope/right/image_raw"

timestamps = []

with open(bag_path, "rb") as f:
    reader = make_reader(f)
    for schema, channel, message in reader.iter_messages():
        if channel.topic == topic_name:
            timestamps.append(message.log_time * 1e-9)

if not timestamps:
    print("No frames found.")
    exit()

video_start = timestamps[0]
video_end   = timestamps[-1]

print("\n----- VIDEO INFO -----")
print("First frame (epoch s):", video_start)
print("Last frame  (epoch s):", video_end)
print("Duration (s):", video_end - video_start)
print("Total frames:", len(timestamps))
print("Approx FPS:", len(timestamps) / (video_end - video_start))