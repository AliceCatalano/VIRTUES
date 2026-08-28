function results = multilevel_correlation_lmm(T, predictor, outcome, phase_type_filter)
% MULTILEVEL_CORRELATION_LMM  Test the association between two outcomes
% recorded on the same trials, separating within-subject (moment-to-
% moment, trial-to-trial) from between-subject (trait-level, who tends to
% be high/low overall) association -- the multilevel/person-mean-centering
% approach specified for the correlation analyses in this project's
% analysis plan, and the standard technique for this exact problem in
% longitudinal/repeated-measures data (Curran & Bauer, 2011, "The
% disaggregation of within-person and between-person effects in
% longitudinal models of change," Annual Review of Psychology).
%
% WHY THIS MATTERS: naively correlating predictor and outcome across all
% trials from all subjects conflates two different questions that can
% have different signs. Example: subjects who are on average more
% aroused (high between-subject SCL) might also be on average slower
% (between-subject association) even if, WITHIN a given subject, trials
% where THEY happen to be more aroused than their own average are FASTER
% (within-subject association) -- a naive pooled correlation would show
% some in-between number that answers neither question correctly. Person-
% mean centering separates them explicitly.
%
% Model:
%   Outcome ~ Predictor_within * Haptic + Predictor_between * Haptic + (1 | Subject)
% where Predictor_between = each subject's own mean of Predictor across
% their (phase_type_filter, default 'training') rows, and
% Predictor_within = Predictor - Predictor_between.
%
% haptic_num interactions test whether either association (within or
% between) differs by haptic-feedback condition -- this is what SAP
% Section 5.1 calls "moderation by haptic condition."
%
% A random intercept only is used (no random slope on Predictor_within
% per subject) -- with many outcome pairs run in a single driver
% (run_correlation_analyses.m), a random-slope structure would need the
% same degeneracy-checking machinery as gsr_training_lmm.m for each pair;
% add it (mirroring that function's fit_lmm_with_re_fallback) if a
% specific pair's within-subject slope turns out to vary meaningfully by
% subject and that's of direct interest.

    if nargin < 4 || isempty(phase_type_filter), phase_type_filter = 'training'; end

    Tp = T(strcmp(T.phase_type, phase_type_filter), :);
    Tp = Tp(isfinite(Tp.(predictor)) & isfinite(Tp.(outcome)), :);

    if height(Tp) < 10
        warning('multilevel_correlation_lmm: only %d usable rows for %s vs %s -- model may not be reliable', ...
            height(Tp), predictor, outcome);
    end

    Tp.subject_cat = categorical(Tp.subject);
    Tp.haptic_num  = double(Tp.haptic);

    [subj_list, ~, subj_idx] = unique(Tp.subject_cat);
    pred_between_by_subj = accumarray(subj_idx, Tp.(predictor), [], @mean);
    Tp.pred_between = pred_between_by_subj(subj_idx);
    Tp.pred_within  = Tp.(predictor) - Tp.pred_between;

    formula = sprintf('%s ~ pred_within*haptic_num + pred_between*haptic_num + (1 | subject_cat)', outcome);

    lastwarn('');
    lme = fitlme(Tp, formula, 'FitMethod', 'REML');
    [warn_msg, ~] = lastwarn();
    if ~isempty(warn_msg)
        fprintf('  [%s vs %s] fitlme warning: %s -- inspect this fit before trusting it\n', predictor, outcome, warn_msg);
    end

    fe = lme.Coefficients;
    row = @(name) find(strcmp(fe.Name, name), 1);
    int_row = @(a, b) find(cellfun(@(n) isequal(sort(strsplit(n, ':')), sort({a, b})), fe.Name), 1);

    r_within    = row('pred_within');
    r_between   = row('pred_between');
    r_within_x  = int_row('pred_within',  'haptic_num');
    r_between_x = int_row('pred_between', 'haptic_num');

    results.predictor = predictor;
    results.outcome   = outcome;
    results.n_obs      = lme.NumObservations;
    results.n_subjects  = numel(subj_list);
    results.fit_warning = warn_msg;
    results.lme          = lme;

    results.within_beta  = fe.Estimate(r_within);  results.within_se  = fe.SE(r_within);  results.within_p  = fe.pValue(r_within);
    results.between_beta = fe.Estimate(r_between); results.between_se = fe.SE(r_between); results.between_p = fe.pValue(r_between);
    results.within_haptic_beta  = fe.Estimate(r_within_x);  results.within_haptic_se  = fe.SE(r_within_x);  results.within_haptic_p  = fe.pValue(r_within_x);
    results.between_haptic_beta = fe.Estimate(r_between_x); results.between_haptic_se = fe.SE(r_between_x); results.between_haptic_p = fe.pValue(r_between_x);
end
