%% VIRTUES — Unified Analysis Script  (phase-split refactor)
% Sensors: GSR (Shimmer) | Eye tracker (Neon) | Accelerometer + Force (NI-DAQ) | Audio Mixer (ch12–ch18)
% Dependencies: positiveFFT.m, cvxEDA.m (optional)
%
% PHASE FUNCTIONS
%   analyse_resting_state  – GSR baseline stats + pupil baseline
%   analyse_baseline       – all sensors, differentiated events, collision detection, audio comparison
%   analyse_test           – same as baseline (full sensor suite)
%   analyse_level          – same as baseline (per repetition)
%
% Each phase function returns a results struct ready for future statistical analysis.

clear; clc; close all;



%  GLOBAL CONFIGURATION


cfg = struct();

% Paths
cfg.BASE_FOLDER = '/home/acatalano/Desktop/Virtues';

% NI-DAQ
cfg.accel_fs          = 3000;   % hardware sample rate (Hz)
cfg.bp_low            = 80;     % bandpass low  cut (Hz)
cfg.bp_high           = 1000;   % bandpass high cut (Hz)
cfg.n_baseline_offset = 50;     % samples used for resting-offset removal
cfg.V2G               = 1/0.4; % 0.4 V/g accelerometer sensitivity

% Audio mixer channels (as they appear in audio.csv columns)
cfg.audio_channels = {'ch12','ch13','ch14','ch16','ch17','ch18'};
cfg.audio_bp_low   = 80;
cfg.audio_bp_high  = 1000;

% Collision detection
cfg.target_fs_display = 500;    % downsample target for detection + display (Hz)
cfg.accel_sensitivity = 20;     % threshold = median + k*MAD on derivative
cfg.force_sensitivity = 15;
cfg.min_distance_sec  = 2.0;    % minimum gap between successive collisions (s)
cfg.merge_window_sec  = 0.50;   % accel+force events within this window -> merged
cfg.thresh_percentile = 99;     % hard-floor percentile of derivative

% GSR / cvxEDA
cfg.use_cvxEDA         = true;
cfg.gsr_unit           = 'ohm'; % 'ohm' or 'kohm'
cfg.scr_latency_window = 5.0;   % s post-collision to search for SCR peak
cfg.scl_window_start   = 2.0;   % tonic window start (s after collision)
cfg.scl_window_end     = 8.0;   % tonic window end   (s after collision)
cfg.baseline_before    = 2.0;   % s of pre-collision baseline
cfg.scr_sensitivity    = 2.5;   % n*MAD phasic threshold
cfg.scl_sensitivity    = 2.0;   % n*MAD tonic threshold

% Eye
cfg.pupil_smooth_sec = 0.3;     % pupil moving-average window (s)

cfg.save_figures = false;



%  SUBJECT & PHASE SELECTION


fprintf('VIRTUES — ANALYSIS\n\n');

subject_id = input('Subject ID (e.g. S001): ', 's');
subject_folder = fullfile(cfg.BASE_FOLDER, subject_id);

if ~isfolder(subject_folder)
    fprintf('[ERROR] Subject folder not found:\n  %s\n', subject_folder); return
end

fprintf('\nPhases available:\n');
fprintf('  1 - Resting state\n');
fprintf('  2 - Baseline\n');
fprintf('  3 - Test\n');
fprintf('  4 - Repetitions (level trials)\n');
phase = input('Select phase (1-4): ', 's');

all_results = struct();

switch phase

    % ---------------------------------------------------------------
    case '1'   % RESTING STATE
        idx = input('Resting state index (1 or 2): ', 's');
        f   = fullfile(subject_folder, 'resting_state', sprintf('%s_r%s', subject_id, idx));
        lbl = sprintf('Resting state %s', idx);
        if ~isfolder(f), fprintf('[ERROR] Not found: %s\n', f); return; end
        all_results.(matlab.lang.makeValidName(lbl)) = ...
            analyse_resting_state(f, lbl, cfg);

    % ---------------------------------------------------------------
    case '2'   % BASELINE
        acq = input('Acquisition number (1 or 2): ', 's');
        baseline_folder = fullfile(subject_folder, sprintf('Baseline%s', acq));
        if ~isfolder(baseline_folder)
            fprintf('[ERROR] Not found: %s\n', baseline_folder); return
        end
        lv_choice = input('Level (1-5) or all (Enter): ', 's');
        if isempty(lv_choice), levels = 1:5; else, levels = str2double(lv_choice); end

        for lv = levels
            for suffix = {sprintf('Level%d',lv), sprintf('Level%d_R',lv)}
                f   = fullfile(baseline_folder, suffix{1});
                lbl = sprintf('Baseline%s/%s', acq, suffix{1});
                if ~isfolder(f), continue; end
                all_results.(matlab.lang.makeValidName(lbl)) = ...
                    analyse_baseline(f, lbl, cfg);
            end
        end

    % ---------------------------------------------------------------
    case '3'   % TEST
        acq = input('Acquisition number (1, 2, or 3): ', 's');
        f   = fullfile(subject_folder, sprintf('Test%s', acq));
        lbl = sprintf('Test%s', acq);
        if ~isfolder(f), fprintf('[ERROR] Not found: %s\n', f); return; end
        all_results.(matlab.lang.makeValidName(lbl)) = ...
            analyse_test(f, lbl, cfg);

    % ---------------------------------------------------------------
    case '4'   % LEVEL REPETITIONS
        level = input('Level (e.g. L1): ', 's');
        level_folder = fullfile(subject_folder, sprintf('level_%s', upper(level)));
        if ~isfolder(level_folder)
            fprintf('[ERROR] Not found: %s\n', level_folder); return
        end
        rep_choice = input('Rep (1-10) or all (Enter): ', 's');
        if isempty(rep_choice), reps = 1:10; else, reps = str2double(rep_choice); end

        for rep = reps
            for suffix = {sprintf('rep_%02d',rep), sprintf('rep_%02d_R',rep)}
                f   = fullfile(level_folder, suffix{1});
                lbl = sprintf('%s/%s', upper(level), suffix{1});
                if ~isfolder(f), continue; end
                all_results.(matlab.lang.makeValidName(lbl)) = ...
                    analyse_level(f, lbl, cfg);
            end
        end

    otherwise
        fprintf('[ERROR] Unknown phase selection.\n'); return
end

% ---- Summary printout ---------------------------------------------------
fprintf('\n==========================================================\n');
fprintf('                  ANALYSIS COMPLETE\n');
fn = fieldnames(all_results);
for k = 1:numel(fn)
    fprintf('\n--- %s ---\n', fn{k});
    r = all_results.(fn{k});
    if isstruct(r), disp(r); end
end
fprintf('==========================================================\n');



%  PHASE 1 — RESTING STATE
%  Sensors shown : GSR + Eye tracker
%  Metrics       : GSR mean/std/range (baseline stats), pupil mean/std,
%                  blink rate, optional cvxEDA tonic level

function results = analyse_resting_state(data_folder, fig_title, cfg)

    fprintf('\n[RESTING STATE]  %s\n  %s\n', fig_title, data_folder);

    % ---- Load -------------------------------------------------------
    gsr    = load_if_exists(fullfile(data_folder, 'gsr.csv'));
    eye    = load_if_exists(fullfile(data_folder, 'eye.csv'));
    events = load_if_exists(fullfile(data_folder, 'events.csv'));

    if isempty(gsr),   fprintf('  [SKIP] gsr.csv missing.\n');   results=[]; return; end
    if height(gsr) > 5, gsr(1:5,:) = []; end

    if isempty(events)
        events = table('Size',[0 2],'VariableTypes',{'double','cell'},...
                       'VariableNames',{'recording_time','data'});
    end

    % ---- Timeline ---------------------------------------------------
    all_unix = gsr.pc_time;
    if ~isempty(eye), all_unix = [all_unix; eye.timestamp_unix_seconds]; end
    all_unix = [all_unix; events.recording_time];
    t0       = min(all_unix);

    gsr.t       = gsr.pc_time - t0;
    event_times = events.recording_time - t0;
    event_labels = events.data;
    if ~isempty(eye), eye.t = eye.timestamp_unix_seconds - t0; end

    gsr_col   = get_gsr_col(gsr);
    fs_gsr    = 1 / median(diff(gsr.pc_time(diff(gsr.pc_time)>0)));

    % ---- GSR BASELINE METRICS ---------------------------------------
    gsr_signal = gsr.(gsr_col);
    gsr_mean   = mean(gsr_signal, 'omitnan');
    gsr_std    = std(gsr_signal,  'omitnan');
    gsr_range  = range(gsr_signal);
    fprintf('\n  GSR Baseline Stats\n');
    fprintf('    Mean  : %.2f\n', gsr_mean);
    fprintf('    Std   : %.2f\n', gsr_std);
    fprintf('    Range : %.2f\n', gsr_range);
    fprintf('    fs    : %.2f Hz\n', fs_gsr);

    % Optional cvxEDA tonic baseline
    cvx_ok = false;  scl_mean = NaN;  scl_std = NaN;
    if cfg.use_cvxEDA
        conductance_uS = 1e6 ./ gsr_signal;
        if strcmp(cfg.gsr_unit,'kohm'), conductance_uS = 1000 ./ gsr_signal; end
        yn = zscore(conductance_uS);
        for si = 1:3
            sv_list = {'quadprog','sedumi',''};  sv = sv_list{si};
            try
                if isempty(sv), [~,p_cvx,t_cvx,~,~,~,obj_cvx] = cvxEDA(yn, 1/fs_gsr);
                else,           [~,p_cvx,t_cvx,~,~,~,obj_cvx] = cvxEDA(yn, 1/fs_gsr,0.7,1.0,1.0,8e-5,1e-2,sv); end
                fprintf('  cvxEDA OK (solver=%s obj=%.4f)\n', sv, obj_cvx);
                gsr.scr = p_cvx;  gsr.scl = t_cvx;
                scl_mean = mean(t_cvx,'omitnan');
                scl_std  = std(t_cvx,'omitnan');
                fprintf('    SCL (tonic) mean : %.4f  std : %.4f  (z-µS)\n', scl_mean, scl_std);
                cvx_ok = true;  break
            catch err
                fprintf('  cvxEDA solver "%s" failed: %s\n', sv, err.message);
            end
        end
    end

    % ---- PUPIL BASELINE METRICS -------------------------------------
    pupil_mean_L = NaN;  pupil_mean_R = NaN;
    pupil_std_L  = NaN;  pupil_std_R  = NaN;
    blink_rate   = NaN;

    if ~isempty(eye) && all(ismember({'pupil_diameter_left','pupil_diameter_right'}, eye.Properties.VariableNames))
        pL = eye.pupil_diameter_left;   pR = eye.pupil_diameter_right;
        fs_eye = 1 / median(diff(eye.timestamp_unix_seconds));
        pupil_mean_L = mean(pL,'omitnan');  pupil_std_L = std(pL,'omitnan');
        pupil_mean_R = mean(pR,'omitnan');  pupil_std_R = std(pR,'omitnan');
        fprintf('\n  Pupil Baseline Stats (%.2f Hz)\n', fs_eye);
        fprintf('    Left  mean=%.3f mm  std=%.4f mm  NaN=%.1f%%\n', ...
            pupil_mean_L, pupil_std_L, 100*mean(isnan(pL)));
        fprintf('    Right mean=%.3f mm  std=%.4f mm  NaN=%.1f%%\n', ...
            pupil_mean_R, pupil_std_R, 100*mean(isnan(pR)));
        if ismember('blink', eye.Properties.VariableNames)
            blink_rate = sum(diff([0;double(eye.blink)])==1) / (range(eye.timestamp_unix_seconds)/60);
            fprintf('    Blink rate : %.2f blinks/min\n', blink_rate);
        end

        % ---- PLOTS (GSR + Pupil only) -------------------------------
        plot_resting_gsr(gsr, gsr_col, event_times, cvx_ok, fig_title);
        plot_resting_pupil(eye, event_times, cfg.pupil_smooth_sec, fig_title);
    else
        fprintf('  Eye tracker data not available.\n');
        plot_resting_gsr(gsr, gsr_col, event_times, cvx_ok, fig_title);
    end

    % ---- Results struct (for future stats) -------------------------
    results = struct(...
        'phase',         'resting_state', ...
        'label',         fig_title,       ...
        'gsr_mean',      gsr_mean,        ...
        'gsr_std',       gsr_std,         ...
        'gsr_range',     gsr_range,       ...
        'scl_mean',      scl_mean,        ...
        'scl_std',       scl_std,         ...
        'pupil_mean_L',  pupil_mean_L,    ...
        'pupil_mean_R',  pupil_mean_R,    ...
        'pupil_std_L',   pupil_std_L,     ...
        'pupil_std_R',   pupil_std_R,     ...
        'blink_rate',    blink_rate       ...
    );
    fprintf('  [DONE] %s\n', fig_title);
end



%  PHASE 2 — BASELINE
%  Sensors shown : all (accel, force, audio, GSR, pupil)
%  Events        : keyboard vs start/end events shown with distinct markers
%  Collisions    : detected from accelerometer, compared with audio spikes

function results = analyse_baseline(data_folder, fig_title, cfg)
    results = run_full_analysis(data_folder, fig_title, cfg, 'baseline');
end



%  PHASE 3 — TEST
%  Same full sensor suite and collision+audio analysis as Baseline

function results = analyse_test(data_folder, fig_title, cfg)
    results = run_full_analysis(data_folder, fig_title, cfg, 'test');
end



%  PHASE 4 — LEVEL (repetitions)
%  Same full sensor suite and collision+audio analysis as Baseline

function results = analyse_level(data_folder, fig_title, cfg)
    results = run_full_analysis(data_folder, fig_title, cfg, 'level');
end



%  SHARED FULL-ANALYSIS ENGINE  (Baseline / Test / Level)

function results = run_full_analysis(data_folder, fig_title, cfg, phase_name)

    fprintf('\n[%s]  %s\n  %s\n', upper(phase_name), fig_title, data_folder);

    % ---- Load -------------------------------------------------------
    gsr    = load_if_exists(fullfile(data_folder, 'gsr.csv'));
    nidaq  = load_if_exists(fullfile(data_folder, 'accel.csv'));
    eye    = load_if_exists(fullfile(data_folder, 'eye.csv'));
    events = load_if_exists(fullfile(data_folder, 'events.csv'));
    audio  = load_if_exists(fullfile(data_folder, 'audio.csv'));

    if isempty(nidaq), fprintf('  [SKIP] accel.csv missing.\n'); results=[]; return; end
    if isempty(gsr),   fprintf('  [SKIP] gsr.csv missing.\n');   results=[]; return; end
    if height(gsr) > 5, gsr(1:5,:) = []; end

    if isempty(events)
        events = table('Size',[0 2],'VariableTypes',{'double','cell'},...
                       'VariableNames',{'recording_time','data'});
    end

    % ---- Build sensor tables ----------------------------------------
    accel_raw         = table();
    accel_raw.xL      = nidaq.ai9;   accel_raw.yL = nidaq.ai10;  accel_raw.zL = nidaq.ai11;
    accel_raw.xR      = nidaq.ai12;  accel_raw.yR = nidaq.ai13;  accel_raw.zR = nidaq.ai14;
    accel_raw.pc_time = nidaq.pc_time;

    force_raw         = table();
    force_raw.F1      = nidaq.ai15  - nidaq.ai15;  force_raw.F2 = nidaq.ai16 - nidaq.ai24;
    force_raw.F3      = nidaq.ai17 - nidaq.ai25;  force_raw.F4 = nidaq.ai18 - nidaq.ai26;
    force_raw.F5      = nidaq.ai19 - nidaq.ai27;  force_raw.F6 = nidaq.ai20 - nidaq.ai28;
    force_raw.pc_time = nidaq.pc_time;
    force_cols        = {'F1','F2','F3','F4','F5','F6'};

    gsr_col   = get_gsr_col(gsr);
    fs_native = cfg.accel_fs;

    % ---- Audio mixer ------------------------------------------------
    has_audio = false;  audio_present_ch = {};
    if ~isempty(audio)
        audio_present_ch = intersect(cfg.audio_channels, audio.Properties.VariableNames);
        has_audio = ~isempty(audio_present_ch);
        if ~has_audio, fprintf('  audio.csv found but no recognised mixer channels.\n'); end
    else
        fprintf('  audio.csv missing — mixer plots skipped.\n');
    end

    % ---- Sanity checks ----------------------------------------------
    fprintf('\n  Sanity checks\n');
    fprintf('    accel/force : %d samples\n', height(accel_raw));
    fprintf('    gsr         : %d samples\n', height(gsr));
    if ~isempty(eye), fprintf('    eye         : %d samples\n', height(eye));
    else,             fprintf('    eye         : NOT FOUND\n'); end
    fprintf('    events      : %d\n', height(events));
    if has_audio
        fprintf('    audio       : %d samples  channels: %s\n', ...
            height(audio), strjoin(audio_present_ch,', '));
    end

    % NI-DAQ timing
    dt_nidaq = diff(nidaq.pc_time);
    n_bad    = sum(dt_nidaq <= 0);
    if n_bad > 0, fprintf('    WARNING: %d non-monotonic NI-DAQ timestamps\n', n_bad); end
    dt_pos   = dt_nidaq(dt_nidaq > 0);
    fs_est   = 1 / median(dt_pos);
    fprintf('    Accel fs est: %.2f Hz  (expected %d Hz)\n', fs_est, cfg.accel_fs);

    % GSR timing
    dt_gsr = diff(gsr.pc_time);
    fs_gsr = 1 / median(dt_gsr(dt_gsr > 0));
    fprintf('    GSR fs      : %.2f Hz  (jitter std = %.4f s)\n', fs_gsr, std(dt_gsr));

    % ---- Timestamp reconstruction -----------------------------------
    raw_t  = nidaq.pc_time;  n_samp = height(nidaq);
    anchor_idx = [1; find(diff(raw_t) ~= 0)+1];
    anchor_t   = raw_t(anchor_idx);
    t_recon    = zeros(n_samp,1);
    for a = 1:numel(anchor_idx)
        i0 = anchor_idx(a);
        if a < numel(anchor_idx)
            i1 = anchor_idx(a+1)-1;  n = i1-i0+1;
            t_recon(i0:i1) = anchor_t(a) + (0:n-1)'*(anchor_t(a+1)-anchor_t(a))/n;
        else
            n = n_samp-i0+1;
            t_recon(i0:end) = anchor_t(a) + (0:n-1)'/cfg.accel_fs;
        end
    end
    accel_raw.t_unix = t_recon;
    force_raw.t_unix = t_recon;

    % ---- Unified relative timeline ----------------------------------
    all_unix = [gsr.pc_time; t_recon; events.recording_time];
    if ~isempty(eye),  all_unix = [all_unix; eye.timestamp_unix_seconds]; end
    if has_audio,      all_unix = [all_unix; audio.recording_time]; end
    t0_unix = min(all_unix);

    gsr.t       = gsr.pc_time  - t0_unix;
    accel_raw.t = t_recon      - t0_unix;
    force_raw.t = t_recon      - t0_unix;
    if ~isempty(eye),  eye.t  = eye.timestamp_unix_seconds - t0_unix; end
    if has_audio,      audio.t = audio.recording_time      - t0_unix; end

    % ---- Parse and classify events ----------------------------------
    %  keyboard_event : any event whose 'data' does NOT contain TRIAL_START/END
    %  start_event    : TRIAL_START
    %  end_event      : TRIAL_END
    [t_trial_start, t_trial_end, event_times_kb, event_times_start, event_times_end] = ...
        classify_events(events, t0_unix);
    event_times_all = events.recording_time - t0_unix;

    fprintf('    Timeline: t0=%.3f UNIX  duration=%.2f s\n', t0_unix, max(all_unix-t0_unix));
    fprintf('    Events — keyboard: %d  trial_start: %d  trial_end: %d\n', ...
        numel(event_times_kb), numel(event_times_start), numel(event_times_end));

    % ---- Offset removal + V -> g ------------------------------------
    for ch = {'xL','yL','zL','xR','yR','zR'}
        c = ch{1};
        accel_raw.(c) = (accel_raw.(c) - mean(accel_raw.(c)(1:cfg.n_baseline_offset))) * cfg.V2G;
    end
    for k = 1:numel(force_cols)
        c = force_cols{k};
        force_raw.(c) = force_raw.(c) - mean(force_raw.(c)(1:cfg.n_baseline_offset));
    end

    % ---- Downsampled force magnitude --------------------------------
    ds_factor     = max(1, round(fs_native / cfg.target_fs_display));
    force_mag_nat = sqrt(force_raw.F1.^2+force_raw.F2.^2+force_raw.F3.^2+...
                         force_raw.F4.^2+force_raw.F5.^2+force_raw.F6.^2);
    [force_mag_ds, t_ds] = antialias_downsample(force_mag_nat, accel_raw.t, ...
                               fs_native, cfg.target_fs_display, 4, ds_factor);

    % ---- Collision detection from accelerometer ----------------------
    mag_accel_nat = max(sqrt(accel_raw.xL.^2+accel_raw.yL.^2+accel_raw.zL.^2), ...
                        sqrt(accel_raw.xR.^2+accel_raw.yR.^2+accel_raw.zR.^2));
    [mag_accel_ds, t_ds] = antialias_downsample(mag_accel_nat, accel_raw.t, ...
                               fs_native, cfg.target_fs_display, 4, ds_factor);

    min_dist_smp = round(cfg.min_distance_sec * cfg.target_fs_display);
    % drv_a        = [0; abs(diff(mag_accel_ds))];
    % thresh_a     = max(median(drv_a)+cfg.accel_sensitivity*mad(drv_a,1), ...
    %                    prctile(drv_a, cfg.thresh_percentile));
    % accel_events = detect_peaks(drv_a, t_ds, thresh_a, min_dist_smp);
    drv_a = [0; abs(diff(mag_accel_ds))];

    % --- Define valid detection window -----------------------------
    if ~isnan(t_trial_start) && ~isnan(t_trial_end)
        valid_mask = (t_ds >= t_trial_start) & (t_ds <= t_trial_end);
    else
        warning('Trial start/end not found → using full signal for detection');
        valid_mask = true(size(t_ds));
    end
    
    % --- Compute threshold ONLY on valid region --------------------
    drv_valid = drv_a(valid_mask);
    
    thresh_a = max( ...
        median(drv_valid) + cfg.accel_sensitivity * mad(drv_valid,1), ...
        prctile(drv_valid, cfg.thresh_percentile) ...
    );
    
    % --- Run detection ONLY inside trial ---------------------------
    accel_events = detect_peaks(drv_a(valid_mask), t_ds(valid_mask), ...
                               thresh_a, min_dist_smp);
    
    % Ensure column vector
    % accel_events = accel_events(:);
    % 
    % all_collisions   = accel_events;
    % collision_source = ones(numel(accel_events),1);  % 1 = accel only
    % fprintf('    Collisions detected — accel: %d\n', numel(all_collisions));
    if has_audio && ~isnan(t_trial_start) && ~isnan(t_trial_end)

        fs_audio = 1 / median(diff(audio.t(diff(audio.t)>0)));
    
        audio_events = detect_audio_collisions( ...
            audio, audio_present_ch, fs_audio, ...
            cfg.audio_bp_low, cfg.audio_bp_high, ...
            t_trial_start, t_trial_end, cfg);
    
        all_collisions   = audio_events;
        collision_source = 2 * ones(numel(audio_events),1); % 2 = audio
    
        fprintf('    Collisions detected — audio: %d\n', numel(all_collisions));
    
    else
        warning('Audio unavailable or trial markers missing → fallback to accel');
    
        all_collisions   = accel_events;
        collision_source = ones(numel(accel_events),1);
    end

    % ---- GSR analysis -----------------------------------------------
    cvx_ok = false;  p_cvx = [];  t_cvx = [];
    if cfg.use_cvxEDA
        conductance_uS = 1e6 ./ gsr.(gsr_col);
        if strcmp(cfg.gsr_unit,'kohm'), conductance_uS = 1000 ./ gsr.(gsr_col); end
        yn = zscore(conductance_uS);
        for si = 1:3
            sv_list = {'quadprog','sedumi',''};  sv = sv_list{si};
            try
                if isempty(sv), [~,p_cvx,t_cvx,~,~,~,obj_cvx] = cvxEDA(yn, 1/fs_gsr);
                else,           [~,p_cvx,t_cvx,~,~,~,obj_cvx] = cvxEDA(yn, 1/fs_gsr,0.7,1.0,1.0,8e-5,1e-2,sv); end
                fprintf('    cvxEDA OK (solver=%s  obj=%.4f)\n', sv, obj_cvx);
                gsr.scr = p_cvx;  gsr.scl = t_cvx;
                cvx_ok = true;  break
            catch err
                fprintf('    cvxEDA solver "%s" failed: %s\n', sv, err.message);
            end
        end
        if ~cvx_ok, fprintf('    All cvxEDA solvers failed, using raw resistance.\n'); end
    end

    if ~isempty(all_collisions)
        if cvx_ok
            [scr_thresh, scl_thresh] = compute_gsr_thresholds_cvx(p_cvx, t_cvx, ...
                cfg.scr_sensitivity, cfg.scl_sensitivity);
            gsr_responses = analyze_gsr_cvxEDA(gsr.t, p_cvx, t_cvx, all_collisions, ...
                cfg.baseline_before, cfg.scr_latency_window, scr_thresh, ...
                cfg.scl_window_start, cfg.scl_window_end, scl_thresh);
        else
            [scr_thresh, scl_thresh] = compute_gsr_thresholds_raw(gsr.(gsr_col), ...
                cfg.scr_sensitivity, cfg.scl_sensitivity);
            gsr_responses = analyze_gsr_raw(gsr.t, gsr.(gsr_col), all_collisions, ...
                cfg.baseline_before, cfg.scr_latency_window, scr_thresh, ...
                cfg.scl_window_start, cfg.scl_window_end, scl_thresh);
        end
        plot_gsr_overview(gsr, mag_accel_ds, force_mag_ds, t_ds, all_collisions, ...
            collision_source, gsr_responses, fig_title, cvx_ok, t_trial_start, t_trial_end);
        plot_each_collision(gsr, all_collisions, collision_source, gsr_responses, fig_title, ...
            cvx_ok, cfg.baseline_before, cfg.scr_latency_window, cfg.scl_window_end, ...
            t_trial_start, t_trial_end);
    else
        gsr_responses = init_responses(0);
        figure('Name',['GSR: ' fig_title]);
        plot(gsr.t, gsr.(gsr_col), 'b', 'LineWidth',1);
        ylabel(gsr_col); xlabel('Time (s)');
        title([fig_title ' | GSR (no collisions detected)']);
        grid on; hold on;
        add_events_differentiated(event_times_kb, event_times_start, event_times_end);
    end

    % ---- Individual sensor plots ------------------------------------
    plot_nidaq_gaps(nidaq.pc_time, cfg.accel_fs, [fig_title ' | NI-DAQ timing']);

    plot_accel_6panel(accel_raw.t, accel_raw.xL, accel_raw.yL, accel_raw.zL, ...
        t_ds, force_mag_ds, event_times_all, cfg.accel_fs, cfg.bp_low, cfg.bp_high, ...
        [fig_title ' | Accel LEFT']);
    plot_accel_6panel(accel_raw.t, accel_raw.xR, accel_raw.yR, accel_raw.zR, ...
        t_ds, force_mag_ds, event_times_all, cfg.accel_fs, cfg.bp_low, cfg.bp_high, ...
        [fig_title ' | Accel RIGHT']);

    plot_force_7panel(force_raw, force_cols, t_ds, force_mag_ds, event_times_all, ...
        [fig_title ' | Force']);

    if has_audio
        audio_fs_est = 1 / median(diff(audio.t(diff(audio.t)>0)));
        plot_audio_mixer(audio, audio_present_ch, audio_fs_est, ...
            cfg.audio_bp_low, cfg.audio_bp_high, event_times_all, [fig_title ' | Audio Mixer']);

        % ---- Collision vs audio spike comparison --------------------
        plot_collision_vs_audio(audio, audio_present_ch, audio_fs_est, ...
            cfg.audio_bp_low, cfg.audio_bp_high, all_collisions, collision_source, ...
            mag_accel_ds, t_ds, event_times_kb, event_times_start, event_times_end, fig_title);
    end

    % ---- Pupil plot -------------------------------------------------
    if ~isempty(eye) && all(ismember({'pupil_diameter_left','pupil_diameter_right'}, eye.Properties.VariableNames))
        plot_pupil(eye, event_times_all, cfg.pupil_smooth_sec, fig_title);
    end

    % ---- Unified overview (all sensors, differentiated events) ------
    plot_unified_overview_full(accel_raw, force_raw, force_mag_ds, t_ds, mag_accel_ds, ...
        gsr, audio, audio_present_ch, eye, ...
        event_times_kb, event_times_start, event_times_end, ...
        all_collisions, collision_source, ...
        cfg.accel_fs, cfg.bp_low, cfg.bp_high, cfg.audio_bp_low, cfg.audio_bp_high, ...
        cfg.pupil_smooth_sec, cvx_ok, t_trial_start, t_trial_end, fig_title);

    % ---- Results struct (for future stats) -------------------------
    results = struct('phase', phase_name, 'label', fig_title);
    results.n_collisions = numel(all_collisions);
    results.collision_times = all_collisions;
    results.collision_sources = collision_source;
    if ~isempty(gsr_responses)
        results.gsr_responses = gsr_responses;
    end
    results.n_events_keyboard = numel(event_times_kb);
    results.n_events_start    = numel(event_times_start);
    results.n_events_end      = numel(event_times_end);

    fprintf('  [DONE] %s\n', fig_title);
end


