function results = gsr_transfer_lmm(T, outcome, phase_type, phase_pre, phase_post_label)
% GSR_TRANSFER_LMM  Fit the pre/post transfer model from SAP Section 4.3
% (baseline vs post-training elastic task) or 4.4 (Peg Transfer carry-over
% control), on the block-level feature table T (see gsr_extract_features.m).
%
% Per your clarification of the folder <-> phase mapping (the SAP predates
% data collection and doesn't spell this out):
%   phase_type='baseline', phase_pre='Baseline1', phase_post_label='Baseline2'
%     -> elastic task, pre-training vs post-training (SAP 4.3, H2)
%   phase_type='test',     phase_pre='Test1',     phase_post_label='Test2'
%     -> Peg Transfer, pre-training vs post-training (SAP 4.4, carry-over
%        control -- the SAP predicts NO Haptic x Phase interaction here)
%
% Model:
%   Y ~ phase_post*haptic_num + level_cat + (1 | subject_cat)
%
% This is the SAP 4.3 model (Phase, Haptic, Phase x Haptic) with level_cat
% added as a covariate -- each phase has one observation per difficulty
% level per subject (5 levels x 2 phases = up to 10 rows/subject), so
% controlling for level soaks up between-level variance the SAP's literal
% two-phase formula doesn't otherwise account for. A random slope on phase
% was deliberately left out: with only 2 phases x 5 levels per subject
% there usually isn't enough information to identify a random Phase slope
% on top of a random intercept, so this uses a random-intercept-only
% structure -- if fitlme still warns about a singular fit, that's reported
% but not silently worked around (unlike gsr_training_lmm.m, there's no
% simpler alternative to a random intercept alone).
%
% The Phase x Haptic interaction is the target: for the baseline family it
% is "superior transfer in the haptic feedback group" (SAP 4.3) if
% significant; for the test/Peg-Transfer family, the SAP's own prediction
% is that it should NOT be significant (evidence against unintended
% carry-over, SAP 4.4) -- a significant hit there is itself the finding.

    Tph = T(strcmp(T.phase_type, phase_type), :);
    Tph = Tph(isfinite(Tph.(outcome)), :);
    Tph = Tph(ismember(Tph.phase, {phase_pre, phase_post_label}), :);

    if height(Tph) < 10
        warning('gsr_transfer_lmm: only %d usable rows for %s (%s vs %s) -- model may not be reliable', ...
            height(Tph), outcome, phase_pre, phase_post_label);
    end

    Tph.subject_cat = categorical(Tph.subject);
    Tph.level_cat   = categorical(Tph.level);
    Tph.haptic_num  = double(Tph.haptic);
    Tph.phase_post  = double(strcmp(Tph.phase, phase_post_label));   % 0=pre, 1=post

    formula = sprintf('%s ~ phase_post*haptic_num + level_cat + (1 | subject_cat)', outcome);

    lastwarn('');
    lme = fitlme(Tph, formula, 'FitMethod', 'REML');
    [warn_msg, ~] = lastwarn();
    if ~isempty(warn_msg)
        fprintf('  [%s, %s vs %s] fitlme warning: %s -- inspect this fit before trusting it\n', ...
            outcome, phase_pre, phase_post_label, warn_msg);
    end 
    % Explicit boundary check -- don't rely on fitlme raising a warning:
    % it did NOT for either real degenerate case seen so far (see header).
    psi = covarianceParameters(lme);
    intercept_sd = sqrt(psi{1}(1,1));
    is_degenerate = intercept_sd < 1e-6 * lme.MSE^0.5;   % negligible vs. residual SD
    if is_degenerate
        fprintf(['  [%s, %s vs %s] random-intercept SD is degenerate (%.3g, ~0 relative to ' ...
            'residual SD %.3g) -- no detectable between-subject variance once level+phase are ' ...
            'fixed effects; fixed-effect point estimates are usually still usable but treat SEs ' ...
            'with extra caution.\n'], outcome, phase_pre, phase_post_label, intercept_sd, lme.MSE^0.5);
    end

    fprintf('\n=== %s (%s vs %s, n=%d obs, %d subjects) ===\n', ...
        outcome, phase_pre, phase_post_label, lme.NumObservations, numel(unique(Tph.subject_cat)));
    disp(lme);

    fe = lme.Coefficients;
    target_terms = sort({'haptic_num', 'phase_post'});
    interaction_row = cellfun(@(name) isequal(sort(strsplit(name, ':')), target_terms), fe.Name);

    results.outcome         = outcome;
    results.phase_pre       = phase_pre;
    results.phase_post      = phase_post_label;
    results.lme              = lme;
    results.fit_warning      = warn_msg;
    results.re_degenerate     = is_degenerate;
    results.re_intercept_sd   = intercept_sd;
    results.n_obs             = lme.NumObservations;
    results.interaction_beta  = fe.Estimate(interaction_row);
    results.interaction_se    = fe.SE(interaction_row);
    results.interaction_p     = fe.pValue(interaction_row);
    results.interaction_CI    = [fe.Lower(interaction_row), fe.Upper(interaction_row)];

    if isempty(results.interaction_p)
        warning('gsr_transfer_lmm: could not locate phase_post:haptic_num term for %s -- check formula/output', outcome);
        results.interaction_p = NaN;
    end
end