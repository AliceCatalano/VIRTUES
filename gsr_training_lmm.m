function results = gsr_training_lmm(T, outcome)
% FIT_TRAINING_LMM  Fit the primary training-phase model from SAP Section 4.2:
%
%   Y ~ Haptic*Level + Haptic*Repetition + (1 + Repetition | Subject)
%
% on the block-level feature table T (see gsr_extract_features.m),
% restricted to phase_type == 'training' rows (the level_L1..L5 / rep_01..10
% acquisitions). The Haptic x Repetition interaction is "the primary test
% of differential learning rate" per the SAP -- reported explicitly below.
%
% NOTE: SAP Section 6 states demographic covariates (age, gender,
% handedness, gaming/robotic experience) will be included in "all primary
% models," but the explicit formula in Section 4.2 omits them, and no
% demographics file has been supplied to this pipeline. If you have one,
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

    formula = sprintf(['%s ~ haptic_num*level_cat + haptic_num*repetition ' ...
        '+ (1 + repetition | subject_cat)'], outcome);

    lme = fitlme(Ttr, formula, 'FitMethod', 'REML');

    fprintf('\n=== %s (training phase, n=%d obs, %d subjects) ===\n', ...
        outcome, lme.NumObservations, numel(unique(Ttr.subject_cat)));
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
    results.interaction_se     = fe.SE(interaction_row);
    results.interaction_p      = fe.pValue(interaction_row);
    results.interaction_CI     = [fe.Lower(interaction_row), fe.Upper(interaction_row)];

    if isempty(results.interaction_p)
        warning('fit_training_lmm: could not locate haptic_num:repetition term for %s -- check formula/output', outcome);
        results.interaction_p = NaN;
    end
end