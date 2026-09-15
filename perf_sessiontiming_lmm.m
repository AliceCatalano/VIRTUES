function results = perf_sessiontiming_lmm(T, outcome, first_n, last_n)
% PERF_SESSIONTIMING_LMM  Log-transformed Haptic x Timing (start vs end of
% training) model, following the log-transform / first-N-vs-last-N-trial-
% averaging / Type III ANOVA / Holm post-hoc method you specified.
%
% ADAPTATION NOTE (read before trusting output): the method as given uses
% a "Session" factor (Natural Learning, Targeted Learning 1/2, Crossover)
% that does not correspond to any phase in this study's actual design.
% VIRTUES's phases are: training (50 trials: 5 Levels x 10 repetitions),
% Baseline1/Baseline2 (5 trials each, one per Level), Test1/Test2 (1 trial
% each). A "start vs end of session" Timing split needs at least
% first_n+last_n trials WITHIN a session to be meaningful -- that only
% holds for the training block here. Baseline/Test do not have enough
% trials for this specific split (they already have their own dedicated
% pre/post model, gsr_transfer_lmm.m/perf_transfer_lmm.m, which IS the
% right tool for a 2-timepoint comparison). This function therefore
% applies Haptic x Timing (no separate Session factor -- there is only
% one session here) to the TRAINING block only, with Timing = first_n vs
% last_n repetitions, POOLED ACROSS all 5 Levels (since the source method
% has no Level factor at all; Level's own effect is already tested
% elsewhere, Table 2/2b). If you intended Session to mean something else
% in your own head (e.g. distinguishing early vs late Levels rather than
% early vs late repetitions), this is not that model -- say so and it can
% be rebuilt.
%
% Steps (matching your specification):
%   1. Restrict to phase_type=='training', outcome finite.
%   2. Timing: repetition in [1, first_n] -> 'start'; repetition in
%      [11-last_n, 10] -> 'end'; middle repetitions excluded from this
%      specific analysis (matching "first three / last three trials",
%      not the full 10).
%   3. Log-transform the outcome (log(x); rows with x<=0 -- e.g. TSSF/TSSV
%      trials entirely below the noise threshold, giving a literal 0 sum
%      -- are EXCLUDED with a printed count, not log(x+epsilon), since
%      adding an arbitrary epsilon would fabricate a value the data don't
%      support; see perf_extract_force_vibration_features.m).
%   4. Average log(outcome) per subject x Timing (this is the "first
%      three trials / last three trials" per-participant average,
%      computed on the log scale to match "log-transformed ... to address
%      non-normality" being the stated reason for the transform).
%   5. Fit: log_outcome ~ haptic_num*timing_num + (1 | subject_cat) --
%      only ONE two-way interaction is possible here (Haptic x Timing),
%      since Session is not a separate factor in this restricted version;
%      see the adaptation note above for why.
%   6. Type III ANOVA. MATLAB's fitlme/anova supports DFMethod
%      'Satterthwaite' or 'Residual' -- NOT Kenward-Roger, which the
%      method you gave specifies. Satterthwaite is used here as the
%      closest available approximation in MATLAB's Statistics and
%      Machine Learning Toolbox; this is a tooling substitution, not a
%      silent deviation -- flag it as such wherever this result is
%      reported.
%   7. If any effect is significant (p<.05), post-hoc pairwise contrasts
%      across all 4 cells (N-start, N-end, H-start, H-end) with Holm-
%      Bonferroni correction (local_holm_correction below) -- not Tukey
%      or FDR, matching "Holm's adjustment for multiple comparisons" as
%      specified.
%
% Returns results with fields: outcome, n_subjects, n_excluded_nonpositive,
% lme, anova_table (Type III, Satterthwaite), posthoc (table of all 6
% pairwise cell contrasts with Holm-adjusted p, populated only if any
% ANOVA effect was significant -- otherwise empty).

    if nargin < 3 || isempty(first_n), first_n = 3; end
    if nargin < 4 || isempty(last_n),  last_n  = 3; end

    Ttr = T(strcmp(T.phase_type, 'training') & isfinite(T.(outcome)), :);

    is_start = Ttr.repetition <= first_n;
    is_end   = Ttr.repetition >= (11 - last_n);
    Ttr = Ttr(is_start | is_end, :);
    Ttr.timing = repmat({'end'}, height(Ttr), 1);
    Ttr.timing(Ttr.repetition <= first_n) = {'start'};

    n_nonpositive = sum(Ttr.(outcome) <= 0);
    Ttr = Ttr(Ttr.(outcome) > 0, :);
    if n_nonpositive > 0
        fprintf('  [%s] excluded %d row(s) with non-positive value before log-transform (cannot log-transform a zero/negative TSS sum)\n', ...
            outcome, n_nonpositive);
    end

    Ttr.log_outcome = log(Ttr.(outcome));
    Ttr.subject_cat = categorical(Ttr.subject);
    Ttr.haptic_num  = double(Ttr.haptic);
    Ttr.timing_cat  = categorical(Ttr.timing, {'start','end'});
    Ttr.timing_num  = double(Ttr.timing_cat == 'end');

    [subj_list, ~, subj_idx] = unique(Ttr.subject_cat);
    [timing_list, ~, timing_idx] = unique(Ttr.timing_cat);
    haptic_by_subj = accumarray(subj_idx, Ttr.haptic_num, [], @mean);

    cell_idx = (subj_idx - 1) * numel(timing_list) + timing_idx;
    log_mean = accumarray(cell_idx, Ttr.log_outcome, [numel(subj_list)*numel(timing_list), 1], @mean, NaN);
    subj_rep    = repelem(subj_list, numel(timing_list));
    timing_rep  = repmat(timing_list, numel(subj_list), 1);
    haptic_rep  = repelem(haptic_by_subj, numel(timing_list));

    Tagg = table(subj_rep, haptic_rep, timing_rep, log_mean, ...
        'VariableNames', {'subject_cat','haptic_num','timing_cat','log_outcome'});
    Tagg = Tagg(isfinite(Tagg.log_outcome), :);
    Tagg.timing_num = double(Tagg.timing_cat == 'end');

    lme = fitlme(Tagg, 'log_outcome ~ haptic_num*timing_num + (1 | subject_cat)', 'FitMethod', 'REML');

    atbl = anova(lme, 'DFMethod', 'satterthwaite');

    fprintf('\n=== %s: Haptic x Timing (start=first %d reps, end=last %d reps, training, log scale) ===\n', ...
        outcome, first_n, last_n);
    disp(lme);
    fprintf('Type III ANOVA (Satterthwaite DF -- Kenward-Roger not available in MATLAB, see header):\n');
    disp(atbl);

    results.outcome = outcome;
    results.n_subjects = numel(subj_list);
    results.n_excluded_nonpositive = n_nonpositive;
    results.lme = lme;
    results.anova_table = atbl;
    results.posthoc = table();

    any_sig = any(atbl.pValue(2:end) < 0.05);   % skip the intercept row
    if any_sig
        fe = lme.Coefficients;
        covb = lme.CoefficientCovariance;
        dfe  = lme.DFE;
        cells = {'N_start','N_end','H_start','H_end'};
        cell_vals = [0 0; 0 1; 1 0; 1 1];   % [haptic_num, timing_num]

        pairs = nchoosek(1:4, 2);
        rows = {};
        for pi = 1:size(pairs,1)
            a = pairs(pi,1); b = pairs(pi,2);
            ca = local_predict_contrast(fe, cell_vals(a,1), cell_vals(a,2));
            cb = local_predict_contrast(fe, cell_vals(b,1), cell_vals(b,2));
            c  = ca - cb;
            est = c' * fe.Estimate;
            se  = sqrt(c' * covb * c);
            t   = est / se;
            p   = 2 * (1 - tcdf(abs(t), dfe));
            rows(end+1,:) = {sprintf('%s vs %s', cells{a}, cells{b}), est, se, t, dfe, p}; %#ok<AGROW>
        end
        posthoc = cell2table(rows, 'VariableNames', {'contrast','beta','se','t','df','p'});
        posthoc.p_holm = local_holm_correction(posthoc.p);
        results.posthoc = posthoc;

        fprintf('\nPost hoc pairwise contrasts (Holm-adjusted, since ANOVA found a significant effect):\n');
        disp(posthoc);
    else
        fprintf('\nNo ANOVA effect significant at p<.05 -- no post hoc comparisons run.\n');
    end
end

function c = local_predict_contrast(fe, haptic_val, timing_val)
    nterms = numel(fe.Name);
    c = zeros(nterms, 1);
    c(strcmp(fe.Name, '(Intercept)')) = 1;
    idx_h  = strcmp(fe.Name, 'haptic_num');
    idx_t  = strcmp(fe.Name, 'timing_num');
    idx_ht = cellfun(@(n) isequal(sort(strsplit(n, ':')), sort({'haptic_num','timing_num'})), fe.Name);
    c(idx_h)  = haptic_val;
    c(idx_t)  = timing_val;
    c(idx_ht) = haptic_val * timing_val;
end

function p_adj = local_holm_correction(p)
% Holm-Bonferroni step-down correction (not FDR) -- matches "Holm's
% adjustment for multiple comparisons" as specified.
    p = p(:);
    n = numel(p);
    [p_sorted, idx] = sort(p);
    mult = (n:-1:1)';
    p_holm_sorted = min(cummax(p_sorted .* mult), 1);
    p_adj = zeros(n, 1);
    p_adj(idx) = p_holm_sorted;
end
