#!/bin/bash

# Shimmer Resting State Recording Script (ROS2)

echo "====================================="
echo "  Shimmer Resting State Recording"
echo "====================================="
echo ""
read -p "Enter Subject ID (e.g., S001): " subject_id

if [ -z "$subject_id" ]; then
    echo "Error: Subject ID cannot be empty!"
    exit 1
fi

echo ""
echo "Subject ID: $subject_id"
echo "Duration: 180 seconds (3 minutes)"
echo ""
echo "The shimmer will publish data for 3 minutes."
echo "All data will be saved at the end."
echo ""
read -p "Press ENTER to start..."

# Launch ROS2 with the subject ID
ros2 launch multi_recording shimmerRest_launch.py subject_id:=$subject_id