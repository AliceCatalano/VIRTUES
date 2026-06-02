from mcap.mcap0.stream_reader import StreamReader

path = "recovered_partial.mcap"

with open(path, "rb") as f:
    sr = StreamReader(f)

    msg_count = 0
    last_topic = None

    try:
        for record in sr.records():
            if record.type == "message":
                msg_count += 1
    except Exception as e:
        print("Stopped due to corruption:", e)

print("Recovered messages:", msg_count)