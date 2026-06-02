%  VIRTUES — Build Power Analysis Dataset
%  Reads the existing folder structure (same logic as DurationMatrices.m and Collisions.m) and saves all
%  outcome matrices to a single  power_analysis_data.mat file ready to drop into  power_analysis_haptic.m.
%
%  Output matrices (all NaN-padded for missing trials):
%
% DURATION  
%    DurationBaseline   [nSubj x 10]   Baseline acq 1-2, L1-5
%    DurationTest       [nSubj x 2]    Test acq 1-2
%    DurationLevels     [nSubj x 5 x 10] Level x Rep (Phase 3)
%
% COLLISIONS 
%    CollisionsBaseline [nSubj x 10]
%    CollisionsTest     [nSubj x 2]
%    CollisionsLevels   [nSubj x 5 x 10]
%
% LONG-FORMAT TABLE  (for direct use in power_analysis_haptic.m)
%    T_long   table with columns:
%       Subject  Haptic  Level  Repetition  Duration  Collisions
%       (one row per Phase-3 observation; NaN rows kept)
%
%  METADATA  
%    participants  cell array of IDs
%    group         cell array: 'HF' or 'NHF' per subject
%    Haptic_num    double vector: 1=HF, 0=NHF

clear; clc;

% CONFIGURATION  (edit paths / IDs here)

BASE_FOLDER  = '/media/acatalano/Volume/VIRTUES';
SAVE_PATH = fullfile('/home/acatalano/Desktop/Virtues', 'power_analysis_data.mat');
% Subject IDs exactly as used in the folder names  subject_<ID> Subjects ending in 'H' → HF group;  ending in 'N' → NHF group
participants = {'s02N','s05N','s07N','s09N','s11N','s14N','s03H','s04H','s06H','s08H','s10H','s12H','s13H','s14N','s15H', ...
                's16N','s17H','s18N','s19H','s20N','s21H','s22N','s23H','s25H','s26H','s27N','s28N','s29H'}; 

nSubj      = numel(participants);
nLevels    = 5;
nRepsLevel = 10;   % repetitions per level  (Phase 3)
nBaseline  = 10;   % 2 acquisitions × 5 levels
nTest      = 2;    % post-training test acquisitions
 
%  Collision detection settings (keep identical to Collisions.m) 
accel_fs          = 3000;
bp_low            = 80;
bp_high           = 1000;
n_baseline_offset = 50;
V2G               = 1 / 0.4;
target_fs_display = 500;
accel_sensitivity  = 40;
thresh_percentile  = 99.5;
audio_channels    = {'ch12','ch13','ch14','ch16','ch17','ch18'};
audio_bp_low      = 80;
audio_bp_high     = 1000;
audio_sensitivity = 15;
audio_rms_win_sec = 0.02;
min_distance_sec  = 2.0;
merge_window_sec  = 0.50;
 
% DERIVE GROUP LABELS FROM PARTICIPANT IDs
group     = cell(nSubj, 1);
Haptic_num = zeros(nSubj, 1);
 
for si = 1:nSubj
    id = participants{si};
    if endsWith(id, 'H')
        group{si}     = 'HF';
        Haptic_num(si) = 1;
    else
        group{si}     = 'NHF';
        Haptic_num(si) = 0;
    end
end
 
fprintf('Group assignments:\n');
for si = 1:nSubj
    fprintf('  %-8s  %s\n', participants{si}, group{si});
end
 
% INITIALISE MATRICES
DurationBaseline   = nan(nSubj, nBaseline);
DurationTest       = nan(nSubj, nTest);
DurationLevels     = nan(nSubj, nLevels, nRepsLevel);
 
CollisionsBaseline = nan(nSubj, nBaseline);
CollisionsTest     = nan(nSubj, nTest);
CollisionsLevels   = nan(nSubj, nLevels, nRepsLevel);
 
% POPULATE MATRICES (subject loop)
 
for si = 1:nSubj
 
    subj        = participants{si};
    subj_folder = fullfile(BASE_FOLDER, ['subject_' subj]);
 
    if ~isfolder(subj_folder)
        fprintf('[WARNING] Subject folder not found: %s — skipping.\n', subj_folder);
        continue
    end
    fprintf('\n[%02d/%02d] Processing %s (%s) ...\n', si, nSubj, subj, group{si});
 
    % BASELINE  (Baseline1 → cols 1-5, Baseline2 → cols 6-10) 
    baseline_col = 0;
    for acq = 1:2
        bl_folder = fullfile(subj_folder, sprintf('Baseline%d', acq));
        if ~isfolder(bl_folder)
            fprintf('  Baseline%d folder not found — skipping.\n', acq);
            baseline_col = baseline_col + nLevels;   % keep column alignment
            continue
        end
        for lv = 1:nLevels
            baseline_col = baseline_col + 1;
            folder = fullfile(bl_folder, sprintf('Level%d', lv));
 
            % Duration
            dur = get_trial_duration(folder);
            if ~isnan(dur)
                DurationBaseline(si, baseline_col) = dur;
            end
 
            % Collisions
            nc = count_collisions_in_folder(folder, accel_fs, bp_low, bp_high, n_baseline_offset, V2G, ...
                    target_fs_display, accel_sensitivity, thresh_percentile,audio_channels, audio_bp_low, audio_bp_high, ...
                    audio_sensitivity, audio_rms_win_sec, min_distance_sec, merge_window_sec);
            if ~isnan(nc)
                CollisionsBaseline(si, baseline_col) = nc;
            end
 
            fprintf('  Baseline%d/L%d : dur=%.1fs  col=%s\n', ...
                acq, lv, ifnan(dur, 'NaN', sprintf('%.1f', dur)), ifnan(nc,  'NaN', sprintf('%d',   nc)));
        end
    end
 
    % TEST
  
    for acq = 1:nTest
        folder = fullfile(subj_folder, sprintf('Test%d', acq));
 
        dur = get_trial_duration(folder);
        if ~isnan(dur), DurationTest(si, acq) = dur; end
 
        nc = count_collisions_in_folder(folder, accel_fs, bp_low, bp_high, n_baseline_offset, V2G, ...
                target_fs_display, accel_sensitivity, thresh_percentile,audio_channels, audio_bp_low, audio_bp_high, ...
                audio_sensitivity, audio_rms_win_sec, min_distance_sec, merge_window_sec);
        if ~isnan(nc), CollisionsTest(si, acq) = nc; end
 
        fprintf('  Test%d : dur=%s  col=%s\n', acq, ...
            ifnan(dur, 'NaN', sprintf('%.1f', dur)), ...
            ifnan(nc,  'NaN', sprintf('%d',   nc)));
    end
 
    % LEVEL REPETITIONS
     
    for lv = 1:nLevels
        lv_folder = fullfile(subj_folder, sprintf('level_L%d', lv));
        if ~isfolder(lv_folder)
            fprintf('  level_L%d : folder not found — skipping.\n', lv);
            continue
        end
        for rep = 1:nRepsLevel
            folder = resolve_rep_folder(lv_folder, rep);
 
            dur = get_trial_duration(folder);
            if ~isnan(dur), DurationLevels(si, lv, rep) = dur; end
 
            nc = count_collisions_in_folder(folder, accel_fs, bp_low, bp_high, n_baseline_offset, V2G, ...
                    target_fs_display, accel_sensitivity, thresh_percentile, audio_channels, audio_bp_low, audio_bp_high, ...
                    audio_sensitivity, audio_rms_win_sec, min_distance_sec, merge_window_sec);
            if ~isnan(nc), CollisionsLevels(si, lv, rep) = nc; end
        end
        fprintf('  L%d : %d/%d durations, %d/%d collisions found\n', lv, ...
            sum(~isnan(DurationLevels(si, lv, :))), nRepsLevel, ...
            sum(~isnan(CollisionsLevels(si, lv, :))), nRepsLevel);
    end
end
 
fprintf('\n Matrix assembly complete \n');
 
% BUILD LONG-FORMAT TABLE FOR POWER ANALYSIS
 
% One row per (Subject x Level x Repetition) observation in Phase 3.
% This table maps directly onto the LMM in power_analysis_haptic.m: Y ~ Haptic * Repetition + Level + (1 + Repetition | Subject)
 
nRows = nSubj * nLevels * nRepsLevel;
 
subj_col  = zeros(nRows, 1);
haptic_col = zeros(nRows, 1);
level_col = zeros(nRows, 1);
rep_col   = zeros(nRows, 1);
dur_col   = nan(nRows, 1);
col_col   = nan(nRows, 1);
 
row = 0;
for si = 1:nSubj
    for lv = 1:nLevels
        for rep = 1:nRepsLevel
            row = row + 1;
            subj_col(row)   = si;
            haptic_col(row) = Haptic_num(si);
            level_col(row)  = lv;
            rep_col(row)    = rep;
            dur_col(row)    = DurationLevels(si, lv, rep);
            col_col(row)    = CollisionsLevels(si, lv, rep);
        end
    end
end
 
T_long = table(subj_col, haptic_col, level_col, rep_col, dur_col, col_col, ...
    'VariableNames', {'Subject','Haptic','Level','Repetition','Duration','Collisions'});
 
% Quick summary
n_obs_dur = sum(~isnan(T_long.Duration));
n_obs_col = sum(~isnan(T_long.Collisions));
fprintf('\nLong-format table: %d rows total\n', nRows);
fprintf('  Duration  : %d/%d observations available (%.1f%%)\n', ...
        n_obs_dur, nRows, 100*n_obs_dur/nRows);
fprintf('  Collisions: %d/%d observations available (%.1f%%)\n', ...
        n_obs_col, nRows, 100*n_obs_col/nRows);
 
 
% PRINT DESCRIPTIVE SUMMARY PER GROUP
fprintf('\n Descriptive summary (Phase 3, group means ± SD) \n');
for g = {'NHF','HF'}
    gname = g{1};
    mask  = strcmp(group, gname);
    dur_g = DurationLevels(mask, :, :);
    col_g = CollisionsLevels(mask, :, :);
    fprintf('  %s  (n=%d)  Duration: %.1f ± %.1f s   Collisions: %.1f ± %.1f\n', ...
        gname, sum(mask),mean(dur_g(:), 'omitnan'), std(dur_g(:), 'omitnan'), mean(col_g(:), 'omitnan'), std(col_g(:), 'omitnan'));
end
 
% ESTIMATE LMM PARAMETERS FOR POWER ANALYSIS
 
% Fit the SAP §4.2 model to the preliminary Duration data and print the parameter estimates you can paste into power_analysis_haptic.m (Section 1).
 
fprintf('\n LMM parameter estimates from preliminary data \n');
fprintf('    (for Duration — repeat for Collisions if needed)\n\n');
 
% Drop rows with missing Duration
T_fit = T_long(~isnan(T_long.Duration), :);
 
if height(T_fit) > 20    % need enough data to fit
    try
        lme = fitlme(T_fit,'Duration ~ Haptic * Repetition + Level + (1 + Repetition | Subject)', 'FitMethod', 'REML');
 
        fe = fixedEffects(lme);
        fprintf('  beta_0           = %.4f   (grand intercept)\n',        fe(1));
        fprintf('  beta_haptic      = %.4f   (HF vs NHF)\n',              fe(2));
        fprintf('  beta_rep         = %.4f   (learning slope)\n',         fe(3));
        fprintf('  beta_level       = %.4f   (difficulty)\n',             fe(4));
        fprintf('  beta_interaction = %.4f   (Haptic x Repetition) <-- KEY\n', fe(end));
 
        psi   = covarianceParameters(lme);
        sd_u0 = sqrt(psi{1}(1,1));
        sd_u1 = sqrt(psi{1}(2,2));
        cor_u = psi{1}(1,2) / (sd_u0 * sd_u1 + eps);
        sd_e  = sqrt(lme.MSE);
        icc_est = sd_u0^2 / (sd_u0^2 + sd_e^2);
 
        fprintf('\n  sd_subj_intercept = %.4f\n', sd_u0);
        fprintf('  sd_subj_slope     = %.4f\n', sd_u1);
        fprintf('  cor_int_slope     = %.4f\n', cor_u);
        fprintf('  sd_residual       = %.4f\n', sd_e);
        fprintf('  estimated ICC     = %.4f\n', icc_est);
 
        % Store for saving
        lmm_params = struct('beta_0', fe(1), 'beta_haptic', fe(2), ...
            'beta_rep', fe(3), 'beta_level', fe(4), ...
            'beta_interaction', fe(end), ...
            'sd_subj_intercept', sd_u0, 'sd_subj_slope', sd_u1, ...
            'cor_int_slope', cor_u, 'sd_residual', sd_e, 'icc', icc_est);
    catch ME
        fprintf('  [WARNING] LMM fit failed: %s\n', ME.message);
        fprintf('  Try fitting manually after loading the .mat file.\n');
        lmm_params = struct();
    end
else
    fprintf('  [SKIP] Too few complete observations to fit LMM (%d rows).\n', height(T_fit));
    lmm_params = struct();
end
 
 
% SAVE .mat FILE
 
 
save(SAVE_PATH, 'participants', 'group', 'Haptic_num', ...
    'nSubj', 'nLevels', 'nRepsLevel', 'nBaseline', 'nTest', ...
    'DurationBaseline',   'DurationTest',   'DurationLevels', ...
    'CollisionsBaseline', 'CollisionsTest', 'CollisionsLevels', ...
    'T_long', 'lmm_params');
 
fprintf('\n✓ Saved: %s\n', SAVE_PATH);
fprintf('  Variables:\n');
fprintf('    DurationBaseline   [%dx%d]\n',   size(DurationBaseline));
fprintf('    DurationTest       [%dx%d]\n',   size(DurationTest));
fprintf('    DurationLevels     [%dx%dx%d]\n', size(DurationLevels));
fprintf('    CollisionsBaseline [%dx%d]\n',   size(CollisionsBaseline));
fprintf('    CollisionsTest     [%dx%d]\n',   size(CollisionsTest));
fprintf('    CollisionsLevels   [%dx%dx%d]\n', size(CollisionsLevels));
fprintf('    T_long             [%dx%d table]\n', size(T_long));
fprintf('    lmm_params         (struct — paste into power_analysis_haptic.m)\n');
 
 
%  LOCAL HELPER FUNCTIONS
function folder = resolve_rep_folder(level_folder, rep)
% Use the _R (redo) folder if it exists, otherwise the original.
    redo = fullfile(level_folder, sprintf('rep_%02d_R', rep));
    orig = fullfile(level_folder, sprintf('rep_%02d',   rep));
    if isfolder(redo), folder = redo; else, folder = orig; end
end
 
function dur = get_trial_duration(folder_path)
% Returns duration (s) between TRIAL_START and TRIAL_END in events.csv.
    dur = NaN;
    if ~isfolder(folder_path), return; end
 
    events_file = fullfile(folder_path, 'events.csv');
    if ~isfile(events_file), return; end
 
    try
        events = readtable(events_file);
    catch
        return
    end
    if isempty(events), return; end
 
    % Timestamp column
    if ismember('recording_time', events.Properties.VariableNames)
        t_col = events.recording_time;
    else
        num_cols = varfun(@isnumeric, events, 'OutputFormat', 'uniform');
        if ~any(num_cols), return; end
        t_col = events{:, find(num_cols, 1)};
    end
    if iscell(t_col) || ischar(t_col), t_col = str2double(t_col); end
 
    if ~ismember('data', events.Properties.VariableNames), return; end
 
    % Start event: prefer event_spacebar; fall back to TRIAL_START
    start_mask    = contains(events.data, 'TRIAL_START');
    spacebar_mask = contains(events.data, 'event_spacebar');
    end_mask      = contains(events.data, 'TRIAL_END');
 
    if any(spacebar_mask)
        t_start = t_col(find(spacebar_mask, 1, 'first'));
    elseif any(start_mask)
        t_start = t_col(find(start_mask,    1, 'first'));
    else
        return   % no usable start event
    end
 
    if ~any(end_mask), return; end
    t_end = t_col(find(end_mask, 1, 'last'));
 
    if isnan(t_start) || isnan(t_end) || t_end <= t_start, return; end
    dur = t_end - t_start;
end
 
function n_col = count_collisions_in_folder(folder, accel_fs, bp_low, bp_high, n_baseline_offset, V2G, ...
        target_fs_display, accel_sensitivity, thresh_percentile, ...
        audio_channels, audio_bp_low, audio_bp_high, ...
        audio_sensitivity, audio_rms_win_sec, ...
        min_distance_sec, merge_window_sec)
% Detects collisions (audio-confirmed) — identical logic to Collisions.m.
 
    n_col = NaN;
    if ~isfolder(folder), return; end
 
    accel_file  = fullfile(folder, 'accel.csv');
    events_file = fullfile(folder, 'events.csv');
    audio_file  = fullfile(folder, 'audio.csv');
 
    if ~isfile(accel_file) || ~isfile(events_file), return; end
 
    try
        nidaq  = readtable(accel_file);
        events = readtable(events_file);
    catch
        return
    end
 
    % Trial window
    [t_trial_start_unix, t_trial_end_unix] = parse_trial_window(events);
    if isnan(t_trial_start_unix) || isnan(t_trial_end_unix), return; end
 
    % Reconstruct continuous timeline from recording_time
    raw_t    = nidaq.recording_time;
    n_samp   = height(nidaq);
    anchor_idx = [1; find(diff(raw_t) ~= 0) + 1];
    anchor_t   = raw_t(anchor_idx);
    t_recon    = zeros(n_samp, 1);
    for a = 1:numel(anchor_idx)
        i0 = anchor_idx(a);
        if a < numel(anchor_idx)
            i1 = anchor_idx(a+1) - 1;  n_seg = i1 - i0 + 1;
            t_recon(i0:i1) = anchor_t(a) + (0:n_seg-1)' * ...
                             (anchor_t(a+1) - anchor_t(a)) / n_seg;
        else
            i1 = n_samp;  n_seg = i1 - i0 + 1;
            t_recon(i0:i1) = anchor_t(a) + (0:n_seg-1)' / accel_fs;
        end
    end
 
    t0_unix     = min(t_recon);
    t_rel       = t_recon - t0_unix;
    t_win_start = t_trial_start_unix - t0_unix;
    t_win_end   = t_trial_end_unix   - t0_unix;
 
    % Accel magnitude
    xL = (nidaq.ai9  - mean(nidaq.ai9(1:n_baseline_offset)))  * V2G;
    yL = (nidaq.ai10 - mean(nidaq.ai10(1:n_baseline_offset))) * V2G;
    zL = (nidaq.ai11 - mean(nidaq.ai11(1:n_baseline_offset))) * V2G;
    xR = (nidaq.ai12 - mean(nidaq.ai12(1:n_baseline_offset))) * V2G;
    yR = (nidaq.ai13 - mean(nidaq.ai13(1:n_baseline_offset))) * V2G;
    zR = (nidaq.ai14 - mean(nidaq.ai14(1:n_baseline_offset))) * V2G;
 
    mag_native = max(sqrt(xL.^2 + yL.^2 + zL.^2), ...
                     sqrt(xR.^2 + yR.^2 + zR.^2));
 
    ds_factor = max(1, round(accel_fs / target_fs_display));
    [mag_ds, t_ds] = antialias_downsample(mag_native, t_rel, ...
                         accel_fs, target_fs_display, 4, ds_factor);
 
    min_dist_smp = round(min_distance_sec * target_fs_display);
    drv_a    = [0; abs(diff(mag_ds))];
    thresh_a = max(median(drv_a) + accel_sensitivity * mad(drv_a, 1), ...
                   prctile(drv_a, thresh_percentile));
    accel_times = detect_peaks(drv_a, t_ds, thresh_a, min_dist_smp);
 
    % Audio RMS envelope
    audio_times = [];
    if isfile(audio_file)
        try
            audio = readtable(audio_file);
            present_ch = intersect(audio_channels, audio.Properties.VariableNames);
            if ~isempty(present_ch)
                t_audio  = audio.recording_time - t0_unix;
                fs_audio = 1 / median(diff(t_audio(diff(t_audio) > 0)));
 
                audio_sum = zeros(height(audio), 1);
                for k = 1:numel(present_ch)
                    raw = double(audio.(present_ch{k}));
                    raw = raw - mean(raw, 'omitnan');
                    if numel(raw) > 10 * fs_audio
                        raw = bandpass(raw, [audio_bp_low audio_bp_high], fs_audio);
                    end
                    audio_sum = audio_sum + raw;
                end
 
                rms_win  = max(3, round(fs_audio * audio_rms_win_sec));
                env      = sqrt(movmean(audio_sum.^2, rms_win));
                drv_au   = [0; abs(diff(env))];
                thresh_au   = median(drv_au) + audio_sensitivity * mad(drv_au, 1);
                min_dist_au = round(min_distance_sec * fs_audio);
                audio_times = detect_peaks(drv_au, t_audio, thresh_au, min_dist_au);
            end
        catch
            % audio unreadable — proceed without
        end
    end
 
    % Merge: audio is foundation; accel confirms
    if isempty(audio_times)
        merged_times  = accel_times;
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
 
    in_window = merged_times >= t_win_start & merged_times <= t_win_end;
    n_col = sum(in_window);
end
 
 
function [t_start, t_end] = parse_trial_window(events)
    t_start = NaN;  t_end = NaN;
    if isempty(events), return; end
 
    if ismember('recording_time', events.Properties.VariableNames)
        t_col = events.recording_time;
    else
        num_cols = varfun(@isnumeric, events, 'OutputFormat', 'uniform');
        if ~any(num_cols), return; end
        t_col = events{:, find(num_cols, 1)};
    end
    if iscell(t_col), t_col = str2double(t_col); end
    if ~ismember('data', events.Properties.VariableNames), return; end
 
    % Start event: prefer event_spacebar; fall back to TRIAL_START
    start_mask    = contains(events.data, 'TRIAL_START');
    spacebar_mask = contains(events.data, 'event_spacebar');
    end_mask      = contains(events.data, 'TRIAL_END');
 
    if any(spacebar_mask)
        t_start = t_col(find(spacebar_mask, 1, 'first'));
    elseif any(start_mask)
        t_start = t_col(find(start_mask,    1, 'first'));
    end
 
    if any(end_mask), t_end = t_col(find(end_mask, 1, 'last')); end
end
 
 
function [sig_ds, t_ds] = antialias_downsample(sig, t, fs_in, fs_out, order, ds_factor)
    Wn = min(fs_out/2*0.9 / (fs_in/2), 0.99);
    [b, a] = butter(order, Wn, 'low');
    sig_filt = filtfilt(b, a, double(sig));
    n_ds = floor(numel(sig_filt) / ds_factor);
    sig_ds = zeros(n_ds, 1);  t_ds = zeros(n_ds, 1);
    for k = 1:n_ds
        idx = (k-1)*ds_factor+1 : k*ds_factor;
        sig_ds(k) = mean(sig_filt(idx));
        t_ds(k)   = t(idx(1));
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
            if edges(j) - edges(i) < min_dist_smp
                if drv(edges(j)) > drv(edges(i))
                    keep(i) = false;
                else
                    keep(j) = false;
                end
            else
                break
            end
        end
    end
    times = t(edges(keep));
end
 
 
function s = ifnan(val, s_nan, s_ok)
% Returns s_nan if val is NaN, s_ok otherwise.
    if isnan(val), s = s_nan; else, s = s_ok; end
end
 
function result = endsWith(str, suffix)
% Back-compatible endsWith for older MATLAB versions.
    result = numel(str) >= numel(suffix) && ...
             strcmp(str(end-numel(suffix)+1:end), suffix);
end