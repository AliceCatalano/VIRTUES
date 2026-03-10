%% Orchestrator Recording Data Visualization
% Unified timeline with all sensors synchronized via PC timestamps
% ========================================================================
% Usage:
%   1. Set session_folder to your recording directory
%   2. Run the script
%   3. All sensors plotted on synchronized timeline with event markers
%
% Features:
%   - PC timestamp alignment (all sensors on same clock)
%   - Gaze plotted as SCATTER (shows distribution)
%   - Force sensors with moving average smoothing
%   - Pupil quality analysis
%   - Event markers on all plots
%   - Supports both CSV and PKL file formats

clear; clc; close all;

% Configuration
% ------------------------------------------------------------------------
session_folder = '/home/acatalano/VIRTUES/recordings/subject_accSkip2/Baseline/Level1';
session_folder = replace(session_folder, '~', getenv('HOME'));

% Accelerometer/Force sensor parameters
accel_fs = 3000;  % Sampling rate in Hz
force_fs = 3000;  % Sampling rate in Hz
smooth_window = accel_fs;  % Moving average window (1 second at 3000Hz)

% Use CSV or PKL files
use_pkl = false;  % Set to true to read from .pkl files instead of .csv

%% ------------------------------------------------------------------------
% Load Data Files
% ------------------------------------------------------------------------
fprintf('Loading data from: %s\n\n', session_folder);

if use_pkl
    % ====================================================================
    % OPTION A: Load from PKL files (requires Python)
    % ====================================================================
    % Note: This requires calling Python from MATLAB
    % Uncomment the following section to use PKL files:

    % gsr   = load_pkl_to_table(fullfile(session_folder, 'gsr.pkl'));
    % eye   = load_pkl_to_table(fullfile(session_folder, 'eye.pkl'));
    % accel = load_pkl_to_table(fullfile(session_folder, 'accel.pkl'));
    % force = load_pkl_to_table(fullfile(session_folder, 'force.pkl'));
    % events = load_pkl_to_table(fullfile(session_folder, 'events.pkl'));

    error('PKL loading not implemented. Set use_pkl = false or implement load_pkl_to_table()');

else
    % ====================================================================
    % OPTION B: Load from CSV files (default)
    % ====================================================================
    % gsr_file    = fullfile(session_folder, 'gsr.csv');
    % % eye_file    = fullfile(session_folder, 'eye.csv');
    nidaq_file  = fullfile(session_folder, 'accel.csv');
    % events_file = fullfile(session_folder, 'events.csv');

    % gsr = readtable(gsr_file);
    % eye = readtable(eye_file);
    nidaq = readtable(nidaq_file);

    % events = readtable(events_file);
    accel = table();
    accel.xL = nidaq.ai1;
    accel.yL = nidaq.ai2;
    accel.zL = nidaq.ai3;
    accel.xR = nidaq.ai4;
    accel.yR = nidaq.ai5;
    accel.zR = nidaq.ai6;
    accel.t_pc = nidaq.pc_time;
    force = table();
    force.F1 = nidaq.ai7  - nidaq.ai13;
    force.F2 = nidaq.ai8  - nidaq.ai14;
    force.F3 = nidaq.ai9 - nidaq.ai15;
    force.F4 = nidaq.ai10 - nidaq.ai16;
    force.F5 = nidaq.ai11 - nidaq.ai17;
    force.F6 = nidaq.ai12 - nidaq.ai18;
    force.t_pc = nidaq.pc_time;
end

%% Print loaded sample counts
fprintf('Loaded samples:\n');
% fprintf('  GSR:    %d\n', height(gsr));
% fprintf('  Eye:    %d\n', height(eye));
fprintf('  Accel:  %d\n', height(accel));
fprintf('  Force:  %d\n', height(force));
% fprintf('  Events: %d\n\n', height(events));

%% ------------------------------------------------------------------------
% Extract PC Timestamps (ABSOLUTE timeline)
% ------------------------------------------------------------------------
% recording_time column contains the PC timestamp when data was received
% This is our unified clock for synchronization

all_pc_times = [];

% gsr.t_pc = gsr.timestamp;
% all_pc_times = [all_pc_times; gsr.t_pc];
%
% eye.t_pc = eye.timestamp_unix_seconds;
% all_pc_times = [all_pc_times; eye.t_pc];

all_pc_times = [all_pc_times; accel.t_pc];

all_pc_times = [all_pc_times; force.t_pc];
%
% events.t_pc = events.recording_time;
% all_pc_times = [all_pc_times; events.t_pc];

% Global reference: earliest PC timestamp across all sensors
t0 = min(all_pc_times);

% Convert to relative seconds for plotting
% gsr.t   = gsr.t_pc   - t0;
% eye.t   = eye.t_pc   - t0;
accel.t = accel.t_pc - t0;
force.t = force.t_pc - t0;

% event_times = events.t_pc - t0;
% event_labels = events.data;  % Event names

fprintf('Unified PC timeline:\n');
fprintf('  Global start (t=0): %.3f s (PC time)\n', t0);
fprintf('  Duration:           %.3f s\n', max(all_pc_times - t0));
fprintf('  Earliest sensor:    ');
% if min(gsr.t_pc) == t0
%     fprintf('GSR\n');
% elseif min(eye.t_pc) == t0
%     fprintf('Eye Tracker\n');
if min(accel.t_pc) == t0
    fprintf('Accelerometer\n');
elseif min(force.t_pc) == t0
    fprintf('Force Sensors\n');
end
fprintf('\n');

%% ------------------------------------------------------------------------
% Sensor Start Times (relative to t0)
% ------------------------------------------------------------------------
fprintf('Sensor start times (relative to global t=0):\n');
% fprintf('  GSR:    %.3f s\n', min(gsr.t));
% fprintf('  Eye:    %.3f s\n', min(eye.t));
fprintf('  Accel:  %.3f s\n', min(accel.t));
fprintf('  Force:  %.3f s\n', min(force.t));
fprintf('\n');

%% ------------------------------------------------------------------------
% Event Times
% ------------------------------------------------------------------------
% fprintf('Events detected:\n');
% for i = 1:length(event_times)
%         fprintf('  %8.3f s: %s\n', event_times(i), event_labels{i});
% end
% fprintf('\n');


%% ------------------------------------------------------------------------
% Pupil Quality Analysis (from eye tracking data)
% ------------------------------------------------------------------------
% if ismember('pupil_diameter_left', eye.Properties.VariableNames)
%
%     fprintf('=== Pupil Quality Analysis ===\n');
%
%     left_raw  = eye.pupil_diameter_left;
%     right_raw = eye.pupil_diameter_right;
%
%     % Remove NaN values
%     left_raw(isnan(left_raw)) = [];
%     right_raw(isnan(right_raw)) = [];
%
%     % Detrend signals
%     if ~isempty(left_raw)
%         detr_left = detrend(left_raw);
%         fprintf('Left Pupil:\n');
%         fprintf('  Noise STD:    %.4f mm\n', std(detr_left));
%         fprintf('  RMS diff:     %.4f mm\n', rms(diff(left_raw)));
%     end
%
%     if ~isempty(right_raw)
%         detr_right = detrend(right_raw);
%         fprintf('Right Pupil:\n');
%         fprintf('  Noise STD:    %.4f mm\n', std(detr_right));
%         fprintf('  RMS diff:     %.4f mm\n', rms(diff(right_raw)));
%     end
%
%     % Frequency analysis
%     if ismember('recording_time', eye.Properties.VariableNames) && ~isempty(left_raw)
%         fs = 1 / median(diff(eye.recording_time));
%
%         if ~isempty(left_raw) && length(left_raw) > 256
%             [pxxL, fL] = pwelch(left_raw, [], [], [], fs);
%             cutoff = 1; % Hz
%             hfL = trapz(fL(fL > cutoff), pxxL(fL > cutoff)) / trapz(fL, pxxL);
%             fprintf('  HF ratio:     %.3f (>1Hz)\n', hfL);
%         end
%     end
%     fprintf('\n');
% end

%% ------------------------------------------------------------------------
% Process Force Sensor Data (moving average for smoothing)
% ------------------------------------------------------------------------
if ~isempty(force)
    fprintf('Processing force sensor data...\n');
    fprintf('  Sampling rate: %d Hz\n', force_fs);
    % fprintf('  Smoothing window: %d samples (%.3f s)\n', ...
    %     smooth_window, smooth_window/force_fs);
    %
    % Find all force/analog input columns
    force_cols = {'F1','F2','F3','F4','F5','F6'};

    % for i = 1:length(force_cols)
    %     col = force_cols{i};
    %     force.([col '_smooth']) = movmean(force.(col), smooth_window);
    % end

    % Compute total force (sum of all channels)
    if ~isempty(force_cols)
        force.total = zeros(height(force), 1);
        for i = 1:length(force_cols)
            force.total = force.total + force.(force_cols{i});
        end
        force.total_smooth = movmean(force.total, smooth_window);
    end

    fprintf('  ✓ Smoothing complete\n\n');
end

%% ------------------------------------------------------------------------
% Process Accelerometer Data (moving average for smoothing)
% ------------------------------------------------------------------------
if ~isempty(accel)
    fprintf('Processing accelerometer data...\n');
    fprintf('  Sampling rate: %d Hz\n', accel_fs);
    fprintf('  Smoothing window: %d samples (%.3f s)\n', ...
        smooth_window, smooth_window/accel_fs);

    % Find all accelerometer columns
    accel_cols = {'xL','yL','zL','xR','yR','zR'};

    % Apply moving average to each channel
    for i = 1:length(accel_cols)
        col = accel_cols{i};
        accel.([col '_smooth']) = movmean(accel.(col), smooth_window);
    end

    % If we have 3-axis data, compute magnitude
    if length(accel_cols) >= 3
        accel.magnitude = sqrt(accel.(accel_cols{1}).^2 + ...
            accel.(accel_cols{2}).^2 + ...
            accel.(accel_cols{3}).^2);
        accel.magnitude_smooth = movmean(accel.magnitude, smooth_window);
    end

    fprintf('  ✓ Smoothing complete\n\n');
end

%% ------------------------------------------------------------------------
% Plot GSR
% ------------------------------------------------------------------------
% figure;
%     % Try different column naming conventions
%     if ismember('GSR_ohm', gsr.Properties.VariableNames)
%         plot(gsr.t, gsr.GSR_ohm, 'b', 'LineWidth', 1);
%         ylabel('GSR (Ω)');
%     end
%
%     title('GSR – Shimmer Sensor (PC-aligned)', 'FontWeight', 'bold');
%     grid on;
%     hold on;
%
%     % Add event markers
%     for i = 1:length(event_times)
%         xline(event_times(i), 'k--', 'LineWidth', 1.2, 'Alpha', 0.7);
%     end
%

%% Plot Eye Tracking - Gaze X (SCATTER)
% figure;
%     scatter(eye.x, eye.y, 1, 'r', 'filled', 'MarkerFaceAlpha', 0.3);
%
%     title('Gaze X Position – Neon (scatter shows distribution)', 'FontWeight', 'bold');
%     grid on;
%     hold on;
%
%     % Add event markers
%     for i = 1:length(event_times)
%         xline(event_times(i), 'k--', 'LineWidth', 1.2, 'Alpha', 0.7);
%     end
%
%     % Pupil Diameter
%     figure;
%     if ismember('pupil_diameter_left', eye.Properties.VariableNames)
%         plot(eye.t, eye.pupil_diameter_left, 'b', 'LineWidth', 1);
%         hold on;
%     end
%
%     if ismember('pupil_diameter_right', eye.Properties.VariableNames)
%         plot(eye.t, eye.pupil_diameter_right, 'g', 'LineWidth', 1);
%     end
%
%     ylabel('Pupil Diameter (mm)');
%     title('Pupil Diameter – Neon', 'FontWeight', 'bold');
%     legend('Left', 'Right', 'Location', 'best');
%     grid on;
%     hold on;
%
%     % Add event markers
%     for i = 1:length(event_times)
%         xline(event_times(i), 'k--', 'LineWidth', 1.2, 'Alpha', 0.7);
%     end
%

%% Blink Detection
% figure;
%
% if ismember('blink', eye.Properties.VariableNames)
%     stairs(eye.t, eye.blink, 'k', 'LineWidth', 1.5);
%     ylim([-0.1, 1.1]);
%     yticks([0, 1]);
%     yticklabels({'No', 'Yes'});
%     ylabel('Blink');
%     title('Blink Detection – Neon', 'FontWeight', 'bold');
%     grid on;
%     hold on;
%
%     % Add event markers
%     for i = 1:length(event_times)
%         xline(event_times(i), 'k--', 'LineWidth', 1.2, 'Alpha', 0.7);
%     end
% end
%


%% Plot Accelerometer Data
figure;

if exist('accel_cols', 'var') && length(accel_cols) >= 3
    % Plot 3-axis
    plot(accel.t, accel.(accel_cols{1}), 'r', 'LineWidth', 0.5, 'DisplayName', accel_cols{1});
    hold on;
    plot(accel.t, accel.(accel_cols{2}), 'g', 'LineWidth', 0.5, 'DisplayName', accel_cols{2});
    plot(accel.t, accel.(accel_cols{3}), 'b', 'LineWidth', 0.5, 'DisplayName', accel_cols{3});
    ylabel('Acceleration (g or V)');
    title('Accelerometer – Raw 3-Axis', 'FontWeight', 'bold');
    legend('Location', 'best');
elseif exist('accel_cols', 'var') && ~isempty(accel_cols)
    % Plot first channel
    plot(accel.t, accel.(accel_cols{1}), 'b', 'LineWidth', 0.5);
    ylabel('Acceleration');
    title(['Accelerometer – ' accel_cols{1}], 'FontWeight', 'bold');
end

grid on;
hold on;

plot_accel_6panel(accel.t, accel.xL, accel.yL, accel.zL, accel_fs, 80, 1000);
% Add event markers
function plot_accel_6panel(t, x, y, z, Fs, bp_lo, bp_hi)

% Bandpass each axis (already in g after V->G conversion)
xbp   = bandpass(x, [bp_lo bp_hi], Fs);
ybp   = bandpass(y, [bp_lo bp_hi], Fs);
zbp   = bandpass(z, [bp_lo bp_hi], Fs);
sumbp = xbp + ybp + zbp;

% Spectrum of the bandpassed sum
[SPEC_f, freq] = positiveFFT(sumbp, Fs);

figure('Name','Try' , 'Position', [50 50 1400 1100]);
sgtitle('Try', 'FontWeight','bold', 'FontSize',10);

% Subplot 1 — X
ax1 = subplot(5,1,1);
plot(t, xbp, 'Color', [0.8 0.1 0.1], 'LineWidth', 0.6);
ylabel('X (g)'); title('X axis (bandpassed)'); grid on;


% Subplot 2 — Y
ax2 = subplot(5,1,2);
plot(t, ybp, 'Color', [0.1 0.6 0.1], 'LineWidth', 0.6);
ylabel('Y (g)'); title('Y axis (bandpassed)'); grid on;


% Subplot 3 — Z
ax3 = subplot(5,1,3);
plot(t, zbp, 'Color', [0.1 0.2 0.8], 'LineWidth', 0.6);
ylabel('Z (g)'); title('Z axis (bandpassed)'); grid on;


% Subplot 4 — Sum X+Y+Z
ax4 = subplot(5,1,4);
plot(t, sumbp, 'Color', [0.5 0 0.7], 'LineWidth', 0.6);
ylabel('Sum (g)'); title('Sum X+Y+Z (bandpassed)'); grid on;


% Subplot 5 — Frequency spectrum of sum
ax5 = subplot(5,1,5);
plot(freq, abs(SPEC_f), 'k', 'LineWidth', 0.7);
xlabel('Frequency (Hz)'); ylabel('|FFT|');
title('Spectrum of Sum (bandpassed)'); grid on;
xlim([0 Fs/2]);

% Subplot 6 — Force magnitude (downsampled, offset-removed)


% Link time axes (all except spectrum)
linkaxes([ax1 ax2 ax3 ax4 ax5], 'x');
xlabel(ax5, 'Time (s)');
end
%% Smoothed accelerometer (magnitude or first channel)
figure;
if ismember('magnitude_smooth', accel.Properties.VariableNames)
    plot(accel.t, accel.magnitude_smooth, 'Color', [0.5 0 0.5], 'LineWidth', 1.5);
    ylabel('Magnitude (g)');
    title(sprintf('Accelerometer – Magnitude (smoothed, %d samples = %.3f s)', ...
        smooth_window, smooth_window/accel_fs), 'FontWeight', 'bold');
elseif exist('accel_cols', 'var') && ~isempty(accel_cols)
    smooth_col = [accel_cols{1} '_smooth'];
    if ismember(smooth_col, accel.Properties.VariableNames)
        plot(accel.t, accel.(smooth_col), 'b', 'LineWidth', 1.5);
        ylabel('Acceleration (smoothed)');
        title(sprintf('Accelerometer – %s (smoothed, %d samples)', ...
            accel_cols{1}, smooth_window), 'FontWeight', 'bold');
    end
end

grid on;

%% Plot Force Sensor Data
% Individual force channels (smoothed)
% figure;
% if exist('force_cols', 'var')
%     colors = lines(length(force_cols));
%     for i = 1:length(force_cols)
%         col = force_cols{i};
%         smooth_col = [col '_smooth'];
%         if ismember(smooth_col, force.Properties.VariableNames)
%             plot(force.t, force.(smooth_col), 'Color', colors(i,:), ...
%                 'LineWidth', 1, 'DisplayName', col);
%             hold on;
%         end
%     end
%     ylabel('Force (N or V)');
%     title(sprintf('Force Sensors – Individual Channels (smoothed, %d samples = %.3f s)', ...
%         smooth_window, smooth_window/force_fs), 'FontWeight', 'bold');
%     legend('Location', 'best');
%     grid on;
% 
%     % Add event markers
%     for i = 1:length(event_times)
%         xline(event_times(i), 'k--', 'LineWidth', 1.2, 'Alpha', 0.7);
%     end
% end
% 
% %% Total force (sum of all channels, smoothed)
% figure;
% if ismember('total_smooth', force.Properties.VariableNames)
%     plot(force.t, force.total_smooth, 'Color', [0.5 0 0.5], 'LineWidth', 2);
%     ylabel('Total Force');
%     title(sprintf('Force Sensors – Total (smoothed, %d samples = %.3f s)', ...
%         smooth_window, smooth_window/force_fs), 'FontWeight', 'bold');
%     grid on;
%     hold on;
% 
%     % Add event markers
%     for i = 1:length(event_times)
%         xline(event_times(i), 'k--', 'LineWidth', 1.2, 'Alpha', 0.7);
%     end
% end


%% ------------------------------------------------------------------------
% Final touches
% %% ------------------------------------------------------------------------
% xlabel('Time (s) – PC unified timeline', 'FontWeight', 'bold');
% linkaxes(findall(gcf, 'Type', 'axes'), 'x');
%
% % Add event labels at the top of the figure
% if ~isempty(events) && p > 1
%     % Go back to first subplot to add event labels
%     subplot(nPlots, 1, 1);
%     ylims = ylim;
%     for i = 1:length(event_times)
%         text(event_times(i), ylims(2), ['  ' event_labels{i}], ...
%             'Rotation', 90, 'VerticalAlignment', 'bottom', ...
%             'FontSize', 8, 'Color', 'k', 'FontWeight', 'bold');
%     end
% end
%
% fprintf('✓ Visualization complete!\n');
% fprintf('\nFigure controls:\n');
% fprintf('  - Zoom: Use zoom tool or scroll\n');
% fprintf('  - Pan: Click and drag\n');
% fprintf('  - All plots share the same x-axis (linked)\n\n');

