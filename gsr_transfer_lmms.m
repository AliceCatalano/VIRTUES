% run_transfer_lmms.m
% Driver for the two pre/post transfer models sitting alongside the
% training-phase models in run_training_lmms.m (whose actual file is
% gsr_lmm.m -- naming mismatch inherited from that file, not repeated
% here):
%
%   SAP Section 4.3 -- elastic task, Baseline1 (pre-training) vs
%     Baseline2 (post-training): tests H2, "superior transfer in the
%     haptic feedback group" via the Phase x Haptic interaction.
%   SAP Section 4.4 -- Peg Transfer, Test1 (pre-training) vs Test2
%     (post-training): carry-over control. The SAP predicts NO Phase x
%     Haptic interaction here; a significant one is itself the finding
%     (haptic training bled into a task that never used haptic feedback).
%
% Folder <-> phase mapping (confirmed with the study author; the SAP
% predates data collection and doesn't specify this):
%   Baseline1 = elastic, pre-training   | Baseline2 = elastic, post-training
%   Test1     = Peg Transfer, pre-training | Test2 = Peg Transfer, post-training
%
% Uses the same cached feature table as run_training_lmms.m/gsr_lmm.m
% (T from gsr_extract_features.m) -- delete cfg.output_root/eda_features.mat
% and rerun gsr_extract_features if upstream preprocessing has changed.

clear; clc;
cfg = config();

feat_file = fullfile(cfg.output_root, 'eda_features.mat');
if ~isfile(feat_file)
    fprintf('No cached feature table found -- running gsr_extract_features (this walks all subjects/acquisitions and may take a while)...\n');
    T = gsr_extract_features(cfg);
else
    fprintf('Loading cached feature table from %s\n', feat_file);
    fprintf('(delete this file and rerun if gsr_extract_features.m or upstream preprocessing has changed)\n');
    loaded = load(feat_file, 'T');
    T = loaded.T;
end

outcomes = {'scl_mean', 'scr_freq', 'scr_mean_amp'};
% collision_scr_amp_mean is intentionally excluded here: Baseline/Test
% acquisitions are single unrepeated trials, and collision counts per
% single trial are typically too sparse for a stable collision-locked
% amplitude estimate outside the 10-repetition training blocks.

families = struct( ...
    'name',       {'baseline_transfer_elastic', 'test_transfer_pegtransfer'}, ...
    'phase_type', {'baseline',                  'test'}, ...
    'phase_pre',  {'Baseline1',                 'Test1'}, ...
    'phase_post', {'Baseline2',                 'Test2'}, ...
    'sap_section', {'4.3 (H2: transfer)',       '4.4 (carry-over control)'});

all_results = struct();
for f = 1:numel(families)
    fam = families(f);
    fprintf('\n\n########## %s -- SAP %s ##########\n', fam.name, fam.sap_section);

    results = cell(numel(outcomes), 1);
    for i = 1:numel(outcomes)
        results{i} = gsr_transfer_lmm(T, outcomes{i}, fam.phase_type, fam.phase_pre, fam.phase_post);
    end

    p_vals = cellfun(@(r) r.interaction_p, results);
    p_fdr  = local_bh_fdr(p_vals);

    fprintf('\n=== Summary: Phase x Haptic interaction, %s vs %s (%s) ===\n', ...
        fam.phase_pre, fam.phase_post, fam.sap_section);
    fprintf('%-25s %10s %10s %10s %10s\n', 'Outcome', 'beta', 'SE', 'p', 'p_FDR');
    for i = 1:numel(outcomes)
        r = results{i};
        fprintf('%-25s %10.4f %10.4f %10.4f %10.4f\n', ...
            outcomes{i}, r.interaction_beta, r.interaction_se, r.interaction_p, p_fdr(i));
    end

    all_results.(fam.name).results = results;
    all_results.(fam.name).outcomes = outcomes;
    all_results.(fam.name).p_fdr = p_fdr;
end

save(fullfile(cfg.output_root, 'transfer_lmm_results.mat'), 'all_results');
fprintf('\nSaved results to %s\n', fullfile(cfg.output_root, 'transfer_lmm_results.mat'));


function p_adj = local_bh_fdr(p)
% Benjamini-Hochberg FDR correction (no toolbox dependency).
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