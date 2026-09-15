%% run_training_lmms.m
% Driver for SAP Section 4.2 (training-phase learning-rate models) applied
% to the physiological (EDA) outcomes listed in Section 3.3, with FDR
% correction across those outcomes per Section 8.
%
% Physiological outcomes tested here (mapped onto columns of the feature
% table from gsr_extract_features.m):
%   - Mean SCL                 -> scl_mean
%   - SCR frequency             -> scr_freq
%   - Mean SCR amplitude        -> scr_mean_amp
%   - Event-locked SCR amplitude -> collision_scr_amp_mean
%
% For each, the primary test is the Haptic x Repetition interaction
% (differential learning rate, H1). Level main/interaction effects are
% also in the fitted model and visible in the full lme output printed by
% gsr_training_lmm.m -- only the interaction term is pulled out here for
% the FDR summary since that's what the SAP designates as primary.

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

outcomes = {'scl_mean', 'scr_freq', 'scr_mean_amp', 'collision_scr_amp_mean'};

results = cell(numel(outcomes), 1);
for i = 1:numel(outcomes)
    results{i} = gsr_training_lmm(T, outcomes{i});
end

p_vals  = cellfun(@(r) r.interaction_p, results);
p_fdr   = local_bh_fdr(p_vals);

fprintf('\n\n=== Summary: Haptic x Repetition interaction (differential learning rate, PRIMARY per SAP 4.2/8) ===\n');
fprintf('%-25s %-38s %10s %10s %10s %10s\n', 'Outcome', 'RE structure used', 'beta', 'SE', 'p', 'p_FDR');
for i = 1:numel(outcomes)
    r = results{i};
    fprintf('%-25s %-38s %10.4f %10.4f %10.4f %10.4f\n', ...
        outcomes{i}, r.re_structure, r.interaction_beta, r.interaction_se, r.interaction_p, p_fdr(i));
end

% Haptic x Level terms (SECONDARY/EXPLORATORY): the SAP's Section 8 FDR  family is defined over the primary Haptic x Repetition test only. These
% are reported separately, FDR-corrected across all outcome x level comparisons pooled together, so they are not silently presented as if
% protected by the primary family's correction.
fprintf('\n=== Secondary: Haptic x Level terms (exploratory -- own FDR family, not SAP''s primary one) ===\n');
lh_outcome = {}; lh_term = {}; lh_beta = []; lh_se = []; lh_p = [];
for i = 1:numel(outcomes)
    lh = results{i}.level_haptic;
    for j = 1:height(lh)
        lh_outcome{end+1,1} = outcomes{i}; %#ok<AGROW>
        lh_term{end+1,1}    = lh.term{j};  %#ok<AGROW>
        lh_beta(end+1,1)    = lh.beta(j);  %#ok<AGROW>
        lh_se(end+1,1)      = lh.se(j);    %#ok<AGROW>
        lh_p(end+1,1)       = lh.p(j);     %#ok<AGROW>
    end
end
lh_p_fdr = local_bh_fdr(lh_p);
fprintf('%-25s %-28s %10s %10s %10s %10s\n', 'Outcome', 'Term', 'beta', 'SE', 'p', 'p_FDR');
for k = 1:numel(lh_term)
    fprintf('%-25s %-28s %10.4f %10.4f %10.4f %10.4f\n', ...
        lh_outcome{k}, lh_term{k}, lh_beta(k), lh_se(k), lh_p(k), lh_p_fdr(k));
end
% Within-group simple effects: the N group's and H group's own within-subject trajectory (repetition slope, per-level effect vs level
% 1), each with a proper SE/p from the model's full coefficient covariance (not eyeballed by adding printed rows together). The N-vs-H
% DIFFERENCE for each of these is exactly the primary interaction / level_haptic terms already reported above -- this table is what makes
% "does each group show an effect on its own" an explicit, citable number rather than something read off by convention from the reference level.
fprintf('\n=== Within-group simple effects (N and H each on their own; N-vs-H difference = interaction terms above) ===\n');
fprintf('%-25s %-32s %-4s %10s %10s %10s %10s\n', 'Outcome', 'Effect', 'Grp', 'beta', 'SE', 'p', '95%% CI');
for i = 1:numel(outcomes)
    se = results{i}.simple_effects;
    for j = 1:height(se)
        fprintf('%-25s %-32s %-4s %10.4f %10.4f %10.4f  [%7.4f, %7.4f]\n', ...
            outcomes{i}, se.effect{j}, se.group{j}, se.beta(j), se.se(j), se.p(j), se.lower(j), se.upper(j));
    end
end
save(fullfile(cfg.output_root, 'training_lmm_results.mat'), 'results', 'outcomes', 'p_fdr', ...
    'lh_outcome', 'lh_term', 'lh_beta', 'lh_se', 'lh_p', 'lh_p_fdr');
fprintf('\nSaved results to %s\n', fullfile(cfg.output_root, 'training_lmm_results.mat'));


function p_adj = local_bh_fdr(p)
% Benjamini-Hochberg FDR correction (no toolbox dependency).
    p = p(:);
    n = numel(p);
    [p_sorted, idx] = sort(p);
    ranks = (1:n)';
    p_adj_sorted = p_sorted .* n ./ ranks;
    % enforce monotonicity from the largest p-value down
    p_adj_sorted = flipud(cummin(flipud(p_adj_sorted)));
    p_adj_sorted = min(p_adj_sorted, 1);
    p_adj = zeros(n, 1);
    p_adj(idx) = p_adj_sorted;
end