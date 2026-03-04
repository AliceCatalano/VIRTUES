import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from scipy import stats
import warnings
warnings.filterwarnings('ignore')

class SensorSyncAnalyzer:
    def __init__(self, shimmer_csv, neon_csv):
        """
        Initialize analyzer with CSV file paths
        """
        self.shimmer_df = pd.read_csv(shimmer_csv)
        self.neon_df = pd.read_csv(neon_csv)
        
        print("="*60)
        print("DATA LOADED SUCCESSFULLY")
        print("="*60)
        print(f"Shimmer samples: {len(self.shimmer_df)}")
        print(f"Neon samples: {len(self.neon_df)}")
        
    def analyze_sampling_rates(self):
        """
        Analyze sampling rate stability for both sensors
        """
        print("\n" + "="*60)
        print("SAMPLING RATE ANALYSIS")
        print("="*60)
        
        # Shimmer analysis
        shimmer_intervals = np.diff(self.shimmer_df['pc_timestamp'])
        shimmer_rate = 1 / shimmer_intervals
        
        print("\nSHIMMER:")
        print(f"  Mean sampling rate: {shimmer_rate.mean():.2f} Hz")
        print(f"  Std sampling rate: {shimmer_rate.std():.2f} Hz")
        print(f"  Min sampling rate: {shimmer_rate.min():.2f} Hz")
        print(f"  Max sampling rate: {shimmer_rate.max():.2f} Hz")
        print(f"  Coefficient of variation: {(shimmer_rate.std()/shimmer_rate.mean())*100:.2f}%")
        
        # Neon analysis
        neon_intervals = np.diff(self.neon_df['pc_timestamp'])
        neon_rate = 1 / neon_intervals
        
        print("\nNEON:")
        print(f"  Mean sampling rate: {neon_rate.mean():.2f} Hz")
        print(f"  Std sampling rate: {neon_rate.std():.2f} Hz")
        print(f"  Min sampling rate: {neon_rate.min():.2f} Hz")
        print(f"  Max sampling rate: {neon_rate.max():.2f} Hz")
        print(f"  Coefficient of variation: {(neon_rate.std()/neon_rate.mean())*100:.2f}%")
        
        # Plot sampling rate over time
        fig, axes = plt.subplots(2, 1, figsize=(12, 8))
        
        axes[0].plot(shimmer_rate, alpha=0.7)
        axes[0].axhline(y=shimmer_rate.mean(), color='r', linestyle='--', label='Mean')
        axes[0].set_title('Shimmer Sampling Rate Over Time')
        axes[0].set_ylabel('Sampling Rate (Hz)')
        axes[0].set_xlabel('Sample Index')
        axes[0].legend()
        axes[0].grid(True, alpha=0.3)
        
        axes[1].plot(neon_rate, alpha=0.7)
        axes[1].axhline(y=neon_rate.mean(), color='r', linestyle='--', label='Mean')
        axes[1].set_title('Neon Sampling Rate Over Time')
        axes[1].set_ylabel('Sampling Rate (Hz)')
        axes[1].set_xlabel('Sample Index')
        axes[1].legend()
        axes[1].grid(True, alpha=0.3)
        
        plt.tight_layout()
        plt.savefig('sampling_rate_analysis.png', dpi=300)
        print("\nSampling rate plot saved as 'sampling_rate_analysis.png'")
        
        return shimmer_rate, neon_rate
    
    def analyze_timestamp_overflow(self):
        """
        Detect and analyze timestamp overflow in Shimmer data
        """
        print("\n" + "="*60)
        print("SHIMMER TIMESTAMP OVERFLOW ANALYSIS")
        print("="*60)
        
        raw_timestamps = self.shimmer_df['timestamp'].values
        diffs = np.diff(raw_timestamps)
        
        # Detect overflows (negative jumps)
        overflow_indices = np.where(diffs < 0)[0]
        
        print(f"\nNumber of overflows detected: {len(overflow_indices)}")
        
        if len(overflow_indices) > 0:
            print("\nOverflow locations:")
            for idx in overflow_indices:
                print(f"  Sample {idx}: {raw_timestamps[idx]} -> {raw_timestamps[idx+1]}")
        
        # Check if corrected timestamp exists
        if 'timestamp_corrected' in self.shimmer_df.columns:
            corrected = self.shimmer_df['timestamp_corrected'].values
            corrected_diffs = np.diff(corrected)
            
            print(f"\nCorrected timestamp statistics:")
            print(f"  Mean diff: {corrected_diffs.mean():.2f}")
            print(f"  Std diff: {corrected_diffs.std():.2f}")
            print(f"  Min diff: {corrected_diffs.min():.2f}")
            print(f"  Max diff: {corrected_diffs.max():.2f}")
            
            # Check for any negative diffs in corrected (should be none)
            neg_corrected = np.where(corrected_diffs < 0)[0]
            if len(neg_corrected) > 0:
                print(f"\nWARNING: {len(neg_corrected)} negative diffs in corrected timestamp!")
            else:
                print("\nCorrected timestamps are monotonically increasing ✓")
        
        return overflow_indices
    
    def analyze_event_synchronization(self):
        """
        Analyze synchronization based on spacebar events
        """
        print("\n" + "="*60)
        print("EVENT SYNCHRONIZATION ANALYSIS")
        print("="*60)
        
        # Find events in both datasets
        shimmer_events = self.shimmer_df[self.shimmer_df['event'] == 1]
        neon_events = self.neon_df[self.neon_df['event'] == 1]
        
        print(f"\nNumber of events detected:")
        print(f"  Shimmer: {len(shimmer_events)}")
        print(f"  Neon: {len(neon_events)}")
        
        if len(shimmer_events) == 0 or len(neon_events) == 0:
            print("\nWARNING: No events detected in one or both datasets!")
            print("Cannot perform synchronization analysis without events.")
            return None
        
        # Get event timestamps
        shimmer_event_times = shimmer_events['pc_timestamp'].values
        neon_event_times = neon_events['pc_timestamp'].values
        
        # Calculate time differences between paired events
        min_events = min(len(shimmer_event_times), len(neon_event_times))
        
        if min_events > 0:
            time_diffs = shimmer_event_times[:min_events] - neon_event_times[:min_events]
            
            print(f"\nEvent timing differences (Shimmer - Neon):")
            print(f"  Mean difference: {time_diffs.mean()*1000:.2f} ms")
            print(f"  Std difference: {time_diffs.std()*1000:.2f} ms")
            print(f"  Min difference: {time_diffs.min()*1000:.2f} ms")
            print(f"  Max difference: {time_diffs.max()*1000:.2f} ms")
            
            # Plot event alignment
            fig, axes = plt.subplots(2, 1, figsize=(12, 8))
            
            axes[0].scatter(range(min_events), time_diffs*1000, alpha=0.7)
            axes[0].axhline(y=0, color='r', linestyle='--')
            axes[0].set_title('Event Timing Differences (Shimmer - Neon)')
            axes[0].set_ylabel('Time Difference (ms)')
            axes[0].set_xlabel('Event Number')
            axes[0].grid(True, alpha=0.3)
            
            # Histogram of time differences
            axes[1].hist(time_diffs*1000, bins=30, alpha=0.7, edgecolor='black')
            axes[1].axvline(x=time_diffs.mean()*1000, color='r', linestyle='--', label='Mean')
            axes[1].set_title('Distribution of Event Timing Differences')
            axes[1].set_xlabel('Time Difference (ms)')
            axes[1].set_ylabel('Count')
            axes[1].legend()
            axes[1].grid(True, alpha=0.3)
            
            plt.tight_layout()
            plt.savefig('event_synchronization.png', dpi=300)
            print("\nEvent synchronization plot saved as 'event_synchronization.png'")
            
            return time_diffs
        
        return None
    
    def analyze_latency(self):
        """
        Estimate system latencies
        """
        print("\n" + "="*60)
        print("LATENCY ANALYSIS")
        print("="*60)
        
        # Recording start times
        shimmer_start = self.shimmer_df['pc_timestamp'].iloc[0]
        neon_start = self.neon_df['pc_timestamp'].iloc[0]
        
        start_diff = abs(shimmer_start - neon_start)
        
        print(f"\nRecording start time difference: {start_diff*1000:.2f} ms")
        print(f"  Shimmer started at: {shimmer_start}")
        print(f"  Neon started at: {neon_start}")
        
        if shimmer_start < neon_start:
            print(f"  Shimmer started {start_diff*1000:.2f} ms earlier")
        else:
            print(f"  Neon started {start_diff*1000:.2f} ms earlier")
    
    def detect_anomalies(self):
        """
        Detect potential bugs and anomalies
        """
        print("\n" + "="*60)
        print("ANOMALY DETECTION")
        print("="*60)
        
        issues = []
        
        # Check for missing data
        shimmer_missing = self.shimmer_df.isnull().sum()
        neon_missing = self.neon_df.isnull().sum()
        
        if shimmer_missing.any():
            print("\nWARNING: Missing data in Shimmer:")
            print(shimmer_missing[shimmer_missing > 0])
            issues.append("Shimmer has missing data")
        
        if neon_missing.any():
            print("\nWARNING: Missing data in Neon:")
            print(neon_missing[neon_missing > 0])
            issues.append("Neon has missing data")
        
        # Check for duplicate timestamps
        shimmer_dupes = self.shimmer_df['pc_timestamp'].duplicated().sum()
        neon_dupes = self.neon_df['pc_timestamp'].duplicated().sum()
        
        if shimmer_dupes > 0:
            print(f"\nWARNING: {shimmer_dupes} duplicate timestamps in Shimmer")
            issues.append(f"Shimmer has {shimmer_dupes} duplicate timestamps")
        
        if neon_dupes > 0:
            print(f"\nWARNING: {neon_dupes} duplicate timestamps in Neon")
            issues.append(f"Neon has {neon_dupes} duplicate timestamps")
        
        # Check for unrealistic GSR values (shimmer)
        if 'GSR_ohm' in self.shimmer_df.columns:
            gsr_outliers = ((self.shimmer_df['GSR_ohm'] < 1) | 
                           (self.shimmer_df['GSR_ohm'] > 5000)).sum()
            if gsr_outliers > 0:
                print(f"\nWARNING: {gsr_outliers} unrealistic GSR values detected")
                issues.append(f"{gsr_outliers} unrealistic GSR values")
        
        if len(issues) == 0:
            print("\nNo major anomalies detected ✓")
        
        return issues
    
    def generate_full_report(self):
        """
        Generate complete analysis report
        """
        print("\n" + "="*60)
        print("GENERATING FULL SYNCHRONIZATION REPORT")
        print("="*60)
        
        shimmer_rate, neon_rate = self.analyze_sampling_rates()
        overflow_indices = self.analyze_timestamp_overflow()
        time_diffs = self.analyze_event_synchronization()
        self.analyze_latency()
        issues = self.detect_anomalies()
        
        # Summary
        print("\n" + "="*60)
        print("SUMMARY")
        print("="*60)
        
        print(f"\n1. Sampling Rates:")
        print(f"   - Shimmer: {shimmer_rate.mean():.2f} Hz (CV: {(shimmer_rate.std()/shimmer_rate.mean())*100:.2f}%)")
        print(f"   - Neon: {neon_rate.mean():.2f} Hz (CV: {(neon_rate.std()/neon_rate.mean())*100:.2f}%)")
        
        print(f"\n2. Timestamp Overflows:")
        print(f"   - Detected: {len(overflow_indices)}")
        
        if time_diffs is not None:
            print(f"\n3. Event Synchronization:")
            print(f"   - Mean latency: {time_diffs.mean()*1000:.2f} ms")
            print(f"   - Jitter (std): {time_diffs.std()*1000:.2f} ms")
        
        print(f"\n4. Issues Detected: {len(issues)}")
        for issue in issues:
            print(f"   - {issue}")
        
        print("\n" + "="*60)
        self.plot_gsr_with_events()
        self.plot_gaze_distribution()

    
    def plot_gsr_with_events(self, output_file="gsr_with_events.png"):
        """
        Plot Shimmer GSR values with vertical dotted red lines at event timestamps
        """
        if "GSR_ohm" not in self.shimmer_df.columns:
            print("\nERROR: 'GSR_ohm' column not found in Shimmer data.")
            return
        
        print("\n" + "="*60)
        print("PLOTTING GSR WITH EVENTS")
        print("="*60)

        fig, ax = plt.subplots(figsize=(14, 6))
        
        # Plot GSR
        ax.plot(self.shimmer_df["pc_timestamp"], self.shimmer_df["GSR_ohm"],
                label="GSR (ohm)", color="blue", alpha=0.8)

        # Plot vertical lines where event == 1
        event_times = self.shimmer_df.loc[self.shimmer_df["event"] == 1, "pc_timestamp"].values
        for t in event_times:
            ax.axvline(x=t, color="red", linestyle=":", linewidth=1.5, alpha=0.7)

        ax.set_title("Shimmer GSR with Events")
        ax.set_xlabel("PC Timestamp (s)")
        ax.set_ylabel("GSR (ohm)")
        ax.legend()
        ax.grid(True, alpha=0.3)

        plt.tight_layout()
        plt.savefig(output_file, dpi=300)
        print(f"\nGSR plot saved as '{output_file}'")

    def plot_gaze_distribution(self, output_file="gaze_distribution.png"):
        """
        Plot gaze x-y distribution from Neon recordings
        """
        if not {"x", "y"}.issubset(self.neon_df.columns):
            print("\nERROR: Neon data must contain 'x' and 'y' columns for gaze coordinates.")
            return

        print("\n" + "="*60)
        print("PLOTTING GAZE DISTRIBUTION")
        print("="*60)

        fig, ax = plt.subplots(figsize=(8, 8))
        ax.scatter(self.neon_df["x"], self.neon_df["y"], s=5, alpha=0.5)

        ax.set_title("Gaze X-Y Distribution")
        ax.set_xlabel("X coordinate (px)")
        ax.set_ylabel("Y coordinate (px)")
        ax.invert_yaxis()  # Often needed for screen coordinates
        ax.grid(True, alpha=0.3)

        plt.tight_layout()
        plt.savefig(output_file, dpi=300)
        print(f"\nGaze distribution plot saved as '{output_file}'")



# Usage example
if __name__ == "__main__":
    # Replace with your actual file paths
    shimmer_file = "/home/acatalano/VIRTUES/test_session/session_2026-01-09_14-34-16/gsr.csv"
    neon_file = "/home/acatalano/VIRTUES/test_session/session_2026-01-09_14-34-16/eye.csv"
    
    analyzer = SensorSyncAnalyzer(shimmer_file, neon_file)
    analyzer.generate_full_report()
    
    plt.show()