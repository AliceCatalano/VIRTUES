#!/bin/bash
source ~/VIRTUES/venv_converter/bin/activate
python3 ~/VIRTUES/rosbag2_to_mp4.py "$@"
deactivate
