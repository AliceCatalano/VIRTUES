#!/usr/bin/env python3

import pickle
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from scipy import stats
import json
import warnings
warnings.filterwarnings('ignore')

class PKLSensorAnalyzer:
    def __init__(self,  neon_pkl, shimmer_pkl=None):
        """
        Initialize analyzer with PKL file paths
        """
        # Load PKL files
        with open(shimmer_pkl, 'rb') as f:
            self.shimmer_data = pickle.load(f)
        self.shimmer_df = self._parse_shimmer_data(self.shimmer_data)
        with open(neon_pkl, 'rb') as f:
            self.neon_data = pickle.load(f)
            #print(f" neon pkl {self.neon_data}")
        self.neon_df = self._parse_neon_data(self.neon_data)
        
        print(f"="*60)
        print(f"PKL DATA LOADED SUCCESSFULLY")
        print(f"="*60)
        print(f"Shimmer samples: {len(self.shimmer_df)}")
        print(f"Neon samples: {len(self.neon_df)}")
        print(f"\nShimmer columns: {list(self.shimmer_df.columns)}")
        print(f"Neon columns: {list(self.neon_df.columns)}")
    
    #def _parse_shimmer_data(self, data):
        """
        Parse Shimmer PKL data into DataFrame.
        Handles several stored formats:
        - list of JSON strings
        - list of dicts
        - list of (ts, json_string) or (ts, dict)
        - list of ROS message objects (with .data attribute)
        """
        records = []

        if not isinstance(data, list):
            # unexpected top-level type
            return pd.DataFrame(records)

        for idx, item in enumerate(data):
            parsed = None

            # Case A: tuple/list with (timestamp, payload)
            if isinstance(item, (tuple, list)) and len(item) >= 2:
                payload = item[1]
                # If payload is bytes, decode
                if isinstance(payload, bytes):
                    try:
                        payload = payload.decode('utf-8')
                    except:
                        payload = payload
                if isinstance(payload, str):
                    try:
                        parsed = json.loads(payload)
                    except Exception:
                        # maybe it's already a plain string value
                        parsed = {"raw_data": payload}
                elif isinstance(payload, dict):
                    parsed = payload
                else:
                    # fallback: store repr
                    parsed = {"raw_repr": repr(payload)}
            # Case B: direct string (JSON)
            elif isinstance(item, str):
                try:
                    parsed = json.loads(item)
                except Exception:
                    parsed = {"raw_data": item}
            # Case C: direct dict
            elif isinstance(item, dict):
                parsed = item
            # Case D: ROS message object - try to access .data
            else:
                # many ROS String messages when pickled may be the message object
                if hasattr(item, 'data'):
                    payload = item.data
                    if isinstance(payload, (bytes, bytearray)):
                        try:
                            payload = payload.decode('utf-8')
                        except:
                            payload = payload
                    if isinstance(payload, str):
                        try:
                            parsed = json.loads(payload)
                        except:
                            parsed = {"raw_data": payload}
                    elif isinstance(payload, dict):
                        parsed = payload
                    else:
                        parsed = {"raw_repr": repr(payload)}
                else:
                    # Unknown: store representation so we don't silently drop data
                    parsed = {"raw_repr": repr(item)}

            # ensure parsed is a dict
            if isinstance(parsed, dict):
                records.append(parsed)
            else:
                # fallback: put into dict form
                records.append({"value": parsed})

        # Convert to DataFrame
        df = pd.DataFrame(records)

        # If 'accel' exists and is a list, split into components
        if 'accel' in df.columns and df['accel'].notna().any():
            try:
                # only attempt if the first non-null is list-like
                first_nonnull = df['accel'].dropna().iloc[0]
                if isinstance(first_nonnull, (list, tuple)):
                    df[['accel_x', 'accel_y', 'accel_z']] = pd.DataFrame(
                        df['accel'].tolist(), index=df.index
                    )
            except Exception:
                pass

        return df
    
    def _parse_neon_data(self, data):
        """
        Parse Neon PKL (list of ROS String, tuples, or raw JSON) into a DataFrame.
        """
        records = []
        if not isinstance(data, list):
            return pd.DataFrame()

        for item in data:
            payload = None

            # Case A: tuple or list (timestamp, payload)
            if isinstance(item, (tuple, list)) and len(item) >= 2:
                payload = item[1]
            elif hasattr(item, "data"):  # ROS String
                payload = item.data
            else:
                payload = item

            # Decode bytes if needed
            if isinstance(payload, (bytes, bytearray)):
                try:
                    payload = payload.decode("utf-8")
                except Exception:
                    pass

            # Parse JSON if string
            if isinstance(payload, str):
                try:
                    rec = json.loads(payload)
                    if isinstance(rec, dict):
                        records.append(rec)
                except Exception:
                    continue
            elif isinstance(payload, dict):
                records.append(payload)

        return pd.DataFrame(records)


    
    def analyze_data_loss(self):
        """
        Comprehensive data loss and stability analysis
        """
        print(f"\n" + "="*60)
        print(f"DATA LOSS & STABILITY ANALYSIS")
        print(f"="*60)
        
        # === SHIMMER ANALYSIS ===
        print(f"\n" + "-"*60)
        print(f"SHIMMER DATA LOSS ANALYSIS")
        print(f"-"*60)
        
        if 'pc_time' in self.shimmer_df.columns:
            shimmer_times = self.shimmer_df['pc_time'].values
        elif 'pc_timestamp' in self.shimmer_df.columns:
            shimmer_times = self.shimmer_df['pc_timestamp'].values
        else:
            print(f"ERROR: No timestamp column found in Shimmer data")
            return
        
        # Calculate expected vs actual samples
        shimmer_duration = shimmer_times[-1] - shimmer_times[0]
        shimmer_intervals = np.diff(shimmer_times)
        expected_rate = 128  # Hz (from your config)
        expected_samples = int(shimmer_duration * expected_rate)
        actual_samples = len(self.shimmer_df)
        
        print(f"\nDuration: {shimmer_duration:.2f} seconds")
        print(f"Expected samples (@ {expected_rate} Hz): {expected_samples}")
        print(f"Actual samples: {actual_samples}")
        print(f"Missing samples: {expected_samples - actual_samples}")
        print(f"Data loss: {((expected_samples - actual_samples) / expected_samples * 100):.3f}%")
        
        # Inter-sample interval analysis
        mean_interval = shimmer_intervals.mean()
        expected_interval = 1 / expected_rate
        
        print(f"\nInter-sample intervals:")
        print(f"  Expected: {expected_interval*1000:.3f} ms")
        print(f"  Mean: {mean_interval*1000:.3f} ms")
        print(f"  Std: {shimmer_intervals.std()*1000:.3f} ms")
        print(f"  Min: {shimmer_intervals.min()*1000:.3f} ms")
        print(f"  Max: {shimmer_intervals.max()*1000:.3f} ms")
        
        # Detect gaps (intervals > 2x expected)
        gap_threshold = expected_interval * 2
        gaps = shimmer_intervals > gap_threshold
        num_gaps = gaps.sum()
        
        print(f"\nGaps detected (> {gap_threshold*1000:.1f} ms): {num_gaps}")
        if num_gaps > 0:
            gap_indices = np.where(gaps)[0]
            print(f"  Total samples lost in gaps: {sum(shimmer_intervals[gaps] / expected_interval - 1):.0f}")
            print(f"  Largest gap: {shimmer_intervals[gaps].max()*1000:.2f} ms")
            print(f"  Gap locations (first 10): {gap_indices[:10].tolist()}")
        
        # === NEON ANALYSIS ===
        print(f"\n" + "-"*60)
        print(f"NEON DATA LOSS ANALYSIS")
        print(f"-"*60)
        
        if self.neon_df is not None:
            if 'timestamp' in self.neon_df.columns:
                neon_times = self.neon_df['timestamp'].values
            elif 'pc_timestamp' in self.neon_df.columns:
                neon_times = self.neon_df['pc_timestamp'].values
            else:
                print(f"ERROR: No timestamp column found in Neon data")
                return
            
            neon_duration = neon_times[-1] - neon_times[0]
            neon_intervals = np.diff(neon_times)
            neon_expected_rate = 200  # Typical Neon rate
            neon_expected_samples = int(neon_duration * neon_expected_rate)
            neon_actual_samples = len(self.neon_df)
            
            print(f"\nDuration: {neon_duration:.2f} seconds")
            print(f"Expected samples (@ ~{neon_expected_rate} Hz): {neon_expected_samples}")
            print(f"Actual samples: {neon_actual_samples}")
            print(f"Missing samples: {neon_expected_samples - neon_actual_samples}")
            print(f"Data loss: {((neon_expected_samples - neon_actual_samples) / neon_expected_samples * 100):.3f}%")
            
            neon_mean_interval = neon_intervals.mean()
            neon_expected_interval = 1 / neon_expected_rate
            
            print(f"\nInter-sample intervals:")
            print(f"  Expected: ~{neon_expected_interval*1000:.3f} ms")
            print(f"  Mean: {neon_mean_interval*1000:.3f} ms")
            print(f"  Std: {neon_intervals.std()*1000:.3f} ms")
            print(f"  Min: {neon_intervals.min()*1000:.3f} ms")
            print(f"  Max: {neon_intervals.max()*1000:.3f} ms")
            
            # Detect Neon gaps
            neon_gap_threshold = neon_expected_interval * 2
            neon_gaps = neon_intervals > neon_gap_threshold
            neon_num_gaps = neon_gaps.sum()
            
            print(f"\nGaps detected (> {neon_gap_threshold*1000:.1f} ms): {neon_num_gaps}")
            if neon_num_gaps > 0:
                neon_gap_indices = np.where(neon_gaps)[0]
                print(f"  Total samples lost in gaps: {sum(neon_intervals[neon_gaps] / neon_expected_interval - 1):.0f}")
                print(f"  Largest gap: {neon_intervals[neon_gaps].max()*1000:.2f} ms")
                print(f"  Gap locations (first 10): {neon_gap_indices[:10].tolist()}")
        
        # Plot data loss visualization
        self._plot_data_loss(shimmer_intervals, None, expected_interval, None)
        
        # Default values in case Neon data is missing
        neon_results = {}
        try:
            neon_results = {
                'data_loss_pct': ((neon_expected_samples - neon_actual_samples) / neon_expected_samples * 100),
                'num_gaps': neon_num_gaps,
                'mean_rate': 1 / neon_mean_interval
            }
        except Exception:
            neon_results = {
                'data_loss_pct': float('nan'),
                'num_gaps': 0,
                'mean_rate': float('nan')
            }


        return {
            'shimmer': {
                'data_loss_pct': ((expected_samples - actual_samples) / expected_samples * 100),
                'num_gaps': num_gaps,
                'mean_rate': 1 / mean_interval
            },
            'neon': neon_results
        }

    def _plot_data_loss(self, shimmer_intervals, neon_intervals, 
                       shimmer_expected, neon_expected):
        """
        Visualize data loss and timing stability
        """
        fig, axes = plt.subplots(3, 1, figsize=(12, 12))
        
        # Shimmer interval over time
        axes[0].plot(shimmer_intervals * 1000, alpha=0.7, linewidth=0.5)
        axes[0].axhline(y=shimmer_expected*1000, color='r', linestyle='--', 
                          label='Expected ({shimmer_expected*1000:.2f} ms)')
        axes[0].set_title('Shimmer: Inter-sample Interval Over Time')
        axes[0].set_ylabel('Interval (ms)')
        axes[0].set_xlabel('Sample Index')
        axes[0].legend()
        axes[0].grid(True, alpha=0.3)
        
        # # Neon interval over time
        if neon_intervals is not None:
            axes[0, 1].plot(neon_intervals * 1000, alpha=0.7, linewidth=0.5)
            axes[0, 1].axhline(y=neon_expected*1000, color='r', linestyle='--',
                              label='Expected (~{neon_expected*1000:.2f} ms)')
            axes[0, 1].set_title('Neon: Inter-sample Interval Over Time')
            axes[0, 1].set_ylabel('Interval (ms)')
            axes[0, 1].set_xlabel('Sample Index')
            axes[0, 1].legend()
            axes[0, 1].grid(True, alpha=0.3)
        
        # Shimmer interval histogram
        axes[1].hist(shimmer_intervals * 1000, bins=50, alpha=0.7, edgecolor='black')
        axes[1].axvline(x=shimmer_expected*1000, color='r', linestyle='--', label='Expected')
        axes[1].set_title('Shimmer: Interval Distribution')
        axes[1].set_xlabel('Interval (ms)')
        axes[1].set_ylabel('Count')
        axes[1].legend()
        axes[1].grid(True, alpha=0.3)
        
        # # Neon interval histogram
        if neon_intervals is not None:
            axes[1, 1].hist(neon_intervals * 1000, bins=50, alpha=0.7, edgecolor='black')
            axes[1, 1].axvline(x=neon_expected*1000, color='r', linestyle='--', label='Expected')
            axes[1, 1].set_title('Neon: Interval Distribution')
            axes[1, 1].set_xlabel('Interval (ms)')
            axes[1, 1].set_ylabel('Count')
            axes[1, 1].legend()
            axes[1, 1].grid(True, alpha=0.3)
        
        # Shimmer sampling rate over time
        shimmer_rate = 1 / shimmer_intervals
        axes[2].plot(shimmer_rate, alpha=0.7, linewidth=0.5)
        axes[2].axhline(y=1/shimmer_expected, color='r', linestyle='--', label='Expected')
        axes[2].set_title('Shimmer: Sampling Rate Over Time')
        axes[2].set_ylabel('Rate (Hz)')
        axes[2].set_xlabel('Sample Index')
        axes[2].legend()
        axes[2].grid(True, alpha=0.3)
        
        # # Neon sampling rate over time
        if neon_intervals is not None:
            axes[2, 1].plot(neon_rate, alpha=0.7, linewidth=0.5)
            axes[2, 1].axhline(y=1/neon_expected, color='r', linestyle='--', label='Expected')
            axes[2, 1].set_title('Neon: Sampling Rate Over Time')
            axes[2, 1].set_ylabel('Rate (Hz)')
            axes[2, 1].set_xlabel('Sample Index')
            axes[2, 1].legend()
            axes[2, 1].grid(True, alpha=0.3)
        
        plt.tight_layout()
        plt.savefig('pkl_data_loss_analysis.png', dpi=300)
        print(f"\nData loss plot saved as 'pkl_data_loss_analysis.png'")
    
    def analyze_event_synchronization(self):
        """
        Analyze synchronization based on spacebar events
        """
        print(f"\n" + "="*60)
        print(f"EVENT DETECTION ANALYSIS")
        print(f"="*60)
        
        # Find events in shimmer dataset
        shimmer_events = self.shimmer_df[self.shimmer_df['event'] == 1]
        
        print(f"\nNumber of events detected:")
        print(f"  Shimmer: {len(shimmer_events)}")
        
        if len(shimmer_events) == 0:
            print(f"\nWARNING: No events detected in Shimmer dataset!")
            return None
        
        # Get event timestamps
        shimmer_time_col = 'pc_time' if 'pc_time' in self.shimmer_df.columns else 'pc_timestamp'
        shimmer_event_times = shimmer_events[shimmer_time_col].values
        
        # Calculate inter-event intervals
        if len(shimmer_event_times) > 1:
            event_intervals = np.diff(shimmer_event_times)
            
            print(f"\nInter-event intervals:")
            print(f"  Mean: {event_intervals.mean():.3f} s")
            print(f"  Std: {event_intervals.std():.3f} s")
            print(f"  Min: {event_intervals.min():.3f} s")
            print(f"  Max: {event_intervals.max():.3f} s")
            
            # Plot event timing
            fig, axes = plt.subplots(2, 1, figsize=(12, 8))
            
            axes[0].plot(event_intervals, 'o-', alpha=0.7)
            axes[0].set_title('Inter-Event Intervals')
            axes[0].set_ylabel('Time (s)')
            axes[0].set_xlabel('Event Pair Index')
            axes[0].grid(True, alpha=0.3)
            
            # Histogram of inter-event intervals
            axes[1].hist(event_intervals, bins=20, alpha=0.7, edgecolor='black')
            axes[1].axvline(x=event_intervals.mean(), color='r', linestyle='--', label='Mean')
            axes[1].set_title('Distribution of Inter-Event Intervals')
            axes[1].set_xlabel('Time (s)')
            axes[1].set_ylabel('Count')
            axes[1].legend()
            axes[1].grid(True, alpha=0.3)
            
            plt.tight_layout()
            plt.savefig('pkl_event_analysis.png', dpi=300)
            print(f"\nEvent analysis plot saved as 'pkl_event_analysis.png'")
        
        return shimmer_event_times
    
    def plot_signals(self):
        """
        Plot GSR and PPG signals with events
        """
        print(f"\n" + "="*60)
        print(f"PLOTTING SIGNALS")
        print(f"="*60)
        
        # Get time column
        shimmer_time_col = 'pc_time' if 'pc_time' in self.shimmer_df.columns else 'pc_timestamp'
        
        # Count available signals
        num_plots = 0
        if 'GSR_ohm' in self.shimmer_df.columns:
            num_plots += 1
        if 'PPG_mv' in self.shimmer_df.columns:
            num_plots += 1
        
        if num_plots == 0:
            print(f"No signal data available to plot")
            return
        
        fig, axes = plt.subplots(num_plots, 1, figsize=(15, 5*num_plots))
        if num_plots == 1:
            axes = [axes]
        
        plot_idx = 0
        
        # Plot GSR
        if 'GSR_ohm' in self.shimmer_df.columns:
            axes[plot_idx].plot(
                self.shimmer_df[shimmer_time_col].to_numpy(),
                self.shimmer_df['GSR_ohm'].to_numpy(),
                label='GSR', color='blue', alpha=0.8, linewidth=0.8
            )

            
            # Mark events
            shimmer_events = self.shimmer_df[self.shimmer_df['event'] == 1]
            for t in shimmer_events[shimmer_time_col].values:
                axes[plot_idx].axvline(x=t, color='red', linestyle=':', linewidth=1.5, alpha=0.7)
            
            axes[plot_idx].set_title('Shimmer GSR with Events')
            axes[plot_idx].set_ylabel('GSR (ohm)')
            axes[plot_idx].legend()
            axes[plot_idx].grid(True, alpha=0.3)
            plot_idx += 1
        
        # Plot PPG if available
        if 'PPG_mv' in self.shimmer_df.columns:
            axes[plot_idx].plot(
                    self.shimmer_df[shimmer_time_col].to_numpy(),
                    self.shimmer_df['PPG_mv'].to_numpy(),
                    label='PPG', color='green', alpha=0.8, linewidth=0.8
                )

            
            shimmer_events = self.shimmer_df[self.shimmer_df['event'] == 1]
            for t in shimmer_events[shimmer_time_col].values:
                axes[plot_idx].axvline(x=t, color='red', linestyle=':', linewidth=1.5, alpha=0.7)
            
            axes[plot_idx].set_title('Shimmer PPG with Events')
            axes[plot_idx].set_ylabel('PPG (mV)')
            axes[plot_idx].set_xlabel('Time (s)')
            axes[plot_idx].legend()
            axes[plot_idx].grid(True, alpha=0.3)
        
        plt.tight_layout()
        plt.savefig('pkl_signals_with_events.png', dpi=300)
        print(f"\nSignals plot saved as 'pkl_signals_with_events.png'")
    
    def plot_gaze_distribution(self):
        """
        Plot gaze distribution heatmap robustly (avoids 'normed' bug in older Matplotlib).
        """
        if self.neon_df is None or 'x' not in self.neon_df.columns or 'y' not in self.neon_df.columns:
            print(f"\nNo gaze data available")
            return

        print(f"\n" + "="*60)
        print(f"PLOTTING GAZE DISTRIBUTION")
        print(f"="*60)

        x = self.neon_df['x'].dropna().to_numpy()
        y = self.neon_df['y'].dropna().to_numpy()

        if len(x) == 0 or len(y) == 0:
            print("No valid gaze coordinates to plot.")
            return

        # --- compute 2D histogram directly to avoid normed issue ---
        heatmap, xedges, yedges = np.histogram2d(x, y, bins=50)

        fig, ax = plt.subplots(figsize=(10, 8))
        extent = [xedges[0], xedges[-1], yedges[-1], yedges[0]]  # invert y-axis

        im = ax.imshow(
            heatmap.T, 
            extent=extent, 
            origin='upper', 
            cmap='hot', 
            interpolation='nearest',
            aspect='auto'
        )

        plt.colorbar(im, ax=ax, label='Sample Count')
        ax.set_title('Gaze Position Heatmap')
        ax.set_xlabel('X coordinate (px)')
        ax.set_ylabel('Y coordinate (px)')
        ax.invert_yaxis()

        plt.tight_layout()
        plt.savefig('pkl_gaze_heatmap.png', dpi=300)
        print(f"\nGaze heatmap saved as 'pkl_gaze_heatmap.png'")

    
    def plot_eye_tracking_metrics(self):
        """
        Plot gaze scatter, blink rate, and pupil size trends from Neon data.
        """
        if self.neon_df is None or len(self.neon_df) == 0:
            print("\nNo Neon eye-tracking data available.")
            return

        print(f"\n" + "="*60)
        print(f"PLOTTING EYE-TRACKING METRICS")
        print(f"="*60)

        time_col = None
        for col in ['timestamp', 'pc_timestamp', 'time']:
            if col in self.neon_df.columns:
                time_col = col
                break

        # --- 1. GAZE SCATTER ---
        if 'x' in self.neon_df.columns and 'y' in self.neon_df.columns:
            plt.figure(figsize=(10, 8))
            plt.scatter(self.neon_df['x'], self.neon_df['y'], s=1, alpha=0.3)
            plt.gca().invert_yaxis()
            plt.title("Gaze Scatter (X vs Y)")
            plt.xlabel("X position (px)")
            plt.ylabel("Y position (px)")
            plt.grid(True, alpha=0.3)
            plt.tight_layout()
            plt.savefig("pkl_gaze_scatter.png", dpi=300)
            print("Gaze scatter plot saved as 'pkl_gaze_scatter.png'")

        # --- 2. BLINK RATE OVER TIME ---
        blink_cols = [c for c in self.neon_df.columns if 'blink' in c.lower() or 'blink' == c.lower()]
        if blink_cols and time_col:
            blink_col = blink_cols[0]
            df_blink = self.neon_df[[time_col, blink_col]].dropna()

            # Smooth blink signal to visualize rate
            blink_signal = df_blink[blink_col].astype(float).rolling(50, min_periods=1).mean()

            plt.figure(figsize=(12, 5))
            plt.plot(df_blink[time_col].to_numpy(), blink_signal.to_numpy(), alpha=0.8, label="Blink probability/rate")
            plt.title("Blink Activity Over Time")
            plt.xlabel("Time (s)")
            plt.ylabel("Blink level")
            plt.grid(True, alpha=0.3)
            plt.legend()
            plt.tight_layout()
            plt.savefig("pkl_blink_rate.png", dpi=300)
            print("Blink rate plot saved as 'pkl_blink_rate.png'")
        else:
            print("No blink column found in Neon data.")

        # --- 3. PUPIL SIZE (LEFT/RIGHT) ---
        pupil_cols = [c for c in self.neon_df.columns if 'pupil' in c.lower()]
        pupil_left = [c for c in pupil_cols if 'left' in c.lower()]
        pupil_right = [c for c in pupil_cols if 'right' in c.lower()]

        if time_col and (pupil_left or pupil_right):
            plt.figure(figsize=(12, 6))
            if pupil_left:
                plt.plot(self.neon_df[time_col].to_numpy(), self.neon_df[pupil_left[0]].to_numpy(),
                         label='Left Pupil', color='blue', alpha=0.7)
            if pupil_right:
                plt.plot(self.neon_df[time_col].to_numpy(), self.neon_df[pupil_right[0]].to_numpy(),
                         label='Right Pupil', color='orange', alpha=0.7)
            plt.title("Pupil Diameter Over Time")
            plt.xlabel("Time (s)")
            plt.ylabel("Pupil size (mm or px)")
            plt.legend()
            plt.grid(True, alpha=0.3)
            plt.tight_layout()
            plt.savefig("pkl_pupil_diameter.png", dpi=300)
            print("Pupil diameter plot saved as 'pkl_pupil_diameter.png'")
        else:
            print("No pupil size data found in Neon dataset.")

    def generate_full_report(self):
        """
        Generate complete analysis report
        """
        print(f"\n" + "="*60)
        print(f"GENERATING FULL PKL ANALYSIS REPORT")
        print(f"="*60)
        
        # Run all analyses
        loss_stats = self.analyze_data_loss()
        time_diffs = self.analyze_event_synchronization()
        self.plot_signals()
        self.plot_gaze_distribution()
        self.plot_eye_tracking_metrics()

        
        # Final summary
        print(f"\n" + "="*60)
        print(f"FINAL SUMMARY")
        print(f"="*60)
        
        if loss_stats:
            print(f"\n1. System Stability:")
            print(f"   Shimmer:")
            print(f"     - Data loss: {loss_stats['shimmer']['data_loss_pct']:.3f}%")
            print(f"     - Gaps detected: {loss_stats['shimmer']['num_gaps']}")
            print(f"     - Actual sampling rate: {loss_stats['shimmer']['mean_rate']:.2f} Hz")

            neon_loss = loss_stats['neon'].get('data_loss_pct')
            neon_gaps = loss_stats['neon'].get('num_gaps')
            neon_rate = loss_stats['neon'].get('mean_rate')

            print(f"   Neon:")
            print(f"     - Data loss: {neon_loss:.3f}%"
                if neon_loss is not None else "     - Data loss: N/A")
            print(f"     - Gaps detected: {neon_gaps if neon_gaps is not None else 'N/A'}")
            print(f"     - Actual sampling rate: {neon_rate:.2f} Hz"
                if neon_rate is not None else "     - Actual sampling rate: N/A")




# Usage
if __name__ == "__main__":
    # Replace with your actual PKL file paths
    shimmer_file = "/home/acatalano/VIRTUES/test_session/gsr.pkl"
    neon_file = "/home/acatalano/VIRTUES/test_session/eye.pkl"
    
    analyzer = PKLSensorAnalyzer(shimmer_file, neon_file)
    analyzer.generate_full_report()
    
    plt.show()