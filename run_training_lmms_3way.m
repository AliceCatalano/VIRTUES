%% training_lmms_3way.m
% Driver for the Haptic*Level*Repetition three-way extension
% (gsr_training_lmm_3way.m / perf_training_lmm_3way.m) -- run
% CONSISTENTLY across all three modalities (GSR, eye-tracking,
% performance), exactly like the additive two-way models in gsr_lmm.m /
% run_eye_lmms.m / run_performance_lmms.m, so this is not a one-off check
% on a single outcome.
%
% WHY THIS EXISTS (see gsr_training_lmm_3way.m's header for the full
% rationale): the original training-phase model tests Haptic x Level and
% Haptic x Repetition as two SEPARATE two-way interactions added
% together, which assumes the repetition (learning-rate) effect is the
% same size at every difficulty level without ever testing that
% assumption. This driver adds the explicit test: does the group
% difference in learning rate depend on level? -- e.g. is Level 1's
% 10-repetition trend actually different from Level 5's.
%
% EXPLORATORY relative to SAP Section 4.2's literal (additive) formula --
% run alongside, not instead of, gsr_lmm.m / run_eye_lmms.m /
% run_performance_lmms.m, whose already-reported numbers this does not
% change or supersede.
%
% One FDR family across ALL outcomes from ALL THREE modalities together
% (not per-modality), since this is one new question ("does the
% group-learning-rate-by-level dependence exist") asked identically of
% every outcome in the study, not three separate families of questions.

clear; clc;
cfg = config();

eda_file  = fullfile(cfg.output_root, 'eda_features.mat');
eye_file  = fullfile(cfg.output_root, 'eye_features.mat');
perf_file = fullfile(cfg.output_root, 'perf_features.mat');
if ~isfile(eda_file) || ~isfile(eye_file) || ~isfile(perf_file)
    error('run_training_lmms_3way: run gsr_extract_features(cfg), eye_extract_features(cfg), and perf_extract_features(cfg) first.');
end
Teda  = load(eda_file,  'T'); Teda  = Teda.T;
Teye  = load(eye_file,  'T'); Teye  = Teye.T;
Tperf = load(perf_file, 'T'); Tperf = Tperf.T;

% {outcome, table, family, modality label}
jobs = {
    'scl_mean',                Teda,  'gaussian', 'GSR'
    'scr_freq',                 Teda,  'gaussian', 'GSR'
    'scr_mean_amp',              Teda,  'gaussian', 'GSR'
    'collision_scr_amp_mean',     Teda,  'gaussian', 'GSR'
    'pupil_slope',               Teye,  'gaussian', 'Eye'
    'gaze_dispersion',            Teye,  'gaussian', 'Eye'
    'saccade_rate',               Teye,  'gaussian', 'Eye'
    'collision_pupil_response_mean', Teye, 'gaussian', 'Eye'
    'duration_s',                 Tperf, 'gaussian', 'Performance'
    'n_collisions',                Tperf, 'poisson',  'Performance'
    };

n = size(jobs, 1);
results  = cell(n, 1);
outcomes = jobs(:,1);
modality = jobs(:,4);

for i = 1:n
    outcome = jobs{i,1};
    Tsrc    = jobs{i,2};
    family  = jobs{i,3};
    if strcmp(modality{i}, 'Performance')
        results{i} = perf_training_lmm_3way(Tsrc, outcome, family);
    else
        results{i} = gsr_training_lmm_3way(Tsrc, outcome);
    end
end

omnibus_p = cellfun(@(r) r.three_way_omnibus_p, results);
omnibus_F = cellfun(@(r) r.three_way_omnibus_F, results);
p_fdr     = local_bh_fdr(omnibus_p);

fprintf('\n\n=== Summary: Haptic x Level x Repetition omnibus test (does the group learning-rate difference depend on difficulty?) ===\n');
fprintf('%-14s %-32s %-38s %10s %10s %10s\n', 'Modality', 'Outcome', 'RE structure used', 'F', 'p', 'p_FDR');
for i = 1:n
    r = results{i};
    fprintf('%-14s %-32s %-38s %10.3f %10.4f %10.4f\n', ...
        modality{i}, outcomes{i}, r.re_structure, omnibus_F(i), omnibus_p(i), p_fdr(i));
end

fprintf(['\nInterpretation: a significant (p_FDR < .05) omnibus test for an outcome means the additive\n' ...
    'model already reported for that outcome (Table 1, gsr_lmm.m/run_eye_lmms.m/run_performance_lmms.m)\n' ...
    'is masking level-dependent structure in the group learning-rate difference -- inspect that outcome''s\n' ...
    'results.repetition_slopes table (5 levels x 2 groups) below to see which level(s) drive it.\n']);

fprintf('\n=== Per-outcome repetition slopes by level and group (the direct "Level 1 trend vs Level 5 trend" answer) ===\n');
fprintf('%-14s %-32s %-6s %-4s %10s %10s %10s %10s\n', 'Modality', 'Outcome', 'Level', 'Grp', 'beta', 'SE', 'p', '');
for i = 1:n
    rs = results{i}.repetition_slopes;
    for j = 1:height(rs)
        fprintf('%-14s %-32s %-6s %-4s %10.4f %10.4f %10.4f  [%7.4f, %7.4f]\n', ...
            modality{i}, outcomes{i}, rs.level{j}, rs.group{j}, rs.beta(j), rs.se(j), rs.p(j), rs.lower(j), rs.upper(j));
    end
end

save(fullfile(cfg.output_root, 'training_lmm_3way_results.mat'), 'results', 'outcomes', 'modality', 'omnibus_F', 'omnibus_p', 'p_fdr');
fprintf('\nSaved results to %s\n', fullfile(cfg.output_root, 'training_lmm_3way_results.mat'));


function p_adj = local_bh_fdr(p)
    p = p(:);
    n = numel(p);
    [p_sorted, idx] = sort(p);
    ranks = (1:n)';
    p_adj_sorted = p_sorted .* n ./ ranks;
    p_adj_sorted = flipud(cummin(flipud(p_adj_sorted)));
    p_adj_sorted = min(p_adj_sorted, 1);
    p_adj = zeros(n, 1);
    p_adj(idx) = p_adj_sorted;
end
