%% behavioral_change_correlation.m
% "Relative change" between the two performance measures: do subjects who
% improve FASTER (steeper repetition slope) on completion time also
% improve faster on collision count? This is a between-subject,
% learning-RATE-to-learning-RATE question -- different from
% run_correlation_analyses.m's trial-level duration_s-vs-n_collisions
% pairing, which asks whether a given trial's duration and collision
% count go together, not whether the two measures' TRENDS across training
% go together for the same person.
%
% Method: extract each subject's own repetition-slope random effect
% (BLUP) from the already-fit training-phase models in
% performance_lmm_results.mat (duration_s: LMM; n_collisions: Poisson
% GLMM, log-rate scale) via randomEffects(), then correlate the two
% per-subject slope vectors across all 47 subjects and within each group.
% Correlating the BLUPs directly (rather than BLUP + fixed effect) is
% equivalent for this purpose -- adding the same fixed-effect offset to
% every subject's value doesn't change a correlation.
%
% Requires performance_lmm_results.mat (run run_performance_lmms.m first).

clear; clc;
cfg = config();

res_file = fullfile(cfg.output_root, 'performance_lmm_results.mat');
if ~isfile(res_file)
    error('behavioral_change_correlation: %s not found -- run run_performance_lmms.m first.', res_file);
end
loaded = load(res_file, 'results', 'outcomes');
results  = loaded.results;
outcomes = loaded.outcomes;

idx_dur  = find(strcmp(outcomes, 'duration_s'), 1);
idx_coll = find(strcmp(outcomes, 'n_collisions'), 1);
if isempty(idx_dur) || isempty(idx_coll)
    error('behavioral_change_correlation: expected duration_s and n_collisions in %s', res_file);
end

slope_table = @(mdl) local_subject_slopes(mdl);
[subj_dur,  slope_dur]  = slope_table(results{idx_dur}.mdl);
[subj_coll, slope_coll] = slope_table(results{idx_coll}.mdl);

[common, ia, ib] = intersect(subj_dur, subj_coll);
slope_dur  = slope_dur(ia);
slope_coll = slope_coll(ib);
haptic = cellfun(@(s) s(end) == 'H', common);

fprintf('=== Behavioral "relative change" correlation: repetition-slope BLUPs, duration_s vs n_collisions ===\n');
fprintf('n subjects matched: %d\n', numel(common));

[r_all, p_all] = corr(slope_dur, slope_coll);
fprintf('All subjects:  Pearson r = %.3f, p = %.4f\n', r_all, p_all);

[r_H, p_H] = corr(slope_dur(haptic),  slope_coll(haptic));
[r_N, p_N] = corr(slope_dur(~haptic), slope_coll(~haptic));
fprintf('HF group  (n=%d): r = %.3f, p = %.4f\n', sum(haptic),  r_H, p_H);
fprintf('NHF group (n=%d): r = %.3f, p = %.4f\n', sum(~haptic), r_N, p_N);

fig = figure('Name', 'Behavioral change correlation', 'Position', [50 50 600 500]);
hold on;
COLOR_N = [55  138 221] / 255;
COLOR_H = [212  83 126] / 255;
scatter(slope_dur(~haptic), slope_coll(~haptic), 50, COLOR_N, 'filled', 'DisplayName', 'NHF');
scatter(slope_dur(haptic),  slope_coll(haptic),  50, COLOR_H, 'filled', 'DisplayName', 'HF');
lsline;
xlabel('Duration repetition-slope BLUP (s/rep)');
ylabel('Collision-count repetition-slope BLUP (log-rate/rep)');
title(sprintf('Relative change: r_{all}=%.2f (p=%.3f), r_{HF}=%.2f, r_{NHF}=%.2f', r_all, p_all, r_H, r_N));
legend('Location', 'best'); grid on;

fig_dir = fullfile(cfg.output_root, 'figures');
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
saveas(fig, fullfile(fig_dir, 'behavioral_change_correlation.png'));
fprintf('Saved %s\n', fullfile(fig_dir, 'behavioral_change_correlation.png'));

save(fullfile(cfg.output_root, 'behavioral_change_correlation.mat'), ...
    'common', 'slope_dur', 'slope_coll', 'haptic', 'r_all', 'p_all', 'r_H', 'p_H', 'r_N', 'p_N');


function [subj_names, slopes] = local_subject_slopes(mdl)
% Extracts the per-subject 'repetition' random-effect estimate (BLUP)
% from a fitted LinearMixedModel or GeneralizedLinearMixedModel, robust
% to whether the RE structure is the maximal (correlated) or reduced
% (uncorrelated, from gsr_training_lmm.m's degeneracy fallback) form --
% either way there is exactly one 'repetition' random-effect row per
% subject to pull out.
    [~, ~, stats] = randomEffects(mdl);
    is_rep = strcmp(stats.Name, 'repetition');
    subj_names = cellstr(stats.Level(is_rep));
    slopes     = stats.Estimate(is_rep);
end
