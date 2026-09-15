clear; clc; close all;
cfg = config();
plot_correlation_forest(cfg);
plot_durations;
plot_eda_performance;
plot_learning_curves(cfg);
plot_level_divergence(cfg);
plot_sessiontiming_paired_estimation(cfg); % duration_s/tssf_raw/tssv, training start-vs-end, same style
plot_transfer_curves(cfg);
plot_transfer_paired_estimation(cfg);      % every outcome, Baseline1/2 + Test1/2, individual data + mean+-CI, regardless of significance

fprintf('\nAll figures saved to %s\n', fullfile(cfg.output_root, 'figures'));