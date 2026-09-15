function results = gsr_training_lmm_3way(T, outcome, covariate_cols)
% GSR_TRAINING_LMM_3WAY  Extends gsr_training_lmm.m's training-phase model
% to test whether the Haptic-vs-no-Haptic difference in LEARNING RATE
% (the repetition slope) itself depends on task difficulty (Level) --
% i.e. whether "the 10 repetitions at Level 1 behave differently from the
% 10 repetitions at Level 5," which the additive model in
% gsr_training_lmm.m cannot answer (see that function's header: it fits
% Haptic*Level and Haptic*Repetition as two SEPARATE two-way interactions
% added together, which assumes -- without testing -- that the repetition
% slope is the same size at every level).
%
%   Y ~ Haptic * Level * Repetition + (1 + Repetition | Subject)
%
% This is a full three-way factorial in Haptic, Level (categorical, 5
% levels), and Repetition (continuous 1-10, within-level trial index --
% see plot_learning_curves.m's header for why this is NOT the subject's
% overall 1-50 trial order). The new, three-way term
% (haptic_num:level_cat:repetition) tests exactly the dependence the
% reader asked about: does the group difference in repetition-slope
% change across levels?
%
% Applied THE SAME WAY across all three modalities in this pipeline (GSR,
% eye-tracking via direct reuse -- same pattern as gsr_training_lmm.m/
% run_eye_lmms.m -- and performance via the sibling perf_training_lmm_3way.m),
% per the explicit request that this test be consistent everywhere, not a
% one-off check on a single outcome.
%
% This is an EXPLORATORY extension of the SAP's literal Section 4.2
% formula (which specifies the additive two-way model, not a three-way
% one) -- report it as such, alongside (not instead of) the original
% gsr_training_lmm.m results, which remain the literal confirmatory H1/H4
% test and whose already-reported numbers are unaffected by this addition.
%
% covariate_cols: same optional additive-covariate mechanism as
% gsr_training_lmm.m (see that function's header).
%
% RANDOM-EFFECTS STRUCTURE: unchanged from gsr_training_lmm.m -- maximal
% (1 + repetition | subject) with the same degeneracy-detection fallback
% to (1 | subject) + (repetition - 1 | subject). A random slope that also
% varies by level (e.g. (1 + repetition | subject:level_cat)) was
% considered and rejected here: with only 10 repetitions per subject per
% level, that structure would need to estimate 5x as many subject-level
% covariance parameters from the same amount of data per cell, and is far
% more likely to be degenerate than the already-sometimes-degenerate
% maximal structure this pipeline uses today. The fixed-effect three-way
% term above is what tests the level-dependence question; the random
% effects continue to describe only overall between-subject variation in
% average level and overall (level-pooled) repetition slope.
%
% Returns results with the same fields as gsr_training_lmm.m PLUS:
%   results.three_way_omnibus_F/p/DF1/DF2  - joint (Type III ANOVA) test
%       of the whole haptic_num:level_cat:repetition term (4 df: one per
%       non-reference level) -- THE primary number for "does difficulty
%       modulate the group learning-rate difference."
%   results.three_way_terms   - table of the 4 individual per-level
%       three-way coefficients (level k vs level 1), each with its own
%       beta/se/p, for follow-up once the omnibus test is significant.
%   results.repetition_slopes - table of all 10 simple repetition slopes
%       (5 levels x 2 groups), each with a proper SE/CI/p from the full
%       coefficient covariance matrix -- this is the direct, per-level,
%       per-group answer to "is the level-1 learning trend different from
%       the level-5 learning trend," read straight off rather than
%       inferred from the omnibus test alone.

    if nargin < 3, covariate_cols = {}; end

    Ttr = T(strcmp(T.phase_type, 'training'), :);
    Ttr = Ttr(isfinite(Ttr.(outcome)), :);
    for c = covariate_cols
        Ttr = Ttr(~ismissing(Ttr.(c{1})), :);
    end

    if height(Ttr) < 10
        warning('gsr_training_lmm_3way: only %d usable rows for %s -- model may not be reliable', ...
            height(Ttr), outcome);
    end

    Ttr.subject_cat = categorical(Ttr.subject);
    Ttr.level_cat   = categorical(Ttr.level);
    Ttr.haptic_num  = double(Ttr.haptic);
    Ttr.repetition  = double(Ttr.repetition);

    fe_terms = 'haptic_num*level_cat*repetition';
    if ~isempty(covariate_cols)
        fe_terms = [fe_terms, ' + ', strjoin(covariate_cols, ' + ')];
    end
    formula_maximal = sprintf('%s ~ %s + (1 + repetition | subject_cat)', outcome, fe_terms);
    formula_reduced = sprintf('%s ~ %s + (1 | subject_cat) + (repetition - 1 | subject_cat)', outcome, fe_terms);

    [lme, re_structure, re_diag] = fit_lmm_with_re_fallback_3way(Ttr, formula_maximal, formula_reduced, outcome);

    fprintf('\n=== %s (training phase, 3-WAY Haptic*Level*Repetition, n=%d obs, %d subjects, RE structure: %s) ===\n', ...
        outcome, lme.NumObservations, numel(unique(Ttr.subject_cat)), re_structure);
    disp(lme);

    fe = lme.Coefficients;

    % --- Omnibus (Type III) test of the whole three-way term ---
    atbl = anova(lme);
    three_way_row = cellfun(@(t) isequal(sort(strsplit(t, ':')), sort({'haptic_num','level_cat','repetition'})), atbl.Term);
    if any(three_way_row)
        results.three_way_omnibus_F   = atbl.FStat(three_way_row);
        results.three_way_omnibus_p   = atbl.pValue(three_way_row);
        results.three_way_omnibus_DF1 = atbl.DF1(three_way_row);
        results.three_way_omnibus_DF2 = atbl.DF2(three_way_row);
    else
        warning('gsr_training_lmm_3way: could not locate the 3-way term in anova(lme) output for %s', outcome);
        results.three_way_omnibus_F   = NaN;
        results.three_way_omnibus_p   = NaN;
        results.three_way_omnibus_DF1 = NaN;
        results.three_way_omnibus_DF2 = NaN;
    end

    % --- Individual per-level 3-way coefficients (level k vs level 1) ---
    is_3way = cellfun(@(name) numel(strsplit(name, ':')) == 3 && ...
        any(strcmp(strsplit(name, ':'), 'haptic_num')) && ...
        any(strcmp(strsplit(name, ':'), 'repetition')) && ...
        any(~cellfun('isempty', regexp(strsplit(name, ':'), '^level_cat_\d+$', 'once'))), fe.Name);
    results.three_way_terms = table(fe.Name(is_3way), fe.Estimate(is_3way), fe.SE(is_3way), fe.pValue(is_3way), ...
        'VariableNames', {'term','beta','se','p'});

    results.outcome        = outcome;
    results.lme            = lme;
    results.n_obs          = lme.NumObservations;
    results.re_structure   = re_structure;
    results.re_diagnostic  = re_diag;

    % --- All 10 simple repetition slopes: 5 levels x 2 groups, each via a
    % proper contrast on the full coefficient covariance matrix (same
    % approach as gsr_training_lmm.m's local_add_contrast) ---
    covb   = lme.CoefficientCovariance;
    dfe    = lme.DFE;
    nterms = numel(fe.Name);
    add_contrast = @(label, group, c) local_add_contrast(fe, covb, dfe, c, label, group);

    idx_rep  = strcmp(fe.Name, 'repetition');
    idx_repH = strcmp(fe.Name, 'repetition:haptic_num');

    level_names = regexp(fe.Name, '^level_cat_(\d+)$', 'tokens', 'once');
    level_ids   = find(~cellfun(@isempty, level_names));
    %level_labels = ['1', cellfun(@(t) t{1}, level_names(level_ids), 'UniformOutput', false)];

    rows = {};
    % Level 1 (reference level): no level_cat:repetition term needed.
    c = zeros(nterms,1); c(idx_rep) = 1;
    rows(end+1,:) = add_contrast('1', 'N', c);
    c = zeros(nterms,1); c(idx_rep) = 1; c(idx_repH) = 1;
    rows(end+1,:) = add_contrast('1', 'H', c);

    for li = level_ids(:)'
        lvl        = level_names{li}{1};
        idx_lvlRep = strcmp(fe.Name, sprintf('level_cat_%s:repetition', lvl)) | ...
                     strcmp(fe.Name, sprintf('repetition:level_cat_%s', lvl));
        idx_3way   = strcmp(fe.Name, sprintf('haptic_num:level_cat_%s:repetition', lvl)) | ...
                     strcmp(fe.Name, sprintf('level_cat_%s:haptic_num:repetition', lvl)) | ...
                     strcmp(fe.Name, sprintf('haptic_num:repetition:level_cat_%s', lvl)) | ...
                     strcmp(fe.Name, sprintf('repetition:haptic_num:level_cat_%s', lvl)) | ...
                     strcmp(fe.Name, sprintf('level_cat_%s:repetition:haptic_num', lvl)) | ...
                     strcmp(fe.Name, sprintf('repetition:level_cat_%s:haptic_num', lvl));
        if ~any(idx_lvlRep) || ~any(idx_3way)
            continue;   % term-name order mismatch safeguard; omnibus test above is unaffected
        end
        c = zeros(nterms,1); c(idx_rep) = 1; c(idx_lvlRep) = 1;
        rows(end+1,:) = add_contrast(lvl, 'N', c);
        c = zeros(nterms,1); c(idx_rep) = 1; c(idx_repH) = 1; c(idx_lvlRep) = 1; c(idx_3way) = 1;
        rows(end+1,:) = add_contrast(lvl, 'H', c);
    end

    results.repetition_slopes = cell2table(rows, ...
        'VariableNames', {'level','group','beta','se','t','df','p','lower','upper'});
end

function row = local_add_contrast(fe, covb, dfe, c, label, group)
    beta_hat = fe.Estimate;
    est      = c' * beta_hat;
    se       = sqrt(c' * covb * c);
    t        = est / se;
    p        = 2 * (1 - tcdf(abs(t), dfe));
    crit     = tinv(0.975, dfe);
    row      = {label, group, est, se, t, dfe, p, est - crit*se, est + crit*se};
end

function [lme, re_structure, diag] = fit_lmm_with_re_fallback_3way(Ttr, formula_maximal, formula_reduced, outcome)
% Identical degeneracy-detection/fallback logic to gsr_training_lmm.m's
% fit_lmm_with_re_fallback (kept as a separate copy here, not a shared
% call, only because that function is local/private to gsr_training_lmm.m
% -- the RULE, not just the code, is meant to be identical).
    lastwarn('');
    lme_max = fitlme(Ttr, formula_maximal, 'FitMethod', 'REML');
    [warn_msg, ~] = lastwarn();

    psi        = covarianceParameters(lme_max);
    Sigma      = psi{1};
    corr_max   = Sigma(1,2) / sqrt(Sigma(1,1) * Sigma(2,2));
    is_boundary = isnan(corr_max) || abs(corr_max) > 0.995;
    is_singular = is_boundary || ~isempty(regexpi(warn_msg, 'singular|ill-conditioned|converge', 'once'));

    diag.maximal_corr    = corr_max;
    diag.maximal_warning = warn_msg;
    diag.maximal_AIC     = lme_max.ModelCriterion.AIC;
    diag.maximal_BIC     = lme_max.ModelCriterion.BIC;

    if ~is_singular
        lme = lme_max;
        re_structure = 'maximal (correlated intercept+slope)';
        diag.reduced_fitted = false;
        return;
    end

    fprintf(['  [%s] maximal RE structure looks degenerate ' ...
        '(corr=%.4f%s) -- refitting with uncorrelated intercept+slope\n'], ...
        outcome, corr_max, local_ternary(isempty(warn_msg), '', sprintf(', warning: "%s"', warn_msg)));

    lastwarn('');
    lme_red = fitlme(Ttr, formula_reduced, 'FitMethod', 'REML');
    [warn_msg_red, ~] = lastwarn();

    diag.reduced_fitted  = true;
    diag.reduced_warning = warn_msg_red;
    diag.reduced_AIC     = lme_red.ModelCriterion.AIC;
    diag.reduced_BIC     = lme_red.ModelCriterion.BIC;

    fprintf('  [%s] maximal AIC=%.1f BIC=%.1f  |  reduced AIC=%.1f BIC=%.1f\n', ...
        outcome, diag.maximal_AIC, diag.maximal_BIC, diag.reduced_AIC, diag.reduced_BIC);

    reduced_ok = isempty(warn_msg_red);
    if reduced_ok
        lme = lme_red;
        re_structure = 'reduced (uncorrelated intercept+slope)';
    else
        fprintf(['  [%s] reduced structure ALSO warned ("%s") -- keeping the ' ...
            'maximal (degenerate) fit; interpret variance components with caution.\n'], outcome, warn_msg_red);
        lme = lme_max;
        re_structure = 'maximal (degenerate, no non-singular alternative found)';
    end
end

function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
