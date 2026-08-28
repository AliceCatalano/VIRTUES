%% run_correlation_analyses.m
% Driver for the multilevel (within-/between-subject) correlation
% analyses between physiological/eye-tracking and performance outcomes,
% and between the two performance outcomes themselves -- extends this
% project's analysis plan's Section 5.1 correlation method (multilevel
% models with within-subject centering, haptic moderation via
% interactions) beyond its literal scope (which specified eye-tracking vs
% physiological measures only) to the physiological/eye vs. PERFORMANCE
% pairings requested directly, plus a performance-vs-performance pairing.
%
% Three families, each with its own separate FDR correction (within-
% subject and between-subject p-values corrected separately within each
% family -- they answer different questions and aren't assumed to share a
% multiplicity budget):
%
%   1. OVERALL-TRIAL physiological/eye measures vs. performance
%      (7 predictors x 2 outcomes = 14 pairs). Predictors: scl_mean,
%      scr_freq, scr_mean_amp (GSR); pupil_mean, pupil_slope,
%      gaze_dispersion, saccade_rate (eye). Outcomes: duration_s,
%      n_collisions.
%   2. EVENT-LOCKED physiological/eye measures vs. collision count
%      (their natural counterpart, since both are collision-triggered):
%      collision_scr_amp_mean vs n_collisions, collision_pupil_response_mean
%      vs n_collisions.
%   3. PERFORMANCE vs. PERFORMANCE: duration_s vs n_collisions (a
%      classic speed-accuracy-tradeoff question -- do trials that take
%      longer also have fewer/more collisions?).
%
% This is a SEPARATE question from "relative change" between the two
% performance measures (do subjects who improve FASTER in one also
% improve faster in the other) -- that's a between-subject,
% learning-RATE-to-learning-RATE comparison, not a trial-level
% correlation, and is handled by behavioral_change_correlation.m instead.

clear; clc;
cfg = config();

merged_file = fullfile(cfg.output_root, 'merged_features.mat');
if ~isfile(merged_file)
    fprintf('No cached merged table found -- running merge_modality_tables (requires eda_features.mat, eye_features.mat, perf_features.mat to already exist)...\n');
    T = merge_modality_tables(cfg);
else
    fprintf('Loading cached merged table from %s\n', merged_file);
    fprintf('(delete this file and rerun merge_modality_tables if any upstream feature table has changed)\n');
    loaded = load(merged_file, 'T');
    T = loaded.T;
end

families = struct( ...
    'name',       {'overall_physio_eye_vs_performance', 'event_locked_vs_collisions', 'performance_vs_performance'}, ...
    'predictors', {{'scl_mean','scr_freq','scr_mean_amp','pupil_mean','pupil_slope','gaze_dispersion','saccade_rate'}, ...
                   {'collision_scr_amp_mean','collision_pupil_response_mean'}, ...
                   {'duration_s'}}, ...
    'outcomes',   {{'duration_s','n_collisions'}, {'n_collisions'}, {'n_collisions'}});

all_results = struct();
for f = 1:numel(families)
    fam = families(f);
    fprintf('\n\n########## Family: %s ##########\n', fam.name);

    pairs = {};
    for pi = 1:numel(fam.predictors)
        for oi = 1:numel(fam.outcomes)
            if strcmp(fam.predictors{pi}, fam.outcomes{oi}), continue; end
            pairs(end+1, :) = {fam.predictors{pi}, fam.outcomes{oi}}; %#ok<AGROW>
        end
    end

    results = cell(size(pairs, 1), 1);
    for i = 1:size(pairs, 1)
        results{i} = multilevel_correlation_lmm(T, pairs{i,1}, pairs{i,2}, 'training');
    end

    within_p  = cellfun(@(r) r.within_p,  results);
    between_p = cellfun(@(r) r.between_p, results);
    within_p_fdr  = local_bh_fdr(within_p);
    between_p_fdr = local_bh_fdr(between_p);

    fprintf('\n=== %s: within-subject and between-subject associations ===\n', fam.name);
    fprintf('%-28s %-28s %10s %10s %10s %10s | %10s %10s %10s %10s\n', ...
        'Predictor', 'Outcome', 'b_within', 'p', 'p_FDR', 'p(x Haptic)', 'b_between', 'p', 'p_FDR', 'p(x Haptic)');
    for i = 1:numel(results)
        r = results{i};
        fprintf('%-28s %-28s %10.4f %10.4f %10.4f %10.4f | %10.4f %10.4f %10.4f %10.4f\n', ...
            r.predictor, r.outcome, r.within_beta, r.within_p, within_p_fdr(i), r.within_haptic_p, ...
            r.between_beta, r.between_p, between_p_fdr(i), r.between_haptic_p);
    end

    all_results.(fam.name).pairs = pairs;
    all_results.(fam.name).results = results;
    all_results.(fam.name).within_p_fdr = within_p_fdr;
    all_results.(fam.name).between_p_fdr = between_p_fdr;
end

save(fullfile(cfg.output_root, 'correlation_results.mat'), 'all_results');
fprintf('\nSaved results to %s\n', fullfile(cfg.output_root, 'correlation_results.mat'));


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
