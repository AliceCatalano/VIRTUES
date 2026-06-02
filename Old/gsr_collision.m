clear; clc; close all;

base_folder = '~/VIRTUES';
base_folder = replace(base_folder, '~', getenv('HOME'));

level_to_process = 'level_L1';

diagnostic_mode = true;

% NI-DAQ actual rate is ~19692 Hz (hardware-timed, verified from recording_time).
% Detection runs at native rate; display is downsampled to target_fs_display.
target_fs_display = 500;

accel_sensitivity = 6;
force_sensitivity = 5;
min_distance_sec  = 0.20;
merge_window_sec  = 0.20;

% =========================================================================
% GSR / EDA Analysis
%
% PATH A  (use_cvxEDA = false):
%   Raw skin resistance. Phasic = min resistance drop in first scr_window s.
%   Tonic = sustained mean change scl_start -> scl_end s after collision.
%
% PATH B  (use_cvxEDA = true):
%   Requires cvxEDA on MATLAB path AND Optimization Toolbox (quadprog).
%   cvxEDA decomposes conductance into:
%     SCR (p_cvx) = phasic driver — spiky, rises after arousal events
%     SCL (t_cvx) = tonic level  — slow drift of autonomic baseline
%   Both returned in z-scored µS units.
%   gsr_unit: 'ohm'  if column is GSR_ohm (Ohms)
%             'kohm' if column is GSR_Skin_Resistance_CAL (kOhms)
% =========================================================================
use_cvxEDA = true;
gsr_unit   = 'ohm';

scr_latency_window = 5.0;
scl_window_start   = 2.0;
scl_window_end     = 8.0;
baseline_before    = 2.0;
scr_sensitivity    = 2.5;
scl_sensitivity    = 2.0;

save_figures = false;

all_results = table();
level_path  = fullfile(base_folder, level_to_process);
fprintf('\n=== LEVEL: %s ===\n', level_to_process);

all_items   = dir(fullfile(level_path, 'rep_*'));
rep_folders = all_items([all_items.isdir]);
test_items  = dir(fullfile(level_path, 'Test'));
test_folder = [];
for j = 1:length(test_items)
    if test_items(j).isdir && strcmp(test_items(j).name, 'Test')
        test_folder = test_items(j); break;
    end
end
if ~isempty(test_folder), all_reps = [test_folder; rep_folders];
else,                      all_reps = rep_folders; end
fprintf('Found %d repetition(s)\n\n', length(all_reps));

%% MAIN LOOP

for rep_idx = 1:length(all_reps)
    rep_name = all_reps(rep_idx).name;
    rep_path = fullfile(level_path, rep_name);
    fprintf('--- Processing: %s ---\n', rep_name);

    gsr   = load_if_exists(fullfile(rep_path, 'gsr.csv'));
    nidaq = load_if_exists(fullfile(rep_path, 'accel.csv'));
    if isempty(gsr),   fprintf('  WARNING: No GSR data\n\n');    continue; end
    if isempty(nidaq), fprintf('  WARNING: No NI-DAQ data\n\n'); continue; end
    [t_trial_start, t_trial_end] = load_trial_events(fullfile(rep_path, 'events.csv'));

    % Build sensor tables
    accel         = table();
    accel.pc_time = nidaq.recording_time;
    accel.xR = nidaq.ai1; accel.yR = nidaq.ai2; accel.zR = nidaq.ai3;
    accel.xL = nidaq.ai4; accel.yL = nidaq.ai5; accel.zL = nidaq.ai6;

    force         = table();
    force.pc_time = nidaq.recording_time;
    force.fx = nidaq.ai7  - nidaq.ai13;
    force.fy = nidaq.ai8  - nidaq.ai14;
    force.fz = nidaq.ai9  - nidaq.ai15;
    force.fw = nidaq.ai10 - nidaq.ai16;
    force.fq = nidaq.ai11 - nidaq.ai17;
    force.fr = nidaq.ai12 - nidaq.ai18;

    % Sync: both sensors share the Ubuntu system clock (recording_time).
    % Use recording_time as the timeline — it is the same reference for
    % NI-DAQ and GSR. For GSR sample spacing, reconstruct from the sensor's
    % internal timestamp (32770 Hz clock, zero jitter) anchored to the
    % recording_time of the first sample.
    [gsr, accel, force, t0_sync] = synchronize_time(gsr, accel, force);

    if ~isnan(t_trial_start), t_trial_start = t_trial_start - t0_sync; end
    if ~isnan(t_trial_end),   t_trial_end   = t_trial_end   - t0_sync; end

    if ~isnan(t_trial_start)
        fprintf('  Trial: START=%.2fs  END=%.2fs  (session 0-%.1fs)\n', ...
            t_trial_start, t_trial_end, range(gsr.t));
    else
        fprintf('  Trial events: not found in events.csv\n');
    end

    fs_native = 1 / median(diff(accel.t));
    fs_gsr    = 1 / median(diff(gsr.t));
    fprintf('  GSR %.1fs (%d smp @ %.1fHz)  NI-DAQ %.1fs (%d smp @ %.0fHz)\n', ...
        range(gsr.t), height(gsr), fs_gsr, range(accel.t), height(accel), fs_native);

    % Warn if force channels appear railed (disconnected sensor)
    force_mag_check = sqrt(force.fx.^2 + force.fy.^2 + force.fz.^2 + ...
                           force.fw.^2 + force.fq.^2 + force.fr.^2);
    rail_val  = 5.378819650329183;
    pct_railed = mean(abs(nidaq.ai7 - rail_val) < 0.01) * 100;
    if pct_railed > 20
        fprintf('  WARNING: Force channels %.0f%% at rail — sensor may be disconnected\n', pct_railed);
    end

    % STEP 1 — Magnitudes at native rate; anti-aliased copy for display only
    mag_accel_native = max(sqrt(accel.xR.^2 + accel.yR.^2 + accel.zR.^2), ...
                           sqrt(accel.xL.^2 + accel.yL.^2 + accel.zL.^2));
    force_mag_native = force_mag_check;

    ds_factor = max(1, round(fs_native / target_fs_display));
    [mag_accel_ds, t_ds] = antialias_downsample(mag_accel_native, accel.t, fs_native, target_fs_display, 4, ds_factor);
    [force_mag_ds,   ~  ] = antialias_downsample(force_mag_native, accel.t, fs_native, target_fs_display, 4, ds_factor);

    % STEP 2 — Collision detection at native NI-DAQ rate (~19692 Hz)
    fprintf('  Collision detection at native rate (%.0f Hz)...\n', fs_native);
    min_dist_smp_native = round(min_distance_sec * fs_native);

    drv_a    = [0; abs(diff(mag_accel_native))];
    thresh_a = median(drv_a) + accel_sensitivity * mad(drv_a, 1);
    if diagnostic_mode
        fprintf('    [ACCEL] drv med=%.5f MAD=%.5f 99th=%.5f max=%.5f thresh=%.5f\n', ...
            median(drv_a), mad(drv_a,1), prctile(drv_a,99), max(drv_a), thresh_a);
    end
    accel_events = detect_peaks(drv_a, accel.t, thresh_a, min_dist_smp_native);

    drv_f    = [0; abs(diff(force_mag_native))];
    thresh_f = median(drv_f) + force_sensitivity * mad(drv_f, 1);
    if diagnostic_mode
        fprintf('    [FORCE] drv med=%.5f MAD=%.5f 99th=%.5f max=%.5f thresh=%.5f\n', ...
            median(drv_f), mad(drv_f,1), prctile(drv_f,99), max(drv_f), thresh_f);
    end
    if pct_railed > 20 || thresh_f == 0
        fprintf('  Skipping force detection — sensor railed or zero variance\n');
        force_events = [];
    else
        force_events = detect_peaks(drv_f, accel.t, thresh_f, min_dist_smp_native);
        force_events = findpeaks
    end

    tagged = [accel_events, ones(length(accel_events),1);
              force_events, 2*ones(length(force_events),1)];
    tagged = sortrows(tagged, 1);
    [all_collisions, collision_source] = merge_close_events_tagged(tagged, merge_window_sec);

    if isempty(all_collisions)
        fprintf('  No collisions detected\n\n'); continue;
    end
    src_labels = {'accel','force','both'};
    fprintf('  Accel: %d  Force: %d  ->  %d unique collision(s)\n', ...
        length(accel_events), length(force_events), length(all_collisions));
    for dbg_i = 1:length(all_collisions)
        fprintf('    #%d  t=%.3fs  source=%s\n', dbg_i, all_collisions(dbg_i), src_labels{collision_source(dbg_i)});
    end

    % STEP 3 — GSR / EDA analysis
    gsr_col = get_gsr_col(gsr);
    cvx_ok  = false;

    if use_cvxEDA
        fprintf('  Running cvxEDA...\n');
        if strcmp(gsr_unit, 'ohm')
            conductance_uS = 1e6  ./ gsr.(gsr_col);
        else
            conductance_uS = 1000 ./ gsr.(gsr_col);
        end
        yn = zscore(conductance_uS);

        solvers_to_try = {'quadprog', 'sedumi', ''};
        for si = 1:length(solvers_to_try)
            try
                sv = solvers_to_try{si};
                if isempty(sv)
                    [~, p_cvx, t_cvx, ~, ~, ~, obj_cvx] = cvxEDA(yn, 1/fs_gsr);
                else
                    [~, p_cvx, t_cvx, ~, ~, ~, obj_cvx] = cvxEDA(yn, 1/fs_gsr, ...
                        0.7, 1.0, 1.0, 8e-5, 1e-2, sv);
                end
                fprintf('  cvxEDA OK (solver=%s  obj=%.4f)\n', sv, obj_cvx);
                gsr.conductance_uS = conductance_uS;
                gsr.scr = p_cvx;
                gsr.scl = t_cvx;
                cvx_ok  = true;
                break;
            catch err
                fprintf('  cvxEDA solver "%s" failed: %s\n', sv, err.message);
            end
        end
        if ~cvx_ok
            fprintf('  All cvxEDA solvers failed -> using raw resistance.\n');
        end
    end

    if cvx_ok
        [scr_thresh, scl_thresh] = compute_gsr_thresholds_cvx(p_cvx, t_cvx, scr_sensitivity, scl_sensitivity);
        fprintf('  Adaptive thresholds (cvxEDA): SCR=%.4f  SCL=%.4f  (z-µS)\n', scr_thresh, scl_thresh);
        gsr_responses = analyze_gsr_cvxEDA( ...
            gsr.t, p_cvx, t_cvx, all_collisions, ...
            baseline_before, scr_latency_window, scr_thresh, ...
            scl_window_start, scl_window_end, scl_thresh);
    else
        [scr_thresh, scl_thresh] = compute_gsr_thresholds_raw(gsr.(gsr_col), scr_sensitivity, scl_sensitivity);
        fprintf('  Adaptive thresholds (raw):    SCR=%.2f  SCL=%.2f  (%s)\n', scr_thresh, scl_thresh, gsr_unit);
        gsr_responses = analyze_gsr_raw( ...
            gsr.t, gsr.(gsr_col), all_collisions, ...
            baseline_before, scr_latency_window, scr_thresh, ...
            scl_window_start, scl_window_end, scl_thresh);
    end

    % STEP 4 — Store results
    for i = 1:length(all_collisions)
        result.level          = level_to_process;
        result.repetition     = rep_name;
        result.collision_time = all_collisions(i);
        result.has_scr        = gsr_responses(i).has_scr;
        result.scr_latency_s  = gsr_responses(i).scr_latency;
        result.scr_amplitude  = gsr_responses(i).scr_amplitude;
        result.has_scl        = gsr_responses(i).has_scl;
        result.scl_change     = gsr_responses(i).scl_change;
        result.baseline       = gsr_responses(i).baseline;
        result.scr_threshold  = scr_thresh;
        result.scl_threshold  = scl_thresh;
        all_results = [all_results; struct2table(result, 'AsArray', true)]; %#ok<AGROW>
    end

    % STEP 5 — Visualise
    plot_overview(gsr, mag_accel_ds, force_mag_ds, t_ds, all_collisions, collision_source, ...
        gsr_responses, rep_name, cvx_ok, t_trial_start, t_trial_end);
    plot_each_collision(gsr, all_collisions, collision_source, gsr_responses, rep_name, cvx_ok, ...
        baseline_before, scr_latency_window, scl_window_start, scl_window_end, t_trial_start, t_trial_end);

    if save_figures
        saveas(gcf, fullfile(rep_path, [rep_name '_overview.png']));
    end
    fprintf('  Complete\n\n');
end

if ~isempty(all_results)
    fprintf('\n=== SUMMARY ===\n'); disp(all_results);
end


%% GSR ANALYSIS — PATH B: cvxEDA
function responses = analyze_gsr_cvxEDA(t_gsr, scr, scl, collision_times, ...
        baseline_before, scr_window, scr_thresh, scl_start, scl_end, scl_thresh)

    responses = init_responses(length(collision_times));

    for i = 1:length(collision_times)
        t0      = collision_times(i);
        bl_mask = (t_gsr >= t0 - baseline_before) & (t_gsr < t0);
        if ~any(bl_mask), responses(i).baseline = NaN; continue; end

        responses(i).baseline = mean(scl(bl_mask));

        scr_mask = (t_gsr >= t0) & (t_gsr < t0 + scr_window);
        if any(scr_mask)
            seg   = scr(scr_mask);
            t_rel = t_gsr(scr_mask) - t0;
            [pk, pi] = max(seg);
            if pk > scr_thresh
                responses(i).has_scr       = true;
                responses(i).scr_latency   = t_rel(pi);
                responses(i).scr_amplitude = pk;
            end
        end

        scl_mask = (t_gsr >= t0 + scl_start) & (t_gsr < t0 + scl_end);
        if sum(scl_mask) > 3
            chg = mean(scl(scl_mask)) - responses(i).baseline;
            if abs(chg) > scl_thresh
                responses(i).has_scl    = true;
                responses(i).scl_change = chg;
            end
        end
    end
end


%% GSR ANALYSIS — PATH A: raw resistance
function responses = analyze_gsr_raw(t_gsr, gsr_raw, collision_times, ...
        baseline_before, scr_window, scr_thresh, scl_start, scl_end, scl_thresh)

    responses = init_responses(length(collision_times));

    for i = 1:length(collision_times)
        t0      = collision_times(i);
        bl_mask = (t_gsr >= t0 - baseline_before) & (t_gsr < t0);
        if ~any(bl_mask), responses(i).baseline = NaN; continue; end

        bl_mean               = mean(gsr_raw(bl_mask));
        responses(i).baseline = bl_mean;

        scr_mask = (t_gsr >= t0) & (t_gsr < t0 + scr_window);
        if any(scr_mask)
            seg   = gsr_raw(scr_mask);
            t_rel = t_gsr(scr_mask) - t0;
            [mn, mi] = min(seg);
            amp = bl_mean - mn;
            if amp > scr_thresh
                responses(i).has_scr       = true;
                responses(i).scr_latency   = t_rel(mi);
                responses(i).scr_amplitude = amp;
            end
        end

        scl_mask = (t_gsr >= t0 + scl_start) & (t_gsr < t0 + scl_end);
        if sum(scl_mask) > 3
            chg = bl_mean - mean(gsr_raw(scl_mask));
            if abs(chg) > scl_thresh
                responses(i).has_scl    = true;
                responses(i).scl_change = chg;
            end
        end
    end
end

%% PLOT 1: Full-session overview
function plot_overview(gsr, mag_accel_ds, force_mag_ds, t_ds, collision_times, collision_source, ...
        gsr_responses, title_str, has_cvx, t_trial_start, t_trial_end)

    gsr_col   = get_gsr_col(gsr);
    gsr_label = 'GSR (Ohm)';
    if contains(gsr_col,'CAL'), gsr_label = 'GSR (kOhm)'; end

    n_plots = 3 + has_cvx;
    figure('Name',['Overview: ' title_str], 'Position',[30,30,1600,210*n_plots]);
    p = 0;

    p = p+1; subplot(n_plots,1,p);
    plot(t_ds, mag_accel_ds, 'b', 'LineWidth',0.8); hold on;
    mark_collisions(collision_times);
    mark_trial(t_trial_start, t_trial_end);
    ylabel('|accel| (g)'); title('Accelerometer magnitude'); grid on;

    p = p+1; subplot(n_plots,1,p);
    plot(t_ds, force_mag_ds, 'Color',[0.5 0 0.5], 'LineWidth',0.8); hold on;
    mark_collisions(collision_times);
    mark_trial(t_trial_start, t_trial_end);
    ylabel('|force|'); title('Force magnitude (all 6 diff channels)'); grid on;

    p = p+1; subplot(n_plots,1,p);
    plot(gsr.t, gsr.(gsr_col), 'b', 'LineWidth',1); hold on;
    yl = ylim;
    for i = 1:length(collision_times)
        switch collision_source(i)
            case 1, ls = '-';  src_sym = 'A';
            case 2, ls = '--'; src_sym = 'F';
            case 3, ls = ':';  src_sym = 'B';
            otherwise, ls = '--'; src_sym = '?';
        end
        r = gsr_responses(i);
        if     r.has_scr && r.has_scl, col = [0.8 0 0];
        elseif r.has_scr,              col = [0.8 0 0.8];
        elseif r.has_scl,              col = [0 0.6 0.7];
        else,                          col = [0.4 0.4 0.4]; end
        xline(collision_times(i), ls, 'Color', col, 'LineWidth', 2.0, 'HandleVisibility','off');
        text(collision_times(i), yl(2), sprintf('%d%s', i, src_sym), 'FontSize', 7, ...
            'Color', col, 'HorizontalAlignment','center', 'VerticalAlignment','top');
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

    sgtitle(['Overview: ' title_str ...
        '  |  LINE: solid=accel  dash=force  dot=both' ...
        '  |  COLOUR: red=SCR+SCL  mag=SCR  cyan=SCL  grey=none' ...
        '  |  green=TRIAL START  orange=TRIAL END'], ...
        'FontWeight','bold','FontSize',8);
end


%% PLOT 2: One figure per collision — zoomed GSR window
function plot_each_collision(gsr, collision_times, collision_source, gsr_responses, ...
        title_str, has_cvx, baseline_before, scr_window, scl_start, scl_end, t_trial_start, t_trial_end)

    gsr_col   = get_gsr_col(gsr);
    gsr_label = 'GSR (Ohm)';
    if contains(gsr_col,'CAL'), gsr_label = 'GSR (kOhm)'; end

    n = length(collision_times);
    n_cols = min(3, n);
    n_rows = ceil(n / n_cols);

    figure('Name',['Collision detail: ' title_str], ...
        'Position',[50,50,n_cols*500,n_rows*360]);

    for i = 1:n
        ax = subplot(n_rows, n_cols, i);
        plot_collision_panel(ax, gsr, gsr_col, gsr_label, ...
            collision_times(i), collision_source(i), gsr_responses(i), i, n, ...
            has_cvx, baseline_before, scr_window, scl_start, scl_end, t_trial_start, t_trial_end);
    end

    sgtitle(['All collisions: ' title_str ...
        '  |  A=accel  F=force  B=both' ...
        '  |  red=SCR+SCL  mag=SCR  cyan=SCL  grey=none' ...
        '  |  green=TRIAL START  orange=TRIAL END'], ...
        'FontWeight','bold','FontSize',8);
end


function plot_collision_panel(ax, gsr, gsr_col, gsr_label, t_col, src, resp, ...
        col_idx, n_total, has_cvx, baseline_before, scr_window, scl_start, scl_end, ...
        t_trial_start, t_trial_end)

    pre_s  = baseline_before + 0.5;
    post_s = scl_end + 1.5;
    zm     = (gsr.t >= t_col - pre_s) & (gsr.t <= t_col + post_s);
    t_rel  = gsr.t(zm) - t_col;

    if ~any(zm), title(ax, sprintf('Col %d — no data', col_idx)); return; end

    plot(ax, t_rel, gsr.(gsr_col)(zm), 'b', 'LineWidth',1.2); hold(ax,'on');

    if has_cvx && ismember('scr', gsr.Properties.VariableNames)
        yyaxis(ax,'right');
        plot(ax, t_rel, gsr.scr(zm), 'r',              'LineWidth',1, 'DisplayName','SCR');
        plot(ax, t_rel, gsr.scl(zm), 'Color',[0 0.6 0],'LineWidth',1, 'DisplayName','SCL');
        ylabel(ax,'SCR/SCL (z-µS)');
        yyaxis(ax,'left');
    end

    xline(ax, 0,               'r--', 'LineWidth',1.8, 'HandleVisibility','off');
    xline(ax, -baseline_before, ':',  'Color',[0.5 0.5 0.5],'LineWidth',1,'HandleVisibility','off');
    xline(ax, scr_window,      '--',  'Color',[0.9 0.5 0],  'LineWidth',1,'HandleVisibility','off');
    xline(ax, scl_start, ':',  'Color',[0 0.6 0.7],  'LineWidth',1,'HandleVisibility','off');
    xline(ax, scl_end,          ':',  'Color',[0 0.6 0.7],  'LineWidth',1,'HandleVisibility','off');

    if ~isnan(resp.baseline)
        yline(ax, resp.baseline,'--','Color',[0 0 0.7],'LineWidth',1,'HandleVisibility','off');
    end

    if ~isnan(t_trial_start)
        tr = t_trial_start - t_col;
        if tr >= -pre_s && tr <= post_s
            xline(ax, tr, '-', 'Color',[0 0.7 0], 'LineWidth',2, 'HandleVisibility','off');
            yl = ylim(ax);
            text(ax, tr, yl(2), 'START', 'FontSize',7, 'Color',[0 0.55 0], ...
                'HorizontalAlignment','center', 'VerticalAlignment','top');
        end
    end
    if ~isnan(t_trial_end)
        tr = t_trial_end - t_col;
        if tr >= -pre_s && tr <= post_s
            xline(ax, tr, '-', 'Color',[0.9 0.5 0], 'LineWidth',2, 'HandleVisibility','off');
            yl = ylim(ax);
            text(ax, tr, yl(2), 'END', 'FontSize',7, 'Color',[0.8 0.4 0], ...
                'HorizontalAlignment','center', 'VerticalAlignment','top');
        end
    end

    if resp.has_scr
        t_peak = resp.scr_latency;
        idx    = find(gsr.t >= t_col + t_peak, 1);
        if ~isempty(idx) && zm(idx)
            plot(ax, t_peak, gsr.(gsr_col)(idx), 'ro','MarkerSize',8,'LineWidth',2,'HandleVisibility','off');
        end
    end

    yl = ylim(ax);
    if     resp.has_scr && resp.has_scl, fc=[1 0.85 0.85];
    elseif resp.has_scr,                 fc=[1 0.85 1];
    elseif resp.has_scl,                 fc=[0.85 0.97 1];
    else,                                fc=[0.93 0.93 0.93]; end
    patch(ax,[0 post_s post_s 0],[yl(1) yl(1) yl(2) yl(2)],fc, ...
        'FaceAlpha',0.2,'EdgeColor','none','HandleVisibility','off');

    src_names  = {'Accel','Force','Both'};
    src_colors = {[0.2 0.4 0.9],[0.6 0.1 0.6],[0.1 0.6 0.1]};
    src_name   = src_names{min(src,3)};
    src_col    = src_colors{min(src,3)};

    scr_str = '-'; scl_str = '-';
    if resp.has_scr, scr_str = sprintf('lat=%.2fs amp=%.4f', resp.scr_latency, resp.scr_amplitude); end
    if resp.has_scl, scl_str = sprintf('D=%.4f', resp.scl_change); end
    title(ax, sprintf('#%d/%d  t=%.3fs  [%s]\nSCR:%s  SCL:%s', ...
        col_idx, n_total, t_col, src_name, scr_str, scl_str), 'FontSize',8);

    text(ax, 0.01, 0.99, src_name, 'Units','normalized', 'FontSize',8, ...
        'FontWeight','bold', 'Color', src_col, 'VerticalAlignment','top', ...
        'BackgroundColor',[src_col 0.15]);

    xlabel(ax,'Time rel. collision (s)'); ylabel(ax,gsr_label); grid(ax,'on');
end

%% SHARED UTILITIES
function [t_start, t_end] = load_trial_events(filepath)
    t_start = NaN; t_end = NaN;
    if ~exist(filepath, 'file'), return; end
    try
        opts = detectImportOptions(filepath);
        opts = setvartype(opts, opts.VariableNames{1}, 'char');
        opts = setvartype(opts, opts.VariableNames{2}, 'double');
        ev   = readtable(filepath, opts);
        for i = 1:height(ev)
            row_data = ev.(1){i};
            row_time = ev.(2)(i);
            if contains(row_data, 'TRIAL_START'), t_start = row_time;
            elseif contains(row_data, 'TRIAL_END'), t_end = row_time; end
        end
    catch err
        fprintf('  WARNING: Could not parse events.csv: %s\n', err.message);
    end
end

function mark_trial(t_start, t_end)
    if ~isnan(t_start)
        xline(t_start, '-', 'Color',[0 0.7 0], 'LineWidth',2.5, ...
            'Label','TRIAL START', 'LabelVerticalAlignment','bottom', 'HandleVisibility','off');
    end
    if ~isnan(t_end)
        xline(t_end, '-', 'Color',[0.9 0.5 0], 'LineWidth',2.5, ...
            'Label','TRIAL END', 'LabelVerticalAlignment','bottom', 'HandleVisibility','off');
    end
end

function r = init_responses(n)
    r = struct('has_scr',false,'scr_latency',NaN,'scr_amplitude',NaN, ...
               'has_scl',false,'scl_change', NaN,'baseline',     NaN);
    r = repmat(r, n, 1);
end

function data = load_if_exists(filepath)
    if exist(filepath,'file'), data = readtable(filepath);
    else, data = []; end
end

function [gsr, accel, force, t0] = synchronize_time(gsr, accel, force)
    % Both sensors use Ubuntu time.time() (recording_time) — shared clock.
    % Use recording_time for the common timeline.
    % For GSR sample spacing, reconstruct from the internal sensor timestamp
    % (32770 Hz crystal, zero jitter) anchored to recording_time of first sample.
    t0 = min([accel.pc_time; gsr.recording_time]);
    accel.t = accel.pc_time - t0;
    force.t = accel.t;

    gsr_tick_hz  = 32770;
    gsr_t0_ticks = gsr.timestamp(1);
    gsr_t0_sec   = gsr.recording_time(1) - t0;
    gsr.t        = gsr_t0_sec + (gsr.timestamp - gsr_t0_ticks) / gsr_tick_hz;

    gsr_isi = diff(gsr.t);
    fprintf('  GSR timing: mean ISI=%.1fms  jitter=%.1fms  max_gap=%.1fms\n', ...
        mean(gsr_isi)*1000, std(gsr_isi)*1000, max(gsr_isi)*1000);
    if max(gsr_isi) > 0.35
        fprintf('  WARNING: GSR gap %.1fms — possible dropped Bluetooth packet\n', max(gsr_isi)*1000);
    end
end

function [sig_ds, t_ds] = antialias_downsample(sig, t, fs_in, fs_out, order, ds_factor)
    cutoff_hz = fs_out / 2 * 0.9;
    Wn        = min(cutoff_hz / (fs_in / 2), 0.99);
    [b, a]    = butter(order, Wn, 'low');
    sig_filt  = filtfilt(b, a, double(sig));
    n    = length(sig_filt);
    n_ds = floor(n / ds_factor);
    sig_ds = zeros(n_ds, 1);
    t_ds   = zeros(n_ds, 1);
    for k = 1:n_ds
        idx       = (k-1)*ds_factor + 1 : k*ds_factor;
        sig_ds(k) = mean(sig_filt(idx));
        t_ds(k)   = t(idx(1));
    end
end

function times = detect_peaks(drv, t, threshold, min_dist_smp)
    above = drv > threshold;
    edges = find(diff([0; above]) == 1);
    if isempty(edges), times = []; return; end
    keep = true(size(edges));
    for i = 1:length(edges)
        if ~keep(i), continue; end
        for j = i+1:length(edges)
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

function gsr_col = get_gsr_col(gsr)
    if ismember('GSR_ohm', gsr.Properties.VariableNames), gsr_col='GSR_ohm';
    elseif ismember('GSR_Skin_Resistance_CAL', gsr.Properties.VariableNames)
        gsr_col='GSR_Skin_Resistance_CAL';
    else, error('No GSR column found.'); end
end

function mark_collisions(times)
    for i=1:length(times)
        xline(times(i),'k--','LineWidth',1,'HandleVisibility','off');
    end
end

function [scr_thresh, scl_thresh] = compute_gsr_thresholds_cvx(p_cvx, t_cvx, scr_sens, scl_sens)
    abs_p      = abs(p_cvx);
    scr_thresh = median(abs_p) + scr_sens * mad(abs_p, 1);
    scr_thresh = max(scr_thresh, 1e-4);
    delta_scl  = abs(diff(t_cvx));
    scl_thresh = median(delta_scl) + scl_sens * mad(delta_scl, 1);
    scl_thresh = max(scl_thresh, 1e-4);
end

function [scr_thresh, scl_thresh] = compute_gsr_thresholds_raw(gsr_raw, scr_sens, scl_sens)
    delta_fast = abs(diff(gsr_raw));
    scr_thresh = median(delta_fast) + scr_sens * mad(delta_fast, 1);
    scr_thresh = max(scr_thresh, 1.0);
    win_pts    = max(3, round(length(gsr_raw) * 0.01));
    gsr_smooth = movmean(gsr_raw, win_pts);
    delta_slow = abs(diff(gsr_smooth));
    scl_thresh = median(delta_slow) + scl_sens * mad(delta_slow, 1);
    scl_thresh = max(scl_thresh, 0.5);
end