import nidaqmx
from nidaqmx.stream_readers import AnalogMultiChannelReader
from nidaqmx.constants import AcquisitionType, TerminalConfiguration
import numpy as np
import matplotlib.pyplot as plt
from scipy.signal import butter, filtfilt
from scipy.fft import fft, fftfreq
from scipy.io import savemat
import time

# === CONFIG ===
DEVICE = "cDAQ1Mod1"
CHANNELS = ["ai1", "ai2", "ai3", "ai6", "ai7", "ai9"]
SAMPLE_RATE = 10000
SAMPLES_PER_READ = 1000  # callback chunk size
SAVE_DIR = "./"

# --- bandpass filter helper ---
def bandpass_filter(data, lowcut, highcut, fs, order=4):
    b, a = butter(order, [lowcut/(fs/2), highcut/(fs/2)], btype='band')
    return filtfilt(b, a, data)

# --- positive FFT helper ---
def positive_fft(data, fs):
    n = len(data)
    freqs = fftfreq(n, 1/fs)
    fft_vals = fft(data)
    idx = np.where(freqs >= 0)
    return fft_vals[idx], freqs[idx]

def main():
    while True:
        input("Press Enter to START recording...")
        print("Recording... (Press Ctrl+C to stop)")

        # Create task
        with nidaqmx.Task() as task:
            # Add all AI channels
            for ch in CHANNELS:
                task.ai_channels.add_ai_voltage_chan(
                    f"{DEVICE}/{ch}",
                    terminal_config=TerminalConfiguration.RSE  # SingleEnded in MATLAB
                )

            task.timing.cfg_samp_clk_timing(
                rate=SAMPLE_RATE,
                sample_mode=AcquisitionType.CONTINUOUS
            )

            reader = AnalogMultiChannelReader(task.in_stream)

            data = []
            timestamps = []
            start_time = time.time()

            try:
                while True:
                    buffer = np.zeros((len(CHANNELS), SAMPLES_PER_READ))
                    reader.read_many_sample(buffer, number_of_samples_per_channel=SAMPLES_PER_READ)
                    data.append(buffer.T)
                    timestamps.append(
                        np.linspace(
                            len(data) * SAMPLES_PER_READ / SAMPLE_RATE - SAMPLES_PER_READ / SAMPLE_RATE,
                            len(data) * SAMPLES_PER_READ / SAMPLE_RATE,
                            SAMPLES_PER_READ,
                        )
                    )
            except KeyboardInterrupt:
                print("\nRecording stopped.")
            
            # Combine chunks
            data = np.vstack(data)
            timestamps = np.concatenate(timestamps)

        filename = input("Enter filename to save (without extension): ").strip()
        if not filename:
            filename = f"session_{int(time.time())}"
        filepath = f"{SAVE_DIR}/{filename}.mat"

        savemat(filepath, {"data": data, "timestamps": timestamps})
        print(f"Recording saved to {filepath}")

        # === PROCESS ===
        print("Processing data...")

        x1, y1, z1, x2, y2, z2 = data.T
        sum1 = x1 + y1 + z1
        sum2 = x2 + y2 + z2

        Fs = SAMPLE_RATE
        FilteredData1 = bandpass_filter(sum1, 20, 1000, Fs)
        FilteredData2 = bandpass_filter(sum2, 20, 1000, Fs)
        Sum1fft, freq1 = positive_fft(sum1, Fs)
        Sum2fft, freq2 = positive_fft(sum2, Fs)
        t = np.arange(len(data)) / Fs

        # === PLOT ===
        plt.figure(1)
        plt.plot(t, data)
        plt.title("Raw data")
        plt.xlabel("Time (s)")
        plt.ylabel("Voltage (V)")
        plt.legend(CHANNELS)

        plt.figure(2, figsize=(10, 12))
        plt.subplot(6, 1, 1)
        plt.plot(t, sum1)
        plt.title("Sum data (upper connector)")

        plt.subplot(6, 1, 2)
        plt.plot(t, FilteredData1)
        plt.title("Filtered X1+Y1+Z1")

        plt.subplot(6, 1, 3)
        plt.plot(freq1, np.abs(Sum1fft))
        plt.xlim([0.1, 1000])
        plt.title("FFT of X1,Y1,Z1")

        plt.subplot(6, 1, 4)
        plt.plot(t, sum2)
        plt.title("Sum data (lower connector)")

        plt.subplot(6, 1, 5)
        plt.plot(t, FilteredData2)
        plt.title("Filtered X2+Y2+Z2")

        plt.subplot(6, 1, 6)
        plt.plot(freq2, np.abs(Sum2fft))
        plt.xlim([0.1, 1000])
        plt.title("FFT of X2,Y2,Z2")

        plt.tight_layout()
        plt.show()

        again = input("Do you want to record again? (y/n): ").lower().strip()
        if again != "y":
            break

if __name__ == "__main__":
    main()
