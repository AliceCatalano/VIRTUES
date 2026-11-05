%% eye_measures_duration_check.m
% Robustness checks for gaze_dispersion and saccade_rate (Table 1),
% continuing the same line of investigation the pupil_slope robustness
% check started: does either measure's relationship with trial duration
% reflect a structural/statistical artifact rather than physiology?
%
%   SACCADE RATE: precomputed as saccade_count / (valid_duration_s/60) and
%   then modeled as an ordinary Gaussian LMM outcome (Table 1). Unlike
%   pupil_slope, this isn't a systematic BIAS toward a particular value of
%   duration (dividing a count by its own exposure time is the textbook-
%   correct way to form a rate) -- but treating the resulting ratio as an
%   ordinary Gaussian outcome ignores that a rate estimated from a SHORT
%   trial is noisier (higher sampling variance) than one from a LONG
%   trial, exactly the situation a Poisson-with-offset GLMM is built to
%   handle correctly and a plain Gaussian model is not. This refits
%   saccade_count directly as Poisson(log(valid_duration_s) as offset) and
%   compares the Haptic x Repetition conclusion against the current
%   Gaussian-on-the-rate model.
%
%   GAZE DISPERSION: sqrt(var(x)+var(y)) over the trial's valid (non-
%   blink) gaze samples. No guaranteed algebraic tie to duration the way
%   pupil_slope had, but two things are checked directly rather than
%   assumed: (1) whether gaze_dispersion correlates with duration_s at
%   all (a real physiological process that isn't stationary across a
%   longer trial -- e.g. gaze wandering to more areas as a longer task
%   unfolds -- would show this, which is fine, but it needs to be known
%   before interpreting a group difference in gaze_dispersion as
%   independent of a group difference in duration_s); (2) whether it
%   correlates with blink_frac (differential data loss changing which
%   part of the trial the variance is actually computed over).
%
% Requires cfg.output_root/merged_features.mat WITH valid_duration_s (i.e.
% eye_extract_features(cfg) and merge_modality_tables(cfg) must be rerun
% after pulling the valid_duration_s addition).

clear; clc;
cfg = config();

eye_file = fullfile(cfg.output_root, 'eye_features_v2.mat');
if ~isfile(eye_file)
    error('eye_measures_duration_check: run eye_extract_features(cfg) first.');
end
loaded = load(eye_file, 'T');
Teye = loaded.T;

if ~ismember('valid_duration_s', Teye.Properties.VariableNames)
    error(['eye_measures_duration_check: eye_features_v2.mat has no valid_duration_s column -- ' ...
        'delete eye_features_v2.mat and rerun eye_extract_features(cfg) to regenerate it with the new column.']);
end

merged_file = fullfile(cfg.output_root, 'merged_features.mat');
if ~isfile(merged_file)
    error('eye_measures_duration_check: run merge_modality_tables(cfg) first (for duration_s alongside eye measures).');
end
loaded = load(merged_file, 'T');
T = loaded.T;

%% ======================================================================
%  PART 1 -- saccade_rate as a rate-with-exposure vs. a plain Gaussian outcome
% =========================================================================
fprintf('=== Part 1: saccade_rate -- Poisson-with-offset vs. Gaussian-on-the-rate ===\n');

Ttr = Teye(strcmp(Teye.phase_type, 'training') & isfinite(Teye.saccade_count) & Teye.valid_duration_s > 0, :);
Ttr.subject_cat = categorical(Ttr.subject);
Ttr.level_cat   = categorical(Ttr.level);
Ttr.haptic_num  = double(Ttr.haptic);
Ttr.repetition  = double(Ttr.repetition);
Ttr.log_exposure_min = log(Ttr.valid_duration_s / 60);

target_terms = sort({'haptic_num', 'repetition'});

fprintf('\n-- Current approach: Gaussian LMM on the precomputed rate --\n');
lastwarn('');
lme_gauss = fitlme(Ttr, 'saccade_rate ~ haptic_num*level_cat + haptic_num*repetition + (1 + repetition | subject_cat)', 'FitMethod', 'REML');
fe_g = lme_gauss.Coefficients;
row_g = cellfun(@(n) isequal(sort(strsplit(n, ':')), target_terms), fe_g.Name);
fprintf('Haptic x Repetition (Gaussian on rate): beta=%.4f, SE=%.4f, p=%.4f\n', ...
    fe_g.Estimate(row_g), fe_g.SE(row_g), fe_g.pValue(row_g));

fprintf('\n-- Alternative: Poisson GLMM on saccade_count, log(valid_duration_s) as offset --\n');
mdl_poiss = fitglme(Ttr, 'saccade_count ~ haptic_num*level_cat + haptic_num*repetition + (1 + repetition | subject_cat) + Offset(log_exposure_min)', ...
'Distribution', 'poisson', 'FitMethod', 'Laplace');
fe_p = mdl_poiss.Coefficients;
row_p = cellfun(@(n) isequal(sort(strsplit(n, ':')), target_terms), fe_p.Name);
fprintf('Haptic x Repetition (Poisson, log-rate scale): beta=%.4f, SE=%.4f, p=%.4f\n', ...
    fe_p.Estimate(row_p), fe_p.SE(row_p), fe_p.pValue(row_p));

pearson_resid = residuals(mdl_poiss, 'ResidualType', 'Pearson');
dispersion = sum(pearson_resid.^2) / mdl_poiss.DFE;
fprintf('Poisson-offset model dispersion ratio: %.3f\n', dispersion);

if (fe_g.pValue(row_g) < 0.05) ~= (fe_p.pValue(row_p) < 0.05)
    fprintf('\n*** Significance FLIPS between the two model specifications -- report both. ***\n');
else
    fprintf('\nBoth specifications agree on significance status for Haptic x Repetition.\n');
end

%% ======================================================================
%  PART 2 -- gaze_dispersion vs. duration_s / blink_frac
% =========================================================================
fprintf('\n=== Part 2: gaze_dispersion vs. duration_s and blink_frac ===\n');
Ttr2 = T(strcmp(T.phase_type, 'training') & isfinite(T.gaze_dispersion) & isfinite(T.duration_s), :);
[r_dur, p_dur] = corr(Ttr2.gaze_dispersion, Ttr2.duration_s, 'rows', 'complete');
fprintf('gaze_dispersion vs. duration_s:  r = %.4f, p = %.3g, n = %d\n', r_dur, p_dur, height(Ttr2));

Ttr3 = Teye(strcmp(Teye.phase_type, 'training') & isfinite(Teye.gaze_dispersion) & isfinite(Teye.blink_frac), :);
[r_blink, p_blink] = corr(Ttr3.gaze_dispersion, Ttr3.blink_frac, 'rows', 'complete');
fprintf('gaze_dispersion vs. blink_frac:   r = %.4f, p = %.3g, n = %d\n', r_blink, p_blink, height(Ttr3));

fprintf(['\nA nontrivial |r| against duration_s here is NOT automatically an artifact the way pupil_slope''s\n' ...
    'was (there is no algebraic tie between a spatial variance and elapsed time) -- but it does mean any\n' ...
    'group difference in gaze_dispersion should be checked against whether the groups also differ in\n' ...
    'duration_s, rather than assumed independent. A nontrivial |r| against blink_frac would mean\n' ...
    'differential data loss (not just less data, but systematically different PARTS of the trial\n' ...
    'excluded) is shaping the variance estimate, which is worth knowing before trusting it as arousal/\n' ...
    'scanning behavior.\n']);
