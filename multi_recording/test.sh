#!/bin/bash

# Shimmer Bluetooth Connection Fix for Ubuntu 24.04
# This addresses BlueZ 5.70+ connection issues

SHIMMER_MAC="00:06:66:D7:C9:C7"
RFCOMM_DEV="/dev/rfcomm0"

echo "======================================"
echo "  Shimmer Bluetooth Connection Fix"
echo "======================================"
echo ""

# Step 1: Kill any existing rfcomm processes
echo "[1/8] Cleaning up existing connections..."
sudo pkill -9 rfcomm 2>/dev/null
sudo rfcomm release 0 2>/dev/null
sudo rfcomm release all 2>/dev/null
sleep 1

# Step 2: Remove any existing rfcomm devices
echo "[2/8] Removing stale rfcomm devices..."
if [ -e "$RFCOMM_DEV" ]; then
    sudo rm -f "$RFCOMM_DEV"
fi
sleep 0.5

# Step 3: Restart Bluetooth service
echo "[3/8] Restarting Bluetooth service..."
sudo systemctl restart bluetooth
sleep 2

# Step 4: Unblock Bluetooth (in case it's soft/hard blocked)
echo "[4/8] Unblocking Bluetooth..."
sudo rfkill unblock bluetooth
sleep 1

# Step 5: Disconnect if already connected
echo "[5/8] Ensuring device is disconnected..."
bluetoothctl disconnect "$SHIMMER_MAC" 2>/dev/null
sleep 1

# Step 6: Remove and re-pair device
echo "[6/8] Removing old pairing..."
bluetoothctl remove "$SHIMMER_MAC" 2>/dev/null
sleep 1

echo "[7/8] Scanning and pairing..."
# Create expect script for automated pairing
expect << EOF
set timeout 20
spawn bluetoothctl
expect "#"
send "power on\r"
expect "#"
send "agent NoInputNoOutput\r"
expect "#"
send "default-agent\r"
expect "#"
send "scan on\r"
sleep 3
send "scan off\r"
expect "#"
send "pair $SHIMMER_MAC\r"
expect {
    "Pairing successful" {
        send "trust $SHIMMER_MAC\r"
        expect "#"
    }
    "already paired" {
        send "trust $SHIMMER_MAC\r"
        expect "#"
    }
    timeout {
        send "trust $SHIMMER_MAC\r"
        expect "#"
    }
}
send "connect $SHIMMER_MAC\r"
expect {
    "Connection successful" {
        puts "Connected successfully!"
    }
    timeout {
        puts "Connection timeout, but device may still work"
    }
}
sleep 2
send "exit\r"
expect eof
EOF

sleep 2

# Step 8: Verify connection
echo "[8/8] Verifying connection..."
if bluetoothctl info "$SHIMMER_MAC" | grep -q "Connected: yes"; then
    echo "✓ Device connected successfully!"
    echo ""
    echo "======================================"
    echo "  Ready to use Shimmer"
    echo "======================================"
    echo "Now run: ./shimmerRest.sh"
else
    echo "⚠ Device may not be fully connected"
    echo "   But rfcomm binding might still work"
    echo ""
    echo "Try running: ./shimmerRest.sh"
fi

echo ""
echo "Device info:"
bluetoothctl info "$SHIMMER_MAC" | grep -E "(Connected|Paired|Trusted)"