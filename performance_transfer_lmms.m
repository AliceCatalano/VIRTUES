%% run_performance_transfer_lmms.m
% Driver for the SAP 4.3/4.4 pre/post transfer models on performance
% outcomes -- mirrors run_transfer_lmms.m (the physiological version).
% This IS the literal H2 test ("greater improvement from baseline to
% post-training on performance outcomes"), unlike run_transfer_lmms.m's
% physiological analogue of the same model structure.
%
% Folder <-> phase mapping (same as run_transfer_lmms.m):
%   Baseline1 = elastic, pre-training   | Baseline2 = elastic, post-training
%   Test1     = Peg Transfer, pre-training | Test2 = Peg Transfer, post-training

clear; clc;
cfg = config();

feat_file = fullfile(cfg.output_root, 'perf_features.mat');
if ~isfile(feat_file)
    fprintf('No cached performance table found -- running perf_extract_features...\n');
    T = perf_extract_features(cfg);
else
    fprintf('Loading cached performance table from %s\n', feat_file);
    fprintf('(delete this file and rerun perf_extract_features if upstream data has changed)\n');
    loaded = load(feat_file, 'T');
    T = loaded.T;
end

outcomes = {'duration_s', 'n_collisions'};
families = {'gaussian',   'poisson'};

fam_defs = struct( ...
    'name',       {'baseline_transfer_elastic', 'test_transfer_pegtransfer'}, ...
    'phase_type', {'baseline',                  'test'}, ...
    'phase_pre',  {'Baseline1',                 'Test1'}, ...
    'phase_post', {'Baseline2',                 'Test2'}, ...
    'sap_section', {'4.3 (H2: transfer, LITERAL)', '4.4 (carry-over control)'});

all_results = struct();
for f = 1:numel(fam_defs)
    fam = fam_defs(f);
    fprintf('\n\n########## %s -- SAP %s ##########\n', fam.name, fam.sap_section);

    results = cell(numel(outcomes), 1);
    for i = 1:numel(outcomes)
        results{i} = perf_transfer_lmm(T, outcomes{i}, families{i}, fam.phase_type, fam.phase_pre, fam.phase_post);
    end

    p_vals = cellfun(@(r) r.interaction_p, results);
    p_fdr  = local_bh_fdr(p_vals);

    fprintf('\n=== Summary: Phase x Haptic interaction, %s vs %s (%s) ===\n', ...
        fam.phase_pre, fam.phase_post, fam.sap_section);
    fprintf('%-15s %-10s %10s %10s %10s %10s\n', 'Outcome', 'Family', 'beta', 'SE', 'p', 'p_FDR');
    for i = 1:numel(outcomes)
        r = results{i};
        fprintf('%-15s %-10s %10.4f %10.4f %10.4f %10.4f\n', ...
            outcomes{i}, families{i}, r.interaction_beta, r.interaction_se, r.interaction_p, p_fdr(i));
    end

    all_results.(fam.name).results = results;
    all_results.(fam.name).outcomes = outcomes;
    all_results.(fam.name).p_fdr = p_fdr;
end

save(fullfile(cfg.output_root, 'performance_transfer_lmm_results.mat'), 'all_results');
fprintf('\nSaved results to %s\n', fullfile(cfg.output_root, 'performance_transfer_lmm_results.mat'));


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
