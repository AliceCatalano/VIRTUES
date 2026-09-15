%% run_layer1_baseline.m
% Layer1 (full-repetition) simple comparisons for the elastic-task
% transfer probe: Baseline1 vs Baseline2. See layer1_simple_comparisons.m
% for exactly what's computed (within-N paired, within-H paired,
% between-group at Baseline1, at Baseline2, and on the Baseline2-Baseline1
% change).
%
% Requires eda_features.mat, eye_features.mat, perf_features.mat,
% force_vibration_features.mat to already exist.
clear; clc;
cfg = config();
results = layer1_simple_comparisons(cfg, 'baseline', 'Baseline1', 'Baseline2', 'baseline_elastic');
plot_layer1_comparisons(cfg, 'baseline_elastic', 'baseline', 'Baseline1', 'Baseline2');
