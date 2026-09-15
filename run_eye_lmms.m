%% eye_lmms.m
% Driver for the training-phase learning-rate models applied to the
% eye-tracking outcomes from eye_extract_features.m, mirroring
% run_training_lmms.m (in gsr_lmm.m) exactly -- same primary/secondary
% FDR structure, same within-group simple-effects breakdown, same
% overall-trial-vs-event-locked outcome split as GSR.
%
% This driver calls gsr_training_lmm.m DIRECTLY (not a duplicate
% eye_training_lmm.m) -- that function is already fully generic (it takes
% any table T with subject/haptic/level/repetition/phase_type columns and
% any numeric outcome column name; nothing in its implementation is
% GSR-specific despite the filename). Writing a byte-for-byte duplicate
% for eye-tracking would only be a maintenance liability -- a future fix
% to the RE-degeneracy fallback should apply to every modality
% automatically, not need to be copied three times.
%
% Outcomes (matching the 3-overall + 1-event-locked split used for GSR):
%   pupil_slope, gaze_dispersion, saccade_rate     [overall-trial]
%   collision_pupil_response_mean                   [event-locked]
% collision_saccade_response_rate is intentionally NOT modeled here (see
% eye_extract_features.m header) -- stored in the table, not fit.

clear; clc;
cfg = config();

feat_file = fullfile(cfg.output_root, 'eye_features.mat');
if ~isfile(feat_file)
    fprintf('No cached feature table found -- running eye_extract_features (this walks all subjects/acquisitions and may take a while)...\n');
    T = eye_extract_features(cfg);
else
    fprintf('Loading cached feature table from %s\n', feat_file);
    fprintf('(delete this file and rerun if eye_extract_features.m or upstream preprocessing has changed)\n');
    loaded = load(feat_file, 'T');
    T = loaded.T;
end

outcomes = {'pupil_slope', 'gaze_dispersion', 'saccade_rate', 'collision_pupil_response_mean'};

results = cell(numel(outcomes), 1);
for i = 1:numel(outcomes)
    results{i} = gsr_training_lmm(T, outcomes{i});
end

p_vals = cellfun(@(r) r.interaction_p, results);
p_fdr  = local_bh_fdr(p_vals);

fprintf('\n\n=== Summary: Haptic x Repetition interaction (differential learning rate, eye-tracking, PRIMARY) ===\n');
fprintf('%-32s %-38s %10s %10s %10s %10s\n', 'Outcome', 'RE structure used', 'beta', 'SE', 'p', 'p_FDR');
for i = 1:numel(outcomes)
    r = results{i};
    fprintf('%-32s %-38s %10.4f %10.4f %10.4f %10.4f\n', ...
        outcomes{i}, r.re_structure, r.interaction_beta, r.interaction_se, r.interaction_p, p_fdr(i));
end

fprintf('\n=== Secondary: Haptic x Level terms (exploratory -- own FDR family) ===\n');
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
fprintf('%-32s %-28s %10s %10s %10s %10s\n', 'Outcome', 'Term', 'beta', 'SE', 'p', 'p_FDR');
for k = 1:numel(lh_term)
    fprintf('%-32s %-28s %10.4f %10.4f %10.4f %10.4f\n', ...
        lh_outcome{k}, lh_term{k}, lh_beta(k), lh_se(k), lh_p(k), lh_p_fdr(k));
end

fprintf('\n=== Within-group simple effects (N and H each on their own) ===\n');
fprintf('%-32s %-32s %-4s %10s %10s %10s %10s\n', 'Outcome', 'Effect', 'Grp', 'beta', 'SE', 'p', '95%% CI');
for i = 1:numel(outcomes)
    se = results{i}.simple_effects;
    for j = 1:height(se)
        fprintf('%-32s %-32s %-4s %10.4f %10.4f %10.4f  [%7.4f, %7.4f]\n', ...
            outcomes{i}, se.effect{j}, se.group{j}, se.beta(j), se.se(j), se.p(j), se.lower(j), se.upper(j));
    end
end

save(fullfile(cfg.output_root, 'eye_lmm_results.mat'), 'results', 'outcomes', 'p_fdr', ...
    'lh_outcome', 'lh_term', 'lh_beta', 'lh_se', 'lh_p', 'lh_p_fdr');
fprintf('\nSaved results to %s\n', fullfile(cfg.output_root, 'eye_lmm_results.mat'));


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
