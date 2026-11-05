function results = layer1_simple_comparisons(cfg, phase_type, phase_pre, phase_post, family_label)
% LAYER1_SIMPLE_COMPARISONS  Simple, transparent pre/post + between-group
% comparisons for every outcome, run BEFORE and separately from the
% mixed-effects models -- per the researcher's explicit request to see
% direct within-condition and between-condition comparisons (paired
% within-subject tests, independent between-group tests) as their own
% reported layer, not only as terms buried inside a multilevel model.
%
% "Full repetition" (Layer1, as opposed to the collision-restricted
% Layer2): each subject contributes ONE value per phase per outcome,
% averaged across every acquisition in that phase (for Baseline1/2, the
% 5 levels; for Test1/2, the single Peg Transfer trial) -- the exact same
% subject-level aggregation plot_transfer_paired_estimation.m already
% uses for its individual-subject lines, so these numbers are the
% statistics behind that figure, not a new/different aggregation.
%
% FIVE comparisons per outcome, matching "within condition groups" and
% "between condition groups" as separate, explicit questions:
%   1. Within N:  paired phase_pre vs phase_post (N group only)
%   2. Within H:  paired phase_pre vs phase_post (H group only)
%   3. Between groups AT phase_pre  (N vs H, independent samples)
%   4. Between groups AT phase_post (N vs H, independent samples)
%   5. Between groups ON THE CHANGE (post-pre delta, N vs H) -- the
%      simple-statistics analogue of the LMM's Haptic x Phase
%      interaction term, computed directly rather than as a model
%      coefficient.
% Each comparison reports a parametric test (paired/independent t-test)
% AND its nonparametric counterpart (Wilcoxon signed-rank / rank-sum) as
% a robustness check, since several outcomes here (n_collisions
% especially) are not expected to be normally distributed.
%
% Benjamini-Hochberg FDR correction is applied WITHIN each of the 5
% comparison types separately (across the 11 outcomes), not pooled
% across comparison types, following the same "family" logic used
% throughout this pipeline (Benjamini & Hochberg, 1995) -- these are 5
% distinct scientific questions, not one family of 55 tests.
%
% outcome list: scl_mean, scr_freq, scr_mean_amp (EDA); pupil_mean,
% pupil_slope_norm, gaze_dispersion, saccade_rate (eye); tssf, tssv
% (force/vibration); duration_s, n_collisions (performance).
% collision_scr_amp_mean / collision_pupil_response_mean are deliberately
% EXCLUDED here -- those are already collision-restricted and belong to
% Layer2, not this full-repetition Layer1.
%
% Usage:
%   layer1_simple_comparisons(cfg, 'baseline', 'Baseline1', 'Baseline2', 'baseline_elastic')
%   layer1_simple_comparisons(cfg, 'test',     'Test1',     'Test2',     'test_pegtransfer')
%
% Saved to cfg.output_root/layer1_<family_label>_results.mat (+ .csv).

    sources = local_load_sources(cfg);
    outcome_list = {
        'scl_mean',          sources.eda
        'scr_freq',          sources.eda
        'scr_mean_amp',      sources.eda
        'pupil_mean',        sources.eye
        'pupil_slope_norm',  sources.eye
        'gaze_dispersion',   sources.eye
        'saccade_rate',      sources.eye
        'tssf',          sources.force_vibration
        'tssv',              sources.force_vibration
        'duration_s',        sources.perf
        'n_collisions',      sources.perf
        };
    outcome_list = outcome_list(~cellfun(@isempty, outcome_list(:,2)), :);
    n_out = size(outcome_list, 1);

    comparison_names = {'within_N', 'within_H', 'between_at_pre', 'between_at_post', 'between_on_delta'};
    n_comp = numel(comparison_names);

    raw = struct();
    for c = 1:n_comp
        raw.(comparison_names{c}) = table('Size', [n_out, 8], ...
            'VariableTypes', {'string','double','double','double','double','double','double','double'}, ...
            'VariableNames', {'outcome','n1','n2','mean_diff','t','df','p','p_wilcoxon'});
    end

    for oi = 1:n_out
        outcome = outcome_list{oi, 1};
        Tsrc    = outcome_list{oi, 2};

        Tph = Tsrc(strcmp(Tsrc.phase_type, phase_type) & isfinite(Tsrc.(outcome)), :);
        Tph = Tph(ismember(Tph.phase, {phase_pre, phase_post}), :);

        subj_list = unique(Tph.subject);
        pre_vals  = nan(numel(subj_list), 1);
        post_vals = nan(numel(subj_list), 1);
        is_h      = false(numel(subj_list), 1);
        for si = 1:numel(subj_list)
            s = subj_list{si};
            pre_vals(si)  = mean(Tph.(outcome)(strcmp(Tph.subject, s) & strcmp(Tph.phase, phase_pre)),  'omitnan');
            post_vals(si) = mean(Tph.(outcome)(strcmp(Tph.subject, s) & strcmp(Tph.phase, phase_post)), 'omitnan');
            is_h(si) = any(Tph.haptic(strcmp(Tph.subject, s)));
        end
        keep = isfinite(pre_vals) & isfinite(post_vals);
        pre_vals = pre_vals(keep); post_vals = post_vals(keep); is_h = is_h(keep);
        delta = post_vals - pre_vals;

        % 1/2: within-group paired
        raw.within_N(oi, :) = local_paired_row(outcome, pre_vals(~is_h), post_vals(~is_h));
        raw.within_H(oi, :) = local_paired_row(outcome, pre_vals(is_h),  post_vals(is_h));

        % 3/4: between-group at each phase
        raw.between_at_pre(oi, :)  = local_indep_row(outcome, pre_vals(~is_h),  pre_vals(is_h));
        raw.between_at_post(oi, :) = local_indep_row(outcome, post_vals(~is_h), post_vals(is_h));

        % 5: between-group on the change score
        raw.between_on_delta(oi, :) = local_indep_row(outcome, delta(~is_h), delta(is_h));
    end

    results = struct('family_label', family_label, 'phase_type', phase_type, ...
        'phase_pre', phase_pre, 'phase_post', phase_post);
    for c = 1:n_comp
        cname = comparison_names{c};
        tbl = raw.(cname);
        tbl.p_fdr = local_bh_fdr(tbl.p);
        results.(cname) = tbl;
    end

    save(fullfile(cfg.output_root, sprintf('layer1_%s_results.mat', family_label)), 'results');
    for c = 1:n_comp
        writetable(results.(comparison_names{c}), ...
            fullfile(cfg.output_root, sprintf('layer1_%s_%s.csv', family_label, comparison_names{c})));
    end

    fprintf('\n========== Layer1 simple comparisons: %s (%s vs %s) ==========\n', ...
        family_label, phase_pre, phase_post);
    for c = 1:n_comp
        fprintf('\n--- %s ---\n', comparison_names{c});
        disp(results.(comparison_names{c}));
    end
    fprintf('\nSaved to %s/layer1_%s_*.{mat,csv}\n', cfg.output_root, family_label);
end

function row = local_paired_row(outcome, x_pre, x_post)
    keep = isfinite(x_pre) & isfinite(x_post);
    x_pre = x_pre(keep); x_post = x_post(keep);
    n = numel(x_pre);
    if n < 2
        row = {string(outcome), n, n, NaN, NaN, NaN, NaN, NaN};
        return
    end
    d = x_post - x_pre;
    [~, p, ~, stats] = ttest(x_post, x_pre);
    p_w = local_signrank_safe(d);
    row = {string(outcome), n, n, mean(d), stats.tstat, stats.df, p, p_w};
end

function row = local_indep_row(outcome, x1, x2)
    x1 = x1(isfinite(x1)); x2 = x2(isfinite(x2));
    n1 = numel(x1); n2 = numel(x2);
    if n1 < 2 || n2 < 2
        row = {string(outcome), n1, n2, NaN, NaN, NaN, NaN, NaN};
        return
    end
    [~, p, ~, stats] = ttest2(x1, x2, 'Vartype', 'unequal');
    p_w = local_ranksum_safe(x1, x2);
    row = {string(outcome), n1, n2, mean(x2) - mean(x1), stats.tstat, stats.df, p, p_w};
end

function p = local_signrank_safe(d)
    try
        p = signrank(d);
    catch
        p = NaN;
    end
end

function p = local_ranksum_safe(x1, x2)
    try
        p = ranksum(x1, x2);
    catch
        p = NaN;
    end
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
