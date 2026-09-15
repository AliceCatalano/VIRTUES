%% eye_transfer_lmms.m
% Driver for the pre/post transfer models applied to the eye-tracking
% outcomes, mirroring run_transfer_lmms.m (the physiological version)
% exactly -- same two families (elastic-task transfer, Peg Transfer
% carry-over control), same folder<->phase mapping. Calls
% gsr_transfer_lmm.m DIRECTLY, same reasoning as run_eye_lmms.m: that
% function is fully generic, not GSR-specific in implementation.
%
% Only the three overall-trial outcomes are tested here --
% collision_pupil_response_mean is excluded for the same reason
% collision_scr_amp_mean is excluded from run_transfer_lmms.m: Baseline/
% Test acquisitions are single unrepeated trials, too few collisions per
% trial for a stable event-locked estimate outside the 10-repetition
% training blocks.
%
% Folder <-> phase mapping (same as run_transfer_lmms.m):
%   Baseline1 = elastic, pre-training   | Baseline2 = elastic, post-training
%   Test1     = Peg Transfer, pre-training | Test2 = Peg Transfer, post-training

clear; clc;
cfg = config();

feat_file = fullfile(cfg.output_root, 'eye_features.mat');
if ~isfile(feat_file)
    fprintf('No cached feature table found -- running eye_extract_features...\n');
    T = eye_extract_features(cfg);
else
    fprintf('Loading cached feature table from %s\n', feat_file);
    fprintf('(delete this file and rerun eye_extract_features if upstream data has changed)\n');
    loaded = load(feat_file, 'T');
    T = loaded.T;
end

outcomes = {'pupil_slope', 'gaze_dispersion', 'saccade_rate'};

families = struct( ...
    'name',       {'baseline_transfer_elastic', 'test_transfer_pegtransfer'}, ...
    'phase_type', {'baseline',                  'test'}, ...
    'phase_pre',  {'Baseline1',                 'Test1'}, ...
    'phase_post', {'Baseline2',                 'Test2'}, ...
    'sap_section', {'transfer (H2 physiological analogue)', 'carry-over control'});

all_results = struct();
for f = 1:numel(families)
    fam = families(f);
    fprintf('\n\n########## %s -- %s ##########\n', fam.name, fam.sap_section);

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

save(fullfile(cfg.output_root, 'eye_transfer_lmm_results.mat'), 'all_results');
fprintf('\nSaved results to %s\n', fullfile(cfg.output_root, 'eye_transfer_lmm_results.mat'));


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
