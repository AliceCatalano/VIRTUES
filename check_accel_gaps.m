%% check_accel_gaps.m
% Analyses a saved accelerometer CSV for data gaps and timing integrity.
%
% Usage:
%   check_accel_gaps                        % opens file picker
%   check_accel_gaps('path/to/file.csv')    % pass path directly
%
% Expects a CSV with at least a 'pc_time' column (Unix timestamps in seconds).
% All other columns are treated as channel data.

function check_accel_gaps(filepath)

EXPECTED_FS  = 3000;                        % Hz
EXPECTED_DT  = 1 / EXPECTED_FS;            % seconds
GAP_THRESH   = EXPECTED_DT * 3;            % flag gaps > ~1 ms

% ── File selection ────────────────────────────────────────────────────────────
if nargin < 1 || isempty(filepath)
    [fname, fpath] = uigetfile('*.csv', 'Select accelerometer CSV');
    if isequal(fname, 0)
        disp('No file selected. Aborting.');
        return
    end
    filepath = fullfile(fpath, fname);
end

fprintf('\n%s\n', repmat('=', 1, 60));
fprintf('Analysing: %s\n', filepath);
fprintf('%s\n', repmat('=', 1, 60));

% ── Load CSV ──────────────────────────────────────────────────────────────────
try
    T = readtable(filepath);
catch ME
    fprintf('ERROR loading file: %s\n', ME.message);
    return
end

if ~ismember('pc_time', T.Properties.VariableNames)
    fprintf('ERROR: No ''pc_time'' column found in file.\n');
    fprintf('Available columns: %s\n', strjoin(T.Properties.VariableNames, ', '));
    return
end

times = T.pc_time;

% Remove any NaN rows
valid = ~isnan(times);
if sum(~valid) > 0
    fprintf('WARNING: Removed %d rows with NaN timestamps.\n', sum(~valid));
end
times = times(valid);
times = sort(times);   % ensure monotonic (should already be)

if numel(times) < 2
    fprintf('Not enough rows to analyse.\n');
    return
end

% ── Core statistics ───────────────────────────────────────────────────────────
diffs        = diff(times);
total_samp   = numel(times);
duration     = times(end) - times(1);
expected_n   = round(duration * EXPECTED_FS);
missing      = expected_n - total_samp;
pct_missing  = 100 * missing / max(expected_n, 1);

gap_idx      = find(diffs > GAP_THRESH);   % indices into diffs

fprintf('\n  First sample time  : %.6f s (Unix)\n', times(1));
fprintf('  Last  sample time  : %.6f s (Unix)\n', times(end));
fprintf('  Duration           : %.3f s\n',         duration);
fprintf('  Samples present    : %d\n',             total_samp);
fprintf('  Samples expected   : %d\n',             expected_n);
fprintf('  Missing samples    : %d  (%.2f %%)\n',  missing, pct_missing);
fprintf('  Gaps (> %.1f ms)   : %d\n',             GAP_THRESH * 1000, numel(gap_idx));

% ── Top 10 gaps ───────────────────────────────────────────────────────────────
if ~isempty(gap_idx)
    gap_sizes   = diffs(gap_idx);
    [~, order]  = sort(gap_sizes, 'descend');
    top_n       = min(10, numel(gap_idx));

    fprintf('\n  Top %d gaps:\n', top_n);
    fprintf('  %5s  %10s  %12s  %12s  %15s\n', ...
        'Rank', 'Sample #', 't (s)', 'Gap (ms)', 'Missing samps');
    fprintf('  %s\n', repmat('-', 1, 58));

    for k = 1:top_n
        gi = gap_idx(order(k));
        fprintf('  %5d  %10d  %12.4f  %12.2f  %15.0f\n', ...
            k, gi, times(gi), diffs(gi) * 1000, round(diffs(gi) / EXPECTED_DT));
    end
end

% ── Inter-sample dt statistics ────────────────────────────────────────────────
median_dt = median(diffs) * 1000;
std_dt    = std(diffs)    * 1000;
max_dt    = max(diffs)    * 1000;
min_dt    = min(diffs)    * 1000;

fprintf('\n  Inter-sample dt statistics:\n');
fprintf('    Median : %.4f ms\n', median_dt);
fprintf('    Std    : %.4f ms\n', std_dt);
fprintf('    Min    : %.4f ms\n', min_dt);
fprintf('    Max    : %.2f ms\n', max_dt);

% ── Summary verdict ───────────────────────────────────────────────────────────
fprintf('\n');
if pct_missing > 1
    fprintf('  ⚠  MORE THAN 1%% DATA LOSS (%.2f%%) — investigate gaps above.\n', pct_missing);
elseif missing == 0
    fprintf('  ✓  No missing samples detected.\n');
else
    fprintf('  ⚠  %d missing samples (<1%%) — likely minor jitter.\n', missing);
end
fprintf('%s\n\n', repmat('=', 1, 60));

% ── Figures ───────────────────────────────────────────────────────────────────
fig = figure('Name', 'Accelerometer Gap Analysis', ...
             'NumberTitle', 'off', 'Position', [100 100 1200 700]);

% -- 1. Inter-sample dt over time ---
ax1 = subplot(3, 1, 1);
plot(times(1:end-1), diffs * 1000, 'Color', [0.2 0.5 0.9], 'LineWidth', 0.5);
hold on;
yline(EXPECTED_DT * 1000, 'k--', 'Expected dt', 'LabelHorizontalAlignment', 'left');
yline(GAP_THRESH  * 1000, 'r--', 'Gap threshold', 'LabelHorizontalAlignment', 'left');
if ~isempty(gap_idx)
    scatter(times(gap_idx), diffs(gap_idx) * 1000, 40, 'r', 'filled');
end
xlabel('Time (s, Unix)');
ylabel('dt (ms)');
title(sprintf('Inter-sample interval  |  %d gaps detected', numel(gap_idx)));
legend('dt', 'Expected', 'Threshold', 'Gaps', 'Location', 'northeast');
grid on;

% -- 2. Gap sizes bar chart (top 20) ---
ax2 = subplot(3, 1, 2);
if ~isempty(gap_idx)
    top20    = min(20, numel(gap_idx));
    [sorted_gaps, sort_ord] = sort(diffs(gap_idx) * 1000, 'descend');
    bar(sorted_gaps(1:top20), 'FaceColor', [0.85 0.33 0.1]);
    xlabel('Gap rank');
    ylabel('Gap size (ms)');
    title(sprintf('Top %d gaps by size', top20));
    grid on;
else
    text(0.5, 0.5, 'No gaps detected', 'HorizontalAlignment', 'center', ...
         'Units', 'normalized', 'FontSize', 14, 'Color', [0.2 0.7 0.2]);
    title('Gaps');
    axis off;
end

% -- 3. dt histogram ---
ax3 = subplot(3, 1, 3);
% Clip extreme outliers for readability
clip_ms  = EXPECTED_DT * 1000 * 5;   % 5× expected dt
dt_plot  = diffs(diffs * 1000 < clip_ms) * 1000;
histogram(dt_plot, 100, 'FaceColor', [0.2 0.6 0.5], 'EdgeColor', 'none');
xline(EXPECTED_DT * 1000, 'r-', 'Expected', 'LabelHorizontalAlignment', 'left', 'LineWidth', 1.5);
xlabel('dt (ms)');
ylabel('Count');
title(sprintf('dt distribution (clipped at %.1f ms, %d outliers not shown)', ...
    clip_ms, sum(diffs * 1000 >= clip_ms)));
grid on;

sgtitle(sprintf('Gap Analysis — %s\nDuration: %.1f s | Present: %d | Missing: %d (%.2f%%)', ...
    filepath, duration, total_samp, missing, pct_missing), ...
    'Interpreter', 'none');

end