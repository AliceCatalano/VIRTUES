function results = perf_training_lmm(T, outcome, family)
% PERF_TRAINING_LMM  SAP Section 4.2 training-phase model applied to a
% performance outcome, mirroring gsr_training_lmm.m's structure (same
% fixed-effects formula, same RE-degeneracy fallback, same within-group
% simple-effects contrasts) so performance and physiological outcomes are
% analyzed with identical rigor and are directly comparable in the paper.
%
%   family = 'gaussian' -> LMM via fitlme (e.g. duration_s / task
%            completion time). REML, with the same maximal/reduced
%            random-effects fallback as gsr_training_lmm.m.
%   family = 'poisson'  -> GLMM via fitglme, log link (e.g. n_collisions /
%            collision count -- SAP 4.2 explicitly calls for "GLMMs for
%            count or binary outcomes"). Laplace approximation (more
%            accurate than the default MPL for count data with moderate
%            cluster sizes). Coefficients are on the log-rate scale --
%            exp(beta) is the rate ratio; this is NOT a raw-count
%            difference, and results/printed tables are labeled
%            accordingly. Overdispersion is not tested here -- Poisson
%            fixes the dispersion at 1; if collision counts turn out
%            over-dispersed relative to Poisson, that would need a
%            negative-binomial alternative, not implemented.
%
% Model (both families):
%   Outcome ~ Haptic*Level + Haptic*Repetition + (1 + Repetition | Subject)

    Ttr = T(strcmp(T.phase_type, 'training'), :);
    Ttr = Ttr(isfinite(Ttr.(outcome)), :);

    if height(Ttr) < 10
        warning('perf_training_lmm: only %d usable rows for %s -- model may not be reliable', ...
            height(Ttr), outcome);
    end

    Ttr.subject_cat = categorical(Ttr.subject);
    Ttr.level_cat   = categorical(Ttr.level);
    Ttr.haptic_num  = double(Ttr.haptic);
    Ttr.repetition  = double(Ttr.repetition);

    fe_terms = 'haptic_num*level_cat + haptic_num*repetition';
    formula_maximal = sprintf('%s ~ %s + (1 + repetition | subject_cat)', outcome, fe_terms);
    formula_reduced = sprintf('%s ~ %s + (1 | subject_cat) + (repetition - 1 | subject_cat)', outcome, fe_terms);

    [mdl, re_structure, re_diag] = fit_with_re_fallback(Ttr, formula_maximal, formula_reduced, outcome, family);

    fprintf('\n=== %s [%s] (training phase, n=%d obs, %d subjects, RE structure: %s) ===\n', ...
        outcome, family, mdl.NumObservations, numel(unique(Ttr.subject_cat)), re_structure);
    disp(mdl);

    fe = mdl.Coefficients;
    target_terms = sort({'haptic_num', 'repetition'});
    interaction_row = cellfun(@(name) isequal(sort(strsplit(name, ':')), target_terms), fe.Name);

    results.outcome        = outcome;
    results.family         = family;
    results.mdl             = mdl;
    results.n_obs            = mdl.NumObservations;
    results.re_structure     = re_structure;
    results.re_diagnostic    = re_diag;
    results.interaction_beta = fe.Estimate(interaction_row);
    results.interaction_se   = fe.SE(interaction_row);
    results.interaction_p    = fe.pValue(interaction_row);
    results.interaction_CI   = [fe.Lower(interaction_row), fe.Upper(interaction_row)];

    if isempty(results.interaction_p)
        warning('perf_training_lmm: could not locate haptic_num:repetition term for %s -- check formula/output', outcome);
        results.interaction_p = NaN;
    end

    level_haptic_mask    = ~cellfun('isempty', regexp(fe.Name, ':haptic_num$', 'once')) ...
                          & ~cellfun('isempty', regexp(fe.Name, '^level_cat', 'once'));
    results.level_haptic = table(fe.Name(level_haptic_mask), fe.Estimate(level_haptic_mask), ...
        fe.SE(level_haptic_mask), fe.pValue(level_haptic_mask), ...
        'VariableNames', {'term','beta','se','p'});

    % --- Within-group simple effects (same contrast approach as
    % gsr_training_lmm.m) -- for family='poisson' these are log-rate
    % contrasts: exp(beta) is the group's own rate ratio per unit
    % repetition / per level vs level 1, not an additive count change.
    covb   = mdl.CoefficientCovariance;
    dfe    = fe.DF(strcmp(fe.Name, 'repetition'));   % approximate; see note above
    nterms = numel(fe.Name);

    contrast_rows = {};
    add_contrast = @(label, group, c) local_add_contrast(fe, covb, dfe, c, label, group);

    idx_rep  = strcmp(fe.Name, 'repetition');
    idx_repH = strcmp(fe.Name, 'repetition:haptic_num');
    c = zeros(nterms,1); c(idx_rep) = 1;
    contrast_rows(end+1,:) = add_contrast('repetition (within-subject slope)', 'N', c);
    c = zeros(nterms,1); c(idx_rep) = 1; c(idx_repH) = 1;
    contrast_rows(end+1,:) = add_contrast('repetition (within-subject slope)', 'H', c);

    level_names = regexp(fe.Name, '^level_cat_(\d+)$', 'tokens', 'once');
    level_ids   = find(~cellfun(@isempty, level_names));
    for li = level_ids(:)'
        lvl      = level_names{li}{1};
        idx_lvl  = false(nterms,1); idx_lvl(li) = true;
        idx_lvlH = strcmp(fe.Name, sprintf('level_cat_%s:haptic_num', lvl));
        c = zeros(nterms,1); c(idx_lvl) = 1;
        contrast_rows(end+1,:) = add_contrast(sprintf('level %s vs level 1', lvl), 'N', c);
        c = zeros(nterms,1); c(idx_lvl) = 1; c(idx_lvlH) = 1;
        contrast_rows(end+1,:) = add_contrast(sprintf('level %s vs level 1', lvl), 'H', c);
    end

    results.simple_effects = cell2table(contrast_rows, ...
        'VariableNames', {'effect','group','beta','se','t','df','p','lower','upper'});
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

function [mdl, re_structure, diag] = fit_with_re_fallback(Ttr, formula_maximal, formula_reduced, outcome, family)
% Same degeneracy-detection strategy as gsr_training_lmm.m's
% fit_lmm_with_re_fallback, generalized to fitlme (gaussian) / fitglme
% (poisson, log link, Laplace approximation).

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
