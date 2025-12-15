#!/home/acatalano/miniforge3/envs/NeonEnv/bin/python3

import socket
import json
import rclpy
from rclpy.node import Node
from std_msgs.msg import String


UDP_IP = "127.0.0.1"
UDP_PORT = 5005


class NeonNode(Node):
   def __init__(self):
       # Initialize ROS2 node and publisher
       super().__init__('neon_node')
       self.pub = self.create_publisher(String, '/eye_data', 2000)
      
       # Create and bind UDP socket
       self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
       self.sock.bind((UDP_IP, UDP_PORT))
       #self.sock.settimeout(0.5)
      
       self.get_logger().info(f"[NEON NODE] Neon Node started - listening on {UDP_IP}:{UDP_PORT}")
       self.get_logger().info("Publishing to /eye_data topic")
      
   def run(self):
       #rate = rospy.Rate(200)  # 200 Hz
      
       while rclpy.ok():
           try:
               raw_data, addr = self.sock.recvfrom(2048)
               gaze = json.loads(raw_data.decode('utf-8'))

               msg = String()
               msg.data = raw_data.decode('utf-8')
               self.pub.publish(msg)
               #print("[NEON NODE] Received gaze data:", json.dumps(gaze, indent=2))
              
           except socket.timeout:
               continue
           except Exception as e:
               self.get_logger().warn(f"Failed to receive or publish data: {e}")
  
   def shutdown(self):
       self.sock.close()
       self.get_logger().info("Neon Node stopped")
def main(args = None):
    rclpy.init(args=args)
    node = NeonNode()

    try:
        node.run()
    except KeyboardInterrupt:
        pass
    finally:
        node.shutdown()
        node.destroy_node()
        rclpy.shutdown()

if __name__ == "__main__":
    main()

