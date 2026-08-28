%% run_performance_lmms.m
% Driver for SAP Section 4.2 training-phase models applied to performance
% outcomes (SAP Section 3.1), mirroring run_training_lmms.m (in gsr_lmm.m)
% for the physiological outcomes -- same primary/secondary FDR structure,
% same within-group simple-effects breakdown.
%
% Outcomes run here (only the two with real extraction code -- see
% perf_extract_features.m header for what's missing and why):
%   duration_s   [gaussian]  -- task completion time (SAP 3.1)
%   n_collisions [poisson]   -- collision count (SAP 3.1)

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

outcomes  = {'duration_s',  'n_collisions'};
families  = {'gaussian',    'poisson'};

results = cell(numel(outcomes), 1);
for i = 1:numel(outcomes)
    results{i} = perf_training_lmm(T, outcomes{i}, families{i});
end

p_vals = cellfun(@(r) r.interaction_p, results);
p_fdr  = local_bh_fdr(p_vals);

fprintf('\n\n=== Summary: Haptic x Repetition interaction (differential learning rate, performance) ===\n');
fprintf('%-15s %-10s %-38s %10s %10s %10s %10s\n', 'Outcome', 'Family', 'RE structure used', 'beta', 'SE', 'p', 'p_FDR');
for i = 1:numel(outcomes)
    r = results{i};
    fprintf('%-15s %-10s %-38s %10.4f %10.4f %10.4f %10.4f\n', ...
        outcomes{i}, families{i}, r.re_structure, r.interaction_beta, r.interaction_se, r.interaction_p, p_fdr(i));
end
fprintf('(n_collisions beta is on the log-rate scale -- exp(beta) is the rate ratio, not an additive count difference.)\n');

fprintf('\n=== Secondary: Haptic x Level terms (exploratory -- own FDR family) ===\n');
lh_outcome = {}; lh_term = {}; lh_beta = []; lh_se = []; lh_p = [];
for i = 1:numel(outcomes)
    lh = results{i}.level_haptic;
    for j = 1:height(lh)
        lh_outcome{end+1,1} = outcomes{i}; %#ok<AGROW>
        lh_term{end+1,1}    = lh.term{j};  %#ok<AGROW>
        lh_beta{end+1,1}    = lh.beta(j);  %#ok<AGROW>
        lh_se{end+1,1}      = lh.se(j);    %#ok<AGROW>
        lh_p(end+1,1)       = lh.p(j);     %#ok<AGROW>
    end
end
lh_beta = cell2mat(lh_beta); lh_se = cell2mat(lh_se);
lh_p_fdr = local_bh_fdr(lh_p);
fprintf('%-15s %-28s %10s %10s %10s %10s\n', 'Outcome', 'Term', 'beta', 'SE', 'p', 'p_FDR');
for k = 1:numel(lh_term)
    fprintf('%-15s %-28s %10.4f %10.4f %10.4f %10.4f\n', ...
        lh_outcome{k}, lh_term{k}, lh_beta(k), lh_se(k), lh_p(k), lh_p_fdr(k));
end

fprintf('\n=== Within-group simple effects (N and H each on their own) ===\n');
fprintf('%-15s %-32s %-4s %10s %10s %10s %10s\n', 'Outcome', 'Effect', 'Grp', 'beta', 'SE', 'p', '95%% CI');
for i = 1:numel(outcomes)
    se = results{i}.simple_effects;
    for j = 1:height(se)
        fprintf('%-15s %-32s %-4s %10.4f %10.4f %10.4f  [%7.4f, %7.4f]\n', ...
            outcomes{i}, se.effect{j}, se.group{j}, se.beta(j), se.se(j), se.p(j), se.lower(j), se.upper(j));
    end
end

save(fullfile(cfg.output_root, 'performance_lmm_results.mat'), 'results', 'outcomes', 'families', 'p_fdr', ...
    'lh_outcome', 'lh_term', 'lh_beta', 'lh_se', 'lh_p', 'lh_p_fdr');
fprintf('\nSaved results to %s\n', fullfile(cfg.output_root, 'performance_lmm_results.mat'));


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
