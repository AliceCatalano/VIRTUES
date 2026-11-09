%% equivalence_tests_performance.m
% Equivalence tests (TOST) for the performance outcomes, HF vs NHF, with subjects as the unit.
% Turns "no difference detected" into "any difference is smaller than X" when the data allow it,
% and says so plainly when they do not.
% Writes ONLY to <output_root>/equivalence_tests.
%
% WHAT IS TESTED (one score per subject, HF minus NHF)
%   Primary (Holm across the 4 TOSTs):
%     1. Improvement Baseline1 -> Baseline2, completion time   (levels valid in both phases only)
%     2. Improvement Baseline1 -> Baseline2, collisions
%     3. Training learning rate, completion time  (subject's repetition slope, level as covariate)
%     4. Training learning rate, collisions
%   Secondary (reported, not corrected): the same for log TSSF and log TSSV, and Test1 -> Test2
%   for completion time.
%
% EQUIVALENCE BOUNDS (smallest effect size of interest, SESOI)
%   Primary bound: d = +/-0.5. Justification: the statistical analysis plan powered the study for a
%   MEDIUM effect of haptic feedback, so 0.5 is the smallest effect the study was designed to care
%   about. It is converted to raw units with the pooled SD of the subject scores (Lakens, 2017).
%   Optional raw bounds: set RAW_BOUNDS below if you can justify a bound in seconds or collisions
%   from the literature or practice (e.g. a difference a trainer would notice). Left NaN = not used.
%
% HOW TO READ THE RESULT (per test)
%   equivalent        : 90% CI of the difference lies inside the bounds (p_TOST < .05)
%   inconclusive      : not different AND not equivalent -> the data cannot decide
%   different         : 95% CI excludes zero
%   smallest_equiv_d  : the smallest bound (in d) the data WOULD support. If this is above 0.5, the
%                       study is too small to show equivalence at a medium effect.
%
% With ~23 per group, the 90% CI for d is roughly +/-0.5 wide around the estimate, so a d = 0.5
% bound is only met if the observed difference is close to zero. "Inconclusive" is a likely and
% honest outcome; it is still more informative than a bare p > .05.

clear; clc; close all; cfg = config();
CN = [64 96 179]/255; CH = [139 82 168]/255;

%% Settings
SESOI_D   = 0.5;
ALPHA     = 0.05;
EXCLUDE_COLLISIONS = {'subject_s16N'};
RAW_BOUNDS = struct('duration_s', NaN, 'n_collisions', NaN);   % e.g. 10 (s), 1 (collision)
MIN_REPS_SLOPE = 15;   % training trials a subject needs for a learning-rate slope

out_dir = fullfile(cfg.output_root,'equivalence_tests');
if ~exist(out_dir,'dir'), mkdir(out_dir); end

%% Data
P = load(fullfile(cfg.output_root,'perf_features.mat'),'T'); P = P.T;
P.n_collisions(ismember(P.subject, EXCLUDE_COLLISIONS)) = NaN;
F = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); F = F.T;
F.tssf(F.tssf<=0) = NaN; F.tssv(F.tssv<=0) = NaN;
F.log_tssf = log(F.tssf); F.log_tssv = log(F.tssv);

jobs = { % outcome, table, label, family, kind
    'duration_s',   P, 'Completion time (s)',  'primary',   'change_baseline'
    'n_collisions', P, 'Collisions per trial', 'primary',   'change_baseline'
    'duration_s',   P, 'Completion time (s)',  'primary',   'training_slope'
    'n_collisions', P, 'Collisions per trial', 'primary',   'training_slope'
    'log_tssf',     F, 'log TSSF',             'secondary', 'change_baseline'
    'log_tssv',     F, 'log TSSV',             'secondary', 'change_baseline'
    'log_tssf',     F, 'log TSSF',             'secondary', 'training_slope'
    'log_tssv',     F, 'log TSSV',             'secondary', 'training_slope'
    'duration_s',   P, 'Completion time (s)',  'secondary', 'change_test'};

rows = {}; scores = {};
for j = 1:size(jobs,1)
    oc = jobs{j,1}; T = jobs{j,2}; kind = jobs{j,5};
    T = T(isfinite(T.(oc)),:);
    subs = unique(T.subject); x = nan(numel(subs),1); isH = false(numel(subs),1);
    for i = 1:numel(subs)
        S = T(strcmp(T.subject,subs{i}),:); isH(i) = logical(S.haptic(1));
        switch kind
            case 'change_baseline'
                % Same levels in both phases, so the change is not partly a difficulty effect
                a = S(strcmp(S.phase,'Baseline1'),:); b = S(strcmp(S.phase,'Baseline2'),:);
                lv = intersect(a.level, b.level);
                if ~isempty(lv)
                    x(i) = mean(b.(oc)(ismember(b.level,lv))) - mean(a.(oc)(ismember(a.level,lv)));
                end
            case 'change_test'
                a = S(strcmp(S.phase,'Test1'),:); b = S(strcmp(S.phase,'Test2'),:);
                if ~isempty(a) && ~isempty(b), x(i) = mean(b.(oc)) - mean(a.(oc)); end
            case 'training_slope'
                % Repetition slope within level: y ~ level + repetition, per subject
                S = S(strcmp(S.phase_type,'training'),:);
                if height(S) >= MIN_REPS_SLOPE && numel(unique(S.repetition)) > 2
                    L = dummyvar(categorical(S.level)); L = L(:,2:end);
                    X = [ones(height(S),1) L double(S.repetition)];
                    X = X(:, any(X,1));                 % drop empty level columns
                    b = X \ S.(oc);
                    x(i) = b(end);
                end
        end
    end
    ok = isfinite(x);
    rawb = NaN; if isfield(RAW_BOUNDS,oc), rawb = RAW_BOUNDS.(oc); end
    r = local_tost(x(ok & isH), x(ok & ~isH), SESOI_D, rawb, ALPHA);
    rows(end+1,:) = [{jobs{j,3}, kind, jobs{j,4}}, r]; %#ok<SAGROW>
    scores{end+1} = table(subs(ok), isH(ok), x(ok), 'VariableNames',{'subject','haptic','score'}); %#ok<SAGROW>
    scores{end}.outcome = repmat({oc},sum(ok),1); scores{end}.kind = repmat({kind},sum(ok),1);
end

R = cell2table(rows,'VariableNames',{'outcome','comparison','family','n_H','n_N','mean_H','mean_N', ...
    'diff_H_minus_N','ci95_low','ci95_high','ci90_low','ci90_high','pooled_sd','d', ...
    'bound_d','bound_raw','p_difference','p_tost','smallest_equiv_d', ...
    'raw_bound','p_tost_raw'});
R.p_tost_holm = nan(height(R),1);
ix = strcmp(R.family,'primary'); R.p_tost_holm(ix) = local_holm(R.p_tost(ix));
R.verdict = repmat({''},height(R),1);
for i = 1:height(R)
    pt = R.p_tost(i); if ix(i), pt = R.p_tost_holm(i); end
    if R.p_difference(i) < ALPHA
        R.verdict{i} = 'different';
    elseif pt < ALPHA
        R.verdict{i} = 'equivalent';
    else
        R.verdict{i} = 'inconclusive';
    end
end
writetable(R, fullfile(out_dir,'equivalence_results.csv'));
writetable(vertcat(scores{:}), fullfile(out_dir,'subject_scores.csv'));
save(fullfile(out_dir,'equivalence_results.mat'),'R','SESOI_D','RAW_BOUNDS');

%% Console summary
fprintf('\nEquivalence bound: d = +/-%.2f (converted to raw units with the pooled SD of the subject scores)\n', SESOI_D);
fprintf('%-22s %-16s %-9s %6s %9s %22s %7s %8s %8s %8s %8s  %s\n','outcome','comparison','family','nH/nN','diff', ...
    '90% CI (raw)','d','bound','p_diff','p_TOST','min_d','verdict');
for i = 1:height(R)
    pt = R.p_tost(i); if strcmp(R.family{i},'primary'), pt = R.p_tost_holm(i); end
    fprintf('%-22s %-16s %-9s %3d/%-2d %9.3f [%9.3f, %9.3f] %7.2f %8.3f %8.3f %8.3f %8.2f  %s\n', R.outcome{i}, R.comparison{i}, R.family{i}, ...
        R.n_H(i), R.n_N(i), R.diff_H_minus_N(i), R.ci90_low(i), R.ci90_high(i), R.d(i), R.bound_raw(i), ...
        R.p_difference(i), pt, R.smallest_equiv_d(i), R.verdict{i});
end
fprintf('\np_TOST for primary rows is Holm-corrected. min_d = smallest bound (in d) at which the result would be "equivalent".\n');

%% Figure: 90% CIs in d units against the bound
f = figure('Position',[50 50 900 90+45*height(R)]); hold on;
for i = 1:height(R)
    yv = height(R) - i + 1; sd = R.pooled_sd(i);
    c = CH; if strcmp(R.family{i},'secondary'), c = [0.5 0.5 0.5]; end
    plot([R.ci90_low(i) R.ci90_high(i)]/sd, [yv yv], '-', 'Color',c, 'LineWidth',3);
    plot([R.ci95_low(i) R.ci95_high(i)]/sd, [yv yv], '-', 'Color',c, 'LineWidth',1);
    plot(R.d(i), yv, 'o', 'Color',c, 'MarkerFaceColor',c, 'MarkerSize',7);
    text(1.25, yv, R.verdict{i}, 'FontSize',9);
end
xline(0,'k-'); xline(-SESOI_D,'r--'); xline(SESOI_D,'r--');
yticks(1:height(R)); yticklabels(flipud(strcat(R.outcome,{' - '},R.comparison)));
xlim([-1.6 1.6]); xlabel('HF minus NHF (standardized); thick = 90% CI, thin = 95% CI; red = equivalence bounds');
title(sprintf('Equivalence tests, bound d = \\pm%.1f', SESOI_D)); grid on; box on;
exportgraphics(f, fullfile(out_dir,'equivalence_plot.png'), 'Resolution',200);
fprintf('\nSaved to %s\n', out_dir);

%% Local functions
function r = local_tost(xH, xN, sesoi_d, rawb, alpha)
% Welch-based TOST for mean(xH) - mean(xN).
    nH = numel(xH); nN = numel(xN);
    if nH < 3 || nN < 3, r = num2cell(nan(1,18)); return; end
    d  = mean(xH) - mean(xN);
    se = sqrt(var(xH)/nH + var(xN)/nN);
    df = se^4 / ((var(xH)/nH)^2/(nH-1) + (var(xN)/nN)^2/(nN-1));
    sp = sqrt(((nH-1)*var(xH) + (nN-1)*var(xN)) / (nH+nN-2));
    t95 = tinv(1-alpha/2, df); t90 = tinv(1-alpha, df);
    p_diff = 2*(1 - tcdf(abs(d/se), df));
    bnd = sesoi_d * sp;
    p_tost = local_tost_p(d, se, df, bnd);
    ci90 = d + [-1 1]*t90*se;
    smallest = max(abs(ci90)) / sp;
    if isfinite(rawb), p_raw = local_tost_p(d, se, df, rawb); else, p_raw = NaN; end
    r = {nH, nN, mean(xH), mean(xN), d, d-t95*se, d+t95*se, ci90(1), ci90(2), sp, d/sp, ...
         sesoi_d, bnd, p_diff, p_tost, smallest, rawb, p_raw};
end
function p = local_tost_p(d, se, df, bnd)
    p_lower = 1 - tcdf((d + bnd)/se, df);   % H0: diff <= -bound
    p_upper = tcdf((d - bnd)/se, df);       % H0: diff >= +bound
    p = max(p_lower, p_upper);
end
function q = local_holm(p)
    q = nan(size(p)); v = find(isfinite(p)); [ps,o] = sort(p(v)); m = numel(ps);
    a = min(cummax(ps .* (m - (1:m)' + 1)), 1); q(v(o)) = a;
end