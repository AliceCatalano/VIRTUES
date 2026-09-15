%% pupil_slope_robustness_check.m
% Investigates whether the pupil_slope x Haptic moderation of the
% within-subject pupil_slope -> duration_s coupling (Results 3.6/3.7,
% p(xHaptic), within ~ 3.5e-19 -- see correlation_results.mat / Table 5)
% is a genuine physiological finding or a structural/mathematical artifact
% of how pupil_slope is computed.
%
% THE CONCERN: pupil_slope (eye_extract_features.m) is fit as
%   polyfit(proc.time, proc.pupil, 1)
% where proc.time spans exactly [t_start, t_end] of the trial -- i.e. the
% regressor's range IS duration_s, the exact outcome pupil_slope then gets
% correlated against. If a trial's total pupil excursion doesn't itself
% scale up with a longer trial, slope ~ constant/duration_s is close to an
% algebraic identity, not a physiological finding. A p-value as extreme as
% 1e-19 from N=47 subjects is exactly the kind of number that should raise
% this suspicion rather than excite it.
%
% This script runs the checks needed to tell the two apart:
%   1. Direct test: raw pupil_slope vs 1/duration_s correlation (the
%      smoking-gun check for the algebraic-artifact hypothesis).
%   2. Refits the SAME within/between correlation model
%      (multilevel_correlation_lmm.m) with pupil_slope_norm --
%      eye_extract_features.m's duration-invariant version of the same
%      linear trend, fit against time rescaled to [0,1] within the trial
%      instead of raw elapsed seconds -- in place of pupil_slope, for both
%      duration_s and n_collisions, and reports whether the Haptic-
%      moderation interaction survives.
%   3. Sensitivity check: repeats the raw-pupil_slope model after
%      excluding the shortest/longest 10% of training trials by duration.
%   4. Group-specific within-subject slope point estimates with 95% CIs
%      (via the model's full coefficient covariance matrix, same
%      contrast approach as gsr_training_lmm.m's local_add_contrast) --
%      a direct look at the "formal test of the difference between the
%      two groups' slopes" the interaction term already provides.
%   5. Saves a descriptive scatter of pupil_slope and pupil_slope_norm
%      against duration_s, colored by group, for visual inspection
%      (pooled/raw, NOT the within-centered model -- for eyeballing only).
%
% Requires cfg.output_root/merged_features.mat WITH pupil_slope_norm
% (i.e. eye_extract_features(cfg) and merge_modality_tables(cfg) must be
% rerun after pulling the pupil_slope_norm addition -- delete
% eye_features.mat/merged_features.mat first if they predate it).

clear; clc;
cfg = config();

merged_file = fullfile(cfg.output_root, 'merged_features.mat');
if ~isfile(merged_file)
    error('pupil_slope_robustness_check: run merge_modality_tables(cfg) first.');
end
loaded = load(merged_file, 'T');
T = loaded.T;

if ~ismember('pupil_slope_norm', T.Properties.VariableNames)
    error(['pupil_slope_robustness_check: merged_features.mat has no pupil_slope_norm column. ' ...
        'Delete eye_features.mat and merged_features.mat and rerun eye_extract_features(cfg) then ' ...
        'merge_modality_tables(cfg) to regenerate them with the new column.']);
end

Ttr = T(strcmp(T.phase_type, 'training') & isfinite(T.pupil_slope) & isfinite(T.duration_s), :);

%% ======================================================================
%  STEP 1 -- the algebraic-artifact smoking gun
% =========================================================================
fprintf('=== Step 1: raw pupil_slope vs 1/duration_s ===\n');
fprintf('(pupil_slope''s regressor range IS duration_s -- a large |r| here means\n');
fprintf(' pupil_slope is substantially a duration proxy, not independent physiology.)\n\n');
inv_dur = 1 ./ Ttr.duration_s;
local_report_corr('Overall',    Ttr.pupil_slope, inv_dur);
local_report_corr('No-haptic',  Ttr.pupil_slope(~Ttr.haptic), inv_dur(~Ttr.haptic));
local_report_corr('Haptic',     Ttr.pupil_slope(Ttr.haptic),  inv_dur(Ttr.haptic));

%% ======================================================================
%  STEP 2 -- does the moderation survive with duration-invariant units?
% =========================================================================
fprintf('\n=== Step 2: pupil_slope vs pupil_slope_norm, same model, both outcomes ===\n');
r_raw_dur   = multilevel_correlation_lmm(T, 'pupil_slope',      'duration_s',   'training');
r_norm_dur  = multilevel_correlation_lmm(T, 'pupil_slope_norm', 'duration_s',   'training');
r_raw_coll  = multilevel_correlation_lmm(T, 'pupil_slope',      'n_collisions', 'training');
r_norm_coll = multilevel_correlation_lmm(T, 'pupil_slope_norm', 'n_collisions', 'training');
local_print_pair('pupil_slope      -> duration_s',   r_raw_dur);
local_print_pair('pupil_slope_norm -> duration_s',   r_norm_dur);
local_print_pair('pupil_slope      -> n_collisions', r_raw_coll);
local_print_pair('pupil_slope_norm -> n_collisions', r_norm_coll);
fprintf(['\nIf pupil_slope_norm''s within_haptic_p is orders of magnitude larger than ' ...
    'pupil_slope''s (or non-significant), the original finding is substantially explained by ' ...
    'pupil_slope''s duration-dependent units, not a duration-invariant physiological effect.\n']);

%% ======================================================================
%  STEP 3 -- sensitivity: exclude extreme-duration trials
% =========================================================================
fprintf('\n=== Step 3: sensitivity, excluding shortest/longest 10%% of training trials by duration ===\n');
lo = prctile(Ttr.duration_s, 10);
hi = prctile(Ttr.duration_s, 90);
train_mask   = strcmp(T.phase_type, 'training') & isfinite(T.duration_s);
extreme_mask = train_mask & (T.duration_s < lo | T.duration_s > hi);
T_trim = T(~extreme_mask, :);
r_trim = multilevel_correlation_lmm(T_trim, 'pupil_slope', 'duration_s', 'training');
fprintf('Dropped %d/%d training trials outside [%.1f, %.1f]s (10th-90th percentile duration)\n', ...
    sum(extreme_mask), sum(train_mask), lo, hi);
local_print_pair('pupil_slope -> duration_s, trimmed', r_trim);

%% ======================================================================
%  STEP 4 -- group-specific within-subject slopes, with CIs and a direct
%  test of the difference (the interaction term, surfaced explicitly)
% =========================================================================
fprintf('\n=== Step 4: group-specific within-subject slopes (pupil_slope -> duration_s) ===\n');
[est_N, se_N, ci_N] = local_group_slope(r_raw_dur.lme, 'pred_within', 'haptic_num', false);
[est_H, se_H, ci_H] = local_group_slope(r_raw_dur.lme, 'pred_within', 'haptic_num', true);
fprintf('No-haptic: slope = %.4f (SE %.4f), 95%% CI [%.4f, %.4f]\n', est_N, se_N, ci_N(1), ci_N(2));
fprintf('Haptic:    slope = %.4f (SE %.4f), 95%% CI [%.4f, %.4f]\n', est_H, se_H, ci_H(1), ci_H(2));
fprintf('Formal test of the difference (pred_within x haptic_num interaction): beta=%.4f, p=%.3g\n', ...
    r_raw_dur.within_haptic_beta, r_raw_dur.within_haptic_p);

%% ======================================================================
%  STEP 5 -- descriptive scatter (pooled/raw, for visual inspection only)
% =========================================================================
COLOR_N = [55  138 221] / 255;
COLOR_H = [212  83 126] / 255;
fig_dir = fullfile(cfg.output_root, 'figures');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

fig = figure('Name', 'pupil_slope robustness', 'Position', [50 50 1200 500]);
sgtitle('pupil\_slope robustness check: raw vs. duration-normalized (pooled scatter, for visual inspection only)', 'FontWeight', 'bold');

subplot(1,2,1); hold on;
scatter(Ttr.duration_s(~Ttr.haptic), Ttr.pupil_slope(~Ttr.haptic), 12, COLOR_N, 'filled', 'MarkerFaceAlpha', 0.4);
scatter(Ttr.duration_s(Ttr.haptic),  Ttr.pupil_slope(Ttr.haptic),  12, COLOR_H, 'filled', 'MarkerFaceAlpha', 0.4);
xlabel('duration_s (s)', 'Interpreter', 'none'); ylabel('pupil\_slope (mm/s)');
title('Raw pupil\_slope (units: mm/s, range=duration\_s)'); grid on;
legend({'No-haptic','Haptic'}, 'Location', 'best', 'FontSize', 8);

subplot(1,2,2); hold on;
Ttr_norm = T(strcmp(T.phase_type, 'training') & isfinite(T.pupil_slope_norm) & isfinite(T.duration_s), :);
scatter(Ttr_norm.duration_s(~Ttr_norm.haptic), Ttr_norm.pupil_slope_norm(~Ttr_norm.haptic), 12, COLOR_N, 'filled', 'MarkerFaceAlpha', 0.4);
scatter(Ttr_norm.duration_s(Ttr_norm.haptic),  Ttr_norm.pupil_slope_norm(Ttr_norm.haptic),  12, COLOR_H, 'filled', 'MarkerFaceAlpha', 0.4);
xlabel('duration_s (s)', 'Interpreter', 'none'); ylabel('pupil\_slope\_norm (mm per fraction of trial)');
title('Duration-normalized pupil\_slope\_norm'); grid on;

fname = fullfile(fig_dir, 'pupil_slope_robustness.png');
saveas(fig, fname);
fprintf('\nSaved %s\n', fname);


function local_report_corr(label, x, y)
    [r, p] = corr(x, y, 'rows', 'complete');
    fprintf('%-12s r = %8.4f, p = %.3g, n = %d\n', label, r, p, sum(isfinite(x) & isfinite(y)));
end

function local_print_pair(label, r)
    fprintf('%-28s within=%9.4f (p=%.3g)  within_x_haptic=%9.4f (p=%.3g)  n=%d\n', ...
        label, r.within_beta, r.within_p, r.within_haptic_beta, r.within_haptic_p, r.n_obs);
end

function [est, se, ci] = local_group_slope(lme, term, interaction_partner, group_is_haptic)
    fe   = lme.Coefficients;
    covb = lme.CoefficientCovariance;
    dfe  = lme.DFE;
    nterms = numel(fe.Name);

    int_idx = find(cellfun(@(n) isequal(sort(strsplit(n, ':')), sort({term, interaction_partner})), fe.Name), 1);

    c = zeros(nterms, 1);
    c(strcmp(fe.Name, term)) = 1;
    if group_is_haptic
        c(int_idx) = 1;
    end

    beta = fe.Estimate;
    est  = c' * beta;
    se   = sqrt(c' * covb * c);
    crit = tinv(0.975, dfe);
    ci   = [est - crit*se, est + crit*se];
end
