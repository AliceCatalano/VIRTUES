%% VIRTUES -- Cross-Participant Collision Count Comparison
%
% HOW TO USE
% ----------
%   FULL RUN    Run the whole script. On first run it loads your existing
%               .mat files and processes only the subjects not yet in them.
%               On every subsequent run it does the same -- existing rows
%               are never touched.
%
%   ADD SUBJECTS  Append new IDs anywhere in 'participants', re-run.
%               The new subjects are detected automatically and appended.
%
%   PLOTS ONLY  Run Section 3 alone (Ctrl+Enter inside the section).
%               It loads the .mat files and plots without recomputing.
%
%   FORCE REDO  Set FORCE_RECOMPUTE = true to ignore existing data.

%% SECTION 1 -- CONFIGURATION

BASE_FOLDER = '/run/user/1003/gvfs/smb-share:server=shark,share=acatalano';
SAVE_PATH   = '/home/acatalano/Desktop/Virtues';

% Paths to your three existing matrix files
FILE_BASELINE = fullfile(SAVE_PATH, 'CollisionBaseline.mat');
FILE_TEST     = fullfile(SAVE_PATH, 'CollisionTest.mat');
FILE_LEVEL    = fullfile(SAVE_PATH, 'CollisionLevel.mat');
% File that tracks which participants are already stored in those matrices.
% Created automatically on first run -- you don't need to make it yourself.
FILE_DONE     = fullfile(SAVE_PATH, 'CollisionDone.mat');

% Full ordered list of ALL participants (done + new).
% Just keep appending new IDs here; the script handles the rest.
participants = {'s02N','s05N','s07N','s09N','s11N','s14N','s15H', 's16N','s18N', 's20N','s22N','s24N','s27N','s28N','s30N','s32N','s34N','s36N','s37N','s39N','s42N','s43N','s44N','s46N','s48N'...
                's03H','s04H','s06H','s08H','s10H','s12H','s13H', 's17H','s19H', 's21H','s23H','s25H','s26H','s29H','s31H','s33H','s35H','s38H','s40H','s41H','s45H','s47H'};

nLevels    = 5;
nRepsLevel = 10;
nBaseline  = 10;
nTest      = 2;

accel_fs          = 3000;
bp_low            = 80;
bp_high           = 1000;
n_baseline_offset = 50;
V2G               = 1 / 0.4;
target_fs_display = 500;

accel_sensitivity = 40;
thresh_percentile = 99.5;

% Audio channels are auto-detected per file.
% Known layouts:  old: ch12 ch13 ch14 ch16 ch17 ch18
%                 new: ch11 ch12 ch13 ch14 ch16 ch17
audio_bp_low      = 80;
audio_bp_high     = 1000;
audio_sensitivity = 15;
audio_rms_win_sec = 0.02;

min_distance_sec = 2.0;
merge_window_sec = 0.50;

YLIM_COUNT      = [0, 20];
FORCE_RECOMPUTE = false;

%% SECTION 2 -- COMPUTE  (incremental)
% Load existing matrices from your .mat files.
% If FORCE_RECOMPUTE, treat everything as new.
if FORCE_RECOMPUTE
    fprintf('FORCE_RECOMPUTE=true -- all subjects will be reprocessed.\n');
    participants_done  = {};
    CollisionsBaseline = nan(0, nBaseline);
    CollisionsTest     = nan(0, nTest);
    CollisionsLevels   = nan(0, nLevels, nRepsLevel);

else
    % Load the matrices that already exist
    if isfile(FILE_BASELINE)
        S = load(FILE_BASELINE, 'CollisionsBaseline');
        CollisionsBaseline = S.CollisionsBaseline;
    else
        CollisionsBaseline = nan(0, nBaseline);
    end

    if isfile(FILE_TEST)
        S = load(FILE_TEST, 'CollisionsTest');
        CollisionsTest = S.CollisionsTest;
    else
        CollisionsTest = nan(0, nTest);
    end

    if isfile(FILE_LEVEL)
        S = load(FILE_LEVEL, 'CollisionsLevels');
        CollisionsLevels = S.CollisionsLevels;
    else
        CollisionsLevels = nan(0, nLevels, nRepsLevel);
    end

    % Load the list of participants whose rows are already in those matrices. On the very first run after switching to this script, FILE_DONE won't
    % exist yet -- in that case we infer from the number of rows already tored and assume they match the first N participants in your list.
    if isfile(FILE_DONE)
        D = load(FILE_DONE, 'participants_done');
        participants_done = D.participants_done;
    else
        nRows = size(CollisionsBaseline, 1);
        if nRows > 0 && nRows <= numel(participants)
            participants_done = participants(1:nRows);
            fprintf(['FILE_DONE not found. Inferring that the first %d participants\n' ...
                     'in your list match the %d existing rows in the matrices.\n' ...
                     'If that is wrong, correct the order of ''participants'' or\n' ...
                     'set FORCE_RECOMPUTE=true to rebuild from scratch.\n'], nRows, nRows);
        else
            participants_done = {};
        end
    end
end

% Identify which subjects in the requested list are missing
is_new   = ~ismember(participants, participants_done);
new_subj = participants(is_new);
nNew     = numel(new_subj);

% Authoritative ordered list: existing order first, new subjects appended
all_participants = [participants_done, new_subj];
nSubj = numel(all_participants);

if nNew > 0
    % Expand matrices with NaN rows for the new subjects
    CollisionsBaseline = [CollisionsBaseline; nan(nNew, nBaseline)];
    CollisionsTest     = [CollisionsTest;     nan(nNew, nTest)];
    CollisionsLevels   = cat(1, CollisionsLevels, nan(nNew, nLevels, nRepsLevel));
    fprintf('Already stored: %d subjects.\nNew to process : %s\n',  numel(participants_done), strjoin(new_subj, ', '));
else
    fprintf('All %d subjects already stored -- nothing to compute.\n', nSubj);
    fprintf('Run Section 3 for plots, or set FORCE_RECOMPUTE=true to redo.\n');
end

participants = all_participants;   % single authoritative list from here on
any_new_computed = false;

% Main loop -- only runs for new subjects
for si = 1:nSubj
    subj = participants{si};

    % Skip subjects already in the matrices
    if ismember(subj, participants_done) && ~FORCE_RECOMPUTE
        fprintf('  [SKIP] %s\n', subj);
        continue
    end

    subj_folder = fullfile(BASE_FOLDER, ['subject_' subj]);
    if ~isfolder(subj_folder)
        fprintf('[WARNING] Folder not found: %s\n', subj_folder);
        continue
    end

    fprintf('\nProcessing %s ...\n', subj);
    any_new_computed = true;

    % BASELINE
    baseline_col = 0;
    for acq = 1:2
        bl_folder = fullfile(subj_folder, sprintf('Baseline%d', acq));
        if ~isfolder(bl_folder), continue; end
        for lv = 1:nLevels
            baseline_col = baseline_col + 1;
            folder = fullfile(bl_folder, sprintf('Level%d', lv));
            n = count_collisions_in_folder(folder, accel_fs, bp_low, bp_high, ...
                    n_baseline_offset, V2G, target_fs_display, ...
                    accel_sensitivity, thresh_percentile, ...
                    audio_bp_low, audio_bp_high, audio_sensitivity, ...
                    audio_rms_win_sec, min_distance_sec, merge_window_sec);
            CollisionsBaseline(si, baseline_col) = n;
            if ~isnan(n), fprintf('  Baseline%d/Level%d : %d\n', acq, lv, n);
            else,         fprintf('  Baseline%d/Level%d : MISSING\n', acq, lv); end
        end
    end

    % TEST
    for acq = 1:nTest
        folder = fullfile(subj_folder, sprintf('Test%d', acq));
        n = count_collisions_in_folder(folder, accel_fs, bp_low, bp_high, ...
                n_baseline_offset, V2G, target_fs_display, ...
                accel_sensitivity, thresh_percentile, ...
                audio_bp_low, audio_bp_high, audio_sensitivity, ...
                audio_rms_win_sec, min_distance_sec, merge_window_sec);
        CollisionsTest(si, acq) = n;
        if ~isnan(n), fprintf('  Test%d : %d\n', acq, n);
        else,         fprintf('  Test%d : MISSING\n', acq); end
    end

    % LEVEL REPETITIONS
    for lv = 1:nLevels
        lv_folder = fullfile(subj_folder, sprintf('level_L%d', lv));
        if ~isfolder(lv_folder)
            fprintf('  level_L%d : folder not found\n', lv); continue
        end
        for rep = 1:nRepsLevel
            folder = resolve_rep_folder(lv_folder, rep);
            n = count_collisions_in_folder(folder, accel_fs, bp_low, bp_high, ...
                    n_baseline_offset, V2G, target_fs_display, ...
                    accel_sensitivity, thresh_percentile, ...
                    audio_bp_low, audio_bp_high, audio_sensitivity, ...
                    audio_rms_win_sec, min_distance_sec, merge_window_sec);
            CollisionsLevels(si, lv, rep) = n;
            [~, used] = fileparts(folder);
            if ~isnan(n), fprintf('  L%d rep%02d [%s] : %d\n', lv, rep, used, n);
            else,         fprintf('  L%d rep%02d : MISSING\n', lv, rep); end
        end
    end

end

% ------------------------------------------------------------------
% Save back to the original three .mat files + update FILE_DONE
% ------------------------------------------------------------------
if any_new_computed || FORCE_RECOMPUTE
    participants_done = participants;

    CollisionsBaseline = CollisionsBaseline; %#ok<ASGSL>
    save(FILE_BASELINE, 'CollisionsBaseline');

    CollisionsTest = CollisionsTest; %#ok<ASGSL>
    save(FILE_TEST, 'CollisionsTest');

    CollisionsLevels = CollisionsLevels; %#ok<ASGSL>
    save(FILE_LEVEL, 'CollisionsLevels');

    save(FILE_DONE, 'participants_done');

    fprintf('\nMatrices saved to:\n  %s\n  %s\n  %s\n', ...
            FILE_BASELINE, FILE_TEST, FILE_LEVEL);
    fprintf('Participant index saved to:\n  %s\n', FILE_DONE);
end

fprintf('\n========== Matrix summary ==========\n');
fprintf('Subjects           : %d\n',           numel(participants));
fprintf('CollisionsBaseline : %d x %d\n',      size(CollisionsBaseline));
fprintf('CollisionsTest     : %d x %d\n',      size(CollisionsTest));
fprintf('CollisionsLevels   : %d x %d x %d\n', size(CollisionsLevels));

%% ========================================================================
%  SECTION 3 -- PLOTS  (run this section alone to regenerate figures)
% =========================================================================

% Load from files if matrices are not already in the workspace
if ~exist('CollisionsBaseline','var') || ~exist('participants','var')
    fprintf('Loading matrices for plotting...\n');
    S1 = load(FILE_BASELINE, 'CollisionsBaseline');
    S2 = load(FILE_TEST,     'CollisionsTest');
    S3 = load(FILE_LEVEL,    'CollisionsLevels');
    D  = load(FILE_DONE,     'participants_done');
    CollisionsBaseline = S1.CollisionsBaseline;
    CollisionsTest     = S2.CollisionsTest;
    CollisionsLevels   = S3.CollisionsLevels;
    participants       = D.participants_done;
end

nSubj_p      = numel(participants);
nBaseline_p  = size(CollisionsBaseline, 2);
nTest_p      = size(CollisionsTest,     2);
nLevels_p    = size(CollisionsLevels,   2);
nRepsLevel_p = size(CollisionsLevels,   3);
YLIM_p       = [0, 20];
colors_p     = lines(nSubj_p);

% Baseline
figure('Name','Collisions -- Baseline Trials','Position',[50 50 900 500]);
hold on;
for si = 1:nSubj_p
    plot(1:nBaseline_p, CollisionsBaseline(si,:), '-o', ...
        'Color', colors_p(si,:), 'LineWidth', 1.4, ...
        'MarkerFaceColor', colors_p(si,:), 'DisplayName', participants{si});
end
plot_mean_line(CollisionsBaseline, [0 0 0]);
xlabel('Baseline repetition'); ylabel('Collision count');
title('Baseline -- detected collisions');
ylim(YLIM_p); xlim([0.5, nBaseline_p+0.5]); xticks(1:nBaseline_p);
legend('Location','best','FontSize',8); grid on;

% Test
figure('Name','Collisions -- Test Trials','Position',[60 60 500 450]);
hold on;
for si = 1:nSubj_p
    plot(1:nTest_p, CollisionsTest(si,:), '-o', ...
        'Color', colors_p(si,:), 'LineWidth', 1.4, ...
        'MarkerFaceColor', colors_p(si,:), 'DisplayName', participants{si});
end
plot_mean_line(CollisionsTest, [0 0 0]);
xlabel('Test acquisition'); ylabel('Collision count');
title('Test -- detected collisions');
ylim(YLIM_p); xlim([0.5, nTest_p+0.5]); xticks(1:nTest_p);
legend('Location','best','FontSize',8); grid on;

% Levels
for lv = 1:nLevels_p
    figure('Name', sprintf('Collisions -- Level %d', lv), ...
           'Position', [70+(lv-1)*30, 70+(lv-1)*30, 900, 500]);
    hold on;
    lv_data = squeeze(CollisionsLevels(:, lv, :));
    for si = 1:nSubj_p
        plot(1:nRepsLevel_p, lv_data(si,:), '-o', ...
            'Color', colors_p(si,:), 'LineWidth', 1.4, ...
            'MarkerFaceColor', colors_p(si,:), 'DisplayName', participants{si});
    end
    plot_mean_line(lv_data, [0 0 0]);
    xlabel('Repetition'); ylabel('Collision count');
    title(sprintf('Level %d -- detected collisions', lv));
    ylim(YLIM_p); xlim([0.5, nRepsLevel_p+0.5]); xticks(1:nRepsLevel_p);
    legend('Location','best','FontSize',8); grid on;
end

fprintf('\nAll plots generated.\n');

%% ========================================================================
%  LOCAL FUNCTIONS
% =========================================================================

function folder = resolve_rep_folder(level_folder, rep)
    redo = fullfile(level_folder, sprintf('rep_%02d_R', rep));
    orig = fullfile(level_folder, sprintf('rep_%02d',   rep));
    if isfolder(redo), folder = redo; else, folder = orig; end
end

function ch = select_audio_channels(col_names)
% Auto-detects which known channel layout is present in this audio.csv.
    new_layout = {'ch11','ch12','ch13','ch14','ch16','ch17'};
    old_layout = {'ch12','ch13','ch14','ch16','ch17','ch18'};
    ch_new = intersect(new_layout, col_names, 'stable');
    ch_old = intersect(old_layout, col_names, 'stable');
    if numel(ch_new) >= numel(ch_old), ch = ch_new; else, ch = ch_old; end
end

function n_col = count_collisions_in_folder(folder,   accel_fs, bp_low, bp_high, n_baseline_offset, V2G, target_fs_display, ...
        accel_sensitivity, thresh_percentile, audio_bp_low, audio_bp_high, audio_sensitivity, audio_rms_win_sec, ...
        min_distance_sec, merge_window_sec)

    n_col = NaN;
    if ~isfolder(folder), return; end

    accel_file  = fullfile(folder, 'accel.csv');
    events_file = fullfile(folder, 'events.csv');
    audio_file  = fullfile(folder, 'audio.csv');

    if ~isfile(accel_file) || ~isfile(events_file), return; end
    try
        nidaq  = readtable(accel_file);
        events = readtable(events_file);
    catch; return; end

    [t_start_unix, t_end_unix] = parse_trial_window(events);
    if isnan(t_start_unix) || isnan(t_end_unix), return; end

    raw_t  = nidaq.recording_time;
    n_samp = height(nidaq);
    anchor_idx = [1; find(diff(raw_t) ~= 0) + 1];
    anchor_t   = raw_t(anchor_idx);
    t_recon    = zeros(n_samp, 1);
    for a = 1:numel(anchor_idx)
        i0 = anchor_idx(a);
        if a < numel(anchor_idx)
            i1 = anchor_idx(a+1)-1; npts = i1-i0+1;
            t_recon(i0:i1) = anchor_t(a) + (0:npts-1)' * ...
                             (anchor_t(a+1)-anchor_t(a)) / npts;
        else
            i1 = n_samp; npts = i1-i0+1;
            t_recon(i0:i1) = anchor_t(a) + (0:npts-1)' / accel_fs;
        end
    end

    t0_unix     = min(t_recon);
    t_rel       = t_recon - t0_unix;
    t_win_start = t_start_unix - t0_unix;
    t_win_end   = t_end_unix   - t0_unix;

    xL = (nidaq.ai9  - mean(nidaq.ai9(1:n_baseline_offset)))  * V2G;
    yL = (nidaq.ai10 - mean(nidaq.ai10(1:n_baseline_offset))) * V2G;
    zL = (nidaq.ai11 - mean(nidaq.ai11(1:n_baseline_offset))) * V2G;
    xR = (nidaq.ai12 - mean(nidaq.ai12(1:n_baseline_offset))) * V2G;
    yR = (nidaq.ai13 - mean(nidaq.ai13(1:n_baseline_offset))) * V2G;
    zR = (nidaq.ai14 - mean(nidaq.ai14(1:n_baseline_offset))) * V2G;

    mag_native = max(sqrt(xL.^2+yL.^2+zL.^2), sqrt(xR.^2+yR.^2+zR.^2));
    ds_factor  = max(1, round(accel_fs / target_fs_display));
    [mag_ds, t_ds] = antialias_downsample(mag_native, t_rel, accel_fs, target_fs_display, 4, ds_factor);

    min_dist_smp = round(min_distance_sec * target_fs_display);
    drv_a    = [0; abs(diff(mag_ds))];
    thresh_a = max(median(drv_a) + accel_sensitivity*mad(drv_a,1), ...
                   prctile(drv_a, thresh_percentile));
    accel_times = detect_peaks(drv_a, t_ds, thresh_a, min_dist_smp);

    audio_times = [];
    if isfile(audio_file)
        try
            audio      = readtable(audio_file);
            present_ch = select_audio_channels(audio.Properties.VariableNames);
            if ~isempty(present_ch)
                t_audio  = audio.recording_time - t0_unix;
                fs_audio = 1 / median(diff(t_audio(diff(t_audio) > 0)));
                audio_sum = zeros(height(audio), 1);
                for k = 1:numel(present_ch)
                    raw = double(audio.(present_ch{k}));
                    raw = raw - mean(raw, 'omitnan');
                    if numel(raw) > 10*fs_audio
                        raw = bandpass(raw, [audio_bp_low audio_bp_high], fs_audio);
                    end
                    audio_sum = audio_sum + raw;
                end
                rms_win     = max(3, round(fs_audio * audio_rms_win_sec));
                env         = sqrt(movmean(audio_sum.^2, rms_win));
                drv_au      = [0; abs(diff(env))];
                thresh_au   = median(drv_au) + audio_sensitivity*mad(drv_au,1);
                min_dist_au = round(min_distance_sec * fs_audio);
                audio_times = detect_peaks(drv_au, t_audio, thresh_au, min_dist_au);
            end
        catch; end
    end

    % Audio-primary merge: accel-only events are discarded
    if isempty(audio_times)
        merged_times  = accel_times;
        merged_source = ones(numel(accel_times), 1);
    else
        merged_times  = audio_times;
        merged_source = 2 * ones(numel(audio_times), 1);
        for ai = 1:numel(accel_times)
            diffs = abs(audio_times - accel_times(ai));
            [mn, idx] = min(diffs);
            if mn <= merge_window_sec
                merged_source(idx) = 3;
            end
        end
    end

    in_window      = merged_times >= t_win_start & merged_times <= t_win_end;
    n_col          = sum(in_window);
    collision_unix = t0_unix + merged_times(in_window);
    writematrix(collision_unix, fullfile(folder, 'collision_unix.csv'));
end

function [t_start, t_end] = parse_trial_window(events)
    t_start = NaN; t_end = NaN;
    if isempty(events), return; end
    if ismember('recording_time', events.Properties.VariableNames)
        t_col = events.recording_time;
    else
        num_cols = varfun(@isnumeric, events, 'OutputFormat','uniform');
        if ~any(num_cols), return; end
        t_col = events{:, find(num_cols,1)};
    end
    if iscell(t_col), t_col = str2double(t_col); end
    if ~ismember('data', events.Properties.VariableNames), return; end
    end_mask   = contains(events.data,'END')   & ~contains(events.data,'START');
    start_mask = contains(events.data,'START') & ~contains(events.data,'END');
    kb_mask    = contains(events.data,'[Publisher]') & contains(events.data,'event_spacebar');
    if ~any(end_mask), return; end
    t_end = t_col(find(end_mask,1,'last'));
    kb_before_end = kb_mask & (t_col < t_end);
    if any(kb_before_end)
        t_start = t_col(find(kb_before_end,1,'last'));
    elseif any(start_mask)
        t_start = t_col(find(start_mask,1,'first'));
    end
end

function [sig_ds, t_ds] = antialias_downsample(sig, t, fs_in, fs_out, order, ds_factor)
    Wn = min(fs_out/2*0.9/(fs_in/2), 0.99);
    [b, a] = butter(order, Wn, 'low');
    sig_filt = filtfilt(b, a, double(sig));
    n_ds = floor(numel(sig_filt)/ds_factor);
    sig_ds = zeros(n_ds,1); t_ds = zeros(n_ds,1);
    for k = 1:n_ds
        idx = (k-1)*ds_factor+1 : k*ds_factor;
        sig_ds(k) = mean(sig_filt(idx)); t_ds(k) = t(idx(1));
    end
end

function times = detect_peaks(drv, t, threshold, min_dist_smp)
    above = drv > threshold;
    edges = find(diff([0; above]) == 1);
    if isempty(edges), times = []; return; end
    keep = true(size(edges));
    for i = 1:numel(edges)
        if ~keep(i), continue; end
        for j = i+1:numel(edges)
            if ~keep(j), continue; end
            if edges(j)-edges(i) < min_dist_smp
                if drv(edges(j)) > drv(edges(i)), keep(i) = false;
                else, keep(j) = false; end
            else, break; end
        end
    end
    times = t(edges(keep));
end

function plot_mean_line(mat, col)
    mn = mean(mat, 1, 'omitnan');
    valid = ~isnan(mn);
    if any(valid)
        plot(find(valid), mn(valid), '--s', 'Color', col, 'LineWidth', 2.2, ...
            'MarkerSize', 6, 'MarkerFaceColor', col, 'DisplayName', 'Group mean');
    end
end