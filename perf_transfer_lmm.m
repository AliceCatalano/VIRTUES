function results = perf_transfer_lmm(T, outcome, family, phase_type, phase_pre, phase_post_label)
% PERF_TRANSFER_LMM  SAP Section 4.3/4.4 pre/post transfer model applied to
% a performance outcome -- mirrors gsr_transfer_lmm.m exactly (same model,
% same phase-mapping convention), so this IS the literal H2 test ("greater
% improvement from baseline to post-training on performance outcomes"),
% as opposed to gsr_transfer_lmm.m's physiological analogue of it.
%
%   phase_type='baseline', phase_pre='Baseline1', phase_post_label='Baseline2'
%     -> elastic task, pre- vs post-training (SAP 4.3, H2 itself here)
%   phase_type='test',     phase_pre='Test1',     phase_post_label='Test2'
%     -> Peg Transfer, pre- vs post-training (SAP 4.4, carry-over control)
%
% family = 'gaussian' (duration_s) or 'poisson' (n_collisions, log link).
%
% Model:
%   Outcome ~ phase_post*haptic_num + level_cat + (1 | subject_cat)

    Tph = T(strcmp(T.phase_type, phase_type), :);
    Tph = Tph(isfinite(Tph.(outcome)), :);
    Tph = Tph(ismember(Tph.phase, {phase_pre, phase_post_label}), :);

    if height(Tph) < 10
        warning('perf_transfer_lmm: only %d usable rows for %s (%s vs %s) -- model may not be reliable', ...
            height(Tph), outcome, phase_pre, phase_post_label);
    end

    Tph.subject_cat = categorical(Tph.subject);
    Tph.level_cat   = categorical(Tph.level);
    Tph.haptic_num  = double(Tph.haptic);
    Tph.phase_post  = double(strcmp(Tph.phase, phase_post_label));

    formula = sprintf('%s ~ phase_post*haptic_num + level_cat + (1 | subject_cat)', outcome);

    lastwarn('');
    if strcmp(family, 'gaussian')
        mdl = fitlme(Tph, formula, 'FitMethod', 'REML');
    else
        mdl = fitglme(Tph, formula, 'Distribution', 'poisson', 'Link', 'log', 'FitMethod', 'Laplace');
    end
    [warn_msg, ~] = lastwarn();
    if ~isempty(warn_msg)
        fprintf('  [%s, %s vs %s] fit warning: %s -- inspect this fit before trusting it\n', ...
            outcome, phase_pre, phase_post_label, warn_msg);
    end
    % Explicit boundary check -- don't rely on a fitlme/fitglme warning:
    % it did NOT fire for duration_s's real degenerate case (see header).
    psi = covarianceParameters(mdl);
    intercept_sd = sqrt(psi{1}(1,1));
    if strcmp(family, 'gaussian')
        scale_ref = mdl.MSE^0.5;   % residual SD -- degenerate if intercept SD is negligible relative to it
    else
        scale_ref = 1;   % Poisson log-rate scale has no residual variance to compare against; use an absolute threshold
    end
    is_degenerate = intercept_sd < 1e-6 * scale_ref;
    if is_degenerate
        fprintf(['  [%s, %s vs %s] random-intercept SD is degenerate (%.3g) -- no detectable ' ...
            'between-subject variance once level+phase are fixed effects; fixed-effect point ' ...
            'estimates are usually still usable but treat SEs with extra caution.\n'], ...
            outcome, phase_pre, phase_post_label, intercept_sd);
    end

    fprintf('\n=== %s [%s] (%s vs %s, n=%d obs, %d subjects) ===\n', ...
        outcome, family, phase_pre, phase_post_label, mdl.NumObservations, numel(unique(Tph.subject_cat)));
    disp(mdl);

    fe = mdl.Coefficients;
    target_terms = sort({'haptic_num', 'phase_post'});
    interaction_row = cellfun(@(name) isequal(sort(strsplit(name, ':')), target_terms), fe.Name);

    results.outcome        = outcome;
    results.family         = family;
    results.phase_pre      = phase_pre;
    results.phase_post     = phase_post_label;
    results.mdl              = mdl;
    results.fit_warning      = warn_msg;
    results.re_degenerate     = is_degenerate;
    results.re_intercept_sd   = intercept_sd;
    results.n_obs             = mdl.NumObservations;
    results.interaction_beta  = fe.Estimate(interaction_row);
    results.interaction_se    = fe.SE(interaction_row);
    results.interaction_p     = fe.pValue(interaction_row);
    results.interaction_CI    = [fe.Lower(interaction_row), fe.Upper(interaction_row)];

    if isempty(results.interaction_p)
        warning('perf_transfer_lmm: could not locate phase_post:haptic_num term for %s -- check formula/output', outcome);
        results.interaction_p = NaN;
    end
end
