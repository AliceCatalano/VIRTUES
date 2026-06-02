% BASELINE ANALYSIS — Unified Script
% Loops over Levels 1-5 of the Baseline task.
% For each level produces:
%   Fig 1L/1R : Accelerometer (left / right) — 5 subplots: X, Y, Z, Sum, Spectrum
%   Fig 2     : Force magnitude + individual force channels (smoothed)
%   Fig 3     : GSR overview with events and collision markers
%   Fig 4     : Per-collision GSR detail panels

% Folder structure expected:
%   <base_folder>/recordings/<subject>/Baseline/Level#/
%       accel.csv   gsr.csv   events.csv

clear; clc; close all;

% USER CONFIGURATION — edit these lines only

base_folder   = '/home/acatalano/VIRTUES/recordings/subject_s00H/Baseline';
levels_to_run = 1:5;           % which Level folders to process

accel_fs      = 3000;          % NI-DAQ sample rate (Hz)
bp_low        = 80;            % bandpass low  cut (Hz)  — for sum signal
bp_high       = 1000;          % bandpass high cut (Hz)
smooth_window = accel_fs / 10; % 0.1 s moving-average window (300 samples)

% Collision detection 
target_fs_display = 500;       % Hz — display / detection downsampling
accel_sensitivity = 20;        % adaptive threshold: median + k*MAD  (high = selective)
force_sensitivity = 15;        % idem for force
min_distance_sec  = 2.0;       % min gap between successive detections (s) — expect ~1-5 total
merge_window_sec  = 0.50;      % cross-sensor events closer than this -> merged
% Hard-floor percentile: threshold is always at least this percentile of the
% derivative distribution.  Prevents quiet recordings from lowering the bar.
thresh_percentile = 99;        % use 99th-percentile as absolute minimum threshold

% GSR / cvxEDA 
use_cvxEDA         = true;
gsr_unit           = 'ohm';    % 'ohm' or 'kohm'
scr_latency_window = 5.0;      % s post-collision to search for SCR peak
scl_window_start   = 2.0;      % tonic window start (s after collision)
scl_window_end     = 8.0;      % tonic window end   (s after collision)
baseline_before    = 2.0;      % s of pre-collision baseline
scr_sensitivity    = 2.5;      % n × MAD — phasic threshold
scl_sensitivity    = 2.0;      % n × MAD — tonic threshold

save_figures = false;          % true -> PNG saved next to data

% MAIN LOOP over levels
all_results = table();

for lv = levels_to_run

    level_folder = fullfile(base_folder, sprintf('Level%d', lv));
    
    if ~isfolder(level_folder)
        fprintf('[Level %d] Folder not found: %s — skipping.\n', lv, level_folder);
        continue
    end
    fprintf('\n LEVEL %d  (%s) \n', lv, level_folder);
    if ~isfolder(level_folder)
        fprintf('[Level %d] Folder not found: %s — skipping.\n', lv, level_folder);
        continue
    end

    %% LOAD CSV FILES
    gsr_file    = fullfile(level_folder, 'gsr.csv');
    nidaq_file  = fullfile(level_folder, 'accel.csv');
    events_file = fullfile(level_folder, 'events.csv');

    gsr   = load_if_exists(gsr_file);
    nidaq = load_if_exists(nidaq_file);
    if isempty(gsr)
        fprintf('  WARNING: gsr.csv not found — skipping level.\n'); continue
    end
    if isempty(nidaq)
        fprintf('  WARNING: accel.csv not found — skipping level.\n'); continue
    end
    if height(gsr) > 5, gsr(1:5,:) = []; end   % drop header-artifact rows

    events = load_if_exists(events_file);
    if isempty(events)
        fprintf('  WARNING: events.csv not found — using empty events.\n');
        events = table('Size',[0 2],'VariableTypes',{'double','cell'},...
                       'VariableNames',{'recording_time','data'});
    end

    %% BUILD SENSOR TABLES
    
    accel_raw          = table();
    accel_raw.xL       = nidaq.ai1;
    accel_raw.yL       = nidaq.ai2;
    accel_raw.zL       = nidaq.ai3;
    accel_raw.xR       = nidaq.ai4;
    accel_raw.yR       = nidaq.ai5;
    accel_raw.zR       = nidaq.ai6;
    accel_raw.pc_time  = nidaq.pc_time;

    % Force channels: differential pairs (ai7-ai18)
    force_raw          = table();
    force_raw.F1       = nidaq.ai7  - nidaq.ai13;
    force_raw.F2       = nidaq.ai8  - nidaq.ai14;
    force_raw.F3       = nidaq.ai9 - nidaq.ai15;
    force_raw.F4       = nidaq.ai10 - nidaq.ai16;
    force_raw.F5       = nidaq.ai11 - nidaq.ai17;
    force_raw.F6       = nidaq.ai12 - nidaq.ai18;
    force_raw.pc_time  = nidaq.pc_time;

    %% SANITY CHECKS
    
    fprintf('--- Sanity checks ---\n');
    
    % sample counts
    fprintf('  Samples accel: %d\n', height(accel_raw));
    fprintf('  Samples force: %d\n', height(force_raw));
    fprintf('  Samples gsr:   %d\n', height(gsr));
    fprintf('  Events:        %d\n', height(events));
    
    % timestamp monotonicity
    dt = diff(nidaq.pc_time);
    bad_time = sum(dt <= 0);
    if bad_time > 0
        fprintf('  WARNING: %d non-monotonic timestamps\n', bad_time);
    end
    
    % sampling rate estimate
    fs_est = 1 / median(dt(dt > 0));
    fprintf('  Estimated accel fs: %.2f Hz\n', fs_est);
    
    % gap detection
    gap_idx = find(dt > 5/accel_fs);
    if ~isempty(gap_idx)
        fprintf('  WARNING: %d timing gaps detected (max %.3f s)\n', ...
            length(gap_idx), max(dt));
    end
    
    % NaN checks
    nan_accel = sum(isnan(accel_raw{:,1:6}), 'all');
    nan_force = sum(isnan(force_raw{:,1:6}), 'all');
    
    if nan_accel > 0
        fprintf('  WARNING: %d NaNs in accelerometer data\n', nan_accel);
    end
    if nan_force > 0
        fprintf('  WARNING: %d NaNs in force data\n', nan_force);
    end
   
    
    % dead channels (almost constant)
    accel_std = std(accel_raw{:,1:6});
    dead_accel = find(accel_std < 1e-6);
    if ~isempty(dead_accel)
        fprintf('  WARNING: accel channels nearly constant: ');
        fprintf('%d ', dead_accel);
        fprintf('\n');
    end
    
    force_std = std(force_raw{:,1:6});
    dead_force = find(force_std < 1e-6);
    if ~isempty(dead_force)
        fprintf('  WARNING: force channels nearly constant: ');
        fprintf('%d ', dead_force);
        fprintf('\n');
    end
    
    % basic range report
    fprintf('  Accel range (V): [%.3f  %.3f]\n', ...
        min(accel_raw{:,1:6},[],'all'), max(accel_raw{:,1:6},[],'all'));
    
    fprintf('  Force range (V): [%.3f  %.3f]\n', ...
        min(force_raw{:,1:6},[],'all'), max(force_raw{:,1:6},[],'all'));
    
    gsr_col = get_gsr_col(gsr);
    fprintf('  GSR range: [%.3f  %.3f]\n', ...
        min(gsr.(gsr_col)), max(gsr.(gsr_col)));
    
    fprintf('--- Sanity checks done ---\n\n');

    %% RECONSTRUCT UNIFORM TIMESTAMPS (block-aware)
    dt_pc  = diff(nidaq.pc_time);
    dt_pos = dt_pc(dt_pc > 0)
    dt_med = median(dt_pos)
    dt_mad = mad(dt_pos, 1)
    block_thresh = max(0.01, dt_med + 20*dt_mad)
    block_edges  = [1; find(dt_pc > block_thresh) + 1];
    n_blocks = numel(block_edges);
    fprintf('  Detected %d NI acquisition block(s)\n', n_blocks);

    t_recon_unix = zeros(height(nidaq), 1);
    for b = 1:n_blocks
        i0 = block_edges(b);
        if b < n_blocks
            i1 = block_edges(b+1) - 1;
        else
            i1 = height(nidaq);
        end
        n  = i1 - i0 + 1;
        if n < 2
            t_recon_unix(i0) = nidaq.pc_time(i0); continue
        end
        t_recon_unix(i0:i1) = nidaq.pc_time(i0) + (0:n-1)' / accel_fs;
    end

    accel_raw.t_unix = t_recon_unix;
    force_raw.t_unix = t_recon_unix;

    %% UNIFIED RELATIVE TIMELINE
    gsr_t_unix    = gsr.pc_time;
    event_t_unix  = events.recording_time;

    t0_unix = min([gsr_t_unix; accel_raw.t_unix; force_raw.t_unix; event_t_unix]);

    gsr.t         = gsr_t_unix   - t0_unix;
    accel_raw.t   = accel_raw.t_unix - t0_unix;
    force_raw.t   = force_raw.t_unix - t0_unix;
    event_times   = event_t_unix - t0_unix;
    event_labels  = events.data;

    [t_trial_start, t_trial_end] = parse_trial_events(events, t0_unix);

    fprintf('  Session duration: %.1f s\n', max(accel_raw.t));
    fprintf('  Events: %d\n', numel(event_times));

    %% BASELINE OFFSET REMOVAL + CONVERT V -> G
% Subtract the mean of the first 100 samples from every channel (same approach as: sig_ori = sig - mean(sig(1:100,:)) ).
% This zeros the sensor activation offset without discarding any data. Accel conversion: sensitivity = 0.4 V/g  =>  g = V / 0.4
    % -------------------------------------------------------------------
    n_baseline = 50;   % samples used to estimate the resting offset

    % -- Accelerometer: offset removal then V -> G 
    V2G = 1 / 0.4;
    for ch = {'xL','yL','zL','xR','yR','zR'}
        c = ch{1};
        offset = mean(accel_raw.(c)(1:n_baseline));
        accel_raw.(c) = (accel_raw.(c) - offset) * V2G;
    end

    % Force: offset removal (stays in V) 
    for k = 1:numel({'F1','F2','F3','F4','F5','F6'})
        c = sprintf('F%d', k);
        offset = mean(force_raw.(c)(1:n_baseline));
        force_raw.(c) = force_raw.(c) - offset;
    end

    fprintf('  Offset removed (first %d samples baseline). Accel: V->G (x%.2f)\n', ...
        n_baseline, V2G);

    %% SIGNAL PROCESSING
    % Smoothed accelerometer magnitudes 
    accel_raw.mag_L        = sqrt(accel_raw.xL.^2 + accel_raw.yL.^2 + accel_raw.zL.^2);
    accel_raw.mag_R        = sqrt(accel_raw.xR.^2 + accel_raw.yR.^2 + accel_raw.zR.^2);
    % accel_raw.mag_L_smooth = movmean(accel_raw.mag_L, smooth_window);
    % accel_raw.mag_R_smooth = movmean(accel_raw.mag_R, smooth_window);

    % Force magnitude (from smoothed channels) 
    force_cols = {'F1','F2','F3','F4','F5','F6'};
    
    force_raw.mag = sqrt(force_raw.F1.^2 + force_raw.F2.^2 + ...
                         force_raw.F3.^2 + force_raw.F4.^2 + ...
                         force_raw.F5.^2 + force_raw.F6.^2);

    %% COLLISION DETECTION (on downsampled + filtered signal)
% Detection runs on the DOWNSAMPLED signal, not raw 3000 Hz. abs(diff()) on raw data turns sample-to-sample noise into thousands
% of false threshold crossings. After anti-alias filtering and downsampling to target_fs_display the derivative is clean.
    fs_native        = 1 / median(diff(accel_raw.t));
    ds_factor        = max(1, round(fs_native / target_fs_display));

    mag_accel_native = max(accel_raw.mag_L, accel_raw.mag_R);
    force_mag_native = sqrt(force_raw.F1.^2 + force_raw.F2.^2 + force_raw.F3.^2 + ...
                            force_raw.F4.^2 + force_raw.F5.^2 + force_raw.F6.^2);

    % Anti-alias + downsample — shared for detection AND display
    [mag_accel_ds, t_ds] = antialias_downsample(mag_accel_native, accel_raw.t, ...
                               fs_native, target_fs_display, 4, ds_factor);
    [force_mag_ds,   ~  ] = antialias_downsample(force_mag_native, accel_raw.t, ...
                               fs_native, target_fs_display, 4, ds_factor);

    % Min inter-event distance in downsampled samples
    min_dist_smp_ds = round(min_distance_sec * target_fs_display);

    drv_a    = [0; abs(diff(mag_accel_ds))];
    thresh_a = max(median(drv_a) + accel_sensitivity * mad(drv_a, 1), ...
                   prctile(drv_a, thresh_percentile));
    accel_events = detect_peaks(drv_a, t_ds, thresh_a, min_dist_smp_ds);
    fprintf('  [Accel] drv 99th=%.4f  thresh=%.4f  -> %d event(s)\n', ...
        prctile(drv_a,99), thresh_a, numel(accel_events));

    drv_f    = [0; abs(diff(force_mag_ds))];
    thresh_f = max(median(drv_f) + force_sensitivity * mad(drv_f, 1), ...
                   prctile(drv_f, thresh_percentile));
    force_events = detect_peaks(drv_f, t_ds, thresh_f, min_dist_smp_ds);
    fprintf('  [Force] drv 99th=%.4f  thresh=%.4f  -> %d event(s)\n', ...
        prctile(drv_f,99), thresh_f, numel(force_events));

    tagged = [accel_events, ones(numel(accel_events),1);
              force_events, 2*ones(numel(force_events),1)];
    tagged = sortrows(tagged, 1);
    [all_collisions, collision_source] = merge_close_events_tagged(tagged, merge_window_sec);

    fprintf('  Collisions — accel: %d  force: %d  merged: %d\n', ...
        numel(accel_events), numel(force_events), numel(all_collisions));

    %% GSR / cvxEDA ANALYSIS
    gsr_col = get_gsr_col(gsr);
    fs_gsr  = 1 / median(diff(gsr.t));
    cvx_ok  = false;

    if use_cvxEDA
        if strcmp(gsr_unit,'ohm'), conductance_uS = 1e6  ./ gsr.(gsr_col);
        else,                      conductance_uS = 1000 ./ gsr.(gsr_col); end
        yn = zscore(conductance_uS);
        for si = 1:3
            sv_list = {'quadprog','sedumi',''};
            sv = sv_list{si};
            try
                if isempty(sv)
                    [~,p_cvx,t_cvx,~,~,~,obj_cvx] = cvxEDA(yn, 1/fs_gsr);
                else
                    [~,p_cvx,t_cvx,~,~,~,obj_cvx] = cvxEDA(yn, 1/fs_gsr, ...
                        0.7,1.0,1.0,8e-5,1e-2,sv);
                end
                fprintf('  cvxEDA OK (solver=%s  obj=%.4f)\n', sv, obj_cvx);
                gsr.conductance_uS = conductance_uS;
                gsr.scr = p_cvx;  gsr.scl = t_cvx;
                cvx_ok = true;  break
            catch err
                fprintf('  cvxEDA solver "%s" failed: %s\n', sv, err.message);
            end
        end
        if ~cvx_ok, fprintf('  All cvxEDA solvers failed -> using raw resistance.\n'); end
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
    else
        gsr_responses = init_responses(0);
    end

    %% STORE RESULTS
    level_tag = sprintf('Level%d', lv);
    for i = 1:numel(all_collisions)
        r.level          = level_tag;
        r.collision_time = all_collisions(i);
        r.has_scr        = gsr_responses(i).has_scr;
        r.scr_latency_s  = gsr_responses(i).scr_latency;
        r.scr_amplitude  = gsr_responses(i).scr_amplitude;
        r.has_scl        = gsr_responses(i).has_scl;
        r.scl_change     = gsr_responses(i).scl_change;
        r.baseline       = gsr_responses(i).baseline;
        all_results = [all_results; struct2table(r,'AsArray',true)]; %#ok<AGROW>
    end

    %% PLOTS
    fig_title = sprintf('Level %d — Baseline', lv);

    % Figure 1L : Left accelerometer (6 subplots incl. force)
    plot_accel_6panel(accel_raw.t, accel_raw.xL, accel_raw.yL, accel_raw.zL, ...
        t_ds, force_mag_ds, event_times, accel_fs, bp_low, bp_high, ...
        sprintf('%s  |  Accelerometer LEFT', fig_title));

    % Figure 1R : Right accelerometer (6 subplots incl. force)
    plot_accel_6panel(accel_raw.t, accel_raw.xR, accel_raw.yR, accel_raw.zR, ...
        t_ds, force_mag_ds, event_times, accel_fs, bp_low, bp_high, ...
        sprintf('%s  |  Accelerometer RIGHT', fig_title));

    % Figure 2 : Force magnitude + individual channels
    plot_force(force_raw, force_cols, t_ds, force_mag_ds, event_times, ...
        all_collisions, fig_title);

    % Figure 3 : GSR overview with events + collisions 
    if ~isempty(all_collisions)
        plot_gsr_overview(gsr, mag_accel_ds, force_mag_ds, t_ds, ...
            all_collisions, collision_source, gsr_responses, ...
            fig_title, cvx_ok, t_trial_start, t_trial_end);

        % ---- Figure 4 : Per-collision GSR detail -----------------------
        plot_each_collision(gsr, all_collisions, collision_source, gsr_responses, ...
            fig_title, cvx_ok, baseline_before, scr_latency_window, scl_window_end, ...
            t_trial_start, t_trial_end);
    else
        % Still show GSR with events even when no collisions detected
        figure('Name', ['GSR: ' fig_title]);
        plot(gsr.t, gsr.(gsr_col), 'b', 'LineWidth',1);
        ylabel(gsr_col); xlabel('Time (s)');
        title([fig_title '  |  GSR (no collisions detected)']);
        grid on; hold on;
        for i = 1:numel(event_times)
            xline(event_times(i),'k--','LineWidth',1.2);
        end
    end

    if save_figures
        figs = findall(0,'Type','figure');
        for fi = 1:numel(figs)
            if contains(get(figs(fi),'Name'), fig_title)
                saveas(figs(fi), fullfile(level_folder, ...
                    [strrep(get(figs(fi),'Name'),' ','_') '.png']));
            end
        end
    end

    fprintf('  Level %d complete.\n', lv);
end

if ~isempty(all_results)
    fprintf('\n=== SUMMARY (all levels) ===\n');
    disp(all_results);
end

%% PLOT FUNCTIONS

% Figure 1 helper: 6-subplot accelerometer panel 
% Subplots: X, Y, Z (bandpassed, in g), Sum (bandpassed), Spectrum, Force mag
function plot_accel_6panel(t, x, y, z, t_force, force_mag, event_times, ...
                            Fs, bp_lo, bp_hi, fig_title)

    % Bandpass each axis (already in g after V->G conversion)
    xbp   = bandpass(x, [bp_lo bp_hi], Fs);
    ybp   = bandpass(y, [bp_lo bp_hi], Fs);
    zbp   = bandpass(z, [bp_lo bp_hi], Fs);
    sumbp = xbp + ybp + zbp;

    % Spectrum of the bandpassed sum
    [SPEC_f, freq] = positiveFFT(sumbp, Fs);

    figure('Name', fig_title, 'Position', [50 50 1400 1100]);
    sgtitle(fig_title, 'FontWeight','bold', 'FontSize',10);

    % Subplot 1 — X
    ax1 = subplot(6,1,1);
    plot(t, xbp, 'Color', [0.8 0.1 0.1], 'LineWidth', 0.6);
    ylabel('X (g)'); title('X axis (bandpassed)'); grid on;
    add_event_lines(event_times);

    % Subplot 2 — Y
    ax2 = subplot(6,1,2);
    plot(t, ybp, 'Color', [0.1 0.6 0.1], 'LineWidth', 0.6);
    ylabel('Y (g)'); title('Y axis (bandpassed)'); grid on;
    add_event_lines(event_times);

    % Subplot 3 — Z
    ax3 = subplot(6,1,3);
    plot(t, zbp, 'Color', [0.1 0.2 0.8], 'LineWidth', 0.6);
    ylabel('Z (g)'); title('Z axis (bandpassed)'); grid on;
    add_event_lines(event_times);

    % Subplot 4 — Sum X+Y+Z
    ax4 = subplot(6,1,4);
    plot(t, sumbp, 'Color', [0.5 0 0.7], 'LineWidth', 0.6);
    ylabel('Sum (g)'); title('Sum X+Y+Z (bandpassed)'); grid on;
    add_event_lines(event_times);

    % Subplot 5 — Frequency spectrum of sum
    ax5 = subplot(6,1,5);
    plot(freq, abs(SPEC_f), 'k', 'LineWidth', 0.7);
    xlabel('Frequency (Hz)'); ylabel('|FFT|');
    title('Spectrum of Sum (bandpassed)'); grid on;
    xlim([0 Fs/2]);

    % Subplot 6 — Force magnitude (downsampled, offset-removed)
    ax6 = subplot(6,1,6);
    plot(t_force, force_mag, 'Color', [0.5 0 0.5], 'LineWidth', 0.8);
    ylabel('|Force| (V)'); title('Force Magnitude (smoothed, offset-removed)'); grid on;
    add_event_lines(event_times);

    % Link time axes (all except spectrum)
    linkaxes([ax1 ax2 ax3 ax4 ax6], 'x');
    xlabel(ax6, 'Time (s)');
end

%% Figure 2 helper: Force magnitude + individual channels
function plot_force(force_raw, force_cols, t_ds, force_mag_ds, event_times, ...
                    collision_times, fig_title)

    figure('Name', [fig_title '  |  Force'], 'Position', [80 80 1400 600]);
    sgtitle([fig_title '  |  Force Sensors'], 'FontWeight','bold','FontSize',10);

    % Top panel: force magnitude (downsampled)
    ax1 = subplot(2,1,1);
    plot(t_ds, force_mag_ds, 'Color',[0.5 0 0.5], 'LineWidth', 1.2);
    hold on;
    mark_collisions(collision_times);
    add_event_lines(event_times);
    ylabel('|Force| (V)'); title('Force Magnitude (downsampled)'); grid on;

    % Bottom panel: individual smoothed channels
    ax2 = subplot(2,1,2);
    clrs = lines(numel(force_cols));
    hold on;
    for k = 1:numel(force_cols)
        c = force_cols{k};
        sc = [c '_smooth'];
        if ismember(sc, force_raw.Properties.VariableNames)
            plot(force_raw.t, force_raw.(sc), 'Color', clrs(k,:), ...
                'LineWidth', 0.8, 'DisplayName', c);
        end
    end
    add_event_lines(event_times);
    ylabel('Force (V)'); title('Individual Channels (smoothed)');
    legend('Location','best'); grid on;

    linkaxes([ax1 ax2], 'x');
    xlabel(ax2, 'Time (s)');
end

%% GSR PLOT FUNCTIONS (adapted from gsr_collisionV2)
function plot_gsr_overview(gsr, mag_accel_ds, force_mag_ds, t_ds, ...
        collision_times, collision_source, gsr_responses, ...
        title_str, has_cvx, t_trial_start, t_trial_end)

    gsr_col   = get_gsr_col(gsr);
    gsr_label = 'GSR (Ohm)';
    if contains(gsr_col,'CAL'), gsr_label = 'GSR (kOhm)'; end

    n_plots = 3 + has_cvx;
    figure('Name',['GSR Overview: ' title_str], ...
           'Position',[30 30 1600 210*n_plots]);
    p = 0;

    p = p+1; subplot(n_plots,1,p);
    plot(t_ds, mag_accel_ds,'b','LineWidth',0.8); hold on;
    mark_collisions(collision_times);
    mark_trial(t_trial_start, t_trial_end);
    ylabel('|accel| (g)'); title('Accelerometer magnitude'); grid on;

    p = p+1; subplot(n_plots,1,p);
    plot(t_ds, force_mag_ds,'Color',[0.5 0 0.5],'LineWidth',0.8); hold on;
    mark_collisions(collision_times);
    mark_trial(t_trial_start, t_trial_end);
    ylabel('|force|'); title('Force magnitude'); grid on;

    p = p+1; subplot(n_plots,1,p);
    plot(gsr.t, gsr.(gsr_col),'b','LineWidth',1); hold on;
    yl = ylim;
    for i = 1:numel(collision_times)
        switch collision_source(i)
            case 1, ls='-';  src_sym='A';
            case 2, ls='--'; src_sym='F';
            case 3, ls=':';  src_sym='B';
            otherwise, ls='--'; src_sym='?';
        end
        r = gsr_responses(i);
        if     r.has_scr && r.has_scl, col=[0.8 0 0];
        elseif r.has_scr,              col=[0.8 0 0.8];
        elseif r.has_scl,              col=[0 0.6 0.7];
        else,                          col=[0.4 0.4 0.4]; end
        xline(collision_times(i), ls,'Color',col,'LineWidth',2,'HandleVisibility','off');
        text(collision_times(i), yl(2), sprintf('%d%s',i,src_sym), ...
            'FontSize',7,'Color',col,'HorizontalAlignment','center','VerticalAlignment','top');
    end
    mark_trial(t_trial_start, t_trial_end);
    ylabel(gsr_label);
    title('Raw GSR  (red=SCR+SCL  magenta=SCR  cyan=SCL  grey=none)'); grid on;

    if has_cvx
        p = p+1; subplot(n_plots,1,p); hold on;
        plot(gsr.t, gsr.scl,'b','LineWidth',1.2,'DisplayName','Tonic SCL');
        plot(gsr.t, gsr.scr,'r','LineWidth',0.8,'DisplayName','Phasic SCR');
        mark_collisions(collision_times);
        mark_trial(t_trial_start, t_trial_end);
        legend('Location','best'); ylabel('z-µS');
        title('cvxEDA: Tonic SCL (blue) + Phasic SCR (red)'); grid on;
    end

    sgtitle([title_str ...
        '  |  LINE: solid=accel  dash=force  dot=both' ...
        '  |  red=SCR+SCL  mag=SCR  cyan=SCL  grey=none'], ...
        'FontWeight','bold','FontSize',8);
end

function plot_each_collision(gsr, collision_times, collision_source, gsr_responses, ...
        title_str, has_cvx, baseline_before, scr_window, scl_end, t_trial_start, t_trial_end)

    gsr_col   = get_gsr_col(gsr);
    gsr_label = 'GSR (Ohm)';
    if contains(gsr_col,'CAL'), gsr_label = 'GSR (kOhm)'; end

    n = numel(collision_times);
    n_cols = min(3, n);
    n_rows = ceil(n / n_cols);

    figure('Name',['Collision Detail: ' title_str], ...
           'Position',[50 50 n_cols*500 n_rows*360]);

    for i = 1:n
        ax = subplot(n_rows, n_cols, i);
        plot_collision_panel(ax, gsr, gsr_col, gsr_label, ...
            collision_times(i), collision_source(i), gsr_responses(i), i, n, ...
            has_cvx, baseline_before, scr_window, scl_end, t_trial_start, t_trial_end);
    end

    sgtitle(['All collisions: ' title_str ...
        '  |  A=accel  F=force  B=both' ...
        '  |  red=SCR+SCL  mag=SCR  cyan=SCL  grey=none'], ...
        'FontWeight','bold','FontSize',8);
end

function plot_collision_panel(ax, gsr, gsr_col, gsr_label, t_col, src, resp, ...
        col_idx, n_total, has_cvx, baseline_before, scr_window, scl_end, ...
        t_trial_start, t_trial_end)

    pre_s  = baseline_before + 0.5;
    post_s = scl_end + 1.5;
    zm     = (gsr.t >= t_col - pre_s) & (gsr.t <= t_col + post_s);
    t_rel  = gsr.t(zm) - t_col;

    if ~any(zm), title(ax,sprintf('Col %d — no data',col_idx)); return; end

    plot(ax, t_rel, gsr.(gsr_col)(zm),'b','LineWidth',1.2); hold(ax,'on');

    if has_cvx && ismember('scr',gsr.Properties.VariableNames)
        yyaxis(ax,'right');
        plot(ax,t_rel,gsr.scr(zm),'r','LineWidth',1,'DisplayName','SCR');
        plot(ax,t_rel,gsr.scl(zm),'Color',[0 0.6 0],'LineWidth',1,'DisplayName','SCL');
        ylabel(ax,'SCR/SCL (z-µS)');
        yyaxis(ax,'left');
    end

    xline(ax, 0,               'r--','LineWidth',1.8,'HandleVisibility','off');
    xline(ax, -baseline_before, ':' ,'Color',[0.5 0.5 0.5],'LineWidth',1,'HandleVisibility','off');
    xline(ax,  scr_window,     '--' ,'Color',[0.9 0.5 0],  'LineWidth',1,'HandleVisibility','off');
    xline(ax,  scl_end,        ':'  ,'Color',[0 0.6 0.7],  'LineWidth',1,'HandleVisibility','off');

    if ~isnan(resp.baseline)
        yline(ax, resp.baseline,'--','Color',[0 0 0.7],'LineWidth',1,'HandleVisibility','off');
    end

    if ~isnan(t_trial_start)
        tr = t_trial_start - t_col;
        if tr >= -pre_s && tr <= post_s
            xline(ax,tr,'-','Color',[0 0.7 0],'LineWidth',2,'HandleVisibility','off');
        end
    end
    if ~isnan(t_trial_end)
        tr = t_trial_end - t_col;
        if tr >= -pre_s && tr <= post_s
            xline(ax,tr,'-','Color',[0.9 0.5 0],'LineWidth',2,'HandleVisibility','off');
        end
    end

    if resp.has_scr
        t_peak = resp.scr_latency;
        idx = find(gsr.t >= t_col + t_peak, 1);
        if ~isempty(idx) && zm(idx)
            plot(ax, t_peak, gsr.(gsr_col)(idx),'ro','MarkerSize',8,'LineWidth',2,'HandleVisibility','off');
        end
    end

    src_names  = {'Accel','Force','Both'};
    src_colors = {[0.2 0.4 0.9],[0.6 0.1 0.6],[0.1 0.6 0.1]};
    src_name   = src_names{min(src,3)};
    src_col    = src_colors{min(src,3)};

    scr_str = '-'; scl_str = '-';
    if resp.has_scr, scr_str = sprintf('lat=%.2fs amp=%.1f',resp.scr_latency,resp.scr_amplitude); end
    if resp.has_scl, scl_str = sprintf('D=%.1f',resp.scl_change); end
    title(ax, sprintf('#%d/%d  t=%.2fs  [%s]\nSCR:%s  SCL:%s', ...
        col_idx, n_total, t_col, src_name, scr_str, scl_str),'FontSize',8);

    text(ax,0.01,0.99,src_name,'Units','normalized','FontSize',8,...
        'FontWeight','bold','Color',src_col,'VerticalAlignment','top',...
        'BackgroundColor',[src_col 0.15]);

    xlabel(ax,'Time rel. collision (s)'); ylabel(ax,gsr_label); grid(ax,'on');
end


%% SHARED UTILITY FUNCTIONS

function add_event_lines(event_times)
    for i = 1:numel(event_times)
        xline(event_times(i),'k--','LineWidth',1.0,'HandleVisibility','off');
    end
end

function mark_collisions(times)
    for i = 1:numel(times)
        xline(times(i),'k--','LineWidth',1,'HandleVisibility','off');
    end
end

function mark_trial(t_start, t_end)
    if ~isnan(t_start)
        xline(t_start,'-','Color',[0 0.7 0],'LineWidth',2.5,...
            'Label','TRIAL START','LabelVerticalAlignment','bottom','HandleVisibility','off');
    end
    if ~isnan(t_end)
        xline(t_end,'-','Color',[0.9 0.5 0],'LineWidth',2.5,...
            'Label','TRIAL END','LabelVerticalAlignment','bottom','HandleVisibility','off');
    end
end

function [t_start, t_end] = parse_trial_events(events, t0_unix)
    t_start = NaN;  t_end = NaN;
    if isempty(events), return; end
    try
        for i = 1:height(events)
            row_data = events.data{i};
            row_time = events.recording_time(i);
            if contains(row_data,'TRIAL_START'), t_start = row_time - t0_unix;
            elseif contains(row_data,'TRIAL_END'), t_end = row_time - t0_unix; end
        end
    catch
    end
end

function data = load_if_exists(filepath)
    if exist(filepath,'file'), data = readtable(filepath);
    else, data = []; end
end

function gsr_col = get_gsr_col(gsr)
    if     ismember('GSR_ohm',                  gsr.Properties.VariableNames), gsr_col='GSR_ohm';
    elseif ismember('GSR_Skin_Resistance_CAL',  gsr.Properties.VariableNames), gsr_col='GSR_Skin_Resistance_CAL';
    else,  error('No GSR column found (expected GSR_ohm or GSR_Skin_Resistance_CAL).'); end
end

function r = init_responses(n)
    r = struct('has_scr',false,'scr_latency',NaN,'scr_amplitude',NaN,...
               'has_scl',false,'scl_change', NaN,'baseline',     NaN);
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
                if drv(edges(j)) > drv(edges(i)), keep(i)=false;
                else, keep(j)=false; end
            else, break; end
        end
    end
    times = t(edges(keep));
end

function [merged_times, merged_source] = merge_close_events_tagged(tagged, window)
    if isempty(tagged), merged_times=[]; merged_source=[]; return; end
    merged_times  = tagged(1,1);
    merged_source = tagged(1,2);
    for i = 2:size(tagged,1)
        t_new = tagged(i,1); src_new = tagged(i,2);
        if t_new - merged_times(end) <= window
            if merged_source(end) ~= src_new, merged_source(end) = 3; end
        else
            merged_times  = [merged_times;  t_new];   %#ok<AGROW>
            merged_source = [merged_source; src_new]; %#ok<AGROW>
        end
    end
end

function [sig_ds, t_ds] = antialias_downsample(sig, t, fs_in, fs_out, order, ds_factor)
    cutoff_hz = fs_out / 2 * 0.9;
    Wn = min(cutoff_hz / (fs_in/2), 0.99);
    [b,a] = butter(order, Wn, 'low');
    sig_filt = filtfilt(b, a, double(sig));
    n = numel(sig_filt);
    n_ds = floor(n / ds_factor);
    sig_ds = zeros(n_ds,1);  t_ds = zeros(n_ds,1);
    for k = 1:n_ds
        idx = (k-1)*ds_factor+1 : k*ds_factor;
        sig_ds(k) = mean(sig_filt(idx));
        t_ds(k)   = t(idx(1));
    end
end

function responses = analyze_gsr_cvxEDA(t_gsr, scr, scl, collision_times, ...
        baseline_before, scr_window, scr_thresh, scl_start, scl_end, scl_thresh)
    responses = init_responses(numel(collision_times));
    for i = 1:numel(collision_times)
        t0 = collision_times(i);
        bl_mask = (t_gsr >= t0 - baseline_before) & (t_gsr < t0);
        if ~any(bl_mask), responses(i).baseline = NaN; continue; end
        baseline_scl = mean(scl(bl_mask));
        responses(i).baseline = baseline_scl;
        scr_mask = (t_gsr >= t0) & (t_gsr < t0 + scr_window);
        if any(scr_mask)
            seg = scr(scr_mask);  t_rel = t_gsr(scr_mask) - t0;
            [pk, pi] = max(seg);
            if pk > scr_thresh
                responses(i).has_scr       = true;
                responses(i).scr_latency   = t_rel(pi);
                responses(i).scr_amplitude = pk;
            end
        end
        scl_mask = (t_gsr >= t0+scl_start) & (t_gsr < t0+scl_end);
        if sum(scl_mask) > 3
            chg = mean(scl(scl_mask)) - baseline_scl;
            if abs(chg) > scl_thresh
                responses(i).has_scl    = true;
                responses(i).scl_change = chg;
            end
        end
    end
end

function responses = analyze_gsr_raw(t_gsr, gsr_raw, collision_times, ...
        baseline_before, scr_window, scr_thresh, scl_start, scl_end, scl_thresh)
    responses = init_responses(numel(collision_times));
    for i = 1:numel(collision_times)
        t0 = collision_times(i);
        bl_mask = (t_gsr >= t0 - baseline_before) & (t_gsr < t0);
        if ~any(bl_mask), responses(i).baseline = NaN; continue; end
        bl_mean = mean(gsr_raw(bl_mask));
        responses(i).baseline = bl_mean;
        scr_mask = (t_gsr >= t0) & (t_gsr < t0 + scr_window);
        if any(scr_mask)
            seg = gsr_raw(scr_mask);  t_rel = t_gsr(scr_mask) - t0;
            [mn, mi] = min(seg);
            amp = bl_mean - mn;
            if amp > scr_thresh
                responses(i).has_scr       = true;
                responses(i).scr_latency   = t_rel(mi);
                responses(i).scr_amplitude = amp;
            end
        end
        scl_mask = (t_gsr >= t0+scl_start) & (t_gsr < t0+scl_end);
        if sum(scl_mask) > 3
            chg = bl_mean - mean(gsr_raw(scl_mask));
            if abs(chg) > scl_thresh
                responses(i).has_scl    = true;
                responses(i).scl_change = chg;
            end
        end
    end
end

function [scr_thresh, scl_thresh] = compute_gsr_thresholds_cvx(p_cvx, t_cvx, scr_sens, scl_sens)
    abs_p      = abs(p_cvx);
    scr_thresh = max(median(abs_p) + scr_sens*mad(abs_p,1), 1e-4);
    delta_scl  = abs(diff(t_cvx));
    scl_thresh = max(median(delta_scl) + scl_sens*mad(delta_scl,1), 1e-4);
end

function [scr_thresh, scl_thresh] = compute_gsr_thresholds_raw(gsr_raw, scr_sens, scl_sens)
    delta_fast = abs(diff(gsr_raw));
    scr_thresh = max(median(delta_fast) + scr_sens*mad(delta_fast,1), 1.0);
    win_pts    = max(3, round(numel(gsr_raw)*0.01));
    gsr_smooth = movmean(gsr_raw, win_pts);
    delta_slow = abs(diff(gsr_smooth));
    scl_thresh = max(median(delta_slow) + scl_sens*mad(delta_slow,1), 0.5);
end

