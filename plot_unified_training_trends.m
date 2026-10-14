%% plot_unified_trends_and_transfers.m
% Consolidates the RAW-DATA trend-by-level/rep figures and the paired
% pre/post transfer figures that were reimplemented separately across:
%   plot_tss_vf_present.m (Parts 3-5), Plot_paper_figures.m (Figs 1,2,4,7,12),
%   Plot_summary.m (descriptive D3,D6), plot_all.m (perf figures),
%   plot_transfer_paired_estimation.m, plot_before_after_cleaning.m
% into TWO reusable engines. Both engines show: faint individual-subject
% lines, bold group mean +/- 95% CI, the extreme subject at every
% x-position labeled by ID, and a BEFORE/AFTER exclusion side-by-side.
%
% NOT included here -- different patterns, not safe to guess at:
%   - Plot_paper_figures.m Figs 5,6,9,10,11: these plot PRE-FIT LMM
%     simple-effects contrasts loaded from a saved .mat (lmm_eda.results,
%     lmm_eye.results), not raw data. Rebuilding from raw means would
%     silently give a different, less-adjusted number. Tell me the
%     filename/struct layout those LMM results are saved under and I'll
%     add a third engine for this pattern specifically.
%   - P0/P1/P2/P6 (single-subject/cohort raw-distribution plots),
%     Fig8 (the known duplicate-panel bug), Fig14-17 (scatter/heatmap/
%     bar chart -- different visual pattern), D1/D2/D4/D5/D7/D8
%     (distributions/scatter/tier composition), TSSF ANCOVA diagnostic.
%
% EYE TABLE COLUMN NAMES: I used pupil_mean_norm, saccade_rate,
% gaze_dispersion -- the names confirmed elsewhere in your codebase
% (run_training_lmms_3way.m). Plot_paper_figures.m separately uses
% gaze_entropy and a fixation-rate metric I could not confirm the exact
% column name for -- if your eye_features_v2.mat has those as separate
% columns from gaze_dispersion, swap them into eye_metrics below.

clear; clc; cfg = config();
if ~exist(fullfile(cfg.output_root,'figures'),'dir'), mkdir(fullfile(cfg.output_root,'figures')); end

tssv_known_bad = {'subject_s02N','subject_s05N','subject_s09N','subject_s10H','subject_s11N','subject_s12H','subject_s23H','subject_s44N'};
tssf_known_bad = {'subject_s02N','subject_s05N','subject_s03H','subject_s04H'};
eda_known_bad  = {};                                   % fill in if you have EDA-specific exclusions
eye_known_bad  = {'subject_s12H','subject_s15H'};      % per the methods doc
perf_known_bad = {};


%% ENGINE A: raw-data trend by level or repetition

FV = load(fullfile(cfg.output_root,'force_vibration_features.mat'),'T'); FV = FV.T;
local_trend_plot(FV, 'tssv', 'log(TSSV)', 'level', tssv_known_bad, cfg, true);
local_trend_plot(FV, 'tssf', 'log(TSSF)', 'level', tssf_known_bad, cfg, true);
local_trend_plot(FV, 'tssv', 'log(TSSV)', 'rep',   tssv_known_bad, cfg, true);
local_trend_plot(FV, 'tssf', 'log(TSSF)', 'rep',   tssf_known_bad, cfg, true);

if isfile(fullfile(cfg.output_root,'perf_features.mat'))
    PERF = load(fullfile(cfg.output_root,'perf_features.mat'),'T'); PERF = PERF.T;
    local_trend_plot(PERF, 'duration_s',   'Completion time (s)',  'rep',   perf_known_bad, cfg, false);
    local_trend_plot(PERF, 'n_collisions', 'Collisions per trial', 'level', perf_known_bad, cfg, false);
end


%% ENGINE B: paired pre/post transfer (Baseline1->2 and Test1->2)

local_paired_plot(FV, 'tssv', 'log(TSSV)', 'baseline','Baseline1','Baseline2', tssv_known_bad, cfg);
local_paired_plot(FV, 'tssf', 'log(TSSF)', 'baseline','Baseline1','Baseline2', tssf_known_bad, cfg);
local_paired_plot(FV, 'tssv', 'log(TSSV)', 'test','Test1','Test2', tssv_known_bad, cfg);
local_paired_plot(FV, 'tssf', 'log(TSSF)', 'test','Test1','Test2', tssf_known_bad, cfg);

if isfile(fullfile(cfg.output_root,'eda_features_v2.mat'))
    EDA = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); EDA = EDA.T;
    local_paired_plot(EDA, 'scl_mean_bc', 'Tonic SCL (\muS)', 'baseline','Baseline1','Baseline2', eda_known_bad, cfg);
    local_paired_plot(EDA, 'scr_freq', 'SCR frequency (events/min)', 'baseline','Baseline1','Baseline2', eda_known_bad, cfg);
    local_paired_plot(EDA, 'scl_mean_bc', 'Tonic SCL (\muS)', 'test','Test1','Test2', eda_known_bad, cfg);
    local_paired_plot(EDA, 'scr_freq', 'SCR frequency (events/min)', 'test','Test1','Test2', eda_known_bad, cfg);
end

if isfile(fullfile(cfg.output_root,'eye_features_v2.mat'))
    EYE = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T'); EYE = EYE.T;
    eye_metrics = {'pupil_mean_norm','Pupil (norm.)'; 'saccade_rate','Saccade rate (/min)'; 'gaze_dispersion','Gaze dispersion'};
    for i = 1:size(eye_metrics,1)
        local_paired_plot(EYE, eye_metrics{i,1}, eye_metrics{i,2}, 'baseline','Baseline1','Baseline2', eye_known_bad, cfg);
    end
end

if isfile(fullfile(cfg.output_root,'perf_features.mat'))
    local_paired_plot(PERF, 'duration_s', 'Completion time (s)', 'baseline','Baseline1','Baseline2', perf_known_bad, cfg);
    local_paired_plot(PERF, 'n_collisions', 'Collisions per trial', 'baseline','Baseline1','Baseline2', perf_known_bad, cfg);
end

fprintf('\nAll figures saved to %s\n', fullfile(cfg.output_root,'figures'));


%% ENGINE A: trend by level/repetition

%% plot_trend_before_after_flatcheck.m
% Your trend-by-level/rep script (Engine A), with two additions you
% asked for:
%   1) known_bad subjects' lines are drawn thicker/darker in the BEFORE
%      panel (no text label) so you can SEE which lines exclusion is
%      supposed to remove, instead of only inferring it from the axis
%      rescaling afterward.
%   2) a FLAT-SUBJECT CHECK printed before each figure: flags any
%      subject whose raw (pre-exclusion) values across reps/levels have
%      near-zero range or coefficient of variation. This is what caught
%      s23H sitting dead flat at 10.3 across all 10 TSSF repetitions --
%      it was never in tssf_known_bad (only tssv_known_bad), so it kept
%      showing up as the "min" in both BEFORE and AFTER panels, making
%      them look identical. The check also surfaces any other similarly
%      flat subjects you noticed but that aren't in either list yet.
%
% Nothing else changed from what you pasted -- local_ternary and any
% other helper functions you already have elsewhere in your file are
% unaffected and still required.

clear; clc; cfg = config();
if ~exist(fullfile(cfg.output_root,'figures'),'dir'), mkdir(fullfile(cfg.output_root,'figures')); end

tssv_known_bad = {'subject_s02N','subject_s05N','subject_s09N','subject_s10H','subject_s11N','subject_s12H','subject_s23H','subject_s44N'};
tssf_known_bad = {'subject_s02N','subject_s05N','subject_s03H','subject_s04H'};
eda_known_bad  = {};                                   % fill in if you have EDA-specific exclusions
eye_known_bad  = {'subject_s12H','subject_s15H'};      % per the methods doc
perf_known_bad = {};


%% ENGINE A: raw-data trend by level or repetition

FV = load(fullfile(cfg.output_root,'force_vibration_features.mat'),'T'); FV = FV.T;
local_trend_plot(FV, 'tssv', 'log(TSSV)', 'level', tssv_known_bad, cfg, true);
local_trend_plot(FV, 'tssf', 'log(TSSF)', 'level', tssf_known_bad, cfg, true);
local_trend_plot(FV, 'tssv', 'log(TSSV)', 'rep',   tssv_known_bad, cfg, true);
local_trend_plot(FV, 'tssf', 'log(TSSF)', 'rep',   tssf_known_bad, cfg, true);

if isfile(fullfile(cfg.output_root,'perf_features.mat'))
    PERF = load(fullfile(cfg.output_root,'perf_features.mat'),'T'); PERF = PERF.T;
    local_trend_plot(PERF, 'duration_s',   'Completion time (s)',  'rep',   perf_known_bad, cfg, false);
    local_trend_plot(PERF, 'n_collisions', 'Collisions per trial', 'level', perf_known_bad, cfg, false);
end

function local_trend_plot(T, oc, oc_label, x_mode, known_bad, cfg, do_log)
    Ttr = T(strcmp(T.phase_type,'training') & isfinite(T.(oc)), :);
    if strcmp(x_mode,'level')
        Ttr = Ttr(isfinite(Ttr.level),:);
        n_x = 5; xlab = 'Training Level';
        x_all = Ttr.level;
    else
        x_all = str2double(regexp(Ttr.acquisition,'\d+','match','once'));
        n_x = max(x_all); xlab = 'Repetition';
    end
    if isempty(Ttr), fprintf('[skip] %s (%s): no rows.\n', oc, x_mode); return; end

    %% --- FLAT-SUBJECT CHECK -------------------------------------------
    % Raw per-trial values (not subject means), computed BEFORE exclusion,
    % so it catches a subject sitting at a near-constant value regardless
    % of whether anyone has flagged them yet.
    fprintf('\n--- FLAT-SUBJECT CHECK: %s by %s (raw per-trial values, before exclusion) ---\n', oc, x_mode);
    subj_all = unique(Ttr.subject);
    for si = 1:numel(subj_all)
        s = subj_all{si};
        v = Ttr.(oc)(strcmp(Ttr.subject,s));
        if do_log, v = v(v>0); end
        if numel(v) < 2, continue; end
        rng_v = max(v) - min(v);
        cv = std(v,'omitnan') / max(mean(v,'omitnan'), eps);
        if rng_v < 1e-6 || cv < 0.01
            tag = '';
            if ismember(s, known_bad), tag = '  [already in known_bad]'; end
            fprintf('  FLAT  %-18s n=%-3d  min=%.6g max=%.6g  range=%.3g  CV=%.4f%s\n', ...
                s, numel(v), min(v), max(v), rng_v, cv, tag);
        end
    end

    fig = figure('Position',[100 100 1300 500]);
    tl = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
    title(tl, sprintf('%s by %s -- before vs after subject exclusion', oc_label, lower(xlab)), 'FontWeight','bold', 'Interpreter','tex');

    keep_masks = {true(height(Ttr),1), ~ismember(Ttr.subject, known_bad)};
    panel_label = {'BEFORE exclusion', 'AFTER exclusion'};

    for pnl = 1:2
        mask = keep_masks{pnl};
        Tp = Ttr(mask,:); xp = x_all(mask);
        nexttile; hold on;
        subj_list = unique(Tp.subject);

        % per-subject mean matrix (si x xv) -- built once, reused for the
        % faint lines AND the extreme-value highlighting below, so both
        % operate at the SAME granularity (subject means, not raw trials).
        subj_mu = nan(numel(subj_list), n_x);
        is_h_list = false(numel(subj_list),1);
        for si = 1:numel(subj_list)
            s = subj_list{si};
            mask_s = strcmp(Tp.subject,s);
            for xv = 1:n_x
                v = Tp.(oc)(mask_s & xp==xv);
                if do_log, v = v(v>0); v = log(v); end
                if ~isempty(v), subj_mu(si,xv) = mean(v,'omitnan'); end
            end
            is_h_list(si) = any(Tp.haptic(mask_s));

            % known_bad subjects drawn thicker/darker, no text label --
            % lets you SEE which lines exclusion removes. In the AFTER
            % panel this is a no-op: known_bad subjects are already
            % filtered out of Tp, so is_bad is never true there.
            is_bad = ismember(s, known_bad);
            if is_bad
                lw = 2.0; alpha_v = 0.55;
            else
                lw = 0.6; alpha_v = 0.18;
            end
            ln = plot(1:n_x, subj_mu(si,:), '-', 'LineWidth', lw);
            if is_h_list(si), ln.Color = [0.55 0.20 0.66 alpha_v]; else, ln.Color = [0.25 0.38 0.70 alpha_v]; end
        end

        for grp = [false true]
            idx_g = is_h_list==grp;
            mu_g = mean(subj_mu(idx_g,:), 1, 'omitnan');
            se_g = std(subj_mu(idx_g,:), 0, 1, 'omitnan') ./ sqrt(sum(isfinite(subj_mu(idx_g,:)),1));
            col = grp*[0.55 0.20 0.66] + ~grp*[0.25 0.38 0.70];
            fill([1:n_x n_x:-1:1], [mu_g+1.96*se_g fliplr(mu_g-1.96*se_g)], col, ...
                'FaceAlpha',0.15, 'EdgeColor','none', 'HandleVisibility','off');
            plot(1:n_x, mu_g, 'o-', 'Color',col, 'LineWidth',2.5, 'MarkerFaceColor',col, ...
                'DisplayName', local_ternary(grp));
        end

        fprintf('\n--- DEBUG %s by %s | %s (per-subject MEANS, matching the plotted lines) ---\n', oc, x_mode, panel_label{pnl});
        for xv = 1:n_x
            col_v = subj_mu(:,xv);
            valid_xv = isfinite(col_v);
            if ~any(valid_xv), continue; end
            v = col_v(valid_xv); subj_x = subj_list(valid_xv);
            [vmax,imax] = max(v); [vmin,imin] = min(v);
            [v_sorted, ord] = sort(v);
            fprintf('  x=%-3d  %s\n', xv, xlab);
            for k = 1:numel(v_sorted)
                fprintf('    %-18s %10.4f\n', subj_x{ord(k)}, v_sorted(k));
            end
            fprintf('  SELECTED max: %-18s %10.4f   SELECTED min: %-18s %10.4f\n', ...
                subj_x{imax}, vmax, subj_x{imin}, vmin);
            scatter(xv, vmax, 45, [0.85 0.10 0.10], 'filled', 'HandleVisibility','off');
            scatter(xv, vmin, 45, [0.10 0.30 0.85], 'filled', 'HandleVisibility','off');
            text(xv+0.07, vmax, erase(subj_x{imax},'subject_'), 'Color',[0.85 0.10 0.10], 'FontSize',6.5, 'FontWeight','bold');
            text(xv+0.07, vmin, erase(subj_x{imin},'subject_'), 'Color',[0.10 0.30 0.85], 'FontSize',6.5, 'FontWeight','bold');
        end

        xlabel(xlab); ylabel(oc_label, 'Interpreter','tex');
        title(sprintf('%s (n=%d subjects)', panel_label{pnl}, numel(subj_list)), 'FontSize',11);
        xlim([0.5 n_x+1]); xticks(1:n_x);
    end
    saveas(fig, fullfile(cfg.output_root,'figures', sprintf('%s_%s_trend_before_after.png', oc, x_mode)));
    fprintf('Saved %s_%s_trend_before_after.png\n', oc, x_mode);
end



%% ENGINE B: paired pre/post transfer

function local_paired_plot(T, oc, oc_label, phase_type, phase_pre, phase_post, known_bad, cfg)
    Tph = T(strcmp(T.phase_type,phase_type) & isfinite(T.(oc)) & T.(oc)>0, :);
    if isempty(Tph), fprintf('[skip] %s %s->%s: no rows.\n', oc, phase_pre, phase_post); return; end

    fig = figure('Position',[100 100 1300 500]);
    tl = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
    title(tl, sprintf('%s: %s to %s -- before vs after subject exclusion', oc_label, phase_pre, phase_post), 'FontWeight','bold', 'Interpreter','tex');

    keep_masks = {true(height(Tph),1), ~ismember(Tph.subject, known_bad)};
    panel_label = {'BEFORE exclusion', 'AFTER exclusion'};

    for pnl = 1:2
        Tp = Tph(keep_masks{pnl}, :);
        nexttile; hold on;
        subj_list = unique(Tp.subject);
        pre_v  = nan(numel(subj_list),1);
        post_v = nan(numel(subj_list),1);
        is_h   = false(numel(subj_list),1);
        for si = 1:numel(subj_list)
            s = subj_list{si};
            v1 = Tp.(oc)(strcmp(Tp.subject,s) & strcmp(Tp.phase,phase_pre));
            v2 = Tp.(oc)(strcmp(Tp.subject,s) & strcmp(Tp.phase,phase_post));
            if ~isempty(v1), pre_v(si)  = mean(v1,'omitnan'); end
            if ~isempty(v2), post_v(si) = mean(v2,'omitnan'); end
            is_h(si) = any(Tp.haptic(strcmp(Tp.subject,s)));
        end
        valid = isfinite(pre_v) & isfinite(post_v);

        for si = find(valid)'
            col = [0.55 0.20 0.66 0.35]; if ~is_h(si), col = [0.25 0.38 0.70 0.35]; end
            ln = plot([1 2],[pre_v(si) post_v(si)],'-','LineWidth',0.8);
            ln.Color = col;
        end
        for grp = [false true]
            idx = valid & is_h==grp;
            if sum(idx)==0, continue; end
            col = grp*[0.55 0.20 0.66] + ~grp*[0.25 0.38 0.70];
            mu1 = mean(pre_v(idx),'omitnan');  se1 = std(pre_v(idx),'omitnan')/sqrt(sum(idx));
            mu2 = mean(post_v(idx),'omitnan'); se2 = std(post_v(idx),'omitnan')/sqrt(sum(idx));
            errorbar([1 2],[mu1 mu2],[se1*1.96 se2*1.96],'o-','Color',col,'LineWidth',2.5, ...
                'MarkerFaceColor',col,'MarkerSize',8,'DisplayName',local_ternary(grp));
        end

        % extreme CHANGE (post-pre), labeled -- the paired-plot analogue
        % of "extreme value" since a single timepoint isn't the point here
        delta = post_v - pre_v;
        valid_idx = find(valid);

        % ---- DEBUG: full subject-by-subject dump, sorted by delta -----
        % Prints every valid subject's pre/post/delta plus how many raw
        % rows were averaged into pre/post (catches a subject silently
        % getting pooled from very few -- or unexpectedly many -- rows).
        % Compare this printout against what the figure shows: if the
        % printed max/min subject doesn't match the one the figure
        % highlights, that's a plotting bug; if it DOES match but looks
        % wrong on the chart, the issue is upstream in the data itself.
        fprintf('\n--- DEBUG %s | %s | %s -> %s | %s ---\n', oc, phase_type, phase_pre, phase_post, panel_label{pnl});
        fprintf('%-18s %5s %10s %10s %10s %6s %6s\n', 'Subject','Grp','pre','post','delta','n_pre','n_post');
        [~,ord] = sort(delta(valid_idx));
        for k = ord(:)'
            sidx = valid_idx(k);
            s = subj_list{sidx};
            n_pre  = sum(strcmp(Tp.subject,s) & strcmp(Tp.phase,phase_pre));
            n_post = sum(strcmp(Tp.subject,s) & strcmp(Tp.phase,phase_post));
            fprintf('%-18s %5s %10.4f %10.4f %10.4f %6d %6d\n', ...
                s, local_ternary(is_h(sidx)), pre_v(sidx), post_v(sidx), delta(sidx), n_pre, n_post);
        end
        fprintf('n_subjects_total=%d  n_valid(both pre&post)=%d  n_unique_subject_strings=%d\n', ...
            numel(subj_list), numel(valid_idx), numel(unique(subj_list)));

        if ~isempty(valid_idx)
            [~,imax] = max(delta(valid_idx)); [~,imin] = min(delta(valid_idx));
            si_max = valid_idx(imax); si_min = valid_idx(imin);
            fprintf('SELECTED max-delta: %s (delta=%.4f)   SELECTED min-delta: %s (delta=%.4f)\n', ...
                subj_list{si_max}, delta(si_max), subj_list{si_min}, delta(si_min));
            text(2.05, post_v(si_max), sprintf('%s (max \\Delta)', erase(subj_list{si_max},'subject_')), ...
                'Color',[0.85 0.10 0.10],'FontSize',7,'FontWeight','bold','Interpreter','tex');
            text(2.05, post_v(si_min), sprintf('%s (min \\Delta)', erase(subj_list{si_min},'subject_')), ...
                'Color',[0.10 0.30 0.85],'FontSize',7,'FontWeight','bold','Interpreter','tex');
            scatter([1 2],[pre_v(si_max) post_v(si_max)],40,[0.85 0.10 0.10],'filled','HandleVisibility','off');
            scatter([1 2],[pre_v(si_min) post_v(si_min)],40,[0.10 0.30 0.85],'filled','HandleVisibility','off');
        end

        xlim([0.7 2.6]); xticks([1 2]); xticklabels({phase_pre, phase_post});
        ylabel(oc_label, 'Interpreter','tex');
        title(sprintf('%s (n=%d paired subjects)', panel_label{pnl}, sum(valid)), 'FontSize',11);
       
    end
    saveas(fig, fullfile(cfg.output_root,'figures', sprintf('%s_%s_%s_paired_before_after.png', oc, phase_pre, phase_post)));
    fprintf('Saved %s_%s_%s_paired_before_after.png\n', oc, phase_pre, phase_post);
end

function out = local_ternary(c)
    labels = {'NHF','HF'};
    out = labels{c+1};
end