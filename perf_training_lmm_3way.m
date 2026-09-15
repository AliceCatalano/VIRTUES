function results = perf_training_lmm_3way(T, outcome, family)
% PERF_TRAINING_LMM_3WAY  perf_training_lmm.m's performance model extended
% with the same Haptic*Level*Repetition three-way term as
% gsr_training_lmm_3way.m, so GSR, eye-tracking, and performance outcomes
% all get the identical "does the group learning-rate difference depend
% on difficulty level" test -- see gsr_training_lmm_3way.m's header for
% the full rationale; this file only adds fitglme/Poisson support on top
% of it, mirroring how perf_training_lmm.m relates to gsr_training_lmm.m.
%
%   family = 'gaussian' -> fitlme, REML  (e.g. duration_s)
%   family = 'poisson'  -> fitglme, log link, Laplace  (e.g. n_collisions;
%            coefficients are log-rate-ratios, as in perf_training_lmm.m)
%
% Model (both families):
%   Outcome ~ Haptic * Level * Repetition + (1 + Repetition | Subject)
%
% Returns the same fields as perf_training_lmm.m PLUS three_way_omnibus_*,
% three_way_terms, and repetition_slopes -- see gsr_training_lmm_3way.m.

    Ttr = T(strcmp(T.phase_type, 'training'), :);
    Ttr = Ttr(isfinite(Ttr.(outcome)), :);

    if height(Ttr) < 10
        warning('perf_training_lmm_3way: only %d usable rows for %s -- model may not be reliable', ...
            height(Ttr), outcome);
    end

    Ttr.subject_cat = categorical(Ttr.subject);
    Ttr.level_cat   = categorical(Ttr.level);
    Ttr.haptic_num  = double(Ttr.haptic);
    Ttr.repetition  = double(Ttr.repetition);

    fe_terms = 'haptic_num*level_cat*repetition';
    formula_maximal = sprintf('%s ~ %s + (1 + repetition | subject_cat)', outcome, fe_terms);
    formula_reduced = sprintf('%s ~ %s + (1 | subject_cat) + (repetition - 1 | subject_cat)', outcome, fe_terms);

    [mdl, re_structure, re_diag] = fit_with_re_fallback_3way(Ttr, formula_maximal, formula_reduced, outcome, family);

    fprintf('\n=== %s [%s] (training phase, 3-WAY Haptic*Level*Repetition, n=%d obs, %d subjects, RE structure: %s) ===\n', ...
        outcome, family, mdl.NumObservations, numel(unique(Ttr.subject_cat)), re_structure);
    disp(mdl);

    fe = mdl.Coefficients;

    atbl = anova(mdl);
    three_way_row = cellfun(@(t) isequal(sort(strsplit(t, ':')), sort({'haptic_num','level_cat','repetition'})), atbl.Term);
    if any(three_way_row)
        results.three_way_omnibus_F   = atbl.FStat(three_way_row);
        results.three_way_omnibus_p   = atbl.pValue(three_way_row);
        results.three_way_omnibus_DF1 = atbl.DF1(three_way_row);
        results.three_way_omnibus_DF2 = atbl.DF2(three_way_row);
    else
        warning('perf_training_lmm_3way: could not locate the 3-way term in anova(mdl) output for %s', outcome);
        results.three_way_omnibus_F   = NaN;
        results.three_way_omnibus_p   = NaN;
        results.three_way_omnibus_DF1 = NaN;
        results.three_way_omnibus_DF2 = NaN;
    end

    is_3way = cellfun(@(name) numel(strsplit(name, ':')) == 3 && ...
        any(strcmp(strsplit(name, ':'), 'haptic_num')) && ...
        any(strcmp(strsplit(name, ':'), 'repetition')) && ...
        any(~cellfun('isempty', regexp(strsplit(name, ':'), '^level_cat_\d+$', 'once'))), fe.Name);
    results.three_way_terms = table(fe.Name(is_3way), fe.Estimate(is_3way), fe.SE(is_3way), fe.pValue(is_3way), ...
        'VariableNames', {'term','beta','se','p'});

    results.outcome        = outcome;
    results.family         = family;
    results.mdl            = mdl;
    results.n_obs          = mdl.NumObservations;
    results.re_structure   = re_structure;
    results.re_diagnostic  = re_diag;

    covb   = mdl.CoefficientCovariance;
    dfe    = fe.DF(strcmp(fe.Name, 'repetition'));
    nterms = numel(fe.Name);
    add_contrast = @(label, group, c) local_add_contrast(fe, covb, dfe, c, label, group);

    idx_rep  = strcmp(fe.Name, 'repetition');
    idx_repH = strcmp(fe.Name, 'repetition:haptic_num');

    level_names = regexp(fe.Name, '^level_cat_(\d+)$', 'tokens', 'once');
    level_ids   = find(~cellfun(@isempty, level_names));

    rows = {};
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
            continue;
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

function [mdl, re_structure, diag] = fit_with_re_fallback_3way(Ttr, formula_maximal, formula_reduced, outcome, family)
    lastwarn('');
    if strcmp(family, 'gaussian')
        mdl_max = fitlme(Ttr, formula_maximal, 'FitMethod', 'REML');
    else
        mdl_max = fitglme(Ttr, formula_maximal, 'Distribution', 'poisson', ...
            'Link', 'log', 'FitMethod', 'Laplace');
    end
    [warn_msg, ~] = lastwarn();

    psi        = covarianceParameters(mdl_max);
    Sigma      = psi{1};
    corr_max   = Sigma(1,2) / sqrt(Sigma(1,1) * Sigma(2,2));
    is_boundary = isnan(corr_max) || abs(corr_max) > 0.995;
    is_singular = is_boundary || ~isempty(regexpi(warn_msg, 'singular|ill-conditioned|converge', 'once'));

    diag.maximal_corr    = corr_max;
    diag.maximal_warning = warn_msg;
    diag.maximal_AIC     = mdl_max.ModelCriterion.AIC;
    diag.maximal_BIC     = mdl_max.ModelCriterion.BIC;

    if ~is_singular
        mdl = mdl_max;
        re_structure = 'maximal (correlated intercept+slope)';
        diag.reduced_fitted = false;
        return;
    end

    fprintf(['  [%s] maximal RE structure looks degenerate ' ...
        '(corr=%.4f%s) -- refitting with uncorrelated intercept+slope\n'], ...
        outcome, corr_max, local_ternary(isempty(warn_msg), '', sprintf(', warning: "%s"', warn_msg)));

    lastwarn('');
    if strcmp(family, 'gaussian')
        mdl_red = fitlme(Ttr, formula_reduced, 'FitMethod', 'REML');
    else
        mdl_red = fitglme(Ttr, formula_reduced, 'Distribution', 'poisson', ...
            'Link', 'log', 'FitMethod', 'Laplace');
    end
    [warn_msg_red, ~] = lastwarn();

    diag.reduced_fitted  = true;
    diag.reduced_warning = warn_msg_red;
    diag.reduced_AIC     = mdl_red.ModelCriterion.AIC;
    diag.reduced_BIC     = mdl_red.ModelCriterion.BIC;

    fprintf('  [%s] maximal AIC=%.1f BIC=%.1f  |  reduced AIC=%.1f BIC=%.1f\n', ...
        outcome, diag.maximal_AIC, diag.maximal_BIC, diag.reduced_AIC, diag.reduced_BIC);

    if isempty(warn_msg_red)
        mdl = mdl_red;
        re_structure = 'reduced (uncorrelated intercept+slope)';
    else
        fprintf(['  [%s] reduced structure ALSO warned ("%s") -- keeping the ' ...
            'maximal (degenerate) fit; interpret variance components with caution.\n'], outcome, warn_msg_red);
        mdl = mdl_max;
        re_structure = 'maximal (degenerate, no non-singular alternative found)';
    end
end

function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
