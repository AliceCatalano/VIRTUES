%% duration_residual_check.m
% Residual diagnostics + a log-scale sensitivity check for Table 1's
% duration_s (completion time) model (perf_training_lmm.m, gaussian
% family, REML). Two things worth checking that the primary model doesn't
% verify on its own:
%
%   1. Completion-time data are typically right-skewed (a long tail of
%      slow trials, a hard floor near zero) -- exactly why the separate
%      Session x Timing model (perf_sessiontiming_lmm.m, Table 9) already
%      log-transforms duration_s before fitting. Table 1's primary model
%      does NOT log-transform; if that skew shows up as non-normal or
%      heteroscedastic residuals, the model's p-values could be
%      unreliable even though REML point estimates are still consistent.
%   2. Whether the Haptic x Repetition interaction's significance/sign
%      is sensitive to fitting on log(duration_s) instead of raw
%      duration_s -- if the two scales disagree, that itself is worth
%      reporting rather than picking whichever one looks better.
%
% Requires cfg.output_root/perf_features.mat.

clear; clc;
cfg = config();

perf_file = fullfile(cfg.output_root, 'perf_features.mat');
if ~isfile(perf_file)
    error('duration_residual_check: run perf_extract_features(cfg) first.');
end
loaded = load(perf_file, 'T');
T = loaded.T;

fprintf('=== Original (raw-scale) Table 1 model ===\n');
r_raw = perf_training_lmm(T, 'duration_s', 'gaussian');
lme_raw = r_raw.mdl;

resid_raw = residuals(lme_raw, 'ResidualType', 'Pearson');
fprintf('\nRaw-scale residuals: skewness=%.3f, kurtosis=%.3f (0/3 = normal)\n', ...
    skewness(resid_raw), kurtosis(resid_raw));

fprintf('\n=== Refit on log(duration_s), same formula/RE structure ===\n');
Ttr = T(strcmp(T.phase_type, 'training') & isfinite(T.duration_s) & T.duration_s > 0, :);
Ttr.log_duration = log(Ttr.duration_s);
Ttr.subject_cat  = categorical(Ttr.subject);
Ttr.level_cat    = categorical(Ttr.level);
Ttr.haptic_num   = double(Ttr.haptic);
Ttr.repetition   = double(Ttr.repetition);

lastwarn('');
lme_log = fitlme(Ttr, 'log_duration ~ haptic_num*level_cat + haptic_num*repetition + (1 + repetition | subject_cat)', 'FitMethod', 'REML');
[warn_msg, ~] = lastwarn();
if ~isempty(warn_msg)
    fprintf('  [fitlme warning on log scale]: %s\n', warn_msg);
end

fe_log = lme_log.Coefficients;
target_terms = sort({'haptic_num', 'repetition'});
interaction_row = cellfun(@(name) isequal(sort(strsplit(name, ':')), target_terms), fe_log.Name);
fprintf('Haptic x Repetition, log(duration_s):  beta=%.4f, SE=%.4f, p=%.4f\n', ...
    fe_log.Estimate(interaction_row), fe_log.SE(interaction_row), fe_log.pValue(interaction_row));
fprintf('Haptic x Repetition, raw duration_s:    beta=%.4f, SE=%.4f, p=%.4f\n', ...
    r_raw.interaction_beta, r_raw.interaction_se, r_raw.interaction_p);

resid_log = residuals(lme_log, 'ResidualType', 'Pearson');
fprintf('\nLog-scale residuals: skewness=%.3f, kurtosis=%.3f (0/3 = normal)\n', ...
    skewness(resid_log), kurtosis(resid_log));

if (r_raw.interaction_p < 0.05) ~= (fe_log.pValue(interaction_row) < 0.05)
    fprintf('\n*** Significance FLIPS between raw and log scale -- report both, do not pick one silently. ***\n');
else
    fprintf('\nSignificance status (n.s. either way, or sig either way) agrees between raw and log scale.\n');
end

%% Diagnostic plots
fig_dir = fullfile(cfg.output_root, 'figures');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

fig = figure('Name', 'duration_s residual diagnostics', 'Position', [50 50 1100 800]);
sgtitle('duration\_s (Table 1) residual diagnostics: raw scale (top) vs. log scale (bottom)', 'FontWeight', 'bold');

fitted_raw = fitted(lme_raw);
subplot(2,2,1);
scatter(fitted_raw, resid_raw, 10, 'filled', 'MarkerFaceAlpha', 0.3);
yline(0, ':k'); xlabel('fitted'); ylabel('Pearson residual'); title('Raw scale: residuals vs. fitted'); grid on;

subplot(2,2,2);
qqplot(resid_raw); title('Raw scale: Q-Q plot'); grid on;

fitted_log = fitted(lme_log);
subplot(2,2,3);
scatter(fitted_log, resid_log, 10, 'filled', 'MarkerFaceAlpha', 0.3);
yline(0, ':k'); xlabel('fitted (log scale)'); ylabel('Pearson residual'); title('Log scale: residuals vs. fitted'); grid on;

subplot(2,2,4);
qqplot(resid_log); title('Log scale: Q-Q plot'); grid on;

fname = fullfile(fig_dir, 'duration_residual_diagnostics.png');
saveas(fig, fname);
fprintf('\nSaved %s\n', fname);
