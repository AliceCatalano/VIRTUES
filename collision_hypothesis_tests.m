%% collision_hypothesis_tests.m
% One test per hypothesis for collision-locked EDA and pupil responses, HF vs NHF.
% Companion to collision_bins_subject_level.m, which gives the descriptive level x bin breakdown.
% Writes ONLY to <output_root>/collision_hypothesis_tests.
%
% WHY THIS SCRIPT
% The level x bin breakdown splits one question into 20 cells of 8-19 people per group. With about
% 17 vs 19 people a t-test has 80% power only for effects of g ~ 0.95, before any correction.
% Here each hypothesis is answered by ONE test that uses every subject's full training data.
%
% TRANSPARENCY NOTE (put this in the paper)
% These tests were specified AFTER the level x bin results were seen. They are the natural summary of
% the original hypothesis ("HF respond differently to collisions"), but they are not preregistered.
%
% HYPOTHESES AND TESTS (training phase unless stated)
% Primary family, Holm-corrected across 4 tests:
%   H1 Overall difference: does the intensity-adjusted collision response differ between groups?
%        Subject score = mean of the residual after removing level and impact intensity, estimated
%        on all collisions with group ignored (group-blind adjustment). Welch t on subject scores.
%   H2 Habituation: does the group difference change across L1->L5?
%        Subject score = slope across levels of the subject's mean intensity-adjusted response.
%        Welch t on slopes. NOTE: level order was fixed (L1->L5), so "level" = difficulty + time.
%   Each for EDA and for pupil -> 4 tests.
% Secondary family, BH-FDR:
%   S1 Within-person variability: SD of each subject's adjusted responses (rank-sum).
%   S2 Intensity scaling: each subject's slope of response on log impact intensity (Welch).
%   S3 Baseline1 (pre-training, negative control: groups should NOT differ) and
%      Baseline2 (post-training, feedback off for both groups: does a difference persist?).
% Every subject-level test is backed by a mixed model on all collisions:
%   H1: y ~ haptic*level + log_acc + (1+log_acc|subject) + (1|subject:level) + (1|trial),
%       contrast = haptic effect averaged over the 5 levels, Satterthwaite df.
%   H2: y ~ haptic*level_c + log_acc + (1+level_c|subject) + (1|subject:level) + (1|trial),
%       term haptic:level_c (level_c = level - 3, linear).
%
% ALSO REPORTED, because a reader needs them to judge a null or a positive result:
%   - Hedges g with 95% CI for every subject-level test
%   - minimum detectable effect (80% power, alpha .05) for the n actually available
%   - leave-one-subject-out range of p for H1 and H2 (is any result carried by one person?)
%
% CAVEAT: pupil_response_norm should be re-derived (the 3 mm/s filter keeps about 24% of samples).

clear; clc; close all; cfg = config();
CN = [64 96 179]/255; CH = [139 82 168]/255;

%% Settings
EXCLUDE_SUBJECTS = {'subject_s16N'};
MIN_COLL_SUBJ    = 10;   % collisions a subject needs in training to get a score
MIN_COLL_LEVEL   = 3;    % collisions a subject needs at a level for that level's mean (H2)
MIN_LEVELS       = 3;    % levels a subject needs for a slope (H2)
MIN_COLL_BASE    = 5;    % collisions a subject needs in a Baseline phase
LOWER_SCR = -0.5; UPPER_SCR = 5.0;

out_dir = fullfile(cfg.output_root,'collision_hypothesis_tests');
fig_dir = fullfile(out_dir,'figures');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

%% Load, join and clean (identical to collision_bins_subject_level.m)
CI  = load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact'); T_CI = CI.T_impact;
EDA = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T_coll'); Ec = EDA.T_coll;
EYE = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T_coll'); Yc = EYE.T_coll;

JE = local_join(T_CI, Ec, 'scr_amp_local_bc');
JE = JE(isfinite(JE.scr_amp_local_bc) & JE.scr_amp_local_bc >= LOWER_SCR & JE.scr_amp_local_bc <= UPPER_SCR,:);
offset_scr = abs(min(JE.scr_amp_local_bc)) + 0.01;
JE.y = log(JE.scr_amp_local_bc + offset_scr);
JP = local_join(T_CI, Yc, 'pupil_response_norm');
JP = JP(isfinite(JP.pupil_response_norm),:);
JP.y = JP.pupil_response_norm;

signals = {'EDA', JE, 'adjusted log SCR'; 'Pupil', JP, 'adjusted pupil response'};

rows = {}; loo = {}; plotData = struct();
for s = 1:size(signals,1)
    sig = signals{s,1}; J = signals{s,2};
    J = J(~ismember(J.subject, EXCLUDE_SUBJECTS),:);
    J.log_acc = log(J.peak_accel_g_nidaq);
    J.log_acc = J.log_acc - mean(J.log_acc);
    T = J(strcmp(J.phase_type,'training'),:);
    T.level_cat = categorical(T.level);
    T.level_c   = T.level - 3;
    T.subj_level = categorical(strcat(string(T.subject),'_',string(T.level)));
    fprintf('\n===== %s: %d training collisions, %d subjects =====\n', sig, height(T), numel(unique(T.subject)));

    % Group-blind adjustments, estimated on everyone together
    lmA = fitlm(T(:,{'y','level_cat','log_acc'}), 'y ~ level_cat*log_acc');
    T.r_full = lmA.Residuals.Raw;                    % level and intensity removed (H1, S1)
    lmI = fitlm(T(:,{'y','log_acc'}), 'y ~ log_acc');
    T.r_int = lmI.Residuals.Raw;                     % intensity removed only (H2)
    lmL = fitlm(T(:,{'y','level_cat'}), 'y ~ level_cat');
    T.r_lvl = lmL.Residuals.Raw;                     % level removed only (S2)

    % ---------- H1: overall difference ----------
    G = groupsummary(T, {'subject','haptic'}, {'mean','std'}, 'r_full');
    G = G(G.GroupCount >= MIN_COLL_SUBJ,:);
    rows(end+1,:) = local_row(sig,'H1 overall difference','primary','subject means, Welch', G.mean_r_full(G.haptic), G.mean_r_full(~G.haptic)); %#ok<SAGROW>
    loo(end+1,:) = [{sig,'H1 overall difference'}, local_loo(G.mean_r_full, G.haptic, G.subject)]; %#ok<SAGROW>
    plotData.(sig).G = G;
    try
        m1 = fitlme(T, 'y ~ haptic_num*level_cat + log_acc + (1+log_acc|subject_cat) + (1|subj_level) + (1|trial_id)', 'FitMethod','REML');
        nm = m1.CoefficientNames; h = zeros(1,numel(nm)); h(local_idx(nm,'haptic_num')) = 1;
        for lv = 2:5, h(local_idx(nm,sprintf('level_cat_%d:haptic_num',lv))) = 1/5; end
        rows(end+1,:) = local_model_row(sig,'H1 overall difference','primary (model check)','mixed model, haptic averaged over levels', m1, h); %#ok<SAGROW>
    catch ME
        warning('%s H1 model failed: %s', sig, ME.message);
    end

    % ---------- H2: change of the group difference across levels ----------
    GL = groupsummary(T, {'subject','haptic','level'}, 'mean', 'r_int');
    GL = GL(GL.GroupCount >= MIN_COLL_LEVEL,:);
    us = unique(GL.subject); sl = nan(numel(us),1); hs = false(numel(us),1);
    for i = 1:numel(us)
        g = GL(strcmp(GL.subject,us{i}),:); hs(i) = g.haptic(1);
        if height(g) >= MIN_LEVELS, b = polyfit(g.level, g.mean_r_int, 1); sl(i) = b(1); end
    end
    ok = isfinite(sl);
    rows(end+1,:) = local_row(sig,'H2 habituation (slope over L1-L5)','primary','subject slopes, Welch', sl(ok & hs), sl(ok & ~hs)); %#ok<SAGROW>
    loo(end+1,:) = [{sig,'H2 habituation (slope over L1-L5)'}, local_loo(sl(ok), hs(ok), us(ok))]; %#ok<SAGROW>
    plotData.(sig).GL = GL;
    try
        m2 = fitlme(T, 'y ~ haptic_num*level_c + log_acc + (1+level_c|subject_cat) + (1|subj_level) + (1|trial_id)', 'FitMethod','REML');
        nm = m2.CoefficientNames; h = zeros(1,numel(nm)); h(local_idx(nm,'haptic_num:level_c')) = 1;
        rows(end+1,:) = local_model_row(sig,'H2 habituation (slope over L1-L5)','primary (model check)','mixed model, haptic x linear level', m2, h); %#ok<SAGROW>
    catch ME
        warning('%s H2 model failed: %s', sig, ME.message);
    end

    % ---------- S1: within-person variability ----------
    rows(end+1,:) = local_row(sig,'S1 within-person SD','secondary','subject SDs, rank-sum', G.std_r_full(G.haptic), G.std_r_full(~G.haptic), true); %#ok<SAGROW>

    % ---------- S2: scaling with impact intensity ----------
    us = unique(T.subject); isl = nan(numel(us),1); hs = false(numel(us),1);
    for i = 1:numel(us)
        g = T(strcmp(T.subject,us{i}),:); hs(i) = g.haptic(1);
        if height(g) >= MIN_COLL_SUBJ && var(g.log_acc) > 0, b = polyfit(g.log_acc, g.r_lvl, 1); isl(i) = b(1); end
    end
    ok = isfinite(isl);
    rows(end+1,:) = local_row(sig,'S2 intensity scaling (slope on log g)','secondary','subject slopes, Welch', isl(ok & hs), isl(ok & ~hs)); %#ok<SAGROW>

    % ---------- S3: Baseline1 (negative control) and Baseline2 (feedback off) ----------
    for ph = {'Baseline1','Baseline2'}
        B = J(strcmp(J.phase,ph{1}),:);
        if height(B) < 20, continue; end
        B.level_cat = categorical(B.level);
        lmB = fitlm(B(:,{'y','level_cat','log_acc'}), 'y ~ level_cat + log_acc');
        B.r = lmB.Residuals.Raw;
        GB = groupsummary(B, {'subject','haptic'}, 'mean', 'r');
        GB = GB(GB.GroupCount >= MIN_COLL_BASE,:);
        lab = 'S3 Baseline1, pre-training (control: expect no difference)';
        if strcmp(ph{1},'Baseline2'), lab = 'S3 Baseline2, post-training, feedback off'; end
        rows(end+1,:) = local_row(sig,lab,'secondary','subject means, Welch', GB.mean_r(GB.haptic), GB.mean_r(~GB.haptic)); %#ok<SAGROW>
    end
end

%% Results table and corrections
R = cell2table(rows,'VariableNames',{'signal','hypothesis','family','method','n_H','n_N', ...
    'diff_H_minus_N','ci_low','ci_high','hedges_g','g_ci_low','g_ci_high','p','p_rank','min_detectable_g'});
R.p_adjusted = nan(height(R),1); R.correction = repmat({''},height(R),1);
ix = strcmp(R.family,'primary');
R.p_adjusted(ix) = local_holm(R.p(ix)); R.correction(ix) = {'Holm across 4 primary tests'};
ix = strcmp(R.family,'secondary');
R.p_adjusted(ix) = local_bh(R.p(ix)); R.correction(ix) = {'BH-FDR across secondary tests'};
L = cell2table(loo,'VariableNames',{'signal','hypothesis','p_all','p_loo_min','p_loo_max','most_influential_subject'});

writetable(R,fullfile(out_dir,'hypothesis_tests.csv'));
writetable(L,fullfile(out_dir,'leave_one_out.csv'));
save(fullfile(out_dir,'collision_hypothesis_tests.mat'),'R','L','plotData','offset_scr','EXCLUDE_SUBJECTS');

%% Console summary
fprintf('\n%-6s %-58s %-22s %6s %8s %18s %7s %16s %8s %8s %6s\n','signal','hypothesis','family','nH/nN','diff','95% CI','g','g 95% CI','p','p_adj','MDE');
for i = 1:height(R)
    fprintf('%-6s %-58s %-22s %3d/%-2d %8.3f [%7.3f,%7.3f] %7.2f [%6.2f,%6.2f] %8.4f %8.4f %6.2f\n', R.signal{i}, R.hypothesis{i}, R.family{i}, ...
        R.n_H(i), R.n_N(i), R.diff_H_minus_N(i), R.ci_low(i), R.ci_high(i), R.hedges_g(i), R.g_ci_low(i), R.g_ci_high(i), R.p(i), R.p_adjusted(i), R.min_detectable_g(i));
end
fprintf('\nLeave-one-subject-out:\n');
for i = 1:height(L)
    fprintf('%-6s %-40s p=%.4f, range without one subject [%.4f, %.4f], most influential: %s\n', ...
        L.signal{i}, L.hypothesis{i}, L.p_all(i), L.p_loo_min(i), L.p_loo_max(i), L.most_influential_subject{i});
end
fprintf(['\nMDE = smallest Hedges g detectable with 80%% power at alpha .05 for these n. ' ...
    'A non-significant test only rules out effects larger than about the MDE.\n']);

%% Figures
for s = 1:size(signals,1)
    sig = signals{s,1}; ylab = signals{s,3}; P = plotData.(sig);
    f = figure('Position',[50 50 1250 420]);
    tl = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
    title(tl, sprintf('%s collision response, training (one value per subject)', sig), 'FontWeight','bold');

    % H1: subject scores
    nexttile; hold on;
    v = {P.G.mean_r_full(~P.G.haptic), P.G.mean_r_full(P.G.haptic)}; cols = {CN, CH};
    for k = 1:2
        scatter(k + (rand(numel(v{k}),1)-0.5)*0.25, v{k}, 28, cols{k}, 'filled', 'MarkerFaceAlpha',0.55);
        ci = tinv(0.975,numel(v{k})-1)*std(v{k})/sqrt(numel(v{k}));
        errorbar(k+0.28, mean(v{k}), ci, 'o', 'Color',cols{k}, 'MarkerFaceColor',cols{k}, 'LineWidth',1.8);
    end
    r = R(strcmp(R.signal,sig) & strcmp(R.hypothesis,'H1 overall difference') & strcmp(R.family,'primary'),:);
    yline(0,'k:'); xlim([0.5 2.6]); xticks([1 2]); xticklabels({'NHF','HF'}); ylabel(['mean ' ylab]); grid on; box on;
    if ~isempty(r), title(sprintf('H1 overall: g = %.2f [%.2f, %.2f], p = %.3f, p_{Holm} = %.3f', r.hedges_g, r.g_ci_low, r.g_ci_high, r.p, r.p_adjusted)); end

    % H2: group means across levels, subject-level SE
    nexttile; hold on;
    GL = P.GL;
    for k = 0:1
        mu = nan(1,5); se = nan(1,5);
        for lv = 1:5
            x = GL.mean_r_int(GL.haptic==k & GL.level==lv);
            mu(lv) = mean(x); se(lv) = std(x)/sqrt(numel(x));
        end
        c = cols{k+1};
        errorbar((1:5) + (k-0.5)*0.12, mu, 1.96*se, 'o-', 'Color',c, 'MarkerFaceColor',c, 'LineWidth',1.8);
    end
    r = R(strcmp(R.signal,sig) & startsWith(R.hypothesis,'H2') & strcmp(R.family,'primary'),:);
    xlim([0.6 5.4]); xticks(1:5); xticklabels({'L1','L2','L3','L4','L5'}); ylabel(ylab); grid on; box on;
    legend({'NHF','HF'},'Location','best');
    if ~isempty(r), title(sprintf('H2 slope difference: g = %.2f [%.2f, %.2f], p = %.3f, p_{Holm} = %.3f', r.hedges_g, r.g_ci_low, r.g_ci_high, r.p, r.p_adjusted)); end
    exportgraphics(f, fullfile(fig_dir, sprintf('%s_H1_H2.png', lower(sig))), 'Resolution',200);
end

% Forest plot of every subject-level test, effect sizes with 95% CI
Rs = R(isfinite(R.hedges_g),:);
f = figure('Position',[50 50 950 60+38*height(Rs)]); hold on;
for i = 1:height(Rs)
    yv = height(Rs) - i + 1;
    c = CH; if strcmp(Rs.family{i},'secondary'), c = [0.5 0.5 0.5]; end
    plot([Rs.g_ci_low(i) Rs.g_ci_high(i)], [yv yv], '-', 'Color',c, 'LineWidth',2);
    plot(Rs.hedges_g(i), yv, 'o', 'Color',c, 'MarkerFaceColor',c, 'MarkerSize',7);
    for sgn = [-1 1]
        plot(sgn*Rs.min_detectable_g(i)*[1 1], yv + [-0.25 0.25], '-', 'Color',[0.8 0.3 0.3], 'LineWidth',1.5);
    end
end
xline(0,'k-');
yticks(1:height(Rs)); yticklabels(flipud(strcat(Rs.signal,{': '},Rs.hypothesis)));
xlabel('Hedges g, HF minus NHF (95% CI); red ticks = minimum detectable effect');
title('Effect sizes for all subject-level tests (purple = primary, grey = secondary)'); grid on; box on;
exportgraphics(f, fullfile(fig_dir,'forest_all_tests.png'), 'Resolution',200);
fprintf('\nSaved to %s\n', out_dir);

%% Local functions
function J = local_join(T_CI, Tc, var)
    a = T_CI(strcmp(T_CI.phase_type,'training'),:);  b = Tc(strcmp(Tc.phase_type,'training'),:);
    J1 = innerjoin(a, b, 'Keys',{'subject','phase','repetition','collision_idx'}, 'RightVariables',{var});
    a = T_CI(~strcmp(T_CI.phase_type,'training'),:); b = Tc(~strcmp(Tc.phase_type,'training'),:);
    J2 = innerjoin(a, b, 'Keys',{'subject','phase','acquisition','collision_idx'}, 'RightVariables',{var});
    J2.repetition = nan(height(J2),1);
    J = [J1; J2];
    J = J(isfinite(J.peak_accel_g_nidaq) & J.peak_accel_g_nidaq > 0,:);
    J.haptic      = logical(J.haptic);
    J.haptic_num  = double(J.haptic);
    J.subject_cat = categorical(J.subject);
    J.trial_id    = categorical(strcat(string(J.subject),'_',string(J.phase),'_',string(J.acquisition)));
end
function row = local_row(sig, hyp, fam, method, xH, xN, use_rank)
% Subject-level comparison HF vs NHF: Welch (or rank-sum as the main p), Hedges g with CI, MDE.
    if nargin < 7, use_rank = false; end
    xH = xH(isfinite(xH)); xN = xN(isfinite(xN)); nH = numel(xH); nN = numel(xN);
    if nH < 2 || nN < 2
        row = {sig,hyp,fam,method,nH,nN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN}; return;
    end
    [~,pw,ci] = ttest2(xH, xN, 'Vartype','unequal');
    pr = ranksum(xH, xN);
    sp = sqrt(((nH-1)*var(xH) + (nN-1)*var(xN)) / (nH+nN-2));
    g  = (mean(xH) - mean(xN)) / sp * (1 - 3/(4*(nH+nN-2) - 1));
    seg = sqrt((nH+nN)/(nH*nN) + g^2/(2*(nH+nN)));
    p = pw; if use_rank, p = pr; end
    row = {sig,hyp,fam,method,nH,nN,mean(xH)-mean(xN),ci(1),ci(2),g,g-1.96*seg,g+1.96*seg,p,pr,local_mde(nH,nN)};
end
function row = local_model_row(sig, hyp, fam, method, mdl, h)
    beta = fixedEffects(mdl); est = h*beta; se = sqrt(h*mdl.CoefficientCovariance*h');
    [p,~,~,df] = coefTest(mdl, h, 0, 'DFMethod','satterthwaite');
    t = tinv(0.975, df);
    row = {sig,hyp,fam,method,NaN,NaN,est,est-t*se,est+t*se,NaN,NaN,NaN,p,NaN,NaN};
end
function out = local_loo(x, isH, subj)
% Welch p with all subjects, and its range when each subject is left out in turn.
    ok = isfinite(x); x = x(ok); isH = logical(isH(ok)); subj = subj(ok);
    [~,p0] = ttest2(x(isH), x(~isH), 'Vartype','unequal');
    pl = nan(numel(x),1);
    for i = 1:numel(x)
        k = true(numel(x),1); k(i) = false;
        [~,pl(i)] = ttest2(x(k & isH), x(k & ~isH), 'Vartype','unequal');
    end
    [~,imax] = max(abs(log(pl) - log(p0)));
    out = {p0, min(pl), max(pl), subj{imax}};
end
function d = local_mde(n1, n2)
% Smallest standardized difference detectable with 80% power, two-sided alpha .05.
    a = min(n1,n2); b = max(n1,n2);
    try
        d = sampsizepwr('t2', [0 1], [], 0.80, a, 'Ratio', b/a);
    catch
        d = (norminv(0.975) + norminv(0.80)) * sqrt(1/n1 + 1/n2);
    end
end
function q = local_holm(p)
    q = nan(size(p)); v = find(isfinite(p)); [ps,o] = sort(p(v)); m = numel(ps);
    a = min(cummax(ps .* (m - (1:m)' + 1)), 1); q(v(o)) = a;
end
function q = local_bh(p)
    q = nan(size(p)); v = find(isfinite(p)); [ps,o] = sort(p(v)); m = numel(ps);
    a = min(cummin(ps .* m ./ (1:m)', 'reverse'), 1); q(v(o)) = a;
end
function ix = local_idx(names, name)
    want = sort(strsplit(name,':'));
    ix = find(cellfun(@(n) isequal(sort(strsplit(n,':')), want), names), 1);
    if isempty(ix), error('Coefficient %s not found.', name); end
end
