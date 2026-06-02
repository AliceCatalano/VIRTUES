%% VIRTUES — Unified Analysis Script
<<<<<<< HEAD
% Sensors: GSR (Shimmer) | Eye tracker (Neon) | Accelerometer + Force (NI-DAQ) Audio Mixer (channels ch12–ch18)
% Dependencies: positiveFFT.m, cvxEDA.m (optional)

clear; clc; close all;
=======
% Sensors: GSR (Shimmer) | Eye tracker (Neon) | Accelerometer + Force (NI-DAQ)
%          Audio Mixer (channels ch12–ch18)
% Dependencies: positiveFFT.m, cvxEDA.m (optional)

clear; clc; %close all;
>>>>>>> woodPC


%  CONFIGURATION


<<<<<<< HEAD
BASE_FOLDER = '/run/user/1003/gvfs/smb-share:server=shark,share=acatalano';
SAVE_PATH   = '/home/acatalano/Desktop/Virtues';
=======
BASE_FOLDER = '/home/acatalano/VIRTUES/recordings';
>>>>>>> woodPC

% NI-DAQ
accel_fs          = 3000;    % hardware sample rate (Hz)
bp_low            = 80;      % bandpass low  cut (Hz)
bp_high           = 1000;    % bandpass high cut (Hz)
n_baseline_offset = 50;      % samples used for resting-offset removal
V2G               = 1/0.4;  % 0.4 V/g accelerometer sensitivity

% Audio mixer channels (as they appear in audio.csv columns)
<<<<<<< HEAD
audio_channels    = {'ch12','ch13','ch14','ch16','ch17','ch18'};
=======
audio_channels    = {'ch11','ch12','ch13','ch14','ch16','ch17'};
>>>>>>> woodPC
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
<<<<<<< HEAD
=======

>>>>>>> woodPC
save_figures = false;


%  SUBJECT & PHASE SELECTION  (same logic as sanity_check.m)


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

<<<<<<< HEAD
    % ----- RESTING STATE 
=======
    % ----- RESTING STATE --------------------------------------------------
>>>>>>> woodPC
    case '1'
        idx = input('Resting state index (1 or 2): ', 's');
        f   = fullfile(subject_folder, 'resting_state', sprintf('%s_r%s', subject_id, idx));
        folders_to_run = {{f, sprintf('Resting state %s', idx)}};

<<<<<<< HEAD
    % ----- BASELINE -----
=======
    % ----- BASELINE -------------------------------------------------------
>>>>>>> woodPC
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
<<<<<<< HEAD
            f = fullfile(baseline_folder, sprintf('Level%d', lv));
=======
            f = fullfile(baseline_folder, sprintf('Level%d_X', lv));
>>>>>>> woodPC
            folders_to_run{end+1} = {f, sprintf('Baseline%s/Level%d', acq, lv)}; %#ok<SAGROW>

            redo = fullfile(baseline_folder, sprintf('Level%d_R', lv));
            if isfolder(redo)
                folders_to_run{end+1} = {redo, sprintf('Baseline%s/Level%d_R', acq, lv)}; %#ok<SAGROW>
            end
        end

<<<<<<< HEAD
    % ----- TEST ---------
=======
    % ----- TEST -----------------------------------------------------------
>>>>>>> woodPC
    case '3'
        acq = input('Acquisition number (1, 2, or 3): ', 's');
        f   = fullfile(subject_folder, sprintf('Test%s', acq));
        folders_to_run = {{f, sprintf('Test%s', acq)}};

<<<<<<< HEAD
    % ----- REPETITIONS --
=======
    % ----- REPETITIONS ----------------------------------------------------
>>>>>>> woodPC
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


%  MAIN LOOP  (one iteration per folder/label pair)


all_results = table();

for fi = 1:numel(folders_to_run)

    data_folder = folders_to_run{fi}{1};
    fig_title   = folders_to_run{fi}{2};

    if ~isfolder(data_folder)
        fprintf('[%s] folder not found, skipping.\n', fig_title); continue
    end
    fprintf('\n%s  --  %s\n', fig_title, data_folder);

<<<<<<< HEAD
    % ---- LOAD FILES ----
=======
    % ---- LOAD FILES ------------------------------------------------------
>>>>>>> woodPC
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
<<<<<<< HEAD
=======
    
>>>>>>> woodPC

    % ---- BUILD SENSOR TABLES --------------------------------------------
    accel_raw         = table();
    accel_raw.xL      = nidaq.ai9;   accel_raw.yL = nidaq.ai10;   accel_raw.zL = nidaq.ai11;
    accel_raw.xR      = nidaq.ai12;   accel_raw.yR = nidaq.ai13;   accel_raw.zR = nidaq.ai14;
    %accel_raw.pc_time = nidaq.pc_time;

    force_raw    = table();
<<<<<<< HEAD
    force_raw.F1 = nidaq.ai15  - nidaq.ai15;  force_raw.F2 = nidaq.ai16  - nidaq.ai24;
=======
    force_raw.F1 = nidaq.ai7  - nidaq.ai15;  force_raw.F2 = nidaq.ai16  - nidaq.ai24;
>>>>>>> woodPC
    force_raw.F3 = nidaq.ai17  - nidaq.ai25;  force_raw.F4 = nidaq.ai18 - nidaq.ai26;
    force_raw.F5 = nidaq.ai19 - nidaq.ai27;  force_raw.F6 = nidaq.ai20 - nidaq.ai28;
    %force_raw.pc_time = nidaq.pc_time;
    % ---- TIMESTAMP: use pc_time if available, reconstruct otherwise ----------
    if ismember('pc_time', nidaq.Properties.VariableNames)
        fprintf('  Using pc_time (per-sample hardware timestamps)\n');
<<<<<<< HEAD
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

    % ---- AUDIO MIXER ---
=======
        accel_raw.t_unix = nidaq.pc_time;
        force_raw.t_unix = nidaq.pc_time;
    else
        fprintf('  WARNING: pc_time not found — reconstructing from recording_time\n');
        t_recon = reconstruct_timestamps_from_recording_time(nidaq.recording_time, accel_fs);
        accel_raw.t_unix = t_recon;
        force_raw.t_unix = t_recon;
    end

    gsr_col = get_gsr_col(gsr);

    % ---- AUDIO MIXER -----------------------------------------------------
>>>>>>> woodPC
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

<<<<<<< HEAD
    % ---- SANITY CHECKS 
    fprintf('\nSanity checks\n');
    fprintf('  Samples  accelc /force : %d\n', height(accel_raw));
=======
    % ---- SANITY CHECKS --------------------------------------------------
    fprintf('\nSanity checks\n');
    fprintf('  Samples  accel/force : %d\n', height(accel_raw));
>>>>>>> woodPC
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
<<<<<<< HEAD
    % ---- LOAD PRECOMPUTED COLLISIONS ------------------------------------

    collision_file = fullfile(data_folder, 'collision_unix.csv');
    
    if isfile(collision_file)
    
        collision_unix = readmatrix(collision_file);
    
        % Remove NaNs / invalid entries
        collision_unix = collision_unix(~isnan(collision_unix));
    
        % Convert UNIX timestamps to relative timeline
        all_collisions = collision_unix - t0_unix;
    
        % Keep only collisions inside trial window
        in_trial = all_collisions >= t_trial_start & ...
                   all_collisions <= t_trial_end;
    
        all_collisions = all_collisions(in_trial);
    
        fprintf('  Loaded %d collisions from collision_unix.csv\n', ...
            numel(all_collisions));
    
    else
    
        warning('collision_unix.csv not found in:\\n%s', data_folder);
    
        all_collisions = [];
    
    end
    
    % Source label retained for compatibility with existing plotting code
    collision_source = ones(numel(all_collisions),1);
=======
>>>>>>> woodPC

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

    % ---- ACCELEROMETER PLOTS (left + right) -----------------------------
    plot_accel_6panel(accel_raw.t, accel_raw.xL, accel_raw.yL, accel_raw.zL, ...
        t_ds, force_mag_ds, event_times, accel_fs, bp_low, bp_high, [fig_title ' | Accel LEFT']);
    plot_accel_6panel(accel_raw.t, accel_raw.xR, accel_raw.yR, accel_raw.zR, ...
        t_ds, force_mag_ds, event_times, accel_fs, bp_low, bp_high, [fig_title ' | Accel RIGHT']);

<<<<<<< HEAD
    % ---- FORCE PLOT ---
=======
    % ---- FORCE PLOT -----------------------------------------------------
>>>>>>> woodPC
    plot_force_7panel(force_raw, force_cols, t_ds, force_mag_ds, event_times, [fig_title ' | Force']);

    % ---- AUDIO MIXER PLOTS ----------------------------------------------
    if has_audio
        audio_fs_est = 1 / median(diff(audio.t(diff(audio.t) > 0)));
        plot_audio_mixer(audio, audio_present_ch, audio_fs_est, ...
            audio_bp_low, audio_bp_high, event_times, [fig_title ' | Audio Mixer']);
    end

    % ---- COLLISION DETECTION --------------------------------------------
<<<<<<< HEAD
    % mag_accel_native = max(sqrt(accel_raw.xL.^2 + accel_raw.yL.^2 + accel_raw.zL.^2), ...
    %                        sqrt(accel_raw.xR.^2 + accel_raw.yR.^2 + accel_raw.zR.^2));
    % [mag_accel_ds, t_ds] = antialias_downsample(mag_accel_native, accel_raw.t, ...
    %                            fs_native, target_fs_display, 4, ds_factor);
    % 
    % min_dist_smp = round(min_distance_sec * target_fs_display);
    % 
    % drv_a    = [0; abs(diff(mag_accel_ds))];
    % thresh_a = max(median(drv_a) + accel_sensitivity*mad(drv_a,1), prctile(drv_a,thresh_percentile));
    % accel_events = detect_peaks(drv_a, t_ds, thresh_a, min_dist_smp);
    % 
    % all_collisions   = accel_events;
    % collision_source = ones(numel(accel_events), 1);   % 1 = accel only
    % fprintf('  Collisions -- accel: %d\n', numel(all_collisions));
    % ---- ACCEL MAGNITUDE (for plotting only) -----------------------------

    mag_accel_native = max(sqrt(accel_raw.xL.^2 + accel_raw.yL.^2 + accel_raw.zL.^2), ...
        sqrt(accel_raw.xR.^2 + accel_raw.yR.^2 + accel_raw.zR.^2));
    
    [mag_accel_ds, t_ds] = antialias_downsample(mag_accel_native,accel_raw.t,fs_native, target_fs_display, 4,ds_factor);
    
    fprintf('  Using precomputed collisions from collision_unix.csv\n');
    fprintf('  Collisions loaded: %d\n', numel(all_collisions));

    % ---- GSR ANALYSIS -
=======
    mag_accel_native = max(sqrt(accel_raw.xL.^2 + accel_raw.yL.^2 + accel_raw.zL.^2), ...
                           sqrt(accel_raw.xR.^2 + accel_raw.yR.^2 + accel_raw.zR.^2));
    [mag_accel_ds, t_ds] = antialias_downsample(mag_accel_native, accel_raw.t, ...
                               fs_native, target_fs_display, 4, ds_factor);

    min_dist_smp = round(min_distance_sec * target_fs_display);

    drv_a    = [0; abs(diff(mag_accel_ds))];
    thresh_a = max(median(drv_a) + accel_sensitivity*mad(drv_a,1), prctile(drv_a,thresh_percentile));
    accel_events = detect_peaks(drv_a, t_ds, thresh_a, min_dist_smp);

    all_collisions   = accel_events;
    collision_source = ones(numel(accel_events), 1);   % 1 = accel only
    fprintf('  Collisions -- accel: %d\n', numel(all_collisions));

    % ---- GSR ANALYSIS ---------------------------------------------------
>>>>>>> woodPC
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

    if ~isempty(all_collisions)
        if cvx_ok
            [scr_thresh, scl_thresh] = compute_gsr_thresholds_cvx(p_cvx, t_cvx, scr_sensitivity, scl_sensitivity);
            gsr_responses = analyze_gsr_cvxEDA(gsr.t, p_cvx, t_cvx, all_collisions, ...
                baseline_before, scr_latency_window, scr_thresh, scl_window_start, scl_window_end, scl_thresh);
        else
            [scr_thresh, scl_thresh] = compute_gsr_thresholds_raw(gsr.(gsr_col), scr_sensitivity, scl_sensitivity);
            gsr_responses = analyze_gsr_raw(gsr.t, gsr.(gsr_col), all_collisions, ...
                baseline_before, scr_latency_window, scr_thresh, scl_window_start, scl_window_end, scl_thresh);
        end
        plot_gsr_overview(gsr, mag_accel_ds, force_mag_ds, t_ds, all_collisions, collision_source, ...
            gsr_responses, fig_title, cvx_ok, t_trial_start, t_trial_end);
        plot_each_collision(gsr, all_collisions, collision_source, gsr_responses, fig_title, cvx_ok, ...
            baseline_before, scr_latency_window, scl_window_end, t_trial_start, t_trial_end);
    else
        gsr_responses = init_responses(0);
        figure('Name', ['GSR: ' fig_title]);
        plot(gsr.t, gsr.(gsr_col), 'b', 'LineWidth',1);
        ylabel(gsr_col); xlabel('Time (s)'); title([fig_title ' | GSR (no collisions detected)']);
        grid on; hold on;  add_event_lines(event_times);
    end

    % ---- PUPIL DIAMETER -------------------------------------------------
    if ~isempty(eye) && all(ismember({'pupil_diameter_left','pupil_diameter_right'}, eye.Properties.VariableNames))
        plot_pupil(eye, event_times, pupil_smooth_sec, fig_title);
    end

    % ---- UNIFIED OVERVIEW FIGURE ----------------------------------------
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
        event_times, event_labels, all_collisions, collision_source, ...
        accel_fs, bp_low, bp_high, audio_bp_low, audio_bp_high, ...
        pupil_smooth_sec, cvx_ok, t_trial_start, t_trial_end, fig_title);

<<<<<<< HEAD
    % ---- STORE RESULTS 
=======
    % ---- STORE RESULTS --------------------------------------------------
>>>>>>> woodPC
    for i = 1:numel(all_collisions)
        r.level          = fig_title;
        r.collision_time = all_collisions(i);
        r.has_scr        = gsr_responses(i).has_scr;
        r.scr_latency_s  = gsr_responses(i).scr_latency;
        r.scr_amplitude  = gsr_responses(i).scr_amplitude;
        r.has_scl        = gsr_responses(i).has_scl;
        r.scl_change     = gsr_responses(i).scl_change;
        r.baseline       = gsr_responses(i).baseline;
        all_results = [all_results; struct2table(r,'AsArray',true)]; %#ok<AGROW>
    end

    if save_figures
        figs = findall(0,'Type','figure');
        for fii = 1:numel(figs)
            if contains(get(figs(fii),'Name'), fig_title)
<<<<<<< HEAD
                saveas(figs(fii), fullfile(SAVE_PATH, [strrep(get(figs(fii),'Name'),' ','_') '.png']));
=======
                saveas(figs(fii), fullfile(data_folder, [strrep(get(figs(fii),'Name'),' ','_') '.png']));
>>>>>>> woodPC
            end
        end
    end

    fprintf('  %s done.\n', fig_title);
end

if ~isempty(all_results)
    fprintf('\nSUMMARY (all folders)\n');
    disp(all_results);
end
fprintf('\n==========================================================\n');
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

% ---- Accel 6-panel (per side) -------------------------------------------
function plot_accel_6panel(t, x, y, z, t_force, force_mag, event_times, Fs, bp_lo, bp_hi, fig_title)
    xbp   = bandpass(x,[bp_lo bp_hi],Fs);  ybp = bandpass(y,[bp_lo bp_hi],Fs);
    zbp   = bandpass(z,[bp_lo bp_hi],Fs);  sumbp = xbp + ybp + zbp;
    [SPEC_f, freq] = positiveFFT(sumbp, Fs);

    figure('Name',fig_title,'Position',[50 50 1400 1100]);
    sgtitle(fig_title,'FontWeight','bold','FontSize',10);

    ax1 = subplot(6,1,1);
    plot(t,xbp,'Color',[0.8 0.1 0.1],'LineWidth',0.6);
    ylabel('X (g)'); title('X axis (bandpassed)'); grid on; add_event_lines(event_times);

    ax2 = subplot(6,1,2);
    plot(t,ybp,'Color',[0.1 0.6 0.1],'LineWidth',0.6);
    ylabel('Y (g)'); title('Y axis (bandpassed)'); grid on; add_event_lines(event_times);

    ax3 = subplot(6,1,3);
    plot(t,zbp,'Color',[0.1 0.2 0.8],'LineWidth',0.6);
    ylabel('Z (g)'); title('Z axis (bandpassed)'); grid on; add_event_lines(event_times);

    ax4 = subplot(6,1,4);
    plot(t,sumbp,'Color',[0.5 0 0.7],'LineWidth',0.6);
    ylabel('Sum (g)'); title('Sum X+Y+Z (bandpassed)'); grid on; add_event_lines(event_times);

    ax5 = subplot(6,1,5);
    plot(freq,abs(SPEC_f),'k','LineWidth',0.7);
    xlabel('Frequency (Hz)'); ylabel('|FFT|'); title('Spectrum of Sum'); grid on; xlim([0 Fs/2]);

    ax6 = subplot(6,1,6);
    plot(t_force,force_mag,'Color',[0.5 0 0.5],'LineWidth',0.8);
    ylabel('|Force| (V)'); title('Force magnitude (downsampled)'); grid on; add_event_lines(event_times);

    linkaxes([ax1 ax2 ax3 ax4 ax6],'x');
    xlabel(ax6,'Time (s)');
end

<<<<<<< HEAD
% ---- Force 7-panel -----
=======
% ---- Force 7-panel -------------------------------------------------------
>>>>>>> woodPC
function plot_force_7panel(force_raw, force_cols, t_ds, force_mag_ds, event_times, fig_title)
    figure('Name',fig_title,'Position',[80 80 1400 1200]);
    sgtitle(fig_title,'FontWeight','bold','FontSize',10);
    clrs = lines(numel(force_cols));
    ax   = gobjects(7,1);
    for k = 1:numel(force_cols)
        c = force_cols{k};
        ax(k) = subplot(7,1,k);
        plot(force_raw.t,force_raw.(c),'Color',clrs(k,:),'LineWidth',0.6);
        ylabel([c ' (V)']); title(c); grid on; add_event_lines(event_times);
    end
    ax(7) = subplot(7,1,7);
    plot(t_ds,force_mag_ds,'Color',[0.5 0 0.5],'LineWidth',1.0);
    ylabel('|Force| (V)'); title('Force magnitude (downsampled)'); grid on; add_event_lines(event_times);
    linkaxes(ax,'x');  xlabel(ax(7),'Time (s)');
end

% ---- Audio mixer multi-panel plot ----------------------------------------
function plot_audio_mixer(audio, channels, fs_audio, bp_lo, bp_hi, event_times, fig_title)
% One panel per channel (bandpassed, FFT underneath) + a summary panel
% showing all channels overlaid and their bandpassed sum.

    nch = numel(channels);
    n_panels = nch + 2;   % one per channel + sum panel + FFT panel

    figure('Name', fig_title, 'Position', [60 60 1600 min(200*n_panels, 1400)]);
    sgtitle(fig_title, 'FontWeight','bold', 'FontSize', 10);

    ax = gobjects(n_panels, 1);
    clrs = lines(nch);

    sum_bp = zeros(height(audio), 1);

    for k = 1:nch
        ch  = channels{k};
        raw = double(audio.(ch));

        % DC removal
        raw = raw - mean(raw, 'omitnan');

        % Bandpass (only if enough samples)
        if numel(raw) > 10 * fs_audio
            raw_bp = bandpass(raw, [bp_lo bp_hi], fs_audio);
        else
            raw_bp = raw;
        end

        sum_bp = sum_bp + raw_bp;

        ax(k) = subplot(n_panels, 1, k);
        plot(audio.t, raw_bp, 'Color', clrs(k,:), 'LineWidth', 0.5);
        ylabel('V'); title(sprintf('%s (bandpassed %d–%d Hz)', ch, bp_lo, bp_hi));
        grid on;
        add_event_lines(event_times);
    end

    % Sum panel
    ax(nch+1) = subplot(n_panels, 1, nch+1);
    plot(audio.t, sum_bp, 'Color', [0.2 0.2 0.8], 'LineWidth', 0.8);
    ylabel('V'); title(sprintf('Mixer sum (all %d channels, bandpassed)', nch));
    grid on;
    add_event_lines(event_times);

    % FFT of sum
    ax(nch+2) = subplot(n_panels, 1, nch+2);
    [Sfft, freqs] = positiveFFT(sum_bp, fs_audio);
    plot(freqs, abs(Sfft), 'k', 'LineWidth', 0.7);
    xlabel('Frequency (Hz)');
    ylabel('|FFT|');
    title('Spectrum of mixer sum');
    xlim([0 min(fs_audio/2, 2000)]);
    grid on;

    linkaxes(ax(1:nch+1), 'x');
    xlabel(ax(nch+1), 'Time (s)');
end

<<<<<<< HEAD
% ---- Pupil diameter ----
=======
% ---- Pupil diameter ------------------------------------------------------
>>>>>>> woodPC
function plot_pupil(eye, event_times, smooth_sec, fig_title)
    fs_eye    = 1 / median(diff(eye.timestamp_unix_seconds));
    win_pts   = max(3, round(fs_eye * smooth_sec));
    pL_smooth = movmean(eye.pupil_diameter_left,  win_pts,'omitnan');
    pR_smooth = movmean(eye.pupil_diameter_right, win_pts,'omitnan');

    figure('Name',[fig_title ' | Pupil'],'Position',[60 60 1400 400]);
    sgtitle(sprintf('%s | Pupil diameter  (%.2f s smoothing, %.0f Hz)',fig_title,smooth_sec,fs_eye),...
        'FontWeight','bold','FontSize',10);

    plot(eye.t,eye.pupil_diameter_left, 'Color',[0.6 0.6 1.0],'LineWidth',0.5,'DisplayName','Left raw');  hold on;
    plot(eye.t,eye.pupil_diameter_right,'Color',[0.6 1.0 0.6],'LineWidth',0.5,'DisplayName','Right raw');
    plot(eye.t,pL_smooth,'b','LineWidth',1.5,'DisplayName','Left smoothed');
    plot(eye.t,pR_smooth,'g','LineWidth',1.5,'DisplayName','Right smoothed');
    add_event_lines(event_times);
    xlabel('Time (s)'); ylabel('Pupil diameter (mm)'); legend('Location','best'); grid on;
end

<<<<<<< HEAD
% ---- GSR overview ------
=======
% ---- GSR overview --------------------------------------------------------
>>>>>>> woodPC
function plot_gsr_overview(gsr, mag_accel_ds, force_mag_ds, t_ds, collision_times, collision_source, ...
        gsr_responses, title_str, has_cvx, t_trial_start, t_trial_end)
    gsr_col   = get_gsr_col(gsr);
    gsr_label = 'GSR (Ohm)';  if contains(gsr_col,'CAL'), gsr_label = 'GSR (kOhm)'; end
    n_plots   = 3 + has_cvx;
    figure('Name',['GSR Overview: ' title_str],'Position',[30 30 1600 210*n_plots]);
    p = 0;

    p = p+1;  subplot(n_plots,1,p);
    plot(t_ds,mag_accel_ds,'b','LineWidth',0.8); hold on;
    mark_collisions(collision_times);  mark_trial(t_trial_start,t_trial_end);
    ylabel('|accel| (g)'); title('Accelerometer magnitude'); grid on;

    p = p+1;  subplot(n_plots,1,p);
    plot(t_ds,force_mag_ds,'Color',[0.5 0 0.5],'LineWidth',0.8); hold on;
    mark_collisions(collision_times);  mark_trial(t_trial_start,t_trial_end);
    ylabel('|force| (V)'); title('Force magnitude'); grid on;

    p = p+1;  subplot(n_plots,1,p);
    plot(gsr.t,gsr.(gsr_col),'b','LineWidth',1); hold on;
    yl = ylim;
    for i = 1:numel(collision_times)
        switch collision_source(i)
            case 1, ls='-';  src_sym='A';
            case 2, ls='--'; src_sym='F';
            case 3, ls=':';  src_sym='B';
            otherwise, ls='--'; src_sym='?';
        end
        r = gsr_responses(i);
        if r.has_scr && r.has_scl, col=[0.8 0 0];
        elseif r.has_scr,          col=[0.8 0 0.8];
        elseif r.has_scl,          col=[0 0.6 0.7];
        else,                      col=[0.4 0.4 0.4]; end
        xline(collision_times(i),ls,'Color',col,'LineWidth',2,'HandleVisibility','off');
        text(collision_times(i),yl(2),sprintf('%d%s',i,src_sym),'FontSize',7,'Color',col,...
            'HorizontalAlignment','center','VerticalAlignment','top');
    end
    mark_trial(t_trial_start,t_trial_end);
    ylabel(gsr_label); title('Raw GSR  (red=SCR+SCL  magenta=SCR  cyan=SCL  grey=none)'); grid on;

    if has_cvx
        p = p+1;  subplot(n_plots,1,p); hold on;
        plot(gsr.t,gsr.scl,'b','LineWidth',1.2,'DisplayName','Tonic SCL');
        plot(gsr.t,gsr.scr,'r','LineWidth',0.8,'DisplayName','Phasic SCR');
        mark_collisions(collision_times);  mark_trial(t_trial_start,t_trial_end);
        legend('Location','best'); ylabel('z-uS');
        title('cvxEDA: Tonic SCL (blue) + Phasic SCR (red)'); grid on;
    end
    sgtitle([title_str ' | solid=accel  dash=force  dot=both | red=SCR+SCL  mag=SCR  cyan=SCL  grey=none'],...
        'FontWeight','bold','FontSize',8);
end

% ---- Per-collision GSR panels -------------------------------------------
function plot_each_collision(gsr, collision_times, collision_source, gsr_responses, ...
        title_str, has_cvx, baseline_before, scr_window, scl_end, t_trial_start, t_trial_end)
    n = numel(collision_times);  n_cols = min(3,n);  n_rows = ceil(n/n_cols);
    figure('Name',['Collision Detail: ' title_str],'Position',[50 50 n_cols*500 n_rows*360]);
    for i = 1:n
        ax = subplot(n_rows,n_cols,i);
        plot_collision_panel(ax,gsr,get_gsr_col(gsr),get_gsr_label(gsr),...
            collision_times(i),collision_source(i),gsr_responses(i),i,n,...
            has_cvx,baseline_before,scr_window,scl_end,t_trial_start,t_trial_end);
    end
    sgtitle(['Collisions: ' title_str ' | A=accel  F=force  B=both | red=SCR+SCL  mag=SCR  cyan=SCL'],...
        'FontWeight','bold','FontSize',8);
end

% ---- Single collision GSR panel -----------------------------------------
function plot_collision_panel(ax, gsr, gsr_col, gsr_label, t_col, src, resp, ...
        col_idx, n_total, has_cvx, baseline_before, scr_window, scl_end, t_trial_start, t_trial_end)
    pre_s = baseline_before+0.5;  post_s = scl_end+1.5;
    zm    = (gsr.t >= t_col-pre_s) & (gsr.t <= t_col+post_s);
    t_rel = gsr.t(zm) - t_col;
    if ~any(zm), title(ax,sprintf('Col %d -- no data',col_idx)); return; end

    plot(ax,t_rel,gsr.(gsr_col)(zm),'b','LineWidth',1.2); hold(ax,'on');
    if has_cvx && ismember('scr',gsr.Properties.VariableNames)
        yyaxis(ax,'right');
        plot(ax,t_rel,gsr.scr(zm),'r','LineWidth',1,'DisplayName','SCR');
        plot(ax,t_rel,gsr.scl(zm),'Color',[0 0.6 0],'LineWidth',1,'DisplayName','SCL');
        ylabel(ax,'SCR/SCL (z-uS)');  yyaxis(ax,'left');
    end
    xline(ax, 0,               'r--','LineWidth',1.8,'HandleVisibility','off');
    xline(ax,-baseline_before, ':' ,'Color',[0.5 0.5 0.5],'LineWidth',1,'HandleVisibility','off');
    xline(ax, scr_window,      '--','Color',[0.9 0.5 0],  'LineWidth',1,'HandleVisibility','off');
    xline(ax, scl_end,         ':' ,'Color',[0 0.6 0.7],  'LineWidth',1,'HandleVisibility','off');
    if ~isnan(resp.baseline)
        yline(ax,resp.baseline,'--','Color',[0 0 0.7],'LineWidth',1,'HandleVisibility','off'); end
    for tr_t = {t_trial_start, t_trial_end}
        tr = tr_t{1};
        if ~isnan(tr) && (tr-t_col) >= -pre_s && (tr-t_col) <= post_s
            xline(ax,tr-t_col,'-','Color',[0 0.7 0],'LineWidth',2,'HandleVisibility','off'); end
    end
    if resp.has_scr
        idx = find(gsr.t >= t_col+resp.scr_latency,1);
        if ~isempty(idx) && zm(idx)
            plot(ax,resp.scr_latency,gsr.(gsr_col)(idx),'ro','MarkerSize',8,'LineWidth',2,'HandleVisibility','off'); end
    end
    src_names  = {'Accel','Force','Both'};
    src_colors = {[0.2 0.4 0.9],[0.6 0.1 0.6],[0.1 0.6 0.1]};
    src_name   = src_names{min(src,3)};  src_col = src_colors{min(src,3)};
    scr_str = '-';  scl_str = '-';
    if resp.has_scr, scr_str = sprintf('lat=%.2fs amp=%.1f',resp.scr_latency,resp.scr_amplitude); end
    if resp.has_scl, scl_str = sprintf('D=%.1f',resp.scl_change); end
    title(ax,sprintf('#%d/%d  t=%.2fs  [%s]\nSCR:%s  SCL:%s',col_idx,n_total,t_col,src_name,scr_str,scl_str),'FontSize',8);
    text(ax,0.01,0.99,src_name,'Units','normalized','FontSize',8,'FontWeight','bold','Color',src_col,...
        'VerticalAlignment','top','BackgroundColor',[src_col 0.15]);
    xlabel(ax,'Time rel. collision (s)'); ylabel(ax,gsr_label); grid(ax,'on');
end

% ---- UNIFIED OVERVIEW FIGURE --------------------------------------------
function plot_unified_overview(accel_raw, force_raw, force_mag_ds, t_ds, ...
        mag_accel_ds, gsr, audio, audio_present_ch, eye, ...
        event_times, event_labels, all_collisions, collision_source, ...
        accel_fs, bp_lo, bp_hi, audio_bp_lo, audio_bp_hi, ...
        pupil_smooth_sec, cvx_ok, t_trial_start, t_trial_end, fig_title)

    gsr_col   = get_gsr_col(gsr);
    gsr_label = 'GSR (Ohm)';
    if contains(gsr_col,'CAL'), gsr_label = 'GSR (kOhm)'; end

    has_audio = ~isempty(audio) && ~isempty(audio_present_ch);
    has_eye   = ~isempty(eye) && all(ismember({'pupil_diameter_left','pupil_diameter_right',...
                 'timestamp_unix_seconds'}, eye.Properties.VariableNames));

    % Determine number of rows: accel_sum | [audio_sum] | force | gsr | [pupil]
    n_rows = 3 + has_audio + has_eye;

    figure('Name', ['OVERVIEW: ' fig_title], ...
           'Position', [20 20 1700 220*n_rows]);
    sgtitle(sprintf('%s  |  Unified Overview', fig_title), ...
            'FontWeight','bold','FontSize',11);

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
    mark_collisions_colored(all_collisions, collision_source);
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
        mark_collisions_colored(all_collisions, collision_source);
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
    add_event_lines(event_times);
    mark_collisions_colored(all_collisions, collision_source);
    mark_trial(t_trial_start, t_trial_end);

    % ---- Row 4: GSR (raw or tonic SCL) ----------------------------------
    row = row + 1;
    ax(row) = subplot(n_rows, 1, row);
    hold on;

    if cvx_ok && ismember('scl', gsr.Properties.VariableNames)
        yyaxis left;
        plot(gsr.t, gsr.(gsr_col), 'Color',[0.6 0.6 1.0], 'LineWidth',0.6, 'DisplayName','GSR raw');
        ylabel(gsr_label);
        yyaxis right;
        plot(gsr.t, gsr.scl, 'b', 'LineWidth',1.2, 'DisplayName','SCL (tonic)');
        plot(gsr.t, gsr.scr, 'r', 'LineWidth',0.7, 'DisplayName','SCR (phasic)');
        ylabel('z-µS');
        yyaxis left;
    else
        plot(gsr.t, gsr.(gsr_col), 'b', 'LineWidth',1.0, 'DisplayName','GSR raw');
        ylabel(gsr_label);
    end

    title('GSR  (blue=tonic SCL  red=phasic SCR  if cvxEDA available)');
    legend('Location','northeast','FontSize',7);
    grid on;
    add_event_lines(event_times);
    mark_collisions_colored(all_collisions, collision_source);
    mark_trial(t_trial_start, t_trial_end);

    % ---- Row 5 (optional): Pupil diameter smoothed ----------------------
    if has_eye
        row = row + 1;
        ax(row) = subplot(n_rows, 1, row);
        hold on;

        fs_eye  = 1 / median(diff(eye.timestamp_unix_seconds));
        win_pts = max(3, round(fs_eye * pupil_smooth_sec));
        pL_sm   = movmean(eye.pupil_diameter_left,  win_pts, 'omitnan');
        pR_sm   = movmean(eye.pupil_diameter_right, win_pts, 'omitnan');

        plot(eye.t, eye.pupil_diameter_left,  'Color',[0.7 0.7 1.0], 'LineWidth',0.4, 'DisplayName','L raw');
        plot(eye.t, eye.pupil_diameter_right, 'Color',[0.7 1.0 0.7], 'LineWidth',0.4, 'DisplayName','R raw');
        plot(eye.t, pL_sm, 'b', 'LineWidth',1.4, 'DisplayName','L smooth');
        plot(eye.t, pR_sm, 'Color',[0 0.6 0], 'LineWidth',1.4, 'DisplayName','R smooth');

        ylabel('Diameter (mm)');
        title(sprintf('Pupil diameter  (%.2f s moving avg, %.0f Hz)', pupil_smooth_sec, fs_eye));
        legend('Location','northeast','FontSize',7);
        grid on;
        add_event_lines(event_times);
        mark_collisions_colored(all_collisions, collision_source);
        mark_trial(t_trial_start, t_trial_end);
        xlabel('Time (s)');
    else
        xlabel(ax(row), 'Time (s)');
    end

    % Link all time axes
    linkaxes(ax(1:row), 'x');

    % Annotate event labels above the top panel
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


function add_event_lines(event_times)
    for i = 1:numel(event_times)
        xline(event_times(i),'k--','LineWidth',0.8,'HandleVisibility','off'); end
end

function mark_collisions(times)
    for i = 1:numel(times)
        xline(times(i),'r-','LineWidth',1,'HandleVisibility','off'); end
end

function mark_collisions_colored(times, sources)
% Same as mark_collisions but colour-coded by source:
%   Accel=blue  Force=magenta  Both=green
    src_colors = {[0.2 0.4 0.9], [0.6 0.1 0.6], [0.1 0.6 0.1]};
    for i = 1:numel(times)
        col = src_colors{min(sources(i), 3)};
        xline(times(i),'-','Color',col,'LineWidth',1.5,'HandleVisibility','off');
    end
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

function responses = analyze_gsr_cvxEDA(t_gsr, scr, scl, collision_times, ...
        baseline_before, scr_window, scr_thresh, scl_start, scl_end, scl_thresh)
    responses = init_responses(numel(collision_times));
    for i = 1:numel(collision_times)
        t0 = collision_times(i);
        bl_mask = (t_gsr >= t0-baseline_before) & (t_gsr < t0);
        if ~any(bl_mask), continue; end
        baseline_scl = mean(scl(bl_mask));  responses(i).baseline = baseline_scl;
        scr_mask = (t_gsr >= t0) & (t_gsr < t0+scr_window);
        if any(scr_mask)
            [pk,pi] = max(scr(scr_mask));  t_rel = t_gsr(scr_mask) - t0;
            if pk > scr_thresh
                responses(i).has_scr = true;  responses(i).scr_latency = t_rel(pi);
                responses(i).scr_amplitude = pk; end
        end
        scl_mask = (t_gsr >= t0+scl_start) & (t_gsr < t0+scl_end);
        if sum(scl_mask) > 3
            chg = mean(scl(scl_mask)) - baseline_scl;
            if abs(chg) > scl_thresh
                responses(i).has_scl = true;  responses(i).scl_change = chg; end
        end
    end
end

function responses = analyze_gsr_raw(t_gsr, gsr_raw, collision_times, ...
        baseline_before, scr_window, scr_thresh, scl_start, scl_end, scl_thresh)
    responses = init_responses(numel(collision_times));
    for i = 1:numel(collision_times)
        t0 = collision_times(i);
        bl_mask = (t_gsr >= t0-baseline_before) & (t_gsr < t0);
        if ~any(bl_mask), continue; end
        bl_mean = mean(gsr_raw(bl_mask));  responses(i).baseline = bl_mean;
        scr_mask = (t_gsr >= t0) & (t_gsr < t0+scr_window);
        if any(scr_mask)
            seg = gsr_raw(scr_mask);  t_rel = t_gsr(scr_mask) - t0;
            [mn,mi] = min(seg);  amp = bl_mean - mn;
            if amp > scr_thresh
                responses(i).has_scr = true;  responses(i).scr_latency = t_rel(mi);
                responses(i).scr_amplitude = amp; end
        end
        scl_mask = (t_gsr >= t0+scl_start) & (t_gsr < t0+scl_end);
        if sum(scl_mask) > 3
            chg = bl_mean - mean(gsr_raw(scl_mask));
            if abs(chg) > scl_thresh
                responses(i).has_scl = true;  responses(i).scl_change = chg; end
        end
    end
end

function [scr_thresh, scl_thresh] = compute_gsr_thresholds_cvx(p_cvx, t_cvx, scr_sens, scl_sens)
    abs_p = abs(p_cvx);
    scr_thresh = max(median(abs_p) + scr_sens*mad(abs_p,1), 1e-4);
    delta_scl  = abs(diff(t_cvx));
    scl_thresh = max(median(delta_scl) + scl_sens*mad(delta_scl,1), 1e-4);
end

function [scr_thresh, scl_thresh] = compute_gsr_thresholds_raw(gsr_raw, scr_sens, scl_sens)
    delta_fast = abs(diff(gsr_raw));
    scr_thresh = max(median(delta_fast) + scr_sens*mad(delta_fast,1), 1.0);
    gsr_smooth = movmean(gsr_raw, max(3,round(numel(gsr_raw)*0.01)));
    delta_slow = abs(diff(gsr_smooth));
    scl_thresh = max(median(delta_slow) + scl_sens*mad(delta_slow,1), 0.5);
end
<<<<<<< HEAD

=======
>>>>>>> woodPC
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