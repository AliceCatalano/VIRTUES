%% run_force_vibration_transfer_lmms.m
% Driver for the pre/post transfer models (Baseline1->Baseline2 elastic
% task, Test1->Test2 Peg Transfer) applied to TSSF/TSSV, mirroring
% run_transfer_lmms.m exactly. Calls gsr_transfer_lmm.m DIRECTLY -- same
% reasoning as run_eye_transfer_lmms.m: that function is fully generic,
% not GSR-specific in implementation, and takes any table with the right
% subject/phase/level/haptic columns plus any numeric outcome name.
%
% Log-transformed, per your specification for these two metrics (see
% perf_sessiontiming_lmm.m for the same transform applied to the training
% block) -- gsr_transfer_lmm.m itself is transform-agnostic, so the log
% transform is applied here, before calling it, on a copy of the table.
%
% Requires force_vibration_features.mat -- run
% perf_extract_force_vibration_features(cfg) first if missing.

clear; clc;
cfg = config();

fv_file = fullfile(cfg.output_root, 'force_vibration_features_clean.mat');
if ~isfile(fv_file)
    error('run_force_vibration_transfer_lmms: run perf_extract_force_vibration_features(cfg) first.');
end
loaded = load(fv_file, 'T');
T = loaded.T;

n_nonpositive = struct();
for oc = {'tssf','tssv'}
    outcome = oc{1};
    mask_nonpos = T.(outcome) <= 0;
    n_nonpositive.(outcome) = sum(mask_nonpos & isfinite(T.(outcome)));
    T.(outcome)(mask_nonpos) = NaN;   % cannot log-transform; excluded, not fabricated
    T.(outcome) = log(T.(outcome));
end
fprintf('Excluded (non-positive, pre-log) rows: tssf=%d, tssv=%d\n', n_nonpositive.tssf, n_nonpositive.tssv);

outcomes = {'tssf', 'tssv'};

families = struct( ...
    'name',       {'baseline_transfer_elastic', 'test_transfer_pegtransfer'}, ...
    'phase_type', {'baseline',                  'test'}, ...
    'phase_pre',  {'Baseline1',                 'Test1'}, ...
    'phase_post', {'Baseline2',                 'Test2'}, ...
    'sap_section', {'force/vibration transfer (H2 analogue)', 'carry-over control'});

all_results = struct();
for f = 1:numel(families)
    fam = families(f);
    fprintf('\n\n########## %s -- %s (log-transformed) ##########\n', fam.name, fam.sap_section);

    results = cell(numel(outcomes), 1);
    for i = 1:numel(outcomes)
        results{i} = gsr_transfer_lmm(T, outcomes{i}, fam.phase_type, fam.phase_pre, fam.phase_post);
    end

    p_vals = cellfun(@(r) r.interaction_p, results);
    p_fdr  = local_bh_fdr(p_vals);

    fprintf('\n=== Summary: Phase x Haptic interaction (log scale), %s vs %s (%s) ===\n', ...
        fam.phase_pre, fam.phase_post, fam.sap_section);
    fprintf('%-10s %10s %10s %10s %10s\n', 'Outcome', 'beta', 'SE', 'p', 'p_FDR');
    for i = 1:numel(outcomes)
        r = results{i};
        fprintf('%-10s %10.4f %10.4f %10.4f %10.4f\n', ...
            outcomes{i}, r.interaction_beta, r.interaction_se, r.interaction_p, p_fdr(i));
    end

    all_results.(fam.name).results = results;
    all_results.(fam.name).outcomes = outcomes;
    all_results.(fam.name).p_fdr = p_fdr;
end

save(fullfile(cfg.output_root, 'force_vibration_transfer_lmm_results.mat'), 'all_results');
fprintf('\nSaved results to %s\n', fullfile(cfg.output_root, 'force_vibration_transfer_lmm_results.mat'));


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
