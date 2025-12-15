#!/bin/bash

# Source ROS2
source /opt/ros/jazzy/setup.bash
source ~/acat_ws/install/setup.bash

# Activate conda environment (Python 3.12 to match ROS2)
source ~/miniforge3/etc/profile.d/conda.sh
conda activate NeonEnv

# Verify we're using the right Python
echo "Using Python: $(which python3)"
echo "Python version: $(python3 --version)"

# Launch your ROS2 system
ros2 launch multi_recording et_launcher.py