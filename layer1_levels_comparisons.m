function results = layer1_levels_comparisons(cfg)
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
%2. between_group_per_level at each of the 5 levels separately: independent-samples N vs H, t-test + Wilcoxon rank-sum.
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
        'scl_mean',          sources.eda
        'scr_freq',          sources.eda
        'scr_mean_amp',      sources.eda
        'pupil_mean',        sources.eye
        'pupil_slope_norm',  sources.eye
        'gaze_dispersion',   sources.eye
        'saccade_rate',      sources.eye
        'tssf_raw',          sources.force_vibration
        'tssv',              sources.force_vibration
        'duration_s',        sources.perf
        'n_collisions',      sources.perf
        };
    outcome_list = outcome_list(~cellfun(@isempty, outcome_list(:,2)), :);
    n_out = size(outcome_list, 1);
    n_levels = 5;

    pairwise_rows = struct('within_N', {{}}, 'within_H', {{}}, 'between_pooled', {{}});
    between_group_rows = {};
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
    results.omnibus_within_N       = local_finalize_omnibus(omnibus_rows.within_N);
    results.omnibus_within_H       = local_finalize_omnibus(omnibus_rows.within_H);
    results.omnibus_pooled         = local_finalize_omnibus(omnibus_rows.pooled);

    save(fullfile(cfg.output_root, 'layer1_levels_results.mat'), 'results');
    fns = fieldnames(results);
    for i = 1:numel(fns)
        writetable(results.(fns{i}), fullfile(cfg.output_root, sprintf('layer1_levels_%s.csv', fns{i})));
    end

    fprintf('\n========== Layer1 Levels comparisons (training phase) ==========\n');
    for i = 1:numel(fns)
        fprintf('\n--- %s ---\n', fns{i});
        disp(results.(fns{i}));
    end
    fprintf('\nSaved to %s/layer1_levels_*.{mat,csv}\n', cfg.output_root);
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
    [~, p, ~, stats] = ttest2(x1, x2, 'Vartype', 'unequal');
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
    sources = struct('eda', [], 'eye', [], 'perf', [], 'force_vibration', []);
    files = {'eda', 'eda_features.mat'; 'eye', 'eye_features.mat'; ...
        'perf', 'perf_features.mat'; 'force_vibration', 'force_vibration_features.mat'};
    for i = 1:size(files, 1)
        path = fullfile(cfg.output_root, files{i, 2});
        if isfile(path)
            L = load(path, 'T');
            sources.(files{i, 1}) = L.T;
        end
    end
end
