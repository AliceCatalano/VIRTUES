function results = Claude_layer1_levels_comparisons(cfg)
% Corrected copy of layer1_levels_comparisons.m. Writes ONLY to <output_root>/Claude_outputs/layer1.
% Changes from the original:
%  1. Same current tables and outcome list as Claude_layer1_simple_comparisons.m.
%  2. NEW table between_group_on_level_change: (Level k - Level 1) per subject, N vs H. This is the
%     simple-statistics analogue of the Haptic x Level model term. The original only compared raw
%     level means between groups, which tests a different question and keeps all stable
%     between-subject variance in the error term.
%  3. Each between-group table also reports p_fdr_within_outcome (BH across that outcome's levels),
%     closer in size to the model families. p_fdr still corrects across the whole table.
%  4. The t statistic of between-group tests now has the same sign as mean_diff (H - N).
% --- original header follows ---
% LAYER1_LEVELS_COMPARISONS  Simple, transparent difficulty-level comparisons for the training phase (5 levels x 10 repetitions),
% mirroring layer1_simple_comparisons.m's Baseline1/2 and Test1/2 logic but restructured for a 5-level factor instead of a 2-phase factor, per
% "within-group, between group and within levels and later betweenlevels"
%
% "Full repetition" (Layer1): each subject contributes ONE value per LEVEL per outcome, averaged across all 10 repetitions within that
% level (not collision-restricted -- that is Layer2).
%
% FOUR comparison tables, matching each phrase in the requested structure:
%
% 1. within_group_pairwise ("within levels": within each group, does the outcome differ between levels?) -- for N and H
%      separately: paired Level_k vs Level_1 (k=2..5), t-test + Wilcoxon signed-rank, PLUS an omnibus Friedman test across all 5 levels
%      (one row per group in omnibus_within_group). Level 1 (easiest) is the reference, matching the "level k vs level 1" contrast
%      convention already used in plot_level_divergence.m / the LMMresults tables.
%
%2. between_group_per_level at each of the 5 levels separately: independent-samples N vs H, t-test + Wilcoxon rasdk-sum.
%
% 3. between_levels_pooled ("between levels", both groups combined) Level_k vs Level_1 (k=2..5), paired t-test + Wilcoxon signed-rank,
%      pooling N and H together, PLUS one pooled omnibus Friedman test per outcome (omnibus_pooled) -- this is "does difficulty matter at
%      all," independent of group.
%
% Same outcome list and FDR-within-family logic as layer1_simple_comparisons.m: BH-FDR applied separately within each of
% the pairwise/omnibus table types (across the 11 outcomes x however many rows that table type has), not pooled across table types.

% Saved to cfg.output_root/layer1_levels_results.mat 
    sources = local_load_sources(cfg);
    outcome_list = {
        'scl_mean_bc',       sources.eda
        'scr_freq',          sources.eda
        'scr_mean_amp_bc',   sources.eda
        'pupil_mean_norm',   sources.eye
        'pupil_slope_norm',  sources.eye_v1
        'gaze_dispersion',   sources.eye
        'gaze_entropy',      sources.eye
        'fixation_rate',     sources.eye
        'fixation_mean_dur', sources.eye
        'tssf_log',          sources.force_vibration
        'tssv_log',          sources.force_vibration
        'duration_s',        sources.perf
        'n_collisions',      sources.perf
        };
    outcome_list = outcome_list(~cellfun(@isempty, outcome_list(:,2)), :);
    n_out = size(outcome_list, 1);
    n_levels = 5;

    pairwise_rows = struct('within_N', {{}}, 'within_H', {{}}, 'between_pooled', {{}});
    between_group_rows = {};
    change_rows = {};
    omnibus_rows = struct('within_N', {{}}, 'within_H', {{}}, 'pooled', {{}});

    for oi = 1:n_out
        outcome = outcome_list{oi,1};
        Tsrc    = outcome_list{oi,2};

        Ttr = Tsrc(strcmp(Tsrc.phase_type, 'training') & isfinite(Tsrc.(outcome)), :);
        subj_list = unique(Ttr.subject);
        subj_by_level = nan(numel(subj_list), n_levels);
        is_h = false(numel(subj_list), 1);
        for si = 1:numel(subj_list)
            s = subj_list{si};
            Ts = Ttr(strcmp(Ttr.subject, s), :);
            is_h(si) = any(Ts.haptic);
            for lv = 1:n_levels
                subj_by_level(si, lv) = mean(Ts.(outcome)(Ts.level == lv), 'omitnan');
            end
        end

        % ---- 1. Within-group pairwise (Level k vs Level 1) + omnibus ----
        for grp_name = {'N','H'}
            g = grp_name{1};
            sel = local_ternary(strcmp(g,'H'), is_h, ~is_h);
            X = subj_by_level(sel, :);
            for k = 2:n_levels
                pairwise_rows.(sprintf('within_%s', g))(end+1,:) = local_paired_row(outcome, k, X(:,1), X(:,k));
            end
            omnibus_rows.(sprintf('within_%s', g))(end+1,:) = local_friedman_row(outcome, X);
        end

        % ---- 2. Between-group at each level ----
        for lv = 1:n_levels
            between_group_rows(end+1,:) = local_indep_row(outcome, lv, subj_by_level(~is_h, lv), subj_by_level(is_h, lv)); %#ok<AGROW>
        end

        % ---- 2b. Between-group on the change from Level 1 (analogue of Haptic x Level) ----
        for k = 2:n_levels
            d = subj_by_level(:, k) - subj_by_level(:, 1);
            change_rows(end+1,:) = local_indep_row(outcome, k, d(~is_h), d(is_h)); %#ok<AGROW>
        end

        % ---- 3. Between levels, pooled across groups ----
        for k = 2:n_levels
            pairwise_rows.between_pooled(end+1,:) = local_paired_row(outcome, k, subj_by_level(:,1), subj_by_level(:,k));
        end
        omnibus_rows.pooled(end+1,:) = local_friedman_row(outcome, subj_by_level);
    end

    results = struct();
    results.within_N_pairwise      = local_finalize_pairwise(pairwise_rows.within_N);
    results.within_H_pairwise      = local_finalize_pairwise(pairwise_rows.within_H);
    results.between_levels_pooled  = local_finalize_pairwise(pairwise_rows.between_pooled);
    results.between_group_per_level = local_finalize_between_group(between_group_rows);
    results.between_group_on_level_change = local_finalize_between_group(change_rows);
    results.omnibus_within_N       = local_finalize_omnibus(omnibus_rows.within_N);
    results.omnibus_within_H       = local_finalize_omnibus(omnibus_rows.within_H);
    results.omnibus_pooled         = local_finalize_omnibus(omnibus_rows.pooled);

    out_dir = fullfile(cfg.output_root, 'Claude_outputs', 'layer1'); if ~exist(out_dir,'dir'), mkdir(out_dir); end
    save(fullfile(out_dir, 'layer1_levels_results.mat'), 'results');
    fns = fieldnames(results);
    for i = 1:numel(fns)
        writetable(results.(fns{i}), fullfile(out_dir, sprintf('layer1_levels_%s.csv', fns{i})));
    end

    fprintf('\n========== Layer1 Levels comparisons (training phase) ==========\n');
    for i = 1:numel(fns)
        fprintf('\n--- %s ---\n', fns{i});
        disp(results.(fns{i}));
    end
    fprintf('\nSaved to %s/layer1_levels_*.{mat,csv}\n', out_dir);
end

function row = local_paired_row(outcome, level_k, x1, x2)
% x1 = Level 1 values, x2 = Level k values, one row per subject
    keep = isfinite(x1) & isfinite(x2);
    x1 = x1(keep); x2 = x2(keep);
    n = numel(x1);
    if n < 2
        row = {string(outcome), level_k, n, NaN, NaN, NaN, NaN, NaN};
        return
    end
    d = x2 - x1;
    [~, p, ~, stats] = ttest(x2, x1);
    p_w = local_signrank_safe(d);
    row = {string(outcome), level_k, n, mean(d), stats.tstat, stats.df, p, p_w};
end

function row = local_indep_row(outcome, level, x1, x2)
    x1 = x1(isfinite(x1)); x2 = x2(isfinite(x2));
    n1 = numel(x1); n2 = numel(x2);
    if n1 < 2 || n2 < 2
        row = {string(outcome), level, n1, n2, NaN, NaN, NaN, NaN, NaN};
        return
    end
    [~, p, ~, stats] = ttest2(x2, x1, 'Vartype', 'unequal');
    p_w = local_ranksum_safe(x1, x2);
    row = {string(outcome), level, n1, n2, mean(x2) - mean(x1), stats.tstat, stats.df, p, p_w};
end

function row = local_friedman_row(outcome, X)
% X: subjects x 5 levels. Friedman = nonparametric repeated-measures
% omnibus test across all 5 levels at once (no normality/sphericity
% assumption) -- complete cases only (Friedman requires no NaNs).
    keep = all(isfinite(X), 2);
    Xc = X(keep, :);
    n = size(Xc, 1);
    if n < 3
        row = {string(outcome), n, NaN, NaN, NaN};
        return
    end
    try
        [p, tbl] = friedman(Xc, 1, 'off');
        chi2 = tbl{2,5};
        df   = tbl{2,3};
    catch
        p = NaN; chi2 = NaN; df = NaN;
    end
    row = {string(outcome), n, chi2, df, p};
end

function tbl = local_finalize_pairwise(rows)
    tbl = cell2table(rows, 'VariableNames', {'outcome','level_vs_1','n','mean_diff','t','df','p','p_wilcoxon'});
    tbl.p_fdr = local_bh_fdr(tbl.p);
end

function tbl = local_finalize_between_group(rows)
    tbl = cell2table(rows, 'VariableNames', {'outcome','level','n1','n2','mean_diff','t','df','p','p_wilcoxon'});
    tbl.p_fdr = local_bh_fdr(tbl.p);
    tbl.p_fdr_within_outcome = nan(height(tbl),1);
    uo = unique(tbl.outcome);
    for u = 1:numel(uo)
        ix = tbl.outcome == uo(u);
        tbl.p_fdr_within_outcome(ix) = local_bh_fdr(tbl.p(ix));
    end
end

function tbl = local_finalize_omnibus(rows)
    tbl = cell2table(rows, 'VariableNames', {'outcome','n','chi2','df','p'});
    tbl.p_fdr = local_bh_fdr(tbl.p);
end

function p = local_signrank_safe(d)
    try, p = signrank(d); catch, p = NaN; end
end

function p = local_ranksum_safe(x1, x2)
    try, p = ranksum(x1, x2); catch, p = NaN; end
end

function p_adj = local_bh_fdr(p)
    n = numel(p);
    p_adj = nan(n, 1);
    valid = find(isfinite(p));
    [ps, ix] = sort(p(valid));
    m = numel(ps);
    adj = nan(m, 1);
    prev = 1;
    for k = m:-1:1
        val = ps(k) * m / k;
        prev = min(prev, val);
        adj(k) = prev;
    end
    p_adj(valid(ix)) = min(adj, 1);
end

function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end

function sources = local_load_sources(cfg)
% Current feature tables: cleaned force/vibration and the _v2 EDA and eye tables, the same
% ones the mixed models use. pupil_slope_norm exists only in the older eye table.
    sources = struct();
    L = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); sources.eda = L.T;
    L = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T'); sources.eye = L.T;
    L = load(fullfile(cfg.output_root,'eye_features.mat'),'T');    sources.eye_v1 = L.T;
    L = load(fullfile(cfg.output_root,'perf_features.mat'),'T');   sources.perf = L.T;
    L = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); F = L.T;
    F.tssf(F.tssf<=0)=NaN; F.tssv(F.tssv<=0)=NaN; F.tssf_log=log(F.tssf); F.tssv_log=log(F.tssv);
    sources.force_vibration = F;
end
