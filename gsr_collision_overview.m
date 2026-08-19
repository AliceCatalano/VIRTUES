%% plot_collision_overview.m
% One figure per acquisition showing ALL collisions side by side.
% Each collision = one column of 4 stacked panels:
%   Row 1: Accelerometer magnitude (L=blue, R=red)
%   Row 2: Raw audio signal (not RMS) — shows the actual waveform
%   Row 3: Raw GSR (µS)
%   Row 4: cvxEDA tonic (SCL, blue) + phasic (SCR, red) on dual y-axis
%
% Background shading encodes EDA response:
%   green  = SCR + SCL detected
%   magenta= SCR only
%   cyan   = SCL only
%   grey   = no response
%
% One PNG saved per acquisition in EventBased_plots/subj/phase/acq.png

clear; clc; close all;

cfg = config();

% PARAMETERS
pre_win    = 2.0;   % s before collision
post_win   = 10.0;  % s after  collision
scr_win    = 5.0;   % s — SCR search window
scl_start  = 2.0;   % s — tonic window start
scl_end    = 8.0;   % s — tonic window end

AUDIO_BP_LOW  = 80;
AUDIO_BP_HIGH = 1000;
TARGET_FS     = 500;
N_BASELINE    = 50;
V2G           = 1 / 0.4;

all_phases = {'Baseline1','Baseline2','level_L1','level_L2','level_L3','level_L4','level_L5'};

plot_root = fullfile(cfg.output_root, 'EventBased_plots');
if ~exist(plot_root,'dir'), mkdir(plot_root); end

n_rows = 4;   % accel | audio | GSR | tonic+phasic

% MAIN LOOP
for si = 1:numel(cfg.all_subjects)
    subj     = cfg.all_subjects{si};
    subj_dir = fullfile(cfg.data_root, subj);
    group    = subj(end);
    fprintf('\n=== %s (Group %s) ===\n', subj, group);

    for ph_idx = 1:numel(all_phases)
        phase     = all_phases{ph_idx};
        phase_dir = fullfile(subj_dir, phase);
        if ~isfolder(phase_dir), continue; end

        if startsWith(phase,'Baseline')
            acquisitions = arrayfun(@(k) sprintf('Level%d',k), 1:5, 'UniformOutput',false);
        else
            acquisitions = arrayfun(@(k) sprintf('rep_%02d',k), 1:10, 'UniformOutput',false);
        end

        for ai = 1:numel(acquisitions)
            acq     = acquisitions{ai};
            acq_dir = fullfile(phase_dir, acq);
            if ~isfolder(acq_dir)
                if isfolder([acq_dir '_R']), acq_dir = [acq_dir '_R'];
                else, continue; end
            end

            coll_path  = fullfile(acq_dir, 'collision_results.mat');
            gsr_path   = fullfile(acq_dir, 'gsr.mat');
            accel_path = fullfile(acq_dir, 'accel.mat');
            audio_path = fullfile(acq_dir, 'audio.mat');

            if ~isfile(coll_path)||~isfile(gsr_path)||~isfile(accel_path)||~isfile(audio_path)
                continue;
            end

            % Load collision timestamps + intensities
            C      = load(coll_path);
            coll_t = C.results.collision_rel;
            n_coll = numel(coll_t);
            if n_coll == 0, continue; end

            peak_g   = C.results.peak_accel_g;
            peak_aud = C.results.peak_audio;

            %% Preprocess GSR → tonic + phasic
            try
                proc = gsr_preprocess(gsr_path, cfg, [], []);
            catch ME
                fprintf('  [skip GSR] %s/%s: %s\n', phase, acq, ME.message);
                continue;
            end
            t_gsr  = proc.time;
            gsr_us = proc.gsr_us;
            tonic  = proc.tonic;
            phasic = proc.phasic;

            % Noise floor for SCR detection
            noise_floor = median(abs(phasic)) + cfg.scr_sensitivity * mad(phasic,1);

            %% Load accelerometer → mag L and R downsampled
            A    = load(accel_path);   ACCEL = A.ACCEL;
            t_acc = ACCEL.time_rel;   fs_acc = ACCEL.fs_nominal;
            raw  = ACCEL.data;

            xL = bsl(raw(:,1),N_BASELINE,V2G); yL = bsl(raw(:,2),N_BASELINE,V2G);
            zL = bsl(raw(:,3),N_BASELINE,V2G); xR = bsl(raw(:,4),N_BASELINE,V2G);
            yR = bsl(raw(:,5),N_BASELINE,V2G); zR = bsl(raw(:,6),N_BASELINE,V2G);

            mag_L = sqrt(xL.^2+yL.^2+zL.^2);
            mag_R = sqrt(xR.^2+yR.^2+zR.^2);

            ds = max(1,round(fs_acc/TARGET_FS));
            [mag_L_ds, t_acc_ds] = aa_ds(mag_L, t_acc, fs_acc, TARGET_FS, 4, ds);
            [mag_R_ds, ~        ] = aa_ds(mag_R, t_acc, fs_acc, TARGET_FS, 4, ds);

            %% Load audio → bandpass, keep raw waveform (not RMS)
            U       = load(audio_path);   AUDIO = U.AUDIO;
            t_aud   = AUDIO.time_rel;     fs_aud = AUDIO.fs_estimated;
            ch_names = AUDIO.channel_names;

            known = {'ch11','ch12','ch13','ch14','ch16','ch17'};
            idx   = find(ismember(ch_names,known));
            if isempty(idx), idx = 1:size(AUDIO.data,2); end

            % Max absolute bandpassed waveform across channels
            audio_sig = bp_max(AUDIO.data(:,idx), fs_aud, AUDIO_BP_LOW, AUDIO_BP_HIGH);

            % Per-collision EDA response assessment
            responses = assess_responses(t_gsr, tonic, phasic, coll_t, ...
                pre_win, scr_win, scl_start, scl_end, noise_floor);

            % Create figure: n_rows rows × n_coll columns
            n_cols   = n_coll;
            fig_w    = max(800, n_cols * 280);
            fig_h    = n_rows * 200;
            fig = figure('Visible','off','Position',[0 0 fig_w fig_h]);

            % Pre-compute shared y-limits per row across all collisions
            ylims = compute_shared_ylims(n_rows, n_coll, coll_t, ...
                t_acc_ds, mag_L_ds, mag_R_ds, ...
                t_aud,    audio_sig, ...
                t_gsr,    gsr_us, tonic, phasic, ...
                pre_win,  post_win);

            %% Fill panels
            for ci = 1:n_coll
                t0   = coll_t(ci);
                resp = responses(ci);

                % Background colour based on EDA response
                if     resp.scr && resp.scl, bg = [1   0.88 0.88];  % pink
                elseif resp.scr,             bg = [1   0.88 1   ];  % magenta-tint
                elseif resp.scl,             bg = [0.88 0.96 1  ];  % cyan-tint
                else,                        bg = [0.93 0.93 0.93]; % grey
                end

                % Row 1 — Accelerometer
                ax1 = subplot(n_rows, n_cols, sub2ind([n_cols n_rows], ci, 1));
                hold(ax1,'on');
                plot_seg(ax1, t_acc_ds, mag_L_ds, t0, pre_win, post_win, [0.2 0.4 0.8], 'L');
                plot_seg(ax1, t_acc_ds, mag_R_ds, t0, pre_win, post_win, [0.8 0.3 0.1], 'R');
                ref_lines(ax1, scr_win, scl_start, scl_end);
                shade_post(ax1, post_win, bg);
                ylim(ax1, ylims(1,:));
                if ci==1, ylabel(ax1,'|accel| (g)','FontSize',7); end
                title(ax1, sprintf('#%d  t=%.2fs\ng=%.2f  aud=%.4f', ...
                    ci, t0, peak_g(ci), peak_aud(ci)), 'FontSize',7);
                grid(ax1,'on'); box(ax1,'on');
                set(ax1,'XTickLabel',{});

                % Row 2 — Audio raw waveform
                ax2 = subplot(n_rows, n_cols, sub2ind([n_cols n_rows], ci, 2));
                hold(ax2,'on');
                plot_seg(ax2, t_aud, audio_sig, t0, pre_win, post_win, [0.5 0.1 0.7], 'Audio');
                ref_lines(ax2, scr_win, scl_start, scl_end);
                shade_post(ax2, post_win, bg);
                ylim(ax2, ylims(2,:));
                if ci==1, ylabel(ax2,'Audio (BP)','FontSize',7); end
                grid(ax2,'on'); box(ax2,'on');
                set(ax2,'XTickLabel',{});

                % Row 3 — Raw GSR
                ax3 = subplot(n_rows, n_cols, sub2ind([n_cols n_rows], ci, 3));
                hold(ax3,'on');
                plot_seg(ax3, t_gsr, gsr_us, t0, pre_win, post_win, [0.3 0.3 0.3], 'GSR');
                ref_lines(ax3, scr_win, scl_start, scl_end);
                shade_post(ax3, post_win, bg);
                ylim(ax3, ylims(3,:));
                if ci==1, ylabel(ax3,'GSR (µS)','FontSize',7); end
                grid(ax3,'on'); box(ax3,'on');
                set(ax3,'XTickLabel',{});

                % Row 4 — Tonic (left y) + Phasic (right y)
                ax4 = subplot(n_rows, n_cols, sub2ind([n_cols n_rows], ci, 4));
                hold(ax4,'on');

                % Left axis: tonic SCL
                yyaxis(ax4,'left');
                plot_seg(ax4, t_gsr, tonic, t0, pre_win, post_win, [0.2 0.5 0.8], 'SCL');
                % Baseline mean
                bl_mask = (t_gsr >= t0-pre_win) & (t_gsr < t0);
                if any(bl_mask)
                    yline(ax4, mean(tonic(bl_mask)), '--', 'Color',[0.2 0.5 0.8], ...
                        'LineWidth',0.8, 'HandleVisibility','off');
                end
                if ci==1, ylabel(ax4,'Tonic (µS)','FontSize',7,'Color',[0.2 0.5 0.8]); end
                ylim(ax4, ylims(4,:));
                ax4.YColor = [0.2 0.5 0.8];

                % Right axis: phasic SCR
                yyaxis(ax4,'right');
                plot_seg(ax4, t_gsr, phasic, t0, pre_win, post_win, [0.9 0.3 0.1], 'SCR');

                % Noise floor
                yline(ax4, noise_floor, ':', 'Color',[0.6 0.6 0.6], ...
                    'LineWidth',1, 'HandleVisibility','off');

                % SCR peak marker
                scr_mask = (t_gsr >= t0) & (t_gsr < t0+scr_win);
                if any(scr_mask)
                    seg_t = t_gsr(scr_mask)-t0;
                    seg_p = phasic(scr_mask);
                    [pk,pi] = max(seg_p);
                    if pk > noise_floor
                        plot(ax4, seg_t(pi), pk, 'g^', 'MarkerSize',8, ...
                            'MarkerFaceColor',[0.1 0.8 0.1], 'HandleVisibility','off');
                    else
                        plot(ax4, seg_t(pi), pk, 'v', 'MarkerSize',6, ...
                            'Color',[0.5 0.5 0.5], 'MarkerFaceColor',[0.8 0.8 0.8], ...
                            'HandleVisibility','off');
                    end
                end
                if ci==1, ylabel(ax4,'Phasic (µS)','FontSize',7,'Color',[0.9 0.3 0.1]); end
                ylim(ax4, ylims(5,:));
                ax4.YColor = [0.9 0.3 0.1];

                % SCL annotation
                scl_mask = (t_gsr >= t0+scl_start) & (t_gsr < t0+scl_end);
                if any(bl_mask) && any(scl_mask)
                    yyaxis(ax4,'left');
                    dscl = mean(tonic(scl_mask)) - mean(tonic(bl_mask));
                    text(ax4, post_win*0.7, ylims(4,2)*0.9, ...
                        sprintf('ΔSCL\n%.3f', dscl), 'FontSize',6, ...
                        'Color',[0.2 0.5 0.8], 'HorizontalAlignment','center');
                end

                ref_lines(ax4, scr_win, scl_start, scl_end);
                shade_post(ax4, post_win, bg);
                xlabel(ax4,'Time rel. collision (s)','FontSize',7);
                grid(ax4,'on'); box(ax4,'on');

                % Response label at bottom
                resp_str = response_label(resp);
                text(ax4, 0.5, 0.02, resp_str, 'Units','normalized', ...
                    'FontSize',7, 'FontWeight','bold', ...
                    'HorizontalAlignment','center', 'VerticalAlignment','bottom', ...
                    'Color', response_color(resp));
            end

            % Supertitle
            sgtitle(sprintf('%s — %s — %s  |  %d collisions  |  bg: pink=SCR+SCL  mag=SCR  cyan=SCL  grey=none', ...
                subj, phase, acq, n_coll), 'FontSize',9, 'FontWeight','bold', 'Interpreter','none');

            % Save one PNG per acquisition
            fig_dir = fullfile(plot_root, subj, phase);
            if ~exist(fig_dir,'dir'), mkdir(fig_dir); end
            out_png = fullfile(fig_dir, sprintf('%s_%s_%s.png', subj, phase, acq));
            exportgraphics(fig, out_png, 'Resolution',120);
            savefig(fig,sprintf('%s_%s_%s.fig', subj, phase, acq))
            close(fig);
            fprintf('  Saved: %s/%s/%s (%d collisions)\n', subj, phase, acq, n_coll);

        end % acquisition
    end % phase
end % subject

fprintf('\n=== Done. Figures in: %s ===\n', plot_root);


%  HELPER FUNCTIONS

function plot_seg(ax, t, sig, t0, pre_win, post_win, col, label)
    mask  = (t >= t0-pre_win) & (t <= t0+post_win);
    t_rel = t(mask) - t0;
    plot(ax, t_rel, sig(mask), '-', 'Color',col, 'LineWidth',1.0, 'DisplayName',label);
end

function ref_lines(ax, scr_win, scl_start, scl_end)
    xline(ax, 0,         'r-',  'LineWidth',1.5, 'HandleVisibility','off');
    xline(ax, scr_win,   '--',  'Color',[0.9 0.5 0],   'LineWidth',0.8, 'HandleVisibility','off');
    xline(ax, scl_start, ':',   'Color',[0.2 0.5 0.8], 'LineWidth',0.8, 'HandleVisibility','off');
    xline(ax, scl_end,   ':',   'Color',[0.2 0.5 0.8], 'LineWidth',0.8, 'HandleVisibility','off');
end

function shade_post(ax, post_win, bg)
% Light background shading in the post-collision region
    yl = ylim(ax);
    patch(ax, [0 post_win post_win 0], [yl(1) yl(1) yl(2) yl(2)], bg, ...
        'FaceAlpha',0.25, 'EdgeColor','none', 'HandleVisibility','off');
end

function responses = assess_responses(t_gsr, tonic, phasic, coll_t, ...
        pre_win, scr_win, scl_start, scl_end, noise_floor)
    n = numel(coll_t);
    responses = struct('scr',false,'scl',false,'scr_amp',NaN,'scr_lat',NaN,'scl_change',NaN);
    responses = repmat(responses,n,1);
    noise_scl = median(abs(diff(tonic))) + 2*mad(diff(tonic),1);

    for i = 1:n
        t0      = coll_t(i);
        bl_mask = (t_gsr >= t0-pre_win) & (t_gsr < t0);
        if ~any(bl_mask), continue; end
        bl_scl  = mean(tonic(bl_mask));

        scr_mask = (t_gsr >= t0) & (t_gsr < t0+scr_win);
        if any(scr_mask)
            [pk,pi] = max(phasic(scr_mask));
            t_rel   = t_gsr(scr_mask)-t0;
            if pk > noise_floor
                responses(i).scr     = true;
                responses(i).scr_amp = pk;
                responses(i).scr_lat = t_rel(pi);
            end
        end

        scl_mask = (t_gsr >= t0+scl_start) & (t_gsr < t0+scl_end);
        if any(scl_mask)
            dscl = mean(tonic(scl_mask)) - bl_scl;
            responses(i).scl_change = dscl;
            if abs(dscl) > noise_scl
                responses(i).scl = true;
            end
        end
    end
end

function s = response_label(resp)
    if     resp.scr && resp.scl, s = 'SCR + SCL';
    elseif resp.scr,             s = 'SCR only';
    elseif resp.scl,             s = 'SCL only';
    else,                        s = 'no response';
    end
end

function c = response_color(resp)
    if     resp.scr && resp.scl, c = [0.7 0 0];
    elseif resp.scr,             c = [0.7 0 0.7];
    elseif resp.scl,             c = [0 0.5 0.7];
    else,                        c = [0.4 0.4 0.4];
    end
end

function ylims = compute_shared_ylims(n_rows, n_coll, coll_t, ...
        t_acc_ds, mag_L_ds, mag_R_ds, ...
        t_aud,    audio_sig, ...
        t_gsr,    gsr_us, tonic, phasic, ...
        pre_win,  post_win)
% Returns [n_rows+1 x 2] matrix of shared y-limits across all collisions
% Row 5 = phasic (separate right axis)
    ylims = NaN(n_rows+1, 2);
    collectors = {[], [], [], [], []};

    for ci = 1:n_coll
        t0 = coll_t(ci);
        collectors{1} = [collectors{1}; ...
            seg(t_acc_ds, mag_L_ds, t0, pre_win, post_win); ...
            seg(t_acc_ds, mag_R_ds, t0, pre_win, post_win)];
        collectors{2} = [collectors{2}; seg(t_aud,   audio_sig, t0, pre_win, post_win)];
        collectors{3} = [collectors{3}; seg(t_gsr,   gsr_us,    t0, pre_win, post_win)];
        collectors{4} = [collectors{4}; seg(t_gsr,   tonic,     t0, pre_win, post_win)];
        collectors{5} = [collectors{5}; seg(t_gsr,   phasic,    t0, pre_win, post_win)];
    end

    for r = 1:5
        v = collectors{r}(isfinite(collectors{r}));
        if isempty(v), ylims(r,:) = [0 1]; continue; end
        mn = min(v); mx = max(v);
        pad = max((mx-mn)*0.1, 1e-6);
        ylims(r,:) = [mn-pad, mx+pad];
    end
end

function v = seg(t, sig, t0, pre_win, post_win)
    mask = (t >= t0-pre_win) & (t <= t0+post_win);
    v    = sig(mask);
end

function ch = bsl(raw, n_base, V2G)
    n_bl = min(n_base,numel(raw));
    ch   = (raw - mean(raw(1:n_bl))) * V2G;
end

function out = bp_max(mat, fs, flo, fhi)
    out = zeros(size(mat,1),1);
    for k = 1:size(mat,2)
        col = double(mat(:,k)) - mean(mat(:,k),'omitnan');
        if numel(col) > 10*fs
            col = bandpass(col,[flo fhi],fs);
        end
        out = max(out, abs(col));
    end
end

function [sd,td] = aa_ds(sig,t,fi,~,ord,ds)
    Wn = min(0.99,(fi/ds/2*0.9)/(fi/2));
    [b,a] = butter(ord,Wn,'low');
    sf = filtfilt(b,a,double(sig));
    nd = floor(numel(sf)/ds);
    sd = zeros(nd,1); td = zeros(nd,1);
    for k = 1:nd
        idx=((k-1)*ds+1):k*ds;
        sd(k)=mean(sf(idx)); td(k)=t(idx(1));
    end
end