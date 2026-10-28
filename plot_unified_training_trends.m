%% plot_unified_trends_and_transfers.m
% Consolidated version of your two pasted copies (an older header +
% the full "flatcheck" version appended after it) -- this is ONE clean
% file, not two overlapping ones.
%
% CHANGE 1 (what you asked for): tssv_known_bad / tssf_known_bad are no
% longer hardcoded here. They're loaded from accel_exclusion_lists.mat,
% which accel_exclusion_list.m now saves -- that script is the single
% source of truth; this one just reads it. Run accel_exclusion_list.m
% first if accel_exclusion_lists.mat doesn't exist yet.
%
% CHANGE 2 (a real fix found while doing #1): the AFTER panel previously
% only removed WHOLE-SUBJECT exclusions (a subject-name mask applied to
% the raw table) -- it never applied your per-acquisition exclusions
% (e.g. s20N/s45H/s36N specific levels/reps). force_vibration_features_
% clean.mat already has BOTH kinds of exclusion correctly NaN'd in, so
% the AFTER panel now loads that file directly and filters on
% isfinite(), instead of re-deriving a coarser mask from the raw table.
% EDA/eye/perf have no separate "clean" file (no acquisition-level
% exclusions exist for them), so for those three the AFTER panel still
% falls back to the same subject-name mask as before -- unchanged
% behavior there.
%
% EYE TABLE COLUMN NAMES: pupil_mean_norm, saccade_rate, gaze_dispersion
% -- confirmed elsewhere in your codebase (run_training_lmms_3way.m).

clear; clc; cfg = config();
if ~exist(fullfile(cfg.output_root,'figures'),'dir'), mkdir(fullfile(cfg.output_root,'figures')); end

excl_path = fullfile(cfg.output_root,'accel_exclusion_lists.mat');
if ~isfile(excl_path)
    error('plot_unified_trends_and_transfers: run accel_exclusion_list.m first (it saves accel_exclusion_lists.mat).');
end
excl = load(excl_path, 'tssv_subj_excl','tssf_subj_excl');
tssv_known_bad = excl.tssv_subj_excl;
tssf_known_bad = excl.tssf_subj_excl;
eda_known_bad  = {};                                   % fill in if you have EDA-specific exclusions
eye_known_bad  = {'subject_s12H','subject_s15H'};      % per the methods doc
perf_known_bad = {};


%% ENGINE A: raw-data trend by level or repetition

FV       = load(fullfile(cfg.output_root,'force_vibration_features.mat'),'T'); FV = FV.T;
FV_clean = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); FV_clean = FV_clean.T;

local_trend_plot(FV, FV_clean, 'tssv', 'log(TSSV)', 'level', tssv_known_bad, cfg, true);
local_trend_plot(FV, FV_clean, 'tssf', 'log(TSSF)', 'level', tssf_known_bad, cfg, true);
local_trend_plot(FV, FV_clean, 'tssv', 'log(TSSV)', 'rep',   tssv_known_bad, cfg, true);
local_trend_plot(FV, FV_clean, 'tssf', 'log(TSSF)', 'rep',   tssf_known_bad, cfg, true);

if isfile(fullfile(cfg.output_root,'perf_features.mat'))
    PERF = load(fullfile(cfg.output_root,'perf_features.mat'),'T'); PERF = PERF.T;
    % No separate "clean" file for perf -- pass PERF as both raw and
    % after-table, which makes the AFTER panel fall back to the
    % known_bad mask (perf_known_bad is empty, so before==after here).
    local_trend_plot(PERF, PERF, 'duration_s',   'Completion time (s)',  'rep',   perf_known_bad, cfg, false);
    local_trend_plot(PERF, PERF, 'n_collisions', 'Collisions per trial', 'level', perf_known_bad, cfg, false);
end


%% ENGINE B: paired pre/post transfer (Baseline1->2 and Test1->2)

local_paired_plot(FV, FV_clean, 'tssv', 'log(TSSV)', 'baseline','Baseline1','Baseline2', tssv_known_bad, cfg);
local_paired_plot(FV, FV_clean, 'tssf', 'log(TSSF)', 'baseline','Baseline1','Baseline2', tssf_known_bad, cfg);
local_paired_plot(FV, FV_clean, 'tssv', 'log(TSSV)', 'test','Test1','Test2', tssv_known_bad, cfg);
local_paired_plot(FV, FV_clean, 'tssf', 'log(TSSF)', 'test','Test1','Test2', tssf_known_bad, cfg);

%%
 if isfile(fullfile(cfg.output_root,'eda_features_v2.mat'))
    EDA = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); EDA = EDA.T;
    local_paired_plot(EDA, EDA, 'scl_mean_bc', 'Tonic SCL (\muS)', 'baseline','Baseline1','Baseline2', eda_known_bad, cfg);
    local_paired_plot(EDA, EDA, 'scr_freq', 'SCR frequency (events/min)', 'baseline','Baseline1','Baseline2', eda_known_bad, cfg);
    local_paired_plot(EDA, EDA, 'scl_mean_bc', 'Tonic SCL (\muS)', 'test','Test1','Test2', eda_known_bad, cfg);
    local_paired_plot(EDA, EDA, 'scr_freq', 'SCR frequency (events/min)', 'test','Test1','Test2', eda_known_bad, cfg);
end

if isfile(fullfile(cfg.output_root,'eye_features_v2.mat'))
    EYE = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T'); EYE = EYE.T;
    eye_metrics = {'pupil_mean_norm','Pupil (norm.)'; 'saccade_rate','Saccade rate (/min)'; 'gaze_dispersion','Gaze dispersion'};
    for i = 1:size(eye_metrics,1)
        local_paired_plot(EYE, EYE, eye_metrics{i,1}, eye_metrics{i,2}, 'baseline','Baseline1','Baseline2', eye_known_bad, cfg);
    end
end

if isfile(fullfile(cfg.output_root,'perf_features.mat'))
    local_paired_plot(PERF, PERF, 'duration_s', 'Completion time (s)', 'baseline','Baseline1','Baseline2', perf_known_bad, cfg);
    local_paired_plot(PERF, PERF, 'n_collisions', 'Collisions per trial', 'baseline','Baseline1','Baseline2', perf_known_bad, cfg);
end

fprintf('\nAll figures saved to %s\n', fullfile(cfg.output_root,'figures'));


%% ========================================================================
%% ENGINE A: trend by level/repetition
%% ========================================================================

function local_trend_plot(T_raw, T_after, oc, oc_label, x_mode, known_bad, cfg, do_log)
% T_raw: unexcluded table (BEFORE panel, and the source for the
%   FLAT-SUBJECT CHECK and known_bad highlighting).
% T_after: the table to draw the AFTER panel from. Pass the real
%   force_vibration_features_clean.mat table for tssv/tssf (applies
%   BOTH whole-subject and per-acquisition exclusions via isfinite()).
%   Pass the SAME table as T_raw when there's no separate clean file
%   (EDA/eye/perf) -- that falls back to a known_bad subject-name mask.
    use_clean_file = ~isequal(T_raw, T_after);

    if strcmp(x_mode,'level'), xlab = 'Training Level'; else, xlab = 'Repetition'; end

    [Ttr_before, x_before, n_x] = local_prep_trend_table(T_raw, oc, x_mode);
    if isempty(Ttr_before), fprintf('[skip] %s (%s): no rows.\n', oc, x_mode); return; end

    if use_clean_file
        [Ttr_after, x_after, ~] = local_prep_trend_table(T_after, oc, x_mode);
    else
        keep = ~ismember(Ttr_before.subject, known_bad);
        Ttr_after = Ttr_before(keep,:); x_after = x_before(keep);
    end

    %% --- FLAT-SUBJECT CHECK (raw, before exclusion) -----------------------
    fprintf('\n--- FLAT-SUBJECT CHECK: %s by %s (raw per-trial values, before exclusion) ---\n', oc, x_mode);
    subj_all = unique(Ttr_before.subject);
    for si = 1:numel(subj_all)
        s = subj_all{si};
        v = Ttr_before.(oc)(strcmp(Ttr_before.subject,s));
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

    panel_tables = {Ttr_before, Ttr_after};
    panel_x      = {x_before,   x_after};
    panel_label  = {'BEFORE exclusion', 'AFTER exclusion'};

    for pnl = 1:2
        Tp = panel_tables{pnl}; xp = panel_x{pnl};
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
            % panel this is a no-op: known_bad subjects aren't in Tp
            % there (either filtered via isfinite() on the clean table,
            % or via the known_bad mask), so is_bad is never true there.
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

function [Ttr, x_all, n_x] = local_prep_trend_table(T, oc, x_mode)
    Ttr = T(strcmp(T.phase_type,'training') & isfinite(T.(oc)), :);
    if strcmp(x_mode,'level')
        Ttr = Ttr(isfinite(Ttr.level),:);
        n_x = 5;
        x_all = Ttr.level;
    else
        x_all = str2double(regexp(Ttr.acquisition,'\d+','match','once'));
        n_x = max(x_all);
    end
end


%% ========================================================================
%% ENGINE B: paired pre/post transfer
%% ========================================================================

function local_paired_plot(T_raw, T_after, oc, oc_label, phase_type, phase_pre, phase_post, known_bad, cfg)
% Same T_raw/T_after convention as local_trend_plot.
    use_clean_file = ~isequal(T_raw, T_after);

    Tph_before = T_raw(strcmp(T_raw.phase_type,phase_type) & isfinite(T_raw.(oc)) & T_raw.(oc)>0, :);
    if isempty(Tph_before), fprintf('[skip] %s %s->%s: no rows.\n', oc, phase_pre, phase_post); return; end

    if use_clean_file
        Tph_after = T_after(strcmp(T_after.phase_type,phase_type) & isfinite(T_after.(oc)) & T_after.(oc)>0, :);
    else
        Tph_after = Tph_before(~ismember(Tph_before.subject, known_bad), :);
    end

    fig = figure('Position',[100 100 1300 500]);
    tl = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
    title(tl, sprintf('%s: %s to %s -- before vs after subject exclusion', oc_label, phase_pre, phase_post), 'FontWeight','bold', 'Interpreter','tex');

    panel_tables = {Tph_before, Tph_after};
    panel_label  = {'BEFORE exclusion', 'AFTER exclusion'};

    for pnl = 1:2
        Tp = panel_tables{pnl};
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