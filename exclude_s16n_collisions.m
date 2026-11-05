%% exclude_s16n_collisions.m
% Whole-subject exclusion of subject_s16N from n_collisions, per
% data_quality_audit.m: s16N's collision counts are extreme, consistent
% outliers across every single acquisition (16-98 collisions/trial, vs.
% every other subject's HIGH-flags topping out at 11-26) -- almost
% certainly a collision-detection artifact, not genuine behavior.
%
% No exclusion mechanism anywhere in the codebase currently touches
% n_collisions (unlike tssv/tssf, which go through accel_exclusion_list.m),
% so this NaNs out subject_s16N's n_collisions in-place in
% perf_features.mat. Overwriting that file (rather than writing a new
% *_clean.mat) means every downstream script that already does
% load('perf_features.mat','T') picks up the exclusion with no changes
% needed on their end.
%
% RUN ORDER: run this once, right after perf_extract_features.m, and
% before re-running any script that fits a GLMM/LMM on n_collisions
% (run_training_lmms_3way.m, run_gsr_lmm.m-adjacent perf scripts,
% run_transfer_lmms.m family, run_completion_tssf_tssv_sessiontiming.m,
% run_layer1_baseline.m / run_layer1_test.m / run_layer1_levels.m,
% run_intensity_variance.m, run_intensity_distribution_check.m,
% n_collisions_dispersion_check.m, run_perf_physiology_correlation.m,
% run_mediation_analysis.m -- anything that reads n_collisions out of
% perf_features.mat). Every one of those results collected so far used
% s16N's unmodified values and should be treated as provisional until
% re-run after this.
%
% If you'd rather keep the raw file untouched, change the save() call at
% the bottom to write 'perf_features_clean.mat' instead -- but then every
% script above needs its load() filename updated to match, which this
% one-line version avoids.

clear; clc; cfg = config();
perf_file = fullfile(cfg.output_root, 'perf_features.mat');
loaded = load(perf_file, 'T');
T = loaded.T;

excl_subj = 'subject_s16N';
mask = strcmp(T.subject, excl_subj);
n_before = sum(mask & isfinite(T.n_collisions));
fprintf('n_collisions whole-subject exclusion: %s (%d rows set to NaN)\n', excl_subj, n_before);

T.n_collisions(mask) = NaN;

fprintf('\n=== Final counts ===\n');
fprintf('n_collisions valid: %d  NaN: %d\n', sum(isfinite(T.n_collisions)), sum(~isfinite(T.n_collisions)));

save(perf_file, 'T');
fprintf('Saved %s (n_collisions exclusion applied in place).\n', perf_file);
