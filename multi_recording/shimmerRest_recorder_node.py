#!/usr/bin/env python3
import rclpy
from rclpy.node import Node
from std_msgs.msg import String
import json
import os
import csv
from datetime import datetime
import threading

class SimpleRestRecorder(Node):
    def __init__(self):
        super().__init__('rest_recorder')
        
        # Declare and get parameters
        self.declare_parameter('subject_id', 'unknown')
        self.declare_parameter('output_folder', os.path.expanduser('~/VIRTUES/resting_state'))
        self.declare_parameter('duration', 180)
        self.declare_parameter('topic', '/gsr_data')
        self.declare_parameter('sensor_name', 'shimmer')
        
        self.subject_id = self.get_parameter('subject_id').value
        self.output_folder = self.get_parameter('output_folder').value
        self.duration = self.get_parameter('duration').value
        self.topic = self.get_parameter('topic').value
        self.sensor_name = self.get_parameter('sensor_name').value
        
        os.makedirs(self.output_folder, exist_ok=True)
        
        # Data buffer with lock
        self.lock = threading.Lock()
        self.data_buffer = []
        
        self.get_logger().info("=" * 60)
        self.get_logger().info(f"[REST RECORDER] Subject ID: {self.subject_id}")
        self.get_logger().info(f"[REST RECORDER] Sensor: {self.sensor_name}")
        self.get_logger().info(f"[REST RECORDER] Duration: {self.duration} seconds")
        self.get_logger().info(f"[REST RECORDER] Topic: {self.topic}")
        self.get_logger().info("=" * 60)
        
        # Subscribe to topic
        self.subscription = self.create_subscription(String, self.topic, self.data_callback, 2000)  # QoS depth
        
        # Start timer to stop after duration
        self.timer = self.create_timer(self.duration, self.timer_callback)
        
        self.get_logger().info("[REST RECORDER] Recording started...")
    
    def data_callback(self, msg):
        with self.lock:
            try:
                data = json.loads(msg.data)
                data['ros_time'] = self.get_clock().now().nanoseconds / 1e9
                self.data_buffer.append(data)
            except Exception as e:
                self.get_logger().warn(f"[REST RECORDER] Error parsing data: {e}")
    
    def timer_callback(self):
        self.get_logger().info(f"[REST RECORDER] {self.duration} seconds elapsed. Stopping...")
        self.save_data()
        rclpy.shutdown()
    
    def save_data(self):
        self.get_logger().info("[REST RECORDER] Saving data...")
        
        with self.lock:
            if not self.data_buffer:
                self.get_logger().warn("[REST RECORDER] No data recorded!")
                return
            
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"{self.sensor_name}_rest_{self.subject_id}_{timestamp}.csv"
            filepath = os.path.join(self.output_folder, filename)
            
            try:
                # Get all unique keys
                all_keys = set()
                for record in self.data_buffer:
                    all_keys.update(record.keys())
                
                fieldnames = sorted(list(all_keys))
                
                with open(filepath, 'w', newline='') as csvfile:
                    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
                    writer.writeheader()
                    
                    for record in self.data_buffer:
                        row = {}
                        for key in fieldnames:
                            value = record.get(key, '')
                            if isinstance(value, (list, dict)):
                                row[key] = json.dumps(value)
                            else:
                                row[key] = value
                        writer.writerow(row)
                
                self.get_logger().info("=" * 60)
                self.get_logger().info(f"[REST RECORDER] Saved {len(self.data_buffer)} samples")
                self.get_logger().info(f"[REST RECORDER] File: {filepath}")
                self.get_logger().info("=" * 60)
                
            except Exception as e:
                self.get_logger().error(f"[REST RECORDER] Error saving file: {e}")

def main(args=None):
    rclpy.init(args=args)
    
    try:
        recorder = SimpleRestRecorder()
        rclpy.spin(recorder)
    except KeyboardInterrupt:
        pass
    finally:
        if rclpy.ok():
            recorder.save_data()
            recorder.destroy_node()
            rclpy.shutdown()

if __name__ == "__main__":
    main()