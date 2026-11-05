%% Claude_run_layer1.m
% Runs the corrected Layer 1 comparisons. Writes only to <output_root>/Claude_outputs/layer1.
clear; clc; cfg = config();
Claude_layer1_simple_comparisons(cfg, 'baseline', 'Baseline1', 'Baseline2', 'baseline_elastic');
Claude_layer1_simple_comparisons(cfg, 'test', 'Test1', 'Test2', 'test_pegtransfer');
Claude_layer1_levels_comparisons(cfg);
