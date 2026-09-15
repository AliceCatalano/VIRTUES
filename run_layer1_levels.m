%% run_layer1_levels.m
% Layer1 (full-repetition) simple difficulty-level comparisons for the
% training phase. See layer1_levels_comparisons.m for exactly what's
% computed (within-group Level k vs Level 1 + omnibus across levels,
% between-group at each level, between-levels pooled across groups).
%
% Requires eda_features.mat, eye_features.mat, perf_features.mat,
% force_vibration_features.mat to already exist.
clear; clc;
cfg = config();
results = layer1_levels_comparisons(cfg);
plot_layer1_levels(cfg);
