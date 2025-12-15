#!/usr/bin/env python3
import rclpy
from rclpy.node import Node
from std_msgs.msg import String
from pynput import keyboard
import time


class EventPublisher(Node):
    def __init__(self):
        super().__init__("event_publisher")
        self.pub = self.create_publisher(String, "/sync_event", 10)
        self.get_logger().info("Press SPACEBAR to send sync event.")

        self.last_press_time = 0.0

        # Start keyboard listener
        self.listener = keyboard.Listener(on_press=self.on_press)
        self.listener.start()

    def on_press(self, key):
        try:
            if key == keyboard.Key.space:
                current_time = time.time()

                # Debounce: 0.3 seconds
                if current_time - self.last_press_time > 0.3:
                    msg = String()
                    msg.data = f"[Publisher] event_spacebar_{current_time}"
                    self.pub.publish(msg)

                    self.get_logger().info(
                        f"[Publisher] Event sent at {current_time}"
                    )

                    self.last_press_time = current_time

        except Exception as e:
            self.get_logger().error(f"Error: {e}")

    def destroy_node(self):
        # Ensure keyboard listener stops cleanly
        self.listener.stop()
        super().destroy_node()


def main(args=None):
    rclpy.init(args=args)
    node = EventPublisher()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
