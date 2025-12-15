#!/home/acatalano/miniforge3/envs/NeonEnv/bin/python3

import rclpy
from rclpy.node import Node
from std_msgs.msg import String
import struct
import serial
import math
import time
import threading
import json
import subprocess
import os


class ShimmerNode(Node):
    def __init__(self):
        super().__init__('shimmer_node')
        
        # Publisher for GSR data
        self.pub = self.create_publisher(String, '/gsr_data', 2000)
    
        self.event_lock = threading.Lock()
        
        # Serial connection
        self.serial = None
        
        self.get_logger().info("Connecting to Shimmer...")
        
        # Initialize Shimmer with rfcomm connection
        self.initialize_shimmer()
    
    
    def _wait_for_ack(self, timeout=2.0):
        """Wait for acknowledgment from Shimmer with timeout"""
        ddata = b""
        ack = struct.pack('B', 0xff)
        start_time = time.time()
        
        while ddata != ack:
            if time.time() - start_time > timeout:
                self.get_logger().error("Timeout waiting for ACK")
                return False
            
            if self.serial.in_waiting > 0:
                ddata = self.serial.read(1)
            else:
                time.sleep(0.01)  # Small delay to avoid busy-waiting
        
        return True
    
    def connect_rfcomm(self, mac="D1:81:23:02:83:E7", channel="2", dev="/dev/rfcomm1",
                       wait_secs=5, release_idx=0):
        """Start rfcomm connect and wait until /dev/rfcomm1 exists and is openable.
           Returns True on success, False on failure.
        """
        # Try to release a stale binding (may print "No such device" — that's OK)
        try:
            subprocess.call(["sudo", "rfcomm", "release", str(release_idx)])
        except Exception as e:
            self.get_logger().warn(f"rfcomm release warning: {e}")

        # Launch rfcomm connect in background
        try:
            p = subprocess.Popen(["sudo", "rfcomm", "connect", dev, mac, channel],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except FileNotFoundError:
            self.get_logger().error("rfcomm not found. Install bluez-utils / bluez. Aborting rfcomm connect.")
            return False
        except Exception as e:
            self.get_logger().error(f"Failed to start rfcomm: {e}")
            return False

        # Wait for device file to appear AND be openable
        t0 = time.time()
        while time.time() - t0 < wait_secs:
            if os.path.exists(dev):
                # quick test: try to open the serial port
                try:
                    ser = serial.Serial(dev, 115200, timeout=1)
                    ser.close()
                    self.get_logger().info(f"{dev} present and openable.")
                    return True
                except serial.SerialException as e:
                    # Device exists but not ready yet; keep waiting
                    self.get_logger().info(f"{dev} exists but not openable yet: {e}")
            time.sleep(0.5)

        # timed out: try to fetch rfcomm process stderr to diagnose
        try:
            out, err = p.communicate(timeout=0.1)
            if err:
                self.get_logger().warn(f"rfcomm stderr: {err[:200]}")
        except Exception:
            pass

        self.get_logger().error(f"{dev} did not appear / become openable within {wait_secs}s.")
        return False
    
    def initialize_shimmer(self):
        """Setup serial connection and configure Shimmer"""
        self.get_logger().info("initialiaze function")
        
        
        if not self.connect_rfcomm():
            self.get_logger().warn(f"failed attempt node will keep trying")

        while not rclpy.shutdown():
            if self.connect_rfcomm():
                break
            time.sleep(2.5)
        
        for attempt in range(6):
            try:
                self.serial = serial.Serial("/dev/rfcomm1", 115200, timeout=2)
                self.get_logger().info("Port opened")
                time.sleep(0.5)  # ADD THIS: Let port stabilize
                break
            except serial.SerialException:
                self.get_logger().info(f"Waiting for /dev/rfcomm1 (attempt {attempt+1})...")
                time.sleep(1)
        else:
            self.get_logger().error("/dev/rfcomm1 failed to connect")
            return

         # Flush any stale data
        self.serial.reset_input_buffer()
        self.serial.reset_output_buffer()
        time.sleep(0.2)    

        # Configuration commands
        # Configuration commands
        self.serial.write(struct.pack('BBBB', 0x08, 0x84, 0x01, 0x00))  # Set sensors
        if not self._wait_for_ack(timeout=2.0):  # Remove self.serial
            self.get_logger().error("Failed to get ACK for set sensors")
            return
        time.sleep(0.2) 
            
        self.serial.write(struct.pack('BB', 0x5E, 0x01))  # Enable internal expansion board power
        if not self._wait_for_ack(timeout=2.0):  # Remove self.serial
            self.get_logger().error("Failed to get ACK for expansion board")
            return
        time.sleep(0.2)
            
        sampling_freq = 10
        clock_wait = math.ceil((2 << 14) / sampling_freq)
        self.serial.write(struct.pack('<BH', 0x05, clock_wait))
        if not self._wait_for_ack(timeout=2.0):  # Remove self.serial
            self.get_logger().error("Failed to get ACK for sampling rate")
            return
        time.sleep(0.2)
            
        # Start streaming
        self.serial.write(struct.pack('B', 0x07))
        if not self._wait_for_ack(timeout=2.0):  # Remove self.serial
            self.get_logger().error("Failed to get ACK for start streaming")
            return
        time.sleep(0.5)
            
        self.get_logger().info("Streaming started")
            
       
    
    def run(self):
        """Main reading loop"""
        self.get_logger().info("run function")
        framesize = 14
        ddata = b""
        MAX_TIMESTAMP = 16777215
        overflow_count = 0
        last_timestamp = 0
        
        try:
            while rclpy.ok():
                # Read data frame
                while len(ddata) < framesize:
                    ddata += self.serial.read(framesize)
                
                pc_time = time.time()
                data = ddata[0:framesize]
                ddata = ddata[framesize:]
                
                # Unpack data
                (packettype,) = struct.unpack('B', data[0:1])
                (timestamp0, timestamp1, timestamp2) = struct.unpack('BBB', data[1:4])
                (x, y, z, PPG_raw, GSR_raw) = struct.unpack('HHHHH', data[4:framesize])
                
                # Handle timestamp overflow
                timestamp = timestamp0 + timestamp1 * 256 + timestamp2 * 65536
                if timestamp < last_timestamp:
                    overflow_count += 1
                last_timestamp = timestamp
                timestamp_corrected = timestamp + (overflow_count * (MAX_TIMESTAMP + 1))
                
                # Calculate GSR
                Range = ((GSR_raw >> 14) & 0xff)
                Rf_values = [40.2, 287.0, 1000.0, 3300.0]
                Rf = Rf_values[Range]
                gsr_to_volts = (GSR_raw & 0x3fff) * (3.0 / 4095.0)
                GSR_ohm = Rf / ((gsr_to_volts / 0.5) - 1.0)
                
                
                # Prepare message
                msg = {
                    "packettype": packettype,
                    "timestamp": timestamp_corrected,
                    "pc_time": pc_time,
                    "accel": [x, y, z],
                    "GSR_ohm": GSR_ohm
                }
                
                # Publish
                msg_str = String()
                msg_str.data = json.dumps(msg)
                self.pub.publish(msg_str)
                
        except Exception as e:
            self.get_logger().error(f"Error in run loop: {e}")
    
    def shutdown(self):
        """Clean shutdown"""
        if self.serial and self.serial.is_open:
            self.get_logger().info("Stopping Shimmer stream...")
            try:
                self.serial.write(struct.pack('B', 0x20))
                self._wait_for_ack()
                self.serial.close()
                self.get_logger().info("Shimmer disconnected cleanly.")
            except Exception as e:
                self.get_logger().error(f"Error during shutdown: {e}")


def main(args=None):
    rclpy.init(args=args)
    node = ShimmerNode()
    
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