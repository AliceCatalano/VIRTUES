%% VIRTUES — Unified Analysis Script
% Sensors: GSR (Shimmer) | Eye tracker (Neon) | Accelerometer + Force (NI-DAQ) Audio Mixer (channels ch12–ch18)
% Dependencies: positiveFFT.m, cvxEDA.m (optional)

clear; clc; close all;

BASE_FOLDER = '/run/user/1001/gvfs/smb-share:server=shark,share=acatalano';
SAVE_PATH   = '/home/acatalano/Desktop/Virtues';

% NI-DAQ
accel_fs          = 3000;    % hardware sample rate (Hz)
bp_low            = 80;      % bandpass low  cut (Hz)
bp_high           = 1000;    % bandpass high cut (Hz)
n_baseline_offset = 50;      % samples used for resting-offset removal
V2G               = 1/0.4;  % 0.4 V/g accelerometer sensitivity
resting_state_index  = '1';        % which resting state to use ('1' or '2')
blink_threshold_mad  = 3.0;        % pupil drops below median - k*MAD = blink
blink_interp_pad_ms  = 100;        % ms to pad around detected blinks before interpolating
% Audio mixer channels (as they appear in audio.csv columns)

audio_channels    = {'ch11','ch12','ch13','ch14','ch16','ch17','ch18'};
audio_bp_low      = 80;      % bandpass low  cut for mixer (Hz)
audio_bp_high     = 1000;    % bandpass high cut for mixer (Hz)

% Collision detection
target_fs_display = 500;     % downsample target for detection + display (Hz)
accel_sensitivity = 20;      % threshold = median + k*MAD on derivative
force_sensitivity = 15;
min_distance_sec  = 2.0;     % minimum gap between successive collisions (s)
merge_window_sec  = 0.50;    % accel+force events within this window -> merged
thresh_percentile = 99;      % hard-floor: threshold >= this percentile of derivative

% GSR / cvxEDA
use_cvxEDA         = true;
gsr_unit           = 'ohm';  % 'ohm' or 'kohm'
scr_latency_window = 5.0;    % s post-collision to search for SCR peak
scl_window_start   = 2.0;    % tonic window start (s after collision)
scl_window_end     = 8.0;    % tonic window end   (s after collision)
baseline_before    = 2.0;    % s of pre-collision baseline
scr_sensitivity    = 2.5;    % n*MAD phasic threshold
scl_sensitivity    = 2.0;    % n*MAD tonic threshold

% Eye
pupil_smooth_sec = 0.3;      % pupil moving-average window (s)
save_figures = false;

fprintf('VIRTUES — ANALYSIS\n\n');

subject_id = input('Subject ID (e.g. S001): ', 's');
subject_folder = fullfile(BASE_FOLDER, sprintf('subject_%s', subject_id));

if ~isfolder(subject_folder)
    fprintf('[ERROR] Subject folder not found:\n  %s\n', subject_folder);
    return
end

fprintf('\nPhases available:\n');
fprintf('  1 - Resting state\n');
fprintf('  2 - Baseline\n');
fprintf('  3 - Test\n');
fprintf('  4 - Repetitions (level trials)\n');
phase = input('Select phase (1-4): ', 's');

folders_to_run = {};   % will be a cell array of {folder_path, label}

switch phase
    case '1'
        idx = input('Resting state index (1 or 2): ', 's');
        f   = fullfile(subject_folder, 'resting_state', sprintf('%s_r%s', subject_id, idx));
        folders_to_run = {{f, sprintf('Resting state %s', idx)}};

    case '2'
        acq = input('Acquisition number (1 or 2): ', 's');
        baseline_folder = fullfile(subject_folder, sprintf('Baseline%s', acq));

        if ~isfolder(baseline_folder)
            fprintf('[ERROR] Folder not found: %s\n', baseline_folder);
            return
        end

        lv_choice = input('Check specific level (1-5) or all (press Enter): ', 's');
        if isempty(lv_choice), levels = 1:5; else, levels = str2double(lv_choice); end

        for lv = levels

            f = fullfile(baseline_folder, sprintf('Level%d', lv));

            folders_to_run{end+1} = {f, sprintf('Baseline%s/Level%d', acq, lv)}; %#ok<SAGROW>

            redo = fullfile(baseline_folder, sprintf('Level%d_R', lv));
            if isfolder(redo)
                folders_to_run{end+1} = {redo, sprintf('Baseline%s/Level%d_R', acq, lv)}; %#ok<SAGROW>
            end
        end


    case '3'
        acq = input('Acquisition number (1, 2, or 3): ', 's');
        f   = fullfile(subject_folder, sprintf('Test%s', acq));
        folders_to_run = {{f, sprintf('Test%s', acq)}};


    case '4'
        level = input('Level (e.g. L1): ', 's');
        level_folder = fullfile(subject_folder, sprintf('level_%s', upper(level)));

        if ~isfolder(level_folder)
            fprintf('[ERROR] Folder not found: %s\n', level_folder);
            return
        end

        rep_choice = input('Check specific rep (1-10) or all (press Enter): ', 's');
        if isempty(rep_choice), reps = 1:10; else, reps = str2double(rep_choice); end

        for rep = reps
            f = fullfile(level_folder, sprintf('rep_%02d', rep));
            if ~isfolder(f)
                fprintf('  rep_%02d — NOT FOUND, skipping.\n', rep); continue
            end
            folders_to_run{end+1} = {f, sprintf('%s/rep_%02d', upper(level), rep)}; %#ok<SAGROW>

            redo = fullfile(level_folder, sprintf('rep_%02d_R', rep));
            if isfolder(redo)
                folders_to_run{end+1} = {redo, sprintf('%s/rep_%02d_R', upper(level), rep)}; %#ok<SAGROW>
            end
        end

    otherwise
        fprintf('[ERROR] Unknown phase selection.\n');
        return
end

fprintf('\n--- Loading resting state baseline (r%s) ---\n', resting_state_index);

rest_folder = fullfile(subject_folder, 'resting_state', ...
    sprintf('%s_r%s', subject_id, resting_state_index));

if ~isfolder(rest_folder)
    fprintf('[WARNING] Resting state folder not found:\n  %s\n', rest_folder);
    fprintf('  Baseline normalization will be SKIPPED.\n\n');
    has_baseline = false;
    baseline = struct( ...
        'gsr_mean',   NaN, 'gsr_std',   NaN, 'gsr_median', NaN, 'gsr_mad', NaN, ...
        'pupil_L_mean', NaN, 'pupil_L_std', NaN, ...
        'pupil_R_mean', NaN, 'pupil_R_std', NaN, ...
        'pupil_mean',   NaN, 'pupil_std',   NaN);
else
    has_baseline = true;

    rest_gsr  = load_if_exists(fullfile(rest_folder, 'gsr.csv'));
    rest_eye  = load_if_exists(fullfile(rest_folder, 'eye.csv'));

    if ~isempty(rest_gsr)
        if height(rest_gsr) > 5, rest_gsr(1:5,:) = []; end   % drop header artifact

        rest_gsr_col = get_gsr_col(rest_gsr);
        gsr_rest_raw = rest_gsr.(rest_gsr_col);

        % Remove obvious NaNs / Infs
        gsr_valid = gsr_rest_raw(isfinite(gsr_rest_raw));

        % Convert to conductance if cvxEDA will be used (same as main pipeline)
        if use_cvxEDA
            if strcmp(gsr_unit, 'ohm')
                gsr_rest_cond = 1e6 ./ gsr_valid;     % µS
            else
                gsr_rest_cond = 1000 ./ gsr_valid;    % µS from kΩ
            end
            baseline.gsr_mean   = mean(gsr_rest_cond);
            baseline.gsr_std    = std(gsr_rest_cond);
            baseline.gsr_median = median(gsr_rest_cond);
            baseline.gsr_mad    = mad(gsr_rest_cond, 1);
            fprintf('  GSR baseline (conductance µS): mean=%.4f  std=%.4f  median=%.4f  MAD=%.4f\n', ...
                baseline.gsr_mean, baseline.gsr_std, baseline.gsr_median, baseline.gsr_mad);
        else
            baseline.gsr_mean   = mean(gsr_valid);
            baseline.gsr_std    = std(gsr_valid);
            baseline.gsr_median = median(gsr_valid);
            baseline.gsr_mad    = mad(gsr_valid, 1);
            fprintf('  GSR baseline (raw Ohm): mean=%.2f  std=%.2f  median=%.2f  MAD=%.2f\n', ...
                baseline.gsr_mean, baseline.gsr_std, baseline.gsr_median, baseline.gsr_mad);
        end
    else
        fprintf('  [WARNING] gsr.csv not found in resting state folder.\n');
        baseline.gsr_mean   = NaN;  baseline.gsr_std  = NaN;
        baseline.gsr_median = NaN;  baseline.gsr_mad  = NaN;
    end

    if ~isempty(rest_eye) && all(ismember({'pupil_diameter_left','pupil_diameter_right', ...
            'timestamp_unix_seconds'}, rest_eye.Properties.VariableNames))

        fs_eye_rest = 1 / median(diff(rest_eye.timestamp_unix_seconds));

        pL_raw = rest_eye.pupil_diameter_left;
        pR_raw = rest_eye.pupil_diameter_right;

        % --- Blink removal via MAD thresholding + interpolation ----------
        % Strategy: values that drop sharply below a robust floor are blinks.
        % We detect them, pad the window, then linearly interpolate.

        pL_clean = remove_blinks_mad(pL_raw, fs_eye_rest, ...
            blink_threshold_mad, blink_interp_pad_ms);
        pR_clean = remove_blinks_mad(pR_raw, fs_eye_rest, ...
            blink_threshold_mad, blink_interp_pad_ms);

        % After cleaning, compute baseline stats
        pL_valid = pL_clean(isfinite(pL_clean));
        pR_valid = pR_clean(isfinite(pR_clean));

        baseline.pupil_L_mean = mean(pL_valid);
        baseline.pupil_L_std  = std(pL_valid);
        baseline.pupil_R_mean = mean(pR_valid);
        baseline.pupil_R_std  = std(pR_valid);

        % Binocular mean (use whichever eyes are valid sample-by-sample)
        pBino = mean([pL_clean, pR_clean], 2, 'omitnan');
        pBino_valid = pBino(isfinite(pBino));
        baseline.pupil_mean = mean(pBino_valid);
        baseline.pupil_std  = std(pBino_valid);

        fprintf('  Pupil baseline  fs=%.1f Hz\n', fs_eye_rest);
        fprintf('    Left  : mean=%.4f mm  std=%.4f mm  (after blink removal)\n', ...
            baseline.pupil_L_mean, baseline.pupil_L_std);
        fprintf('    Right : mean=%.4f mm  std=%.4f mm  (after blink removal)\n', ...
            baseline.pupil_R_mean, baseline.pupil_R_std);
        fprintf('    Bino  : mean=%.4f mm  std=%.4f mm\n', ...
            baseline.pupil_mean, baseline.pupil_std);

        % Optional: plot resting state pupil for visual inspection
        plot_resting_pupil(rest_eye, pL_clean, pR_clean, ...
            fs_eye_rest, pupil_smooth_sec, subject_id, resting_state_index);

    else
        fprintf('  [WARNING] eye.csv not found or missing columns in resting state folder.\n');
        baseline.pupil_L_mean = NaN;  baseline.pupil_L_std = NaN;
        baseline.pupil_R_mean = NaN;  baseline.pupil_R_std = NaN;
        baseline.pupil_mean   = NaN;  baseline.pupil_std   = NaN;
    end
    fprintf('--- Baseline computation complete ---\n\n');
end
%  MAIN LOOP  (one iteration per folder/label pair)


all_results = table();

for fi = 1:numel(folders_to_run)

    data_folder = folders_to_run{fi}{1};
    fig_title   = folders_to_run{fi}{2};

    if ~isfolder(data_folder)
        fprintf('[%s] folder not found, skipping.\n', fig_title); continue
    end
    fprintf('\n%s  --  %s\n', fig_title, data_folder);

    gsr    = load_if_exists(fullfile(data_folder, 'gsr.csv'));
    nidaq  = load_if_exists(fullfile(data_folder, 'accel.csv'));
    eye    = load_if_exists(fullfile(data_folder, 'eye.csv'));
    events = load_if_exists(fullfile(data_folder, 'events.csv'));
    audio  = load_if_exists(fullfile(data_folder, 'audio.csv'));

    if isempty(nidaq), fprintf('  accel.csv missing, skipping.\n'); continue; end
    if isempty(gsr),   fprintf('  gsr.csv missing, skipping.\n');   continue; end
    if isempty(events)
        events = table('Size',[0 2],'VariableTypes',{'double','cell'},...
                       'VariableNames',{'recording_time','data'});
    end
    if height(gsr) > 5, gsr(1:5,:) = []; end  % drop header-artifact rows


    accel_raw         = table();
    accel_raw.xL      = nidaq.ai9;   accel_raw.yL = nidaq.ai10;   accel_raw.zL = nidaq.ai11;
    accel_raw.xR      = nidaq.ai12;   accel_raw.yR = nidaq.ai13;   accel_raw.zR = nidaq.ai14;
    %accel_raw.pc_time = nidaq.pc_time;

    force_raw    = table();

    force_raw.F1 = nidaq.ai15  - nidaq.ai15;  force_raw.F2 = nidaq.ai16  - nidaq.ai24;
    force_raw.F3 = nidaq.ai17  - nidaq.ai25;  force_raw.F4 = nidaq.ai18 - nidaq.ai26;
    force_raw.F5 = nidaq.ai19 - nidaq.ai27;  force_raw.F6 = nidaq.ai20 - nidaq.ai28;
    %force_raw.pc_time = nidaq.pc_time;
    % ---- TIMESTAMP: use pc_time if available, reconstruct otherwise ----------
    if ismember('pc_time', nidaq.Properties.VariableNames)
        fprintf('  Using pc_time (per-sample hardware timestamps)\n');

        accel_raw.pc_time = nidaq.pc_time;
        force_raw.pc_time = nidaq.pc_time;
    else
        fprintf('  WARNING: pc_time not found — reconstructing from recording_time\n');
        t_recon = reconstruct_timestamps_from_recording_time(nidaq.recording_time, accel_fs);
        nidaq.pc_time = t_recon;
        accel_raw.pc_time = t_recon;
        force_raw.pc_time = t_recon;
    end 

    gsr_col = get_gsr_col(gsr);
    
    has_audio = false;
    audio_present_ch = {};
    if ~isempty(audio)
        audio_present_ch = intersect(audio_channels, audio.Properties.VariableNames);
        has_audio = ~isempty(audio_present_ch);
        if ~has_audio
            fprintf('  audio.csv found but no recognised mixer channels.\n');
        end
    else
        fprintf('  audio.csv missing — mixer plots will be skipped.\n');
    end


    % ---- SANITY CHECKS --------------------------------------------------
    fprintf('\nSanity checks\n');
    fprintf('  Samples  accel/force : %d\n', height(accel_raw));

    fprintf('  Samples  gsr         : %d\n', height(gsr));
    if ~isempty(eye), fprintf('  Samples  eye         : %d\n', height(eye));
    else,             fprintf('  Eye tracker          : NOT FOUND\n'); end
    fprintf('  Events               : %d\n', height(events));
    if has_audio
        fprintf('  Audio samples        : %d  channels: %s\n', ...
            height(audio), strjoin(audio_present_ch,', '));
    end

    dt_nidaq = diff(nidaq.pc_time);
    n_bad    = sum(dt_nidaq <= 0);
    if n_bad > 0, fprintf('  WARNING: %d non-monotonic NI-DAQ timestamps\n', n_bad); end

    dt_pos = dt_nidaq(dt_nidaq > 0);
    fs_est = 1 / median(dt_pos);
    fprintf('  Accel fs estimate    : %.2f Hz  (expected %d Hz)\n', fs_est, accel_fs);

    gap_thresh = 5 / accel_fs;
    gap_idx    = find(dt_nidaq > gap_thresh);
    if ~isempty(gap_idx)
        fprintf('  WARNING: %d timing gaps (max %.4f s)\n', numel(gap_idx), max(dt_nidaq));
    end

    nan_a = sum(isnan(accel_raw{:,1:6}),'all');  nan_f = sum(isnan(force_raw{:,1:6}),'all');
    nan_g = sum(isnan(gsr.(gsr_col)));
    if nan_a > 0, fprintf('  WARNING: %d NaNs in accel\n', nan_a); end
    if nan_f > 0, fprintf('  WARNING: %d NaNs in force\n', nan_f); end
    if nan_g > 0, fprintf('  WARNING: %d NaNs in GSR\n',   nan_g); end

    dead_a = find(std(accel_raw{:,1:6}) < 1e-6);
    dead_f = find(std(force_raw{:,1:6}) < 1e-6);
    if ~isempty(dead_a), fprintf('  WARNING: near-constant accel channels: %s\n', num2str(dead_a)); end
    if ~isempty(dead_f), fprintf('  WARNING: near-constant force channels: %s\n', num2str(dead_f)); end

    fprintf('  Accel range (V) : [%.3f  %.3f]\n', min(accel_raw{:,1:6},[],'all'), max(accel_raw{:,1:6},[],'all'));
    fprintf('  Force range (V) : [%.3f  %.3f]\n', min(force_raw{:,1:6},[],'all'), max(force_raw{:,1:6},[],'all'));
    fprintf('  GSR range       : [%.2f  %.2f]\n', min(gsr.(gsr_col)), max(gsr.(gsr_col)));

    dt_gsr = diff(gsr.pc_time);
    fs_gsr = 1 / median(dt_gsr(dt_gsr > 0));
    fprintf('  GSR fs          : %.2f Hz  (jitter std = %.4f s)\n', fs_gsr, std(dt_gsr));

    if ~isempty(eye) && all(ismember({'pupil_diameter_left','pupil_diameter_right'}, eye.Properties.VariableNames))
        pL = eye.pupil_diameter_left;   pR = eye.pupil_diameter_right;
        fs_eye = 1 / median(diff(eye.timestamp_unix_seconds));
        fprintf('  Eye fs          : %.2f Hz\n', fs_eye);
        fprintf('  Pupil L NaNs    : %d (%.1f%%)\n', sum(isnan(pL)), 100*mean(isnan(pL)));
        fprintf('  Pupil R NaNs    : %d (%.1f%%)\n', sum(isnan(pR)), 100*mean(isnan(pR)));
        if sum(~isnan(pL)) > 10, fprintf('  Pupil L noise std: %.4f mm\n', std(detrend(pL(~isnan(pL))))); end
        if sum(~isnan(pR)) > 10, fprintf('  Pupil R noise std: %.4f mm\n', std(detrend(pR(~isnan(pR))))); end
        if ismember('blink', eye.Properties.VariableNames)
            blink_rate = sum(diff([0; double(eye.blink)]) == 1) / (range(eye.timestamp_unix_seconds)/60);
            fprintf('  Blink rate      : %.2f blinks/min\n', blink_rate);
        end
    end

    % ---- NI-DAQ GAP DIAGNOSTICS -----------------------------------------
    plot_nidaq_gaps(nidaq.pc_time, accel_fs, sprintf('%s | NI-DAQ timestamp diagnostics', fig_title));

    % ---- TIMESTAMP RECONSTRUCTION ----------------------------------------
    %
    % The NI-DAQ node writes pc_time once per 300-sample hardware buffer.
    % Strategy: interpolate linearly between anchor timestamps, extrapolate
    % at nominal rate after the last anchor. Real wall-clock gaps are preserved.

    raw_t    = nidaq.pc_time;
    n_samp   = height(nidaq);

    anchor_idx = [1; find(diff(raw_t) ~= 0) + 1];
    anchor_t   = raw_t(anchor_idx);

    fprintf('  Anchor points (unique pc_time values) : %d  (out of %d samples)\n', ...
        numel(anchor_idx), n_samp);

    t_recon = zeros(n_samp, 1);

    for a = 1:numel(anchor_idx)
        i0 = anchor_idx(a);
        if a < numel(anchor_idx)
            i1   = anchor_idx(a+1) - 1;
            n    = i1 - i0 + 1;
            t0_a = anchor_t(a);
            t1_a = anchor_t(a+1);
            t_recon(i0:i1) = t0_a + (0:n-1)' * (t1_a - t0_a) / n;
        else
            i1 = n_samp;
            n  = i1 - i0 + 1;
            t_recon(i0:i1) = anchor_t(a) + (0:n-1)' / accel_fs;
        end
    end

    dt_recon      = diff(t_recon);
    fs_recon      = 1 / median(dt_recon(dt_recon > 0));
    n_gaps_recon  = sum(dt_recon > 5/accel_fs);
    fprintf('  Reconstructed fs  : %.2f Hz\n', fs_recon);
    fprintf('  True gaps in recon timeline (>5 samples): %d\n', n_gaps_recon);

    accel_raw.t_unix = t_recon;
    force_raw.t_unix = t_recon;

    % ---- UNIFIED RELATIVE TIMELINE  (t=0 at earliest sample) -----------
    all_unix = [gsr.pc_time; t_recon; events.recording_time];
    if ~isempty(eye),   all_unix = [all_unix; eye.timestamp_unix_seconds]; end
    if has_audio,       all_unix = [all_unix; audio.recording_time]; end
    t0_unix = min(all_unix);

    gsr.t        = gsr.pc_time      - t0_unix;
    accel_raw.t  = accel_raw.t_unix - t0_unix;
    force_raw.t  = force_raw.t_unix - t0_unix;
    event_times  = events.recording_time - t0_unix;
    event_labels = events.data;
    if ~isempty(eye),  eye.t = eye.timestamp_unix_seconds - t0_unix; end
    if has_audio,      audio.t = audio.recording_time - t0_unix; end

    [t_trial_start, t_trial_end] = parse_trial_events(events, t0_unix);
    fprintf('  Timeline: t0=%.3f UNIX  duration=%.2f s\n', t0_unix, max(all_unix-t0_unix));

    % ---- OFFSET REMOVAL + V -> G ----------------------------------------
    for ch = {'xL','yL','zL','xR','yR','zR'}
        c = ch{1};
        accel_raw.(c) = (accel_raw.(c) - mean(accel_raw.(c)(1:n_baseline_offset))) * V2G;
    end
    force_cols = {'F1','F2','F3','F4','F5','F6'};
    for k = 1:numel(force_cols)
        c = force_cols{k};
        force_raw.(c) = force_raw.(c) - mean(force_raw.(c)(1:n_baseline_offset));
    end

    % ---- DOWNSAMPLED FORCE MAGNITUDE ------------------------------------
    force_mag_native = sqrt(force_raw.F1.^2 + force_raw.F2.^2 + force_raw.F3.^2 + ...
                            force_raw.F4.^2 + force_raw.F5.^2 + force_raw.F6.^2);
    fs_native = accel_fs;
    ds_factor = max(1, round(fs_native / target_fs_display));
    [force_mag_ds, t_ds] = antialias_downsample(force_mag_native, accel_raw.t, ...
                               fs_native, target_fs_display, 4, ds_factor);

    mag_accel_native = max(sqrt(accel_raw.xL.^2 + accel_raw.yL.^2 + accel_raw.zL.^2), ...
        sqrt(accel_raw.xR.^2 + accel_raw.yR.^2 + accel_raw.zR.^2));
    
    [mag_accel_ds, t_ds] = antialias_downsample(mag_accel_native,accel_raw.t,fs_native, target_fs_display, 4,ds_factor);
   

    % ---- GSR ANALYSIS -

    mag_accel_native = max(sqrt(accel_raw.xL.^2 + accel_raw.yL.^2 + accel_raw.zL.^2), ...
                           sqrt(accel_raw.xR.^2 + accel_raw.yR.^2 + accel_raw.zR.^2));
    [mag_accel_ds, t_ds] = antialias_downsample(mag_accel_native, accel_raw.t, ...
                               fs_native, target_fs_display, 4, ds_factor);

    min_dist_smp = round(min_distance_sec * target_fs_display);

    drv_a    = [0; abs(diff(mag_accel_ds))];
    thresh_a = max(median(drv_a) + accel_sensitivity*mad(drv_a,1), prctile(drv_a,thresh_percentile));
    accel_events = detect_peaks(drv_a, t_ds, thresh_a, min_dist_smp);

    % ---- GSR ANALYSIS ---------------------------------------------------

    cvx_ok = false;
    if use_cvxEDA
        conductance_uS = 1e6 ./ gsr.(gsr_col);
        if strcmp(gsr_unit,'kohm'), conductance_uS = 1000 ./ gsr.(gsr_col); end
        yn = zscore(conductance_uS);
        for si = 1:3
            sv_list = {'quadprog','sedumi',''};  sv = sv_list{si};
            try
                if isempty(sv), [~,p_cvx,t_cvx,~,~,~,obj_cvx] = cvxEDA(yn, 1/fs_gsr);
                else,           [~,p_cvx,t_cvx,~,~,~,obj_cvx] = cvxEDA(yn, 1/fs_gsr,0.7,1.0,1.0,8e-5,1e-2,sv); end
                fprintf('  cvxEDA OK (solver=%s obj=%.4f)\n', sv, obj_cvx);
                gsr.conductance_uS = conductance_uS;  gsr.scr = p_cvx;  gsr.scl = t_cvx;
                cvx_ok = true;  break
            catch err
                fprintf('  cvxEDA solver "%s" failed: %s\n', sv, err.message);
            end
        end
        if ~cvx_ok, fprintf('  All cvxEDA solvers failed, using raw resistance.\n'); end
    end

    
    %% ---- UNIFIED OVERVIEW FIGURE ----------------------------------------
    % One figure, shared x-axis (relative time):
    %   1. Accel sum (L+R, bandpassed) — with collision markers
    %   2. Audio mixer sum (bandpassed), each channel faint + sum bold
    %   3. Force magnitude (downsampled)
    %   4. GSR (raw, or tonic SCL if cvxEDA succeeded)
    %   5. Pupil diameter (smoothed, left + right)
    % Events are marked on every panel as dashed vertical lines.
    % Collisions are marked with solid vertical lines, colour-coded by source.

     plot_unified_overview(accel_raw, force_raw, force_mag_ds, t_ds, ...
        mag_accel_ds, gsr, audio, audio_present_ch, eye, ...
        event_times, event_labels, ...
        accel_fs, bp_low, bp_high, audio_bp_low, audio_bp_high, ...
        pupil_smooth_sec, cvx_ok, t_trial_start, t_trial_end, fig_title, ...
        baseline, has_baseline, ...
        blink_threshold_mad, blink_interp_pad_ms); 


    % ---- STORE RESULTS --------------------------------------------------

    % for i = 1:numel(all_collisions)
    %     r.level          = fig_title;
    %     r.collision_time = all_collisions(i);
    %     r.has_scr        = gsr_responses(i).has_scr;
    %     r.scr_latency_s  = gsr_responses(i).scr_latency;
    %     r.scr_amplitude  = gsr_responses(i).scr_amplitude;
    %     r.has_scl        = gsr_responses(i).has_scl;
    %     r.scl_change     = gsr_responses(i).scl_change;
    %     r.baseline       = gsr_responses(i).baseline;
    %     all_results = [all_results; struct2table(r,'AsArray',true)]; %#ok<AGROW>
    % end

    if save_figures
        figs = findall(0,'Type','figure');
        for fii = 1:numel(figs)
            if contains(get(figs(fii),'Name'), fig_title)

                saveas(figs(fii), fullfile(SAVE_PATH, [strrep(get(figs(fii),'Name'),' ','_') '.png']));

                saveas(figs(fii), fullfile(data_folder, [strrep(get(figs(fii),'Name'),' ','_') '.png']));

            end
        end
    end

    fprintf('  %s done.\n', fig_title);
end

if ~isempty(all_results)
    fprintf('\nSUMMARY (all folders)\n');
    disp(all_results);
end
fprintf('\n==\n');
fprintf('                  ANALYSIS COMPLETE\n');



%  PLOT FUNCTIONS


% ---- NI-DAQ gap diagnostics --------------------------------------------
function plot_nidaq_gaps(pc_time, accel_fs, fig_title)
    dt         = diff(pc_time);
    dt_nominal = 1 / accel_fs;
    t_axis     = (1:numel(dt))';

    figure('Name', fig_title, 'Position',[100 100 1400 700]);
    sgtitle(fig_title, 'FontWeight','bold','FontSize',10);

    ax1 = subplot(3,1,1);
    plot(t_axis, dt*1000, 'Color',[0.2 0.4 0.8], 'LineWidth',0.4);  hold on;
    yline(dt_nominal*1000,   'r--', 'LineWidth',1.2, 'Label','nominal dt');
    yline(5*dt_nominal*1000, 'k:',  'LineWidth',1.0, 'Label','5x nominal');
    ylabel('dt (ms)');  title('Inter-sample interval (full range)');  grid on;

    ax2 = subplot(3,1,2);
    plot(t_axis, dt*1000, 'Color',[0.2 0.4 0.8], 'LineWidth',0.4);  hold on;
    yline(dt_nominal*1000, 'r--', 'LineWidth',1.2);
    ylim([0  10*dt_nominal*1000]);
    ylabel('dt (ms)');  title('Inter-sample interval (clamped to 10x nominal)');
    grid on;  xlabel('Sample index');

    ax3 = subplot(3,1,3);
    dt_clip = dt(dt < 50*dt_nominal);
    histogram(dt_clip*1000, 200, 'FaceColor',[0.2 0.6 0.4], 'EdgeColor','none');  hold on;
    xline(dt_nominal*1000,   'r--', 'LineWidth',1.5, 'Label','nominal');
    xline(5*dt_nominal*1000, 'k:',  'LineWidth',1.2, 'Label','5x nominal');
    xlabel('dt (ms)');  ylabel('Count');
    title(sprintf('dt histogram  (%d outliers > 50x nominal not shown)', sum(dt >= 50*dt_nominal)));
    grid on;

    linkaxes([ax1 ax2], 'x');

    gap_mask  = dt > 5*dt_nominal;
    gap_times = pc_time(find(gap_mask)+1);
    gap_sizes = dt(gap_mask);
    fprintf('\n  Gap report  (threshold = 5x nominal = %.2f ms)\n', 5*dt_nominal*1000);
    fprintf('  Total gaps : %d\n', numel(gap_sizes));
    if ~isempty(gap_sizes)
        fprintf('  min / median / max : %.4f / %.4f / %.4f s\n', ...
            min(gap_sizes), median(gap_sizes), max(gap_sizes));
        n_show = min(20, numel(gap_times));
        for g = 1:n_show
            fprintf('    gap %2d:  pc_time = %.4f   dt = %.4f s\n', g, gap_times(g), gap_sizes(g));
        end
        if numel(gap_times) > 20
            fprintf('    ... and %d more\n', numel(gap_times)-20);
        end
    end
end

% ---- UNIFIED OVERVIEW FIGURE --------------------------------------------
function plot_unified_overview(accel_raw, force_raw, force_mag_ds, t_ds, ...
        mag_accel_ds, gsr, audio, audio_present_ch, eye, ...
        event_times, event_labels, ...
        accel_fs, bp_lo, bp_hi, audio_bp_lo, audio_bp_hi, ...
        pupil_smooth_sec, cvx_ok, t_trial_start, t_trial_end, fig_title, ...
        baseline, has_baseline, ...
        blink_threshold_mad, blink_interp_pad_ms) 

    gsr_col   = get_gsr_col(gsr);
    gsr_label = 'GSR (Ohm)';
    if contains(gsr_col,'CAL'), gsr_label = 'GSR (kOhm)'; end

    has_audio = ~isempty(audio) && ~isempty(audio_present_ch);
    has_eye   = ~isempty(eye) && all(ismember({'pupil_diameter_left','pupil_diameter_right',...
                 'timestamp_unix_seconds'}, eye.Properties.VariableNames));

    % Determine number of rows: accel_sum | [audio_sum] | force | gsr | [pupil]
    n_rows = 3 + has_audio + has_eye;

    figure('Name', ['OVERVIEW: ' fig_title],'Position', [20 20 1700 220*n_rows]);
    sgtitle(sprintf('%s  |  Unified Overview', fig_title),'FontWeight','bold','FontSize',11);

    ax = gobjects(n_rows, 1);
    row = 0;

    % ---- Row 1: Accel sum (L mag + R mag, bandpassed, downsampled) ------
    row = row + 1;
    ax(row) = subplot(n_rows, 1, row);
    hold on;

    % Bandpass at full rate then downsample for display
    sumL_bp = bandpass(accel_raw.xL, [bp_lo bp_hi], accel_fs) + ...
              bandpass(accel_raw.yL, [bp_lo bp_hi], accel_fs) + ...
              bandpass(accel_raw.zL, [bp_lo bp_hi], accel_fs);
    sumR_bp = bandpass(accel_raw.xR, [bp_lo bp_hi], accel_fs) + ...
              bandpass(accel_raw.yR, [bp_lo bp_hi], accel_fs) + ...
              bandpass(accel_raw.zR, [bp_lo bp_hi], accel_fs);

    ds_factor = max(1, round(accel_fs / 500));
    tA_ds  = accel_raw.t(1:ds_factor:end);
    sumL_ds = sumL_bp(1:ds_factor:end);
    sumR_ds = sumR_bp(1:ds_factor:end);

    plot(tA_ds, sumL_ds, 'Color',[0.2 0.4 0.9], 'LineWidth',0.6, 'DisplayName','Accel sum L');
    plot(tA_ds, sumR_ds, 'Color',[0.9 0.3 0.1], 'LineWidth',0.6, 'DisplayName','Accel sum R');
    ylabel('Sum (g)');
    title(sprintf('Accel X+Y+Z  (bandpassed %d–%d Hz)', bp_lo, bp_hi));
    legend('Location','northeast','FontSize',7);
    grid on;
    add_event_lines(event_times);
    mark_trial(t_trial_start, t_trial_end);

    % ---- Row 2 (optional): Audio mixer sum -------------------------------
    if has_audio
        row = row + 1;
        ax(row) = subplot(n_rows, 1, row);
        hold on;

        fs_audio = 1 / median(diff(audio.t(diff(audio.t) > 0)));
        audio_sum_bp = zeros(height(audio), 1);
        clrs_a = lines(numel(audio_present_ch));

        for k = 1:numel(audio_present_ch)
            ch  = audio_present_ch{k};
            raw = double(audio.(ch)) - mean(double(audio.(ch)), 'omitnan');
            if numel(raw) > 10 * fs_audio
                raw_bp = bandpass(raw, [audio_bp_lo audio_bp_hi], fs_audio);
            else
                raw_bp = raw;
            end
            audio_sum_bp = audio_sum_bp + raw_bp;
            plot(audio.t, raw_bp, 'Color', [clrs_a(k,:) 0.35], 'LineWidth', 0.4, ...
                 'DisplayName', ch);
        end

        plot(audio.t, audio_sum_bp, 'Color',[0.1 0.1 0.7], 'LineWidth', 1.2, ...
             'DisplayName', 'Sum');
        ylabel('V');
        title(sprintf('Audio mixer  (bandpassed %d–%d Hz)', audio_bp_lo, audio_bp_hi));
        legend('Location','northeast','FontSize',7);
        grid on;
        add_event_lines(event_times);
        mark_trial(t_trial_start, t_trial_end);
    end

    % ---- Row 3: Force magnitude ------------------------------------------
    row = row + 1;
    ax(row) = subplot(n_rows, 1, row);
    hold on;
    plot(t_ds, force_mag_ds, 'Color',[0.5 0 0.5], 'LineWidth', 0.8, 'DisplayName','|Force|');
    ylabel('|Force| (V)');
    title('Force sensor magnitude (downsampled)');
    grid on;
    add_event_lines(event_times);mark_trial(t_trial_start, t_trial_end);

    % ---- Row 4: GSR (raw or tonic SCL) ----------------------------------
    row = row + 1;
    ax(row) = subplot(n_rows, 1, row);
    hold on;

    if cvx_ok && ismember('scl', gsr.Properties.VariableNames)
        % --- Z-score SCL/SCR relative to resting state ---
        if has_baseline && isfinite(baseline.gsr_mean) && baseline.gsr_std > 0
            scl_norm = (gsr.scl - baseline.gsr_mean) / baseline.gsr_std;
            scr_norm = (gsr.scr - baseline.gsr_mean) / baseline.gsr_std;
            y_label_gsr  = 'GSR (z-score vs rest)';
            norm_note    = ' [z-scored vs resting state]';
        else
            scl_norm = gsr.scl;
            scr_norm = gsr.scr;
            y_label_gsr = 'z-µS';
            norm_note   = ' [no baseline available]';
        end

        yyaxis left;
        % Raw GSR as light background reference
        gsr_raw_vals = gsr.(gsr_col);
        if has_baseline && isfinite(baseline.gsr_mean) && baseline.gsr_std > 0
            gsr_raw_norm = (gsr_raw_vals - baseline.gsr_mean) / baseline.gsr_std;
        else
            gsr_raw_norm = gsr_raw_vals;
        end
        plot(gsr.t, gsr_raw_norm, 'Color',[0.6 0.6 1.0], 'LineWidth',0.6, 'DisplayName','GSR raw');
        ylabel(y_label_gsr);

        yyaxis right;
        plot(gsr.t, scl_norm, 'b', 'LineWidth',1.2, 'DisplayName','SCL tonic');
        plot(gsr.t, scr_norm, 'r', 'LineWidth',0.7, 'DisplayName','SCR phasic');
        ylabel('Normalised z-µS');

        yyaxis left;
        title(['GSR — cvxEDA SCL/SCR' norm_note]);

    else
        % --- Raw resistance, percent change from resting baseline ---------
        gsr_raw_vals = gsr.(gsr_col);

        if has_baseline && isfinite(baseline.gsr_mean) && baseline.gsr_std > 0
            % Z-score: (x - mu_rest) / sigma_rest
            gsr_plot    = (gsr_raw_vals - baseline.gsr_mean) / baseline.gsr_std;
            y_label_gsr = 'GSR (z-score vs rest)';
            norm_note   = sprintf(' [z-scored  rest µ=%.1f σ=%.1f]', ...
                baseline.gsr_mean, baseline.gsr_std);

            % Overlay a horizontal reference band at 0 ± 1 SD
            yline(0,  'k--', 'LineWidth',0.8, 'HandleVisibility','off');
            yline( 1, ':',   'Color',[0.5 0.5 0.5], 'LineWidth',0.6, 'HandleVisibility','off');
            yline(-1, ':',   'Color',[0.5 0.5 0.5], 'LineWidth',0.6, 'HandleVisibility','off');
        else
            gsr_plot    = gsr_raw_vals;
            y_label_gsr = gsr_label;
            norm_note   = ' [no baseline]';
        end

        plot(gsr.t, gsr_plot, 'b', 'LineWidth',1.0, 'DisplayName','GSR');
        ylabel(y_label_gsr);
        title(['GSR' norm_note]);
    end

    legend('Location','northeast','FontSize',7);
    grid on;
    add_event_lines(event_times);
    
    mark_trial(t_trial_start, t_trial_end);

    % ---- Row 5 (optional): Pupil diameter — baseline normalised ----------
    if has_eye
        row = row + 1;
        ax(row) = subplot(n_rows, 1, row);
        hold on;

        fs_eye  = 1 / median(diff(eye.timestamp_unix_seconds));
        win_pts = max(3, round(fs_eye * pupil_smooth_sec));

        % Blink removal on task signal before smoothing
        pL_clean = remove_blinks_mad(eye.pupil_diameter_left,  fs_eye, ...
            blink_threshold_mad, blink_interp_pad_ms);
        pR_clean = remove_blinks_mad(eye.pupil_diameter_right, fs_eye, ...
            blink_threshold_mad, blink_interp_pad_ms);

        pL_sm = movmean(pL_clean, win_pts, 'omitnan');
        pR_sm = movmean(pR_clean, win_pts, 'omitnan');

        if has_baseline && isfinite(baseline.pupil_L_mean) && baseline.pupil_L_std > 0

            % --- Z-score relative to resting state -----------------------
            pL_norm = (pL_sm - baseline.pupil_L_mean) / baseline.pupil_L_std;
            pR_norm = (pR_sm - baseline.pupil_R_mean) / baseline.pupil_R_std;

            % --- Percent change from resting baseline --------------------
            % Uncomment these two lines (and comment the z-score lines above)
            % if you prefer % change:
            % pL_norm = ((pL_sm - baseline.pupil_L_mean) / baseline.pupil_L_mean) * 100;
            % pR_norm = ((pR_sm - baseline.pupil_R_mean) / baseline.pupil_R_mean) * 100;

            plot(eye.t, pL_norm, 'b',               'LineWidth',1.4, 'DisplayName','L (z)');
            plot(eye.t, pR_norm, 'Color',[0 0.6 0],  'LineWidth',1.4, 'DisplayName','R (z)');

            % Reference lines at 0 ± 1 SD
            yline(0, 'k--', 'LineWidth',0.8, 'HandleVisibility','off');
            yline( 1, ':',  'Color',[0.5 0.5 0.5], 'LineWidth',0.6, 'HandleVisibility','off');
            yline(-1, ':',  'Color',[0.5 0.5 0.5], 'LineWidth',0.6, 'HandleVisibility','off');

            ylabel('Pupil (z-score vs rest)');
            title(sprintf('Pupil  (blink-removed → z-scored vs rest  |  L µ=%.3f R µ=%.3f mm)', ...
                baseline.pupil_L_mean, baseline.pupil_R_mean));
        else
            % No baseline: just plot smoothed mm
            plot(eye.t, eye.pupil_diameter_left,  'Color',[0.7 0.7 1.0], 'LineWidth',0.4, 'DisplayName','L raw');
            plot(eye.t, eye.pupil_diameter_right, 'Color',[0.7 1.0 0.7], 'LineWidth',0.4, 'DisplayName','R raw');
            plot(eye.t, pL_sm, 'b',               'LineWidth',1.4,       'DisplayName','L smooth');
            plot(eye.t, pR_sm, 'Color',[0 0.6 0],  'LineWidth',1.4,       'DisplayName','R smooth');
            ylabel('Diameter (mm)');
            title(sprintf('Pupil  (%.2f s moving avg, %.0f Hz)  [no baseline]', ...
                pupil_smooth_sec, fs_eye));
        end

        legend('Location','northeast','FontSize',7);
        grid on;
        add_event_lines(event_times);
        
        mark_trial(t_trial_start, t_trial_end);
        xlabel('Time (s)');
    else
        xlabel(ax(row), 'Time (s)');
    end

    linkaxes(ax(1:row), 'x');

    % Annotate event labels above top panel
    if ~isempty(event_times)
        axes(ax(1));
        yl = ylim;
        for ei = 1:numel(event_times)
            lbl = '';
            if ~isempty(event_labels) && ei <= numel(event_labels)
                lbl = event_labels{ei};
            end
            text(event_times(ei), yl(2), lbl, 'FontSize',6, 'Color',[0 0 0], ...
                 'Rotation',90, 'VerticalAlignment','bottom', ...
                 'HorizontalAlignment','right', 'Interpreter','none');
        end
    end
end
%  UTILITY FUNCTIONS
% ---- Blink removal via MAD thresholding + linear interpolation ----------
function p_clean = remove_blinks_mad(p_raw, fs, k_mad, pad_ms)
% Detects blinks as samples where pupil diameter drops far below the
% robust floor (median - k*MAD). Pads the detected region by pad_ms on
% each side, then linearly interpolates across the gap.
%
%   p_raw   : raw pupil diameter vector (NaNs / zeros allowed)
%   fs      : sampling rate (Hz)
%   k_mad   : threshold multiplier  (default 3.0)
%   pad_ms  : padding in ms around each detected blink (default 100 ms)

    p_clean  = double(p_raw);
    pad_samp = round(pad_ms / 1000 * fs);

    % ---- Robust statistics on valid (finite, positive) samples ----------
    valid = isfinite(p_clean) & (p_clean > 0);
    if sum(valid) < 10
        return          % not enough data — return as-is
    end

    p_med     = median(p_clean(valid));
    p_mad_val = mad(p_clean(valid), 1);

    % Floor threshold: anything below this is flagged as a blink/artefact
    floor_thresh = p_med - k_mad * p_mad_val;

    % ---- Build bad-sample mask ------------------------------------------
    % Bad = already NaN/zero  OR  below the floor threshold
    bad = ~valid | (p_clean < floor_thresh);

    % Morphological dilation: pad each bad region by pad_samp on each side
    if pad_samp > 0
        bad = imdilate(bad, ones(2*pad_samp + 1, 1));
    end

    % ---- Find contiguous bad segments -----------------------------------
    d      = diff([0; bad(:); 0]);   % force column vector
    starts = find(d ==  1);
    ends   = find(d == -1) - 1;

    % ---- Interpolate across each segment --------------------------------
    for i = 1:numel(starts)
        s = starts(i);
        e = ends(i);

        % Search outward for the nearest good anchor on each side
        left_anchor  = s - 1;
        right_anchor = e + 1;

        % Walk left until we find a finite, non-bad sample
        while left_anchor >= 1 && (bad(left_anchor) || ~isfinite(p_clean(left_anchor)))
            left_anchor = left_anchor - 1;
        end

        % Walk right until we find a finite, non-bad sample
        while right_anchor <= numel(p_clean) && (bad(right_anchor) || ~isfinite(p_clean(right_anchor)))
            right_anchor = right_anchor + 1;
        end

        % ---- Decide what to do with this segment ------------------------
        if left_anchor >= 1 && right_anchor <= numel(p_clean) && ...
           isfinite(p_clean(left_anchor)) && isfinite(p_clean(right_anchor))

            % Both anchors exist → linear interpolation
            % We want to fill indices  left_anchor+1 : right_anchor-1
            n_fill = right_anchor - left_anchor - 1;   % number of points to fill

            if n_fill > 0
                % linspace from anchor values, generate exactly n_fill interior pts
                interp_vals = linspace(p_clean(left_anchor), ...
                                       p_clean(right_anchor), ...
                                       n_fill + 2);          % +2 includes the anchors
                % Assign only the interior points (exclude first and last)
                p_clean(left_anchor+1 : right_anchor-1) = interp_vals(2:end-1);
            end
            % n_fill == 0 means the two anchors are adjacent — nothing to fill

        else
            % At least one anchor is missing (segment at signal edge) → NaN
            p_clean(s:e) = NaN;
        end
    end
end
% ---- Resting state pupil diagnostic plot --------------------------------
function plot_resting_pupil(rest_eye, pL_clean, pR_clean, fs_eye, smooth_sec, subject_id, rest_idx)
    t_rest = rest_eye.timestamp_unix_seconds - rest_eye.timestamp_unix_seconds(1);
    win_pts = max(3, round(fs_eye * smooth_sec));

    figure('Name', sprintf('RESTING STATE PUPIL — %s r%s', subject_id, rest_idx), ...
           'Position', [100 100 1400 600]);
    sgtitle(sprintf('Resting State Pupil  |  Subject %s  r%s  (%.0f Hz)', ...
        subject_id, rest_idx, fs_eye), 'FontWeight','bold','FontSize',10);

    subplot(2,1,1);  hold on;
    plot(t_rest, rest_eye.pupil_diameter_left,  'Color',[0.8 0.8 0.8], 'LineWidth',0.5, ...
         'DisplayName','L raw');
    plot(t_rest, rest_eye.pupil_diameter_right, 'Color',[0.7 1.0 0.7], 'LineWidth',0.5, ...
         'DisplayName','R raw');
    plot(t_rest, pL_clean, 'b',               'LineWidth',1.2, 'DisplayName','L blink-removed');
    plot(t_rest, pR_clean, 'Color',[0 0.6 0],  'LineWidth',1.2, 'DisplayName','R blink-removed');
    ylabel('Diameter (mm)');
    title('Raw vs blink-removed  (grey/green=raw, blue/dark-green=cleaned)');
    legend('Location','best','FontSize',7);  grid on;

    subplot(2,1,2);  hold on;
    pL_sm = movmean(pL_clean, win_pts, 'omitnan');
    pR_sm = movmean(pR_clean, win_pts, 'omitnan');
    plot(t_rest, pL_sm, 'b',               'LineWidth',1.5, 'DisplayName', ...
        sprintf('L smooth  µ=%.3f', mean(pL_sm,'omitnan')));
    plot(t_rest, pR_sm, 'Color',[0 0.6 0],  'LineWidth',1.5, 'DisplayName', ...
        sprintf('R smooth  µ=%.3f', mean(pR_sm,'omitnan')));
    yline(mean(pL_sm,'omitnan'), 'b--', 'LineWidth',1, 'HandleVisibility','off');
    yline(mean(pR_sm,'omitnan'), '--',  'Color',[0 0.6 0], 'LineWidth',1, 'HandleVisibility','off');
    ylabel('Diameter (mm)');
    xlabel('Time (s)');
    title(sprintf('Smoothed (%.2f s)  — Dashed = mean (used as baseline)', smooth_sec));
    legend('Location','best','FontSize',7);  grid on;
end

function add_event_lines(event_times)
    for i = 1:numel(event_times)
        xline(event_times(i),'k--','LineWidth',0.8,'HandleVisibility','off'); end
end

function mark_trial(t_start, t_end)
    if ~isnan(t_start)
        xline(t_start,'-','Color',[0 0.7 0],'LineWidth',2.5,...
            'Label','TRIAL START','LabelVerticalAlignment','bottom','HandleVisibility','off'); end
    if ~isnan(t_end)
        xline(t_end,'-','Color',[0.9 0.5 0],'LineWidth',2.5,...
            'Label','TRIAL END','LabelVerticalAlignment','bottom','HandleVisibility','off'); end
end

function [t_start, t_end] = parse_trial_events(events, t0_unix)
    t_start = NaN;  t_end = NaN;
    if isempty(events), return; end
    try
        for i = 1:height(events)
            if contains(events.data{i},'TRIAL_START'), t_start = events.recording_time(i) - t0_unix;
            elseif contains(events.data{i},'TRIAL_END'), t_end = events.recording_time(i) - t0_unix; end
        end
    catch; end
end

function data = load_if_exists(filepath)
    if exist(filepath,'file'), data = readtable(filepath); else, data = []; end
end

function gsr_col = get_gsr_col(gsr)
    if     ismember('GSR_ohm',                gsr.Properties.VariableNames), gsr_col = 'GSR_ohm';
    elseif ismember('GSR_Skin_Resistance_CAL',gsr.Properties.VariableNames), gsr_col = 'GSR_Skin_Resistance_CAL';
    else,  error('No GSR column found.'); end
end

function lbl = get_gsr_label(gsr)
    if contains(get_gsr_col(gsr),'CAL'), lbl = 'GSR (kOhm)'; else, lbl = 'GSR (Ohm)'; end
end

function r = init_responses(n)
    r = struct('has_scr',false,'scr_latency',NaN,'scr_amplitude',NaN,...
               'has_scl',false,'scl_change',NaN,'baseline',NaN);
    if n > 0, r = repmat(r,n,1); end
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
                if drv(edges(j)) > drv(edges(i)), keep(i)=false; else, keep(j)=false; end
            else, break; end
        end
    end
    times = t(edges(keep));
end

function [merged_times, merged_source] = merge_close_events_tagged(tagged, window)
    if isempty(tagged), merged_times=[]; merged_source=[]; return; end
    merged_times = tagged(1,1);  merged_source = tagged(1,2);
    for i = 2:size(tagged,1)
        if tagged(i,1)-merged_times(end) <= window
            if merged_source(end) ~= tagged(i,2), merged_source(end) = 3; end
        else
            merged_times  = [merged_times;  tagged(i,1)]; %#ok<AGROW>
            merged_source = [merged_source; tagged(i,2)]; %#ok<AGROW>
        end
    end
end

function [sig_ds, t_ds] = antialias_downsample(sig, t, fs_in, fs_out, order, ds_factor)
    Wn = min(fs_out/2*0.9 / (fs_in/2), 0.99);
    [b,a] = butter(order, Wn, 'low');
    sig_filt = filtfilt(b, a, double(sig));
    n_ds = floor(numel(sig_filt) / ds_factor);
    sig_ds = zeros(n_ds,1);  t_ds = zeros(n_ds,1);
    for k = 1:n_ds
        idx = (k-1)*ds_factor+1 : k*ds_factor;
        sig_ds(k) = mean(sig_filt(idx));  t_ds(k) = t(idx(1));
    end
end

function t_recon = reconstruct_timestamps_from_recording_time(recording_time, accel_fs)
% Reconstruct per-sample timestamps when only recording_time (ROS batch clock)
% is available instead of pc_time (per-sample hardware back-calculation).
%
% recording_time: the ROS clock stamped once per batch (same value repeated
%                 for all 300 samples in a batch). Corresponds approximately
%                 to the END of the batch (stamped after data arrives).

    n_samp     = numel(recording_time);
    t_recon    = zeros(n_samp, 1);

    % Find where the timestamp changes — these are batch boundaries
    anchor_idx = [1; find(diff(recording_time) > 0) + 1];
    anchor_t   = recording_time(anchor_idx);  % timestamp of each batch (≈ batch end time)

    for a = 1:numel(anchor_idx)
        i0 = anchor_idx(a);

        if a < numel(anchor_idx)
            i1 = anchor_idx(a+1) - 1;
        else
            i1 = n_samp;
        end

        n_in_batch = i1 - i0 + 1;

        % recording_time ≈ end of batch, so back-calculate like accelerometer_node.py does:
        %   sample_time = batch_end - (samples_from_end / fs)
        samples_from_end = (n_in_batch - 1 : -1 : 0)';
        t_recon(i0:i1) = anchor_t(a) - samples_from_end / accel_fs;
    end
end