#!/home/acatalano/miniforge3/envs/NeonEnv/bin/python3
import rclpy
from rclpy.node import Node
import pickle, os, signal, sys, json, csv
from std_msgs.msg import String
from collections import defaultdict
from datetime import datetime

class RecorderNode(Node):
    def __init__(self):
        super().__init__("recorder_node")
        
        self.buffers = defaultdict(list)
        self.counts = defaultdict(int)

        # Get parameter with default value
        self.declare_parameter("output_folder", "./data/session")
        base_folder = self.get_parameter("output_folder").value
        
        timestamp_str = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        self.output_folder = os.path.join(base_folder, f"session_{timestamp_str}")
        os.makedirs(self.output_folder, exist_ok=True)

        # Create subscriptions
        #self.create_subscription(String, "/gsr_data", self.gsr_callback, 2000)
        self.create_subscription(String, "/eye_data", self.eye_callback, 2000)
        self.create_subscription(String, "/sync_event", self.event_callback, 100)

        # Set up signal handler
        signal.signal(signal.SIGINT, self.handle_shutdown)
        
        self.get_logger().info(f"RecorderNode started – saving data to {self.output_folder}")

    def _append(self, key, msg):
        current_time = self.get_clock().now().nanoseconds / 1e9
        self.buffers[key].append((current_time, msg))
        self.counts[key] += 1

    def gsr_callback(self, msg): 
        self._append("gsr", msg.data)
    
    def eye_callback(self, msg): 
        self._append("eye", msg.data)
    
    def event_callback(self, msg): 
        self._append("events", msg.data)

    def _save_as_csv(self, name, buf):
        """
        Save buffered data as expanded CSV: each JSON field = separate column.
        """
        csv_path = os.path.join(self.output_folder, f"{name}.csv")

        parsed_rows = []
        all_keys = set()

        for t, data in buf:
            try:
                parsed = json.loads(data)
                if isinstance(parsed, dict):
                    parsed["recording_time"] = t  # add ROS timestamp
                    parsed_rows.append(parsed)
                    all_keys.update(parsed.keys())
                else:
                    parsed_rows.append({"recording_time": t, "data": data})
                    all_keys.update(["recording_time", "data"])
            except json.JSONDecodeError:
                parsed_rows.append({"recording_time": t, "data": data})
                all_keys.update(["recording_time", "data"])

        # Write CSV with all collected columns
        with open(csv_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=sorted(all_keys))
            writer.writeheader()
            writer.writerows(parsed_rows)

        self.get_logger().info(f"[RECORDER NODE] Saved expanded CSV: {csv_path}")

    def handle_shutdown(self, sig, frame):
        self.get_logger().info("Saving buffered data...")
        self.get_logger().info(f"[RECORDER NODE] Topics recorded: {list(self.buffers.keys())}")

        for name, buf in self.buffers.items():
            self.get_logger().info(f"  - {name}: {len(buf)} messages")

            if len(buf) > 0:
                self.get_logger().info(f"[RECORDER NODE]   First timestamp: {buf[0][0]:.3f}")
                self.get_logger().info(f"[RECORDER NODE]   Last timestamp:  {buf[-1][0]:.3f}")
                self.get_logger().info(f"[RECORDER NODE]   Duration:        {buf[-1][0] - buf[0][0]:.3f} s")

            # Save PKL (raw)
            pkl_path = os.path.join(self.output_folder, f"{name}.pkl")
            with open(pkl_path, "wb") as f:
                pickle.dump(buf, f)
            self.get_logger().info(f"[RECORDER NODE] Saved PKL: {pkl_path}")

            # Save as expanded CSV
            self._save_as_csv(name, buf)
        
        self.get_logger().info(f"All data saved in {self.output_folder}")
        sys.exit(0)

def main(args=None):
    rclpy.init(args=args)
    node = RecorderNode()
    
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()