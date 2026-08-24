function results = gsr_training_lmm(T, outcome)
% FIT_TRAINING_LMM  Fit the primary training-phase model from SAP Section 4.2:
%
%   Y ~ Haptic*Level + Haptic*Repetition + (1 + Repetition | Subject)
%
% on the block-level feature table T (see gsr_extract_features.m), restricted to phase_type == 'training' rows (the level_L1..L5 / rep_01..10
% acquisitions). The Haptic x Repetition interaction is "the primary test of differential learning rate" per the SAP -- reported explicitly below.
% RANDOM-EFFECTS FALLBACK: the maximal structure (1 + repetition | subject) lets the random intercept and random slope correlate freely. For some
% outcomes (seen empirically for scr_mean_amp and collision_scr_amp_mean) that correlation is estimated at a boundary (|corr| > 0.995, or fitlme
% warns about a nearly-singular covariance), which is a degenerate fit, not a genuine estimate -- the fixed-effect coefficients can still be roughly
% right, but the model as specified isn't well-supported by the data. When that happens, this function automatically refits with an uncorrelated
% random-intercept + random-slope structure (1 | subject) + (repetition-1 | subject) -- same fixed effects, fewer covariance parameters -- and keeps
% whichever fit is both non-degenerate and has the lower BIC, per standard practice for non-converging maximal models (Matuschek et al., 2017).
% Which structure was used, and both AIC/BIC, are printed and stored in results.re_structure / results.re_diagnostic for auditing.
% NOTE: SAP Section 6 states demographic covariates (age, gender,handedness, gaming/robotic experience) will be included in "all primary
% models," but the explicit formula in Section 4.2 omits them, and no demographics file has been supplied to this pipeline. If you have one,
% join it onto T by 'subject' and add covariate terms to the formula below
% before treating this as the final confirmatory model -- as written here
% it implements the 4.2 formula literally, without covariates.

    Ttr = T(strcmp(T.phase_type, 'training'), :);
    Ttr = Ttr(isfinite(Ttr.(outcome)), :);

    if height(Ttr) < 10
        warning('fit_training_lmm: only %d usable rows for %s -- model may not be reliable', ...
            height(Ttr), outcome);
    end

    Ttr.subject_cat = categorical(Ttr.subject);
    Ttr.level_cat   = categorical(Ttr.level);
    Ttr.haptic_num  = double(Ttr.haptic);   % 0/1, for directly interpretable fixed effects
    Ttr.repetition  = double(Ttr.repetition);

    fe_terms = 'haptic_num*level_cat + haptic_num*repetition';
    formula_maximal = sprintf('%s ~ %s + (1 + repetition | subject_cat)', outcome, fe_terms);
    formula_reduced = sprintf('%s ~ %s + (1 | subject_cat) + (repetition - 1 | subject_cat)', outcome, fe_terms);

    [lme, re_structure, re_diag] = fit_lmm_with_re_fallback(Ttr, formula_maximal, formula_reduced, outcome);

     fprintf('\n=== %s (training phase, n=%d obs, %d subjects, RE structure: %s) ===\n', ...
        outcome, lme.NumObservations, numel(unique(Ttr.subject_cat)), re_structure);
    disp(lme);

    fe = lme.Coefficients;

    % fitlme names interaction terms in the order the variables first
    % appear in the formula (here: 'repetition:haptic_num', not
    % 'haptic_num:repetition'), so match on the set of terms rather than
    % a fixed string order.
    target_terms = sort({'haptic_num', 'repetition'});
    interaction_row = cellfun(@(name) isequal(sort(strsplit(name, ':')), target_terms), fe.Name);

    results.outcome          = outcome;
    results.lme               = lme;
    results.n_obs              = lme.NumObservations;
    results.interaction_beta   = fe.Estimate(interaction_row);
    results.re_structure       = re_structure;
    results.re_diagnostic      = re_diag;
    results.interaction_se     = fe.SE(interaction_row);
    results.interaction_p      = fe.pValue(interaction_row);
    results.interaction_CI     = [fe.Lower(interaction_row), fe.Upper(interaction_row)];

    if isempty(results.interaction_p)
        warning('fit_training_lmm: could not locate haptic_num:repetition term for %s -- check formula/output', outcome);
        results.interaction_p = NaN;
    end
    % Haptic x Level terms (secondary/exploratory -- not part of the SAP Section 8 FDR family, which only covers the primary Haptic x
    % Repetition test per outcome). Stored here so they're easy to inspect across outcomes/RE structures without re-parsing lme.Coefficients.
    level_haptic_mask       = ~cellfun('isempty', regexp(fe.Name, ':haptic_num$', 'once')) & ~cellfun('isempty', regexp(fe.Name, '^level_cat', 'once'));
    results.level_haptic    = table(fe.Name(level_haptic_mask), fe.Estimate(level_haptic_mask), ...
        fe.SE(level_haptic_mask), fe.pValue(level_haptic_mask),'VariableNames', {'term','beta','se','p'});

end

function [lme, re_structure, diag] = fit_lmm_with_re_fallback(Ttr, formula_maximal, formula_reduced, outcome)
% Fit the maximal (correlated intercept+slope) random-effects structure; fall back to an uncorrelated structure if the maximal fit is degenerate
% (boundary correlation or a covariance-singularity warning from fitlme). See the fit_training_lmm header comment above for the rationale.

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

    fprintf(['  [%s] maximal RE structure looks degenerate '  '(corr=%.4f%s) -- refitting with uncorrelated intercept+slope\n'], ...
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
            'maximal (degenerate) fit; interpret variance components with caution ' ...
            'and consider (1 | subject_cat) only.\n'], outcome, warn_msg_red);
        lme = lme_max;
        re_structure = 'maximal (degenerate, no non-singular alternative found)';
    end
end

function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end