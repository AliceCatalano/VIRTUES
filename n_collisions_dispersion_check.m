%% n_collisions_dispersion_check.m
% Checks the Poisson-GLMM assumption behind Table 1's n_collisions model
% (perf_training_lmm.m, SAP 4.2): Poisson fixes the conditional variance
% equal to the conditional mean. If collision counts are over-dispersed
% relative to that (common for count data -- extra between-trial
% variability Poisson can't represent), the model's SEs are anti-
% conservative and p-values too easily significant even though the point
% estimates themselves stay roughly consistent. perf_training_lmm.m's own
% header already flags this as untested ("Overdispersion is not tested
% here"); this script closes that gap rather than leaving it as a caveat.
%
%   1. Refits the EXACT, unchanged Table 1 model via perf_training_lmm.m
%      and computes the Pearson chi-square dispersion statistic
%      (sum(Pearson residuals^2) / DFE) -- ~1 for a well-specified
%      Poisson fit, notably >1 = overdispersion, <1 = underdispersion.
%      (MATLAB's mdl.Dispersion property is NOT useful here -- it is
%      fixed at 1 by definition for Poisson/binomial families regardless
%      of the actual fit, which is exactly why this needs computing
%      separately from the Pearson residuals.)
%   2. Zero-inflation check: observed proportion of zero-collision trials
%      vs. the Poisson-expected proportion (mean of exp(-fitted mu) across
%      trials, using conditional/BLUP-inclusive fitted values).
%   3. If overdispersion is substantial (Pearson ratio > 1.5, a common
%      rule-of-thumb threshold), refits with an added observation-level
%      random intercept (1 | obs_id) -- the standard "OLRE" (Harrison,
%      2014, PeerJ) trick for absorbing extra-Poisson variance in a GLMM
%      when a true negative-binomial mixed model isn't available.
%      MATLAB's fitglme has no negative-binomial family (only normal,
%      binomial, poisson, gamma, inversegaussian), so this is the
%      standard workaround, not an ad hoc substitute. Reports whether the
%      Haptic x Repetition interaction survives once dispersion is
%      absorbed.
%
% Requires cfg.output_root/perf_features.mat (run perf_extract_features(cfg)
% first).

clear; clc;
cfg = config();

perf_file = fullfile(cfg.output_root, 'perf_features.mat');
if ~isfile(perf_file)
    error('n_collisions_dispersion_check: run perf_extract_features(cfg) first.');
end
loaded = load(perf_file, 'T');
T = loaded.T;

r = perf_training_lmm(T, 'n_collisions', 'poisson');
mdl = r.mdl;

fprintf('\n=== Overdispersion check (Pearson chi-square / DFE) ===\n');
pearson_resid = residuals(mdl, 'ResidualType', 'Pearson');
dispersion = sum(pearson_resid.^2) / mdl.DFE;
fprintf('Pearson chi-square / DFE = %.3f  (n=%d, DFE=%d)\n', dispersion, mdl.NumObservations, mdl.DFE);
if dispersion > 1.5
    fprintf('-> Substantial overdispersion: Poisson SEs are likely anti-conservative (too easily significant).\n');
elseif dispersion < 0.67
    fprintf('-> Substantial UNDERdispersion (less common -- check for excess zeros or a mis-specified model).\n');
else
    fprintf('-> Within the range usually considered acceptable for Poisson (~1).\n');
end

fprintf('\n=== Zero-inflation check ===\n');
fitted_mu = fitted(mdl, 'Conditional', true);
p_zero_expected = mean(exp(-fitted_mu));
Ttr = T(strcmp(T.phase_type, 'training') & isfinite(T.n_collisions), :);
p_zero_observed = mean(Ttr.n_collisions == 0);
fprintf('Observed P(collisions=0)  = %.4f (%d/%d trials)\n', p_zero_observed, sum(Ttr.n_collisions==0), height(Ttr));
fprintf('Poisson-expected P(Y=0)   = %.4f (mean of exp(-fitted mu) across trials, conditional on BLUPs)\n', p_zero_expected);
if p_zero_observed - p_zero_expected > 0.05
    fprintf('-> More zeros than Poisson predicts -- possible zero-inflation.\n');
else
    fprintf('-> No strong evidence of excess zeros beyond what Poisson already predicts.\n');
end

if dispersion > 1.5
    fprintf('\n=== Refit with an observation-level random intercept (overdispersion fix) ===\n');
    fprintf('(This can take a while to converge -- one random-effect level per trial.)\n');
    Ttr.obs_id      = categorical((1:height(Ttr))');
    Ttr.level_cat   = categorical(Ttr.level);
    Ttr.haptic_num  = double(Ttr.haptic);
    Ttr.repetition  = double(Ttr.repetition);
    Ttr.subject_cat = categorical(Ttr.subject);
    formula_od = 'n_collisions ~ haptic_num*level_cat + haptic_num*repetition + (1 + repetition | subject_cat) + (1 | obs_id)';
    mdl_od = fitglme(Ttr, formula_od, 'Distribution', 'poisson', 'FitMethod', 'Laplace');

    fe = mdl_od.Coefficients;
    target_terms = sort({'haptic_num', 'repetition'});
    interaction_row = cellfun(@(name) isequal(sort(strsplit(name, ':')), target_terms), fe.Name);
    fprintf('Haptic x Repetition, WITH obs-level RE: beta=%.4f, SE=%.4f, p=%.4f\n', ...
        fe.Estimate(interaction_row), fe.SE(interaction_row), fe.pValue(interaction_row));
    fprintf('Haptic x Repetition, ORIGINAL Table 1 model: beta=%.4f, SE=%.4f, p=%.4f\n', ...
        r.interaction_beta, r.interaction_se, r.interaction_p);

    pearson_resid_od = residuals(mdl_od, 'ResidualType', 'Pearson');
    dispersion_od = sum(pearson_resid_od.^2) / mdl_od.DFE;
    fprintf('Post-fix dispersion ratio: %.3f (compare to original %.3f -- should move closer to 1)\n', dispersion_od, dispersion);
end
