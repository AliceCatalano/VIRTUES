%% run_layer1_test.m
% Layer1 (full-repetition) simple comparisons for the Peg Transfer
% carry-over control: Test1 vs Test2. See layer1_simple_comparisons.m for
% exactly what's computed (within-N paired, within-H paired, between-group
% at Test1, at Test2, and on the Test2-Test1 change).
%
% Requires eda_features.mat, eye_features.mat, perf_features.mat,
% force_vibration_features.mat to already exist.
clear; clc;
cfg = config();
results = layer1_simple_comparisons(cfg, 'test', 'Test1', 'Test2', 'test_pegtransfer');
plot_layer1_comparisons(cfg, 'test_pegtransfer', 'test', 'Test1', 'Test2');
