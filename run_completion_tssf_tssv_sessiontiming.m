%% run_completion_tssf_tssv_sessiontiming.m
% Driver for the Haptic x Timing (start vs end of training) log-transformed
% LMM you specified, applied to completion time, TSSF, and TSSV --
% perf_sessiontiming_lmm.m's header explains why this runs on the
% training block only (Session is not a separate factor here) and why
% Satterthwaite degrees of freedom are used instead of Kenward-Roger
% (MATLAB does not implement Kenward-Roger for fitlme/anova).
%
% NASA-TLX is NOT included: this pipeline has no NASA-TLX (or any other
% subjective workload questionnaire) data anywhere in it -- config.m,
% every *_extract_features.m, and every raw-data folder structure
% referenced throughout this project contain no such measure. Per this
% project's own "exclude/error, don't fabricate" rule (documented
% identically for error_count/task_success/force measures in
% perf_extract_features.m), NASA-TLX is left out of this table entirely
% rather than filled with a placeholder that implies it might exist
% somewhere -- if you have NASA-TLX data collected outside this pipeline,
% it needs its own extraction step before it can be added here.
%
% Requires perf_features.mat (duration_s) and force_vibration_features.mat
% (tssf, tssv) -- run perf_extract_features(cfg) and
% perf_extract_force_vibration_features(cfg) first if missing.

clear; clc;
cfg = config();

perf_file = fullfile(cfg.output_root, 'perf_features.mat');
fv_file   = fullfile(cfg.output_root, 'force_vibration_features_clean.mat');
if ~isfile(perf_file)
    error('run_completion_tssf_tssv_sessiontiming: run perf_extract_features(cfg) first.');
end
if ~isfile(fv_file)
    error('run_completion_tssf_tssv_sessiontiming: run perf_extract_force_vibration_features(cfg) first.');
end

Tperf = load(perf_file, 'T'); Tperf = Tperf.T;
Tfv   = load(fv_file,   'T'); Tfv   = Tfv.T;

join_keys = {'subject','phase_type','phase','acquisition','level','repetition','group','haptic'};
Tmerged = innerjoin(Tperf, Tfv, 'Keys', join_keys);

outcomes = {'duration_s', 'tssf', 'tssv'};
results = cell(numel(outcomes), 1);
for i = 1:numel(outcomes)
    results{i} = perf_sessiontiming_lmm(Tmerged, outcomes{i}, 3, 3);
end

fprintf('\n\n=== Summary: Haptic x Timing (start vs end of training), Type III ANOVA (Satterthwaite) ===\n');
fprintf('%-14s %-20s %10s %10s %10s\n', 'Outcome', 'Term', 'F', 'p', 'Sig?');
for i = 1:numel(outcomes)
    atbl = results{i}.anova_table;
    for r = 2:height(atbl)   % skip intercept row
        fprintf('%-14s %-20s %10.3f %10.4f %10s\n', outcomes{i}, atbl.Term{r}, ...
            atbl.FStat(r), atbl.pValue(r), local_ternary(atbl.pValue(r) < 0.05, 'YES', 'no'));
    end
end

save(fullfile(cfg.output_root, 'sessiontiming_lmm_results.mat'), 'results', 'outcomes');
fprintf('\nSaved results to %s\n', fullfile(cfg.output_root, 'sessiontiming_lmm_results.mat'));


function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
