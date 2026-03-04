%% Load data
shimmer = readtable('/home/acatalano/VIRTUES/recordings/subject_ioTry/level_L1/rep_01/session_2026-01-20_16-49-42/gsr.csv');
neon = readtable('/home/acatalano/VIRTUES/recordings/subject_ioTry/level_L1/rep_01/session_2026-01-20_16-49-42/eye.csv', ReadVariableNames=true);
events = readtable('/home/acatalano/VIRTUES/recordings/subject_ioTry/level_L1/rep_01/session_2026-01-20_16-49-42/events.csv');
%% Detrended Standard Deviation

left_raw = neon.pupil_diameter_left;
right_raw = neon.pupil_diameter_right;

% Remove slow trends
detr_left = detrend(left_raw);
detr_right = detrend(right_raw);

% Noise level = standard deviation of detrended signal
noise_std_left = std(detr_left, 'omitnan');
noise_std_right = std(detr_right, 'omitnan');

fprintf('Noise (std) - Left: %.4f | Right: %.4f\n', noise_std_left, noise_std_right);

%% Power Spectral Density (High-Frequency Energy)
fs = 1 / median(diff(neon.timestamp_unix_seconds)); % Sampling frequency [Hz]

[pxxL, fL] = pwelch(left_raw, [], [], [], fs);
[pxxR, fR] = pwelch(right_raw, [], [], [], fs);

% Define "high-frequency" noise band (adjust cutoff as needed)
cutoff = 1; % Hz, for example
hf_power_left = trapz(fL(fL > cutoff), pxxL(fL > cutoff));
hf_power_right = trapz(fR(fR > cutoff), pxxR(fR > cutoff));

total_power_left = trapz(fL, pxxL);
total_power_right = trapz(fR, pxxR);

% Fraction of power considered "noise"
noise_ratio_left = hf_power_left / total_power_left;
noise_ratio_right = hf_power_right / total_power_right;

fprintf('High-frequency noise ratio - Left: %.3f | Right: %.3f\n', noise_ratio_left, noise_ratio_right);
%% Local Variability Metric (Short-Term Fluctuation)
% First-order difference (rate of change)
diff_left = diff(left_raw);
diff_right = diff(right_raw);

% RMS of the derivative = measure of noise/jitter
noise_rms_left = rms(diff_left, 'omitnan');
noise_rms_right = rms(diff_right, 'omitnan');

fprintf('Noise (RMS of derivative) - Left: %.4f | Right: %.4f\n', ...
    noise_rms_left, noise_rms_right);


%% --- 1. Plot GSR with event markers (use pc_timestamp) ---
figure('Name','GSR with Events');
plot(shimmer.pc_time, shimmer.GSR_ohm, 'b', 'LineWidth', 1.2);
hold on;
xlabel('PC Timestamp (s)');
ylabel('GSR (Ohm)');
title('GSR with Event Markers (using pc\_timestamp)');

% Add red dotted lines where event == 1
event_times_shimmer = shimmer.pc_time(shimmer.event ~= 0);
for t = event_times_shimmer'
    xline(t, 'r--', 'LineWidth', 1);
end
grid on;
%% --- Plot Eyelid aperture with event markers ---
figure('Name','Eyelid aperture with Events');
plot(neon.timestamp_unix_seconds, neon.eyelid_angle_top_left, 'b', 'DisplayName', 'Left eyelid');
hold on;
plot(neon.timestamp_unix_seconds, neon.eyelid_angle_top_right, 'g', 'DisplayName', 'Right eyelid');

% Event lines
event_times_neon = neon.timestamp_unix_seconds(neon.event ~= 0);
for t = event_times_neon'
    xline(t, 'r--', 'LineWidth', 1);
end

xlabel('Timestamp (s)');
ylabel('Eyelid aperture');
title('Eyelid aperture (Left/Right) with Event Markers');
legend;
grid on;
%% --- 2. Plot pupil diameter (left/right) with event markers ---
figure('Name','Pupil Diameters with Events');
plot(neon.timestamp_unix_seconds, smooth(neon.pupil_diameter_left), 'b', 'DisplayName', 'Left Pupil');
hold on;
plot(neon.timestamp_unix_seconds, smooth(neon.pupil_diameter_right), 'g', 'DisplayName', 'Right Pupil');

% Event lines
% event_times_neon = neon.timestamp_unix_seconds(neon.event ~= 0);
% for t = event_times_neon'
%     xline(t, 'r--', 'LineWidth', 1);
% end

xlabel('Timestamp (s)');
ylabel('Pupil Diameter');
title('Pupil Diameters (Left/Right) with Event Markers');
legend;
grid on;

%% --- Weighted Moving Average (Binomial) Filter on Pupil Data ---

% Define the binomial coefficients using 5 iterations of [1/2 1/2]
h = [1/2 1/2];
binomialCoeff = conv(h,h);
for n = 1:4
    binomialCoeff = conv(binomialCoeff,h);
end

% Normalize (important so gain = 1)
binomialCoeff = binomialCoeff / sum(binomialCoeff);

% Apply filter to pupil diameters
pupil_left_filt  = %filter(binomialCoeff, 1, neon.pupil_diameter_left);
pupil_right_filt = %filter(binomialCoeff, 1, neon.pupil_diameter_right);

% Compute filter delay (half the kernel length)
fDelay = (length(binomialCoeff)-1)/2;

%% --- Plot filtered vs. raw pupil signals with event lines ---
figure('Name','Filtered Pupil Diameters (Binomial Weighted Average)');
plot(neon.timestamp_unix_seconds, neon.pupil_diameter_left,  'Color',[0.6 0.6 1], 'DisplayName','Left Raw');
hold on;
plot(neon.timestamp_unix_seconds, neon.pupil_diameter_right, 'Color',[0.6 1 0.6], 'DisplayName','Right Raw');

% Apply delay compensation by shifting timestamps
t_shifted = neon.timestamp_unix_seconds - fDelay * mean(diff(neon.timestamp_unix_seconds));

plot(t_shifted, pupil_left_filt,  'b', 'LineWidth',1.5, 'DisplayName','Left Filtered');
plot(t_shifted, pupil_right_filt, 'g', 'LineWidth',1.5, 'DisplayName','Right Filtered');

% Event markers
event_times_neon = neon.timestamp_unix_seconds(neon.event ~= 0);
for t = event_times_neon'
    xline(t, 'r--', 'LineWidth', 1);
end

xlabel('Timestamp (s)');
ylabel('Pupil Diameter');
title('Binomial Weighted Moving Average Filter on Pupil Diameters');
legend('Location','best');
grid on;
%% --- 3. Gaze position scatter plot ---
figure('Name','Gaze Scatter');
scatter(neon.x, neon.y, 8, 'filled');
xlabel('Gaze X Position');
ylabel('Gaze Y Position');
title('Gaze Scatter Plot');
set(gca, 'YDir','reverse'); % optional: match screen coordinates
grid on;

%% --- 4. Blink detection (from worn flag) ---
% Convert 'True'/'False' text cells into numeric 1/0
if iscell(neon.worn)
    blink_signal = zeros(height(neon),1);
    for i = 1:height(neon)
        if strcmpi(neon.worn{i}, 'True')
            blink_signal(i) = 0;
        elseif strcmpi(neon.worn{i}, 'False')
            blink_signal(i) = 1;
        else
            blink_signal(i) = NaN; % handle unexpected values
        end
    end
else
    % If it's already logical or numeric
    blink_signal = double(neon.worn);
end

% Optional: invert if 0=seen, 1=blink
blink_signal = 1 - blink_signal; % so 1 = blink (not worn)


figure('Name','Blink Detection with Events');
stairs(neon.timestamp_unix_seconds, blink_signal, 'k', 'LineWidth', 1.5);
hold on;
for t = event_times_neon'
    xline(t, 'r--', 'LineWidth', 1);
end
xlabel('Timestamp (s)');
ylabel('Blink (1 = blink)');
title('Blink Detection with Event Markers');
ylim([-0.1 1.1]);
grid on;

%% --- 2) choose downsample rate (Hz) ---
ts = double(neon.timestamp_unix_seconds);
pL = double(neon.pupil_diameter_left);
pR = double(neon.pupil_diameter_right);

% --- Choose downsample rate (Hz) ---
target_fs = 5;              % desired frequency
target_dt = 1 / target_fs;   % seconds per bin

% --- Create time bins ---
t0 = ts(1);
tend = ts(end);
numBins = floor((tend - t0) / target_dt) + 1;

% Assign samples to bins
binIndex = floor((ts - t0) / target_dt) + 1;
binIndex(binIndex < 1) = 1;
binIndex(binIndex > numBins) = numBins;

% --- Compute mean per bin ---
left_ds  = accumarray(binIndex, pL, [numBins 1], @mean, NaN);
right_ds = accumarray(binIndex, pR, [numBins 1], @mean, NaN);

% Corresponding timestamps (bin centers)
time_ds = t0 + ((0:numBins-1)' + 0.5) * target_dt;

% --- Plot downsampled vs raw data ---
event_times_neon = neon.timestamp_unix_seconds(neon.event ~= 0);

figure('Name','Pupil Diameters Downsampled');
%plot(ts, pL, '.', 'MarkerSize', 4, 'DisplayName','Left Raw');
%plot(ts, pR, '.', 'MarkerSize', 4, 'DisplayName','Right Raw');
plot(time_ds, left_ds, '-b', 'LineWidth', 1.5, 'DisplayName', sprintf('Left %.1f Hz', target_fs)); hold on;
plot(time_ds, right_ds, '-g', 'LineWidth', 1.5, 'DisplayName', sprintf('Right %.1f Hz', target_fs));

% Add event markers
for t = event_times_neon'
    xline(t, 'r--', 'LineWidth', 1);
end

xlabel('Timestamp (s)');
ylabel('Pupil Diameter');
title(sprintf('Downsampled Pupil Diameters (%.1f Hz)', target_fs));
legend('Location','best');
grid on;

fprintf('Downsampled %d samples into %d bins (%.1f Hz)\n', ...
    length(ts), numBins, target_fs);