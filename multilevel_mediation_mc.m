function results = multilevel_mediation_mc(T, mediator, outcome, phase_type_filter, n_sim)
% MULTILEVEL_MEDIATION_MC  Test whether a physiological/oculomotor
% mediator carries part of haptic feedback's effect on a performance
% outcome, via the product-of-coefficients method with Monte Carlo
% confidence intervals -- exactly the method the analysis plan specifies
% for this (SAP Section 5.2: "Indirect effects will be estimated using
% Monte Carlo confidence intervals ... "), using the standard approach
% (MacKinnon, Lockwood, & Williams, 2004; Selig & Preacher, 2008) rather
% than a from-scratch reimplementation.
%
% Model (simple multilevel mediation, subject-level a and b paths):
%   Path a:  Mediator ~ Haptic + (1 | Subject)
%   Path b:  Outcome  ~ Mediator_between + Haptic + (1 | Subject)
%     where Mediator_between is each subject's own mean of Mediator
%     across their training rows (person-mean centering, same as
%     multilevel_correlation_lmm.m) -- both paths operate on the
%     mediator's SUBJECT-LEVEL average, so a and b are estimating the
%     same construct.
%   Indirect effect = a * b, with a Monte Carlo CI built by drawing
%   a_sim ~ N(a_hat, SE_a) and b_sim ~ N(b_hat, SE_b) independently
%   n_sim times and taking the 2.5/97.5 percentiles of a_sim.*b_sim.
%   Independence of the sampling distributions of a and b is the
%   standard simplifying assumption of this method.
%
% NOTE -- this is deliberately the SIMPLE mediation model, not a
% moderated-mediation model: the standout finding in this project so far
% (pupil_slope's WITHIN-subject coupling to performance being
% significantly moderated by haptic group, from
% multilevel_correlation_lmm.m) is a different, more elaborate
% phenomenon than "haptic changes the mediator's average level, which in
% turn predicts performance" -- testing that specific moderated-indirect-
% effect properly needs a first-stage-moderated multilevel mediation
% design (see e.g. Preacher, Zyphur, & Zhang, 2010) that hasn't been
% built here. Use this function for candidate mediators where a level
% effect (not a coupling-strength effect) is the theoretically motivated
% question -- e.g. haptic -> mean SCL -> duration, per the SAP's own H5
% framing -- and treat the pupil_slope moderation finding as a separate,
% already-reported result (Section 3.7) rather than folding it into this
% same framework without further work.

    if nargin < 4 || isempty(phase_type_filter), phase_type_filter = 'training'; end
    if nargin < 5 || isempty(n_sim), n_sim = 20000; end

    Tp = T(strcmp(T.phase_type, phase_type_filter), :);
    Tp = Tp(isfinite(Tp.(mediator)) & isfinite(Tp.(outcome)), :);
    Tp.subject_cat = categorical(Tp.subject);
    Tp.haptic_num  = double(Tp.haptic);

    % --- Path a: Mediator ~ Haptic + (1 | Subject) ---
    formula_a = sprintf('%s ~ haptic_num + (1 | subject_cat)', mediator);
    lme_a = fitlme(Tp, formula_a, 'FitMethod', 'REML');
    fe_a  = lme_a.Coefficients;
    a_hat = fe_a.Estimate(strcmp(fe_a.Name, 'haptic_num'));
    a_se  = fe_a.SE(strcmp(fe_a.Name, 'haptic_num'));
    a_p   = fe_a.pValue(strcmp(fe_a.Name, 'haptic_num'));

    % --- Path b: Outcome ~ Mediator_between + Haptic + (1 | Subject) ---
    [subj_list, ~, subj_idx] = unique(Tp.subject_cat);
    med_between_by_subj = accumarray(subj_idx, Tp.(mediator), [], @mean);
    Tp.med_between = med_between_by_subj(subj_idx);

    formula_b = sprintf('%s ~ med_between + haptic_num + (1 | subject_cat)', outcome);
    lme_b = fitlme(Tp, formula_b, 'FitMethod', 'REML');
    fe_b  = lme_b.Coefficients;
    b_hat = fe_b.Estimate(strcmp(fe_b.Name, 'med_between'));
    b_se  = fe_b.SE(strcmp(fe_b.Name, 'med_between'));
    b_p   = fe_b.pValue(strcmp(fe_b.Name, 'med_between'));

    direct_hat = fe_b.Estimate(strcmp(fe_b.Name, 'haptic_num'));
    direct_p   = fe_b.pValue(strcmp(fe_b.Name, 'haptic_num'));

    % --- Indirect effect: Monte Carlo CI ---
    a_sim = normrnd(a_hat, a_se, n_sim, 1);
    b_sim = normrnd(b_hat, b_se, n_sim, 1);
    indirect_sim = a_sim .* b_sim;
    indirect_hat = a_hat * b_hat;
    ci = prctile(indirect_sim, [2.5, 97.5]);

    results.mediator      = mediator;
    results.outcome       = outcome;
    results.n_subjects     = numel(subj_list);
    results.path_a_beta    = a_hat; results.path_a_se = a_se; results.path_a_p = a_p;
    results.path_b_beta    = b_hat; results.path_b_se = b_se; results.path_b_p = b_p;
    results.direct_effect  = direct_hat; results.direct_p = direct_p;
    results.indirect_effect = indirect_hat;
    results.indirect_CI     = ci;
    results.indirect_significant = ~(ci(1) <= 0 && ci(2) >= 0);

    fprintf('\n=== Mediation: Haptic -> %s -> %s ===\n', mediator, outcome);
    fprintf('  Path a (Haptic -> %-25s): beta=%.4g, SE=%.4g, p=%.4f\n', mediator, a_hat, a_se, a_p);
    fprintf('  Path b (%-25s -> %s, |Haptic): beta=%.4g, SE=%.4g, p=%.4f\n', mediator, outcome, b_hat, b_se, b_p);
    fprintf('  Direct effect (Haptic -> %s, |mediator): beta=%.4g, p=%.4f\n', outcome, direct_hat, direct_p);
    fprintf('  Indirect effect (a*b): %.4g, 95%% Monte Carlo CI [%.4g, %.4g] -- %s\n', ...
        indirect_hat, ci(1), ci(2), local_ternary(results.indirect_significant, 'SIGNIFICANT (CI excludes 0)', 'not significant (CI includes 0)'));
end

function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
