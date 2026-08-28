%% make_all_result_plots.m
% Generates all figures supporting the Results section:
%   1. learning_curves_training.png  -- Results 3.1 (learning-rate null,
%      physiology + performance side by side)
%   2. level_divergence.png          -- Results 3.2 (the dissociation:
%      physiological Group x Level divergence vs. flat performance)
%   3. transfer_baseline.png / transfer_test.png -- Results 3.3/3.4
%      (pre/post Phase x Group interaction, elastic task and Peg Transfer)

% plot_learning_curves.m — raw group-mean trajectories across the 10 training repetitions for all 6 outcomes 
% (4 physiological + 2 performance), supporting §3.1 (both groups improve, no differential rate). 
% plot_level_divergence.m — the dissociation figure for §3.2: within-group Level-effect (β vs. Level 1, with 95% CI) 
% for NHF and HF plotted side by side, physiology on top / performance on bottom, pulled directly from the exact contrast 
% values in simple_effects rather than re-derived — so it can't drift from the numbers in the text. 
% plot_transfer_curves.m — pre/post interaction plot for §3.3/3.4: group means at Baseline1→Baseline2 
% (and Test1→Test2, once that data exists — it skips and labels "no data yet" rather than erroring, matching where you actually are).

% Requires the feature tables and model-result .mat files to already
% exist (i.e. gsr_extract_features.m, perf_extract_features.m, gsr_lmm.m,
% run_performance_lmms.m have been run at least once). Each plotting
% function loads what it needs independently and errors with a clear
% message naming the missing file if a prerequisite hasn't been run.

clear; clc; close all;
cfg = config();

plot_learning_curves(cfg);
plot_level_divergence(cfg);
plot_transfer_curves(cfg);

fprintf('\nAll figures saved to %s\n', fullfile(cfg.output_root, 'figures'));
