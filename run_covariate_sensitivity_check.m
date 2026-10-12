%% run_covariate_sensitivity_check.m
% SAP Section 6 compliance check: refits the primary training-phase GSR
% models WITH demographic covariates (age, gender, handedness, gaming
% experience, robotic experience) added as additive fixed effects, and
% compares the primary Haptic x Repetition interaction against the
% without-covariates version already reported (gsr_lmm.m). Per the SAP's
% own framing, covariates are "not interpreted unless they substantially
% alter the primary effects" -- this script exists to make that
% comparison explicit and reportable, not to re-report the covariates
% themselves as findings.
%
% Requires a demographics file -- see join_demographics.m's header for
% the expected columns and path (cfg.demographics_file, default
% <data_root>/demographics.csv). This has not been supplied to the
% pipeline before; this script will error clearly naming what's missing
% if it still isn't there.

clear; clc;
cfg = config();

feat_file = fullfile(cfg.output_root, 'eda_features_v2.mat');
if ~isfile(feat_file)
    error('run_covariate_sensitivity_check: %s not found -- run gsr_extract_features(cfg) first.', feat_file);
end
loaded = load(feat_file, 'T');
T = loaded.T;

T = join_demographics(T, cfg);

covariate_cols = {'age','gender','handedness','gaming_experience','robotic_experience'};
outcomes = {'scl_mean', 'scr_freq', 'scr_mean_amp', 'collision_scr_amp_mean'};

fprintf('=== Sensitivity check: Haptic x Repetition interaction, with vs without SAP Section 6 covariates ===\n');
fprintf('%-25s %12s %12s %10s %10s | %12s %12s %10s %10s\n', ...
    'Outcome', 'beta(no cov)', 'p(no cov)', '', '', 'beta(+cov)', 'p(+cov)', '', 'beta shift');
for i = 1:numel(outcomes)
    r_base = gsr_training_lmm(T, outcomes{i});
    r_cov  = gsr_training_lmm(T, outcomes{i}, covariate_cols);

    beta_shift_pct = 100 * abs(r_cov.interaction_beta - r_base.interaction_beta) / abs(r_base.interaction_beta);
    flag = '';
    if beta_shift_pct > 20 || (r_base.interaction_p < 0.05) ~= (r_cov.interaction_p < 0.05)
        flag = '  <-- covariates materially changed this result, interpret with covariates included';
    end

    fprintf('%-25s %12.4f %12.4f %10s %10s | %12.4f %12.4f %10s %10.1f%%%s\n', ...
        outcomes{i}, r_base.interaction_beta, r_base.interaction_p, '', '', ...
        r_cov.interaction_beta, r_cov.interaction_p, '', beta_shift_pct, flag);
end

fprintf(['\nInterpretation per SAP Section 6: if no outcome above is flagged, report the\n' ...
    'no-covariate models (already in the paper) as final and simply note in Methods\n' ...
    'that covariate-adjusted models were checked and did not materially change results.\n' ...
    'If any outcome IS flagged, the covariate-adjusted estimate for that outcome should\n' ...
    'be the one reported, with the covariates named as the reason.\n']);
