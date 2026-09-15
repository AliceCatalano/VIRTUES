%% run_mediation_analysis.m
% SAP Section 5.2 / H5: does haptic feedback's effect on performance run
% (partially) through physiological/oculomotor arousal? Tests a small,
% explicit set of candidate mediators against both performance outcomes,
% using multilevel_mediation_mc.m's simple (level-effect) mediation model.
% FDR correction is applied across all indirect-effect tests run here,
% since this is now its own confirmatory-adjacent family once you decide
% to report it as such -- see the confirmatory/exploratory register.
%
% Candidate mediators chosen for a defensible Path-a rationale (SAP's own
% framing: haptic -> arousal), not chosen after seeing Path b -- picking
% mediators post-hoc based on which b-paths already looked interesting
% would make the "confirmatory" framing meaningless:
%   scl_mean, scr_freq          - SAP's own primary EDA arousal measures
%   pupil_mean                  - the eye-tracking analogue of scl_mean
% pupil_slope is deliberately NOT included here despite being the
% strongest correlation-analysis finding -- that finding is a moderated
% WITHIN-subject coupling effect, not a mediator-level effect, and
% doesn't fit this function's model (see multilevel_mediation_mc.m's
% header). Report it as what it is (Section 3.7), not shoehorned into a
% mediation framework that doesn't match what was actually found.

clear; clc;
cfg = config();

merged_file = fullfile(cfg.output_root, 'merged_features.mat');
if ~isfile(merged_file)
    error('run_mediation_analysis: %s not found -- run run_correlation_analyses first.', merged_file);
end
loaded = load(merged_file, 'T');
T = loaded.T;

mediators = {'scl_mean', 'scr_freq', 'pupil_mean'};
outcomes  = {'duration_s', 'n_collisions'};

pairs = {};
for mi = 1:numel(mediators)
    for oi = 1:numel(outcomes)
        pairs(end+1, :) = {mediators{mi}, outcomes{oi}}; %#ok<AGROW>
    end
end

results = cell(size(pairs, 1), 1);
for i = 1:size(pairs, 1)
    results{i} = multilevel_mediation_mc(T, pairs{i,1}, pairs{i,2}, 'training');
end

indirect_p_proxy = cellfun(@(r) 2*min(normcdf(-abs(r.indirect_effect / (diff(r.indirect_CI)/(2*1.96)))), 0.5), results);
% Note: FDR correction here uses a normal-approximation p-value derived
% from the Monte Carlo CI half-width (there is no direct p-value for a
% product-of-coefficients estimate) -- treat as approximate.
p_fdr = local_bh_fdr(indirect_p_proxy);

fprintf('\n\n=== Summary: indirect effects (Haptic -> Mediator -> Outcome) ===\n');
fprintf('%-15s %-15s %12s %20s %10s %10s\n', 'Mediator', 'Outcome', 'indirect', '95% CI', 'sig?', 'p_FDR(approx)');
for i = 1:numel(results)
    r = results{i};
    fprintf('%-15s %-15s %12.4g   [%8.4g, %8.4g] %10s %10.4f\n', ...
        r.mediator, r.outcome, r.indirect_effect, r.indirect_CI(1), r.indirect_CI(2), ...
        local_ternary(r.indirect_significant, 'YES', 'no'), p_fdr(i));
end

save(fullfile(cfg.output_root, 'mediation_results.mat'), 'results', 'pairs', 'p_fdr');
fprintf('\nSaved results to %s\n', fullfile(cfg.output_root, 'mediation_results.mat'));


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

function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
