#!/home/acatalano/miniforge3/envs/NeonEnv/bin/python3

import socket
import json
import threading
from datetime import datetime, timezone
from pupil_labs.realtime_api.simple import discover_one_device
from pupil_labs.realtime_api.streaming.eye_events import (
    BlinkEventData,
    FixationEventData,
)


UDP_IP = "127.0.0.1"
UDP_PORT = 5005


def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    # Shared dictionary to store the latest eye events
    latest_events = {
        'blink': 0,
        'fixation': 0,
        'saccade': 0
    }
    events_lock = threading.Lock()
    
    def eye_events_thread(device):
        """Thread to continuously receive eye events"""
        nonlocal latest_events
        try:
            while True:
                eye_event = device.receive_eye_events()
                
                with events_lock:
                    # Reset all events
                    latest_events['blink'] = 0
                    latest_events['fixation'] = 0
                    latest_events['saccade'] = 0
                    
                    # Set the current event
                    if isinstance(eye_event, BlinkEventData):
                        latest_events['blink'] = 1
                        #print(f"[BLINK] detected")
                    
                    elif isinstance(eye_event, FixationEventData):
                        if eye_event.event_type == 0:  # Saccade
                            latest_events['saccade'] = 1
                            angle = eye_event.amplitude_angle_deg
                            #print(f"[SACCADE] {angle:.0f}° amplitude")
                        elif eye_event.event_type == 1:  # Fixation
                            latest_events['fixation'] = 1
                            duration = (eye_event.end_time_ns - eye_event.start_time_ns) / 1e9
                            #print(f"[FIXATION] {duration:.2f}s duration")
        except Exception as e:
            print(f"Eye events thread error: {e}")
    
    print("Looking for the Neon...")
    device = discover_one_device(max_search_duration_seconds=10.0)
    if device is None:
        print("No device found.")
        raise SystemExit(-1)
    
    # Start the eye events thread
    events_thread = threading.Thread(target=eye_events_thread, args=(device,), daemon=True)
    events_thread.start()
    
    print(f"Publishing started to {UDP_IP}:{UDP_PORT}...")
    try:
        while True:
            gaze_data = device.receive_gaze_datum()
            
            # Get current event states
            with events_lock:
                blink = latest_events['blink']
                fixation = latest_events['fixation']
                saccade = latest_events['saccade']
            
            # Prepare message with all data
            msg_data = {
                'x': gaze_data.x,
                'y': gaze_data.y,
                'pupil_diameter_left': gaze_data.pupil_diameter_left,
                'pupil_diameter_right': gaze_data.pupil_diameter_right,
                'pc_timestamp': gaze_data.timestamp_unix_seconds,
                'timestamp_unix_seconds': gaze_data.timestamp_unix_seconds,
                'blink': blink,
                'fixation': fixation,
                'saccade': saccade
            }
            
            msg = json.dumps(msg_data).encode('utf-8')
            sock.sendto(msg, (UDP_IP, UDP_PORT))
            
    except KeyboardInterrupt:
        pass
    finally:
        device.close()
        sock.close()
        print("Stopped.")


if __name__ == "__main__":
    main()