%% CollisionDetection_Local.m
%  Automatically walks through every acquisition of a given PHASE for one
%  SUBJECT, using a FIXED, validated detection threshold.
%
%  Only acquisitions whose automatic collision count is SUSPICIOUS
%  (n < REVIEW_LOW_N  or  n > REVIEW_HIGH_N) are shown for interactive
%  review. All others are auto-saved without any plot or prompt.
%
%  WORKFLOW:
%    1. Enter SUBJECT and PHASE when prompted.
%    2. Script determines all acquisitions in that phase automatically.
%    3. For each acquisition:
%         - runs auto-detection with the FIXED threshold
%         - if collision count is within the trusted range → auto-saves, no plot
%         - if collision count is OUTSIDE the trusted range → shows plot +
%           interactive review (a=add, d=delete, 0=save & next, q=quit)
%    4. Prints a final summary showing which acquisitions were auto-accepted
%       vs. manually reviewed.
% done: s03H s04H s05N s06H s07n s08h s09n s10H s11n s12h 
clear; clc; close all;

%% SECTION 1 — FIXED PARAMETERS (edit as needed)
BASE_FOLDER   = '~/Desktop/Virtues_Data';

% --- Display downsampling ---
TARGET_FS            = 500;        % Hz — accelerometer display target
SHOW_RAW_CH          = true;       % show individual X/Y/Z subplots

% --- Audio detection ---
AUDIO_BP_LOW         = 80;         % Hz
AUDIO_BP_HIGH        = 1000;       % Hz
AUDIO_RMS_WIN_SEC    = 0.02;       % RMS envelope window (s)
PEAK_MIN_DIST_SEC    = 1;        % minimum gap between detections (s)

%% >>> NEW — validated fixed threshold (replaces adaptive mean-based one)
FIXED_AUDIO_THRESHOLD = 0.2;     % absolute amplitude threshold, same for all subjects

%% >>> NEW — review-trigger range
REVIEW_LOW_N  = 2;      % review if n_collisions < this
REVIEW_HIGH_N = 10;     % review if n_collisions > this

% --- Intensity readout window ---
INTENSITY_WIN_SEC    = 0.10;       % ± half-window around each collision (s)

% --- Plot limits ([] = auto) ---
YLIM_ACCEL           = [0 15];
YLIM_AUDIO           = [];

%% SECTION 2 — ASK USER FOR SUBJECT + PHASE
base = expanduser(BASE_FOLDER);

SUBJECT = input('Enter subject ID (e.g. s02N): ', 's');

validPhases = {'Baseline1','Baseline2','level_L1','level_L2','level_L3','level_L4','level_L5'};
fprintf('\nValid phases: %s\n', strjoin(validPhases, ', '));
PHASE = input('Enter phase to analyse: ', 's');

if ~ismember(PHASE, validPhases)
    warning('Phase "%s" not in the known list — proceeding anyway.', PHASE);
end

subj_folder = fullfile(base, ['subject_' SUBJECT]);
phase_folder = fullfile(subj_folder, PHASE);
assert(isfolder(phase_folder), 'Phase folder not found:\n  %s', phase_folder);

%% SECTION 3 — DETERMINE ACQUISITION LIST AUTOMATICALLY
if startsWith(PHASE, 'Baseline', 'IgnoreCase', true)
    acquisitions = arrayfun(@(k) sprintf('Level%d', k), 1:5, 'UniformOutput', false);
else
    acquisitions = arrayfun(@(k) sprintf('rep_%02d', k), 1:10, 'UniformOutput', false);
end

fprintf('\n=== CollisionDetection_Local ===\n');
fprintf('Subject : %s\n', SUBJECT);
fprintf('Phase   : %s\n', PHASE);
fprintf('Fixed threshold      : %.4f\n', FIXED_AUDIO_THRESHOLD);
fprintf('Auto-accept range    : %d ≤ n ≤ %d collisions\n', REVIEW_LOW_N, REVIEW_HIGH_N);
fprintf('Acquisitions to process : %s\n\n', strjoin(acquisitions, ', '));

%% SECTION 4 — MAIN LOOP OVER ACQUISITIONS
hFig = 1;   % figure handle reused across acquisitions
summary = struct('acquisition', {}, 'n_collisions', {}, 'reviewed', {});

for aIdx = 1:numel(acquisitions)

    ACQUISITION = acquisitions{aIdx};
    acq_folder  = fullfile(phase_folder, ACQUISITION);

    if ~isfolder(acq_folder)
        if isfolder([acq_folder '_R'])
            acq_folder = [acq_folder '_R'];
        else
            warning('Skipping missing acquisition folder:\n  %s', acq_folder);
            continue;
        end
    end

    accel_file  = fullfile(acq_folder, 'accel.mat');
    audio_file  = fullfile(acq_folder, 'audio.mat');
    events_file = fullfile(acq_folder, 'events.mat');

    if ~isfile(accel_file) || ~isfile(audio_file) || ~isfile(events_file)
        warning('Missing accel/audio/events.mat in:\n  %s — skipping.', acq_folder);
        continue;
    end

    fprintf(' Processing: %s | %s | %s\n', SUBJECT, PHASE, ACQUISITION);
    fprintf(' Folder    : %s\n', acq_folder);

    %% LOAD .mat FILES
    A = load(accel_file);   ACCEL  = A.ACCEL;
    U = load(audio_file);   AUDIO  = U.AUDIO;
    E = load(events_file);  EVENTS = E.EVENTS;

    %% EXTRACT SIGNALS — accelerometer
    t_niq      = ACCEL.time_rel;
    t0_unix    = ACCEL.t0_unix;
    ACCEL_FS   = ACCEL.fs_nominal;

    N_BASELINE = 50;
    V2G        = 1 / 0.4;
    accel_raw  = ACCEL.data;

    xL = baseline_and_scale(accel_raw(:,1), N_BASELINE, V2G);
    yL = baseline_and_scale(accel_raw(:,2), N_BASELINE, V2G);
    zL = baseline_and_scale(accel_raw(:,3), N_BASELINE, V2G);
    xR = baseline_and_scale(accel_raw(:,4), N_BASELINE, V2G);
    yR = baseline_and_scale(accel_raw(:,5), N_BASELINE, V2G);
    zR = baseline_and_scale(accel_raw(:,6), N_BASELINE, V2G);

    mag_nat = max(sqrt(xL.^2+yL.^2+zL.^2), sqrt(xR.^2+yR.^2+zR.^2));

    ds = max(1, round(ACCEL_FS / TARGET_FS));
    [mag_ds, t_ds] = aa_downsample(mag_nat, t_niq, ACCEL_FS, TARGET_FS, 4, ds);

    %% EXTRACT SIGNALS — audio
    t_aud    = AUDIO.time_rel;
    fs_audio = AUDIO.fs_estimated;
    ch_names = AUDIO.channel_names;

    known_new = {'ch11','ch12','ch13','ch14','ch16','ch17'};
    known_old = {'ch12','ch13','ch14','ch16','ch17','ch18'};
    idx_new   = find(ismember(ch_names, known_new));
    idx_old   = find(ismember(ch_names, known_old));
    if numel(idx_new) >= numel(idx_old)
        audio_ch_idx = idx_new;
    else
        audio_ch_idx = idx_old;
    end
    if isempty(audio_ch_idx)
        audio_ch_idx = 1:size(AUDIO.data, 2);
    end

    audio_raw = AUDIO.data(:, audio_ch_idx);
    audio_bp  = bandpass_channels(audio_raw, fs_audio, AUDIO_BP_LOW, AUDIO_BP_HIGH);
    env       = rms_envelope(audio_bp, fs_audio, AUDIO_RMS_WIN_SEC);

    %% TRIAL WINDOW
    t_ws = EVENTS.t_trial_start;
    t_we = EVENTS.t_trial_end;
    fprintf('Trial window : %.3f – %.3f s  (%.1f s)\n', t_ws, t_we, t_we - t_ws);

    %% restore trial-window slicing (was accidentally commented out)
    in_trial    = (t_aud >= t_ws) & (t_aud <= t_we);
    audio_trial = audio_bp(in_trial);
    t_trial     = t_aud(in_trial);
    env_trial   = env(in_trial);
    keep = true(size(t_trial));
        last_t = -inf;
        for k = 1:numel(t_trial)
            if t_trial(k) > last_t
                last_t = t_trial(k);
            else
                keep(k) = false;
            end
        end
        
        n_dropped = sum(~keep);
        if n_dropped > 0
            fprintf('  [warn] %s — %d non-monotonic audio timestamps removed\n', ...
                ACQUISITION, n_dropped);
            t_trial     = t_trial(keep);
            audio_trial = audio_trial(keep);
            env_trial   = env_trial(keep);
        end
        
        if isempty(env_trial) || all(isnan(env_trial))
            fprintf('  [skip] %s — empty/invalid trial window\n', ACQUISITION);
            continue;
        end
        
        % ---- AUTO-DETECT (adaptive threshold, no plot, no prompt) ----
        thresh = 6 * mean(env_trial, 'omitnan');
        
        [~, locs] = findpeaks(env_trial, t_trial, 'MinPeakDistance', PEAK_MIN_DIST_SEC, 'MinPeakHeight', thresh);
    % 
    % %% AUTO-DETECT COLLISIONS — FIXED THRESHOLD
    % %thresh = 0.1;   %#ok — kept name for compatibility with plot fn
    % thresh = 4*mean(env_trial, 'omitnan')
    % 
    % [~, locs] = findpeaks(env_trial, t_trial,'MinPeakDistance', PEAK_MIN_DIST_SEC, 'MinPeakHeight', thresh);

    coll_t = locs(:);
    n_coll = numel(coll_t);
    fprintf('Auto-detected : %d collisions\n', n_coll);

    % INTENSITY FEATURES
    [intens_g, intens_audio] = compute_intensity(coll_t, mag_ds, t_ds, audio_bp, t_aud,INTENSITY_WIN_SEC, TARGET_FS, fs_audio);

    %% DECIDE WHETHER THIS ACQUISITION NEEDS REVIEW
    needs_review = 0;%(n_coll < REVIEW_LOW_N) || (n_coll > REVIEW_HIGH_N);

    if ~needs_review
        
        fprintf('  ✔ n=%d within trusted range [%d, %d] → auto-accepted, no review needed.\n',n_coll, REVIEW_LOW_N, REVIEW_HIGH_N);
        plot_collision_figure(hFig, coll_t, intens_g, intens_audio, ...
        t_aud, audio_bp, env, thresh, t_ds, mag_ds, t_ws, t_we, ...
        SHOW_RAW_CH, t_niq, ACCEL_FS, xL, yL, zL, xR, yR, zR, ...
        YLIM_ACCEL, YLIM_AUDIO, TARGET_FS, AUDIO_BP_LOW, AUDIO_BP_HIGH, ...
        FIXED_AUDIO_THRESHOLD, INTENSITY_WIN_SEC, SUBJECT, PHASE, ACQUISITION);

        results = build_results(SUBJECT, PHASE, ACQUISITION, acq_folder, t0_unix,t_ws, t_we, coll_t, intens_g, intens_audio, ...
            AUDIO_BP_LOW, AUDIO_BP_HIGH, AUDIO_RMS_WIN_SEC, FIXED_AUDIO_THRESHOLD, INTENSITY_WIN_SEC);

        out_file = fullfile(acq_folder, 'collision_results.mat');
        %save(out_file, 'results');
        fprintf('  [SAVE]   %d collisions → %s\n', n_coll, out_file);

        summary(end+1) = struct('acquisition', ACQUISITION, 'n_collisions', n_coll, 'reviewed', false); %#ok<SAGROW>
        continue;   %skip straight to next acquisition
    end

    %%  SUSPICIOUS COUNT: show plot + review
    fprintf('  ⚠ n=%d OUTSIDE trusted range [%d, %d] → manual review required.\n',n_coll, REVIEW_LOW_N, REVIEW_HIGH_N);

    % OPTIONAL: RELOAD PREVIOUS MANUAL CORRECTIONS
    out_file = fullfile(acq_folder, 'collision_results.mat');
    if isfile(out_file)
        useOld = input('  Previous collision_results.mat found — reload it instead of fresh auto-detect? (y/n): ', 's');
        if ~isempty(useOld) && lower(useOld(1)) == 'y'
            prev = load(out_file, 'results');
            coll_t       = prev.results.collision_rel;
            intens_g     = prev.results.peak_accel_g;
            intens_audio = prev.results.peak_audio;
            fprintf('  Loaded %d previously-saved collisions.\n', numel(coll_t));
        end
    end

    %% SHOW PLOT
    if isempty(hFig) || ~ishandle(hFig)
        hFig = figure('Units','normalized', 'Position',[0.03 0.05 0.94 0.85]);
    end
    plot_collision_figure(hFig, coll_t, intens_g, intens_audio, ...
        t_aud, audio_bp, env, thresh, t_ds, mag_ds, t_ws, t_we, ...
        SHOW_RAW_CH, t_niq, ACCEL_FS, xL, yL, zL, xR, yR, zR, ...
        YLIM_ACCEL, YLIM_AUDIO, TARGET_FS, AUDIO_BP_LOW, AUDIO_BP_HIGH, ...
        FIXED_AUDIO_THRESHOLD, INTENSITY_WIN_SEC, SUBJECT, PHASE, ACQUISITION);

    %% INTERACTIVE REVIEW LOOP FOR THIS ACQUISITION
    fprintf('\n--- Reviewing %s (n=%d) ---\n', ACQUISITION, n_coll);
    fprintf('  a = add a collision | d = delete by index | 0 = save & go to NEXT acquisition | q = quit entirely\n\n');

    quitAll = false;
    while true

        print_collision_list(coll_t, intens_g, intens_audio);
        action = input('Action (a/d/0/q): ', 's');
        if isempty(action), continue; end

        switch lower(action(1))

            case '0'
                break;

            case 'q'
                quitAll = true;
                break;

            case 'a'
                t_new = input('  Time of new collision (seconds, absolute file time): ');
                if isempty(t_new) || ~isnumeric(t_new)
                    fprintf('  Invalid time — cancelled.\n'); continue;
                end
                [g_new, a_new] = compute_intensity(t_new, mag_ds, t_ds, ...
                    audio_bp, t_aud, INTENSITY_WIN_SEC, TARGET_FS, fs_audio);
                insert_pos = sum(coll_t < t_new) + 1;
                coll_t       = [coll_t(1:insert_pos-1);       t_new; coll_t(insert_pos:end)];
                intens_g     = [intens_g(1:insert_pos-1);     g_new; intens_g(insert_pos:end)];
                intens_audio = [intens_audio(1:insert_pos-1); a_new; intens_audio(insert_pos:end)];
                fprintf('  ✔ Added collision at t=%.3f s (peak-g=%.2f, peak-audio=%.5f)\n', ...
                    t_new, g_new, a_new);

            case 'd'
                if isempty(coll_t)
                    fprintf('  No collisions to delete.\n'); continue;
                end
                idx = input('  Index number to delete: ');
                if isempty(idx) || ~isnumeric(idx) || idx < 1 || idx > numel(coll_t)
                    fprintf('  Invalid index — cancelled.\n'); continue;
                end
                idx = round(idx);
                t_del = coll_t(idx);
                coll_t(idx)       = [];
                intens_g(idx)     = [];
                intens_audio(idx) = [];
                fprintf('  ✔ Deleted collision #%d (t=%.3f s)\n', idx, t_del);

            otherwise
                fprintf('  Unrecognized action — use a, d, 0, or q.\n'); continue;
        end

        % Redraw after every change
        plot_collision_figure(hFig, coll_t, intens_g, intens_audio, ...
            t_aud, audio_bp, env, thresh, t_ds, mag_ds, t_ws, t_we, ...
            SHOW_RAW_CH, t_niq, ACCEL_FS, xL, yL, zL, xR, yR, zR, ...
            YLIM_ACCEL, YLIM_AUDIO, TARGET_FS, AUDIO_BP_LOW, AUDIO_BP_HIGH, ...
            FIXED_AUDIO_THRESHOLD, INTENSITY_WIN_SEC, SUBJECT, PHASE, ACQUISITION);
    end

    %% SAVE RESULTS FOR THIS ACQUISITION
    results = build_results(SUBJECT, PHASE, ACQUISITION, acq_folder, t0_unix, ...
        t_ws, t_we, coll_t, intens_g, intens_audio, ...
        AUDIO_BP_LOW, AUDIO_BP_HIGH, AUDIO_RMS_WIN_SEC, FIXED_AUDIO_THRESHOLD, INTENSITY_WIN_SEC);

    %save(out_file, 'results');
    fprintf('[SAVE]   %d collisions → %s\n', numel(coll_t), out_file);

    summary(end+1) = struct('acquisition', ACQUISITION, ...
        'n_collisions', numel(coll_t), 'reviewed', true); %#ok<SAGROW>

    if quitAll
        fprintf('\n[QUIT] Stopping phase processing early at %s.\n', ACQUISITION);
        break;
    end

end % acquisition loop

%% SECTION 5 — SUMMARY
fprintf('\n=== Phase Summary: %s | %s ===\n', SUBJECT, PHASE);
for k = 1:numel(summary)
    tag = 'auto ';
    if summary(k).reviewed, tag = 'REVIEWED'; end
    fprintf('  %-10s : %2d collisions   [%s]\n',summary(k).acquisition, summary(k).n_collisions, tag);
end
fprintf('\nDone.\n\n');


%% factored out results-struct builder (used in both save paths)
function results = build_results(SUBJECT, PHASE, ACQUISITION, acq_folder, t0_unix, ...
        t_ws, t_we, coll_t, intens_g, intens_audio, ...
        AUDIO_BP_LOW, AUDIO_BP_HIGH, AUDIO_RMS_WIN_SEC, FIXED_AUDIO_THRESHOLD, INTENSITY_WIN_SEC)

    results.subject        = SUBJECT;
    results.phase          = PHASE;
    results.acquisition    = ACQUISITION;
    results.acq_folder     = acq_folder;
    results.t0_unix        = t0_unix;
    results.t_win_start    = t_ws;
    results.t_win_end      = t_we;
    results.n_collisions   = numel(coll_t);
    results.collision_rel  = coll_t;
    results.collision_unix = t0_unix + coll_t;
    results.peak_accel_g   = intens_g;
    results.peak_audio     = intens_audio;
    results.save_time      = datetime('now');
    results.params         = struct( ...
        'audio_bp_low',        AUDIO_BP_LOW, ...
        'audio_bp_high',       AUDIO_BP_HIGH, ...
        'audio_rms_win_sec',   AUDIO_RMS_WIN_SEC, ...
        'fixed_audio_thresh',  FIXED_AUDIO_THRESHOLD, ...
        'intensity_win_sec',   INTENSITY_WIN_SEC);
end

function print_collision_list(coll_t, intens_g, intens_audio)
    fprintf('\n--- Current collisions (%d) ---\n', numel(coll_t));
    for ci = 1:numel(coll_t)
        fprintf('  [%02d]  t = %7.3f s   |  peak-g = %6.2f   |  peak-audio = %.5f\n', ...
            ci, coll_t(ci), intens_g(ci), intens_audio(ci));
    end
    if isempty(coll_t)
        fprintf('  (none)\n');
    end
    fprintf('\n');
end

function plot_collision_figure(hFig, coll_t, intens_g, intens_audio, ...
        t_aud, audio_bp, env, thresh, t_ds, mag_ds, t_ws, t_we, ...
        SHOW_RAW_CH, t_niq, ACCEL_FS, xL, yL, zL, xR, yR, zR, ...
        YLIM_ACCEL, YLIM_AUDIO, TARGET_FS, AUDIO_BP_LOW, AUDIO_BP_HIGH, ...
        FIXED_AUDIO_THRESHOLD, INTENSITY_WIN_SEC, SUBJECT, PHASE, ACQUISITION)

    figure(hFig); clf(hFig);
    n_rows = 2 + SHOW_RAW_CH * 2;

    ax_aud = subplot(n_rows, 1, 1, 'Parent', hFig);
    hold(ax_aud, 'on');
    plot(ax_aud, t_aud, audio_bp, 'Color',[0.5 0.5 0.5 0.35], 'LineWidth',0.4, 'DisplayName','bandpassed max');
    plot(ax_aud, t_aud, env, 'r', 'LineWidth',1.6, 'DisplayName','RMS envelope');
    yline(ax_aud, thresh, 'k--', 'LineWidth',1.0, 'HandleVisibility','off');
    draw_window(ax_aud, t_ws, t_we);
    draw_collisions(ax_aud, coll_t, env, t_aud, intens_g, intens_audio, 'audio');
    if ~isempty(YLIM_AUDIO), ylim(ax_aud, YLIM_AUDIO); end
    ylabel(ax_aud, 'Amplitude (V)');
    title(ax_aud, sprintf('Audio — bandpass %d–%d Hz | fixed threshold = %.4f  →  %d collisions', ...
        AUDIO_BP_LOW, AUDIO_BP_HIGH, FIXED_AUDIO_THRESHOLD, numel(coll_t)));
    grid(ax_aud, 'on');

    ax_niq = subplot(n_rows, 1, 2, 'Parent', hFig);
    hold(ax_niq, 'on');
    plot(ax_niq, t_ds, mag_ds, 'Color',[0.2 0.45 0.8], 'LineWidth',0.8, ...
        'DisplayName','Accel magnitude');
    draw_window(ax_niq, t_ws, t_we);
    draw_collisions(ax_niq, coll_t, mag_ds, t_ds, intens_g, intens_audio, 'accel');
    if ~isempty(YLIM_ACCEL), ylim(ax_niq, YLIM_ACCEL); end
    ylabel(ax_niq, 'Magnitude (g)');
    title(ax_niq, sprintf('Accelerometer magnitude — downsampled to %d Hz', TARGET_FS));
    grid(ax_niq, 'on');

    all_ax = [ax_aud, ax_niq];

    if SHOW_RAW_CH
        ds2 = max(1, round(ACCEL_FS / 200));
        td  = t_niq(1:ds2:end);

        ax_L = subplot(n_rows, 1, 3, 'Parent', hFig);
        hold(ax_L, 'on');
        plot(ax_L, td, xL(1:ds2:end), 'r', 'LineWidth',0.5, 'DisplayName','X');
        plot(ax_L, td, yL(1:ds2:end), 'g', 'LineWidth',0.5, 'DisplayName','Y');
        plot(ax_L, td, zL(1:ds2:end), 'b', 'LineWidth',0.5, 'DisplayName','Z');
        draw_window(ax_L, t_ws, t_we);
        ylabel(ax_L, 'g'); title(ax_L, 'Left sensor — X / Y / Z');
        grid(ax_L, 'on');

        ax_R = subplot(n_rows, 1, 4, 'Parent', hFig);
        hold(ax_R, 'on');
        plot(ax_R, td, xR(1:ds2:end), 'r', 'LineWidth',0.5, 'DisplayName','X');
        plot(ax_R, td, yR(1:ds2:end), 'g', 'LineWidth',0.5, 'DisplayName','Y');
        plot(ax_R, td, zR(1:ds2:end), 'b', 'LineWidth',0.5, 'DisplayName','Z');
        draw_window(ax_R, t_ws, t_we);
        ylabel(ax_R, 'g'); title(ax_R, 'Right sensor — X / Y / Z');
        grid(ax_R, 'on');

        all_ax = [all_ax, ax_L, ax_R];
    end

    linkaxes(all_ax, 'x');
    xlabel(all_ax(end), 'Time (s)');
    margin = (t_we - t_ws) * 0.05;
    xlim(all_ax(1), [t_ws - margin, t_we + margin]);
    %sgtitle(hFig, sprintf('%s  |  %s  |  %s  —  %d collisions detected  [NEEDS REVIEW]', ...
     %   SUBJECT, PHASE, ACQUISITION, numel(coll_t)), 'FontSize',12,'FontWeight','bold', 'Color',[0.7 0 0]);

    drawnow;
end

function p = expanduser(p)
    if startsWith(p,'~')
        home = char(java.lang.System.getProperty('user.home'));
        p    = [home, p(2:end)];
    end
end

function ch = baseline_and_scale(raw, n_base, V2G)
    n_bl = min(n_base, numel(raw));
    ch   = (raw - mean(raw(1:n_bl))) * V2G;
end

function out = bandpass_channels(mat, fs, flo, fhi)
    out = zeros(size(mat,1), 1);
    for k = 1:size(mat,2)
        col = double(mat(:,k));
        col = col - mean(col, 'omitnan');
        if numel(col) > 10*fs
            col = bandpass(col, [flo fhi], fs);
        end
        out = max(out, abs(col));
    end
end

function env = rms_envelope(sig, fs, win_sec)
    win = max(3, round(fs * win_sec));
    env = sqrt(movmean(sig.^2, win));
end

function [sd, td] = aa_downsample(sig, t, fi, ~, ord, ds)
    Wn = min(0.99, (fi/ds/2*0.9) / (fi/2));
    [b,a] = butter(ord, Wn, 'low');
    sf = filtfilt(b, a, double(sig));
    nd = floor(numel(sf)/ds);
    sd = zeros(nd,1);  td = zeros(nd,1);
    for k = 1:nd
        idx    = (k-1)*ds+1 : k*ds;
        sd(k)  = mean(sf(idx));
        td(k)  = t(idx(1));
    end
end

function [ig, ia] = compute_intensity(ct, mag_ds, t_ds, audio_bp, t_aud, ...
                                       win_sec, tgt_fs, fs_aud)
    n   = numel(ct);
    ig  = nan(n,1);
    ia  = nan(n,1);
    hwa = round(win_sec * tgt_fs);
    hwu = round(win_sec * fs_aud);
    for ci = 1:n
        [~,ic] = min(abs(t_ds  - ct(ci)));
        [~,iu] = min(abs(t_aud - ct(ci)));
        ig(ci) = max(mag_ds(  max(1,ic-hwa):min(numel(mag_ds),  ic+hwa)));
        ia(ci) = max(audio_bp(max(1,iu-hwu):min(numel(audio_bp),iu+hwu)));
    end
end

function draw_window(ax, tw_s, tw_e)
    yl = ylim(ax);
    fill(ax, [tw_s tw_e tw_e tw_s], [yl(1) yl(1) yl(2) yl(2)], ...
        [0.85 0.95 0.75], 'EdgeColor','none','FaceAlpha',0.25,'HandleVisibility','off');
    xline(ax, tw_s,'--','START','Color',[0.25 0.55 0.25],'LineWidth',1.2, ...
        'HandleVisibility','off','LabelHorizontalAlignment','right');
    xline(ax, tw_e,'--','END',  'Color',[0.65 0.15 0.15],'LineWidth',1.2, ...
        'HandleVisibility','off','LabelHorizontalAlignment','left');
end

function draw_collisions(ax, ct, ref_sig, ref_t, intens_g, intens_audio, mode)
    clr = [0.85 0.18 0.08];
    for ci = 1:numel(ct)
        [~,ix] = min(abs(ref_t - ct(ci)));
        yval   = ref_sig(ix) * 1.18;

        dn = '';
        if ci == 1, dn = 'Collision'; end

        stem(ax, ct(ci), yval, 'Color',clr,'LineWidth',2.0,'Marker','v', ...
            'MarkerSize',7,'MarkerFaceColor',clr,'DisplayName',dn);

        switch mode
            case 'audio'
                lbl = sprintf('#%d\n%.4fV', ci, intens_audio(ci));
            case 'accel'
                lbl = sprintf('#%d\n%.2fg', ci, intens_g(ci));
            otherwise
                lbl = sprintf('#%d', ci);
        end
        text(ax, ct(ci), yval*1.06, lbl, 'HorizontalAlignment','center', ...
            'FontSize',7, 'Color',clr,'FontWeight','bold');
    end
end