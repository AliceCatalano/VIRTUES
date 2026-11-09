%% collision_bins_subject_level.m
% Collision-locked EDA and pupil responses by impact-intensity bin and training level, HF vs NHF,
% with SUBJECTS as the unit of inference.
%
% Research question (unchanged from Gsr_h2_per_level_bins.m and Eye_collBins_groups.m):
%   At the same collision intensity, and at the same training level, do HF participants respond
%   differently from NHF participants? Both the size of the response and its variability.
%
% What is kept from the originals:
%   - per-level analysis (L1..L5 separately), four intensity bins (quartiles of peak_accel_g_nidaq)
%   - EDA: scr_amp_local_bc, hard bounds [-0.5, 5], log(x + offset), same offset rule
%   - pupil: pupil_response_norm
%   - the same joins between collision_impact_features.mat and the *_features_v2.mat T_coll tables
%
% What is changed, and why:
%   1. Bins are defined ONCE per level on both groups pooled, not separately per group. With
%      group-specific quartiles, "Bin 1" covered different g ranges in HF and NHF, so responses were
%      not compared at matched intensity. A check column (p_intensity_check) confirms that within each
%      bin the two groups' subjects really had similar impact strengths.
%   2. Each subject contributes ONE value per level x bin cell (their mean response, and their SD),
%      so a subject with 60 collisions in a cell weighs the same as a subject with 5. Group tests
%      then compare ~20 HF people with ~24 NHF people, which is what the question is about.
%   3. Variability is split into two distinct questions that the pooled Levene test mixed together:
%        a) WITHIN-person variability: is each HF person's response more variable from collision to
%           collision? -> compare subject SDs between groups (rank-sum).
%        b) BETWEEN-person spread: do HF people differ more from each other? -> Brown-Forsythe test
%           on the subject means.
%   4. A mixed model per level uses every collision but accounts for nesting:
%        y ~ haptic*bin + (1|subject) + (1|subject:bin) + (1|trial)
%      Satterthwaite df. Gives the HF-NHF difference in each bin, averaged over bins, and the
%      Haptic x Bin interaction (does the group difference depend on intensity?).
%   5. s16N is excluded (detection artifact; already excluded from n_collisions). Set
%      EXCLUDE_SUBJECTS = {} to reproduce the inclusive version.
%   6. Both signals use peak_accel_g_nidaq. (Eye_collBins_groups.m used peak_accel_g.)
%   7. Baseline and Test phases: one trial per level (Baseline) or one trial (Test) gives too few
%      collisions per subject per level per bin, so levels are pooled within each of these phases.
%   8. BH-FDR across the 20 level x bin tests of each signal (training), and across the 16
%      phase x bin tests of each signal (Baseline/Test), separately for each measure.
%   The original collision-level p-values are also reported (p_naive_*) so the two can be compared
%   side by side. They are NOT valid for group inference.
%
% CAVEAT: Claude_collision_and_coupling_models.m notes that the 3 mm/s pupil filter keeps only about
% 24% of pupil samples, so pupil_response_norm should be re-derived before the pupil results are final.
%
% Writes ONLY to <output_root>/collision_bins_subject_level. Overwrites nothing else.

clear; clc; close all; cfg = config();
CN = [64 96 179]/255; CH = [139 82 168]/255;

%% Settings
EXCLUDE_SUBJECTS = {'subject_s16N'};   % {} to include everyone
MIN_COLL_MEAN    = 3;    % collisions a subject needs in a cell for their mean to be used
MIN_COLL_SD      = 5;    % collisions a subject needs in a cell for their SD to be used
LOWER_SCR = -0.5; UPPER_SCR = 5.0;     % same hard bounds as Gsr_h2_per_level_bins.m
qp = [0 0.25 0.50 0.75 1.0];

out_dir = fullfile(cfg.output_root,'collision_bins_subject_level');
fig_dir = fullfile(out_dir,'figures');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

%% Load and join (same joins as the originals)
CI  = load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact'); T_CI = CI.T_impact;
EDA = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T_coll'); Ec = EDA.T_coll;
EYE = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T_coll'); Yc = EYE.T_coll;

JE = local_join(T_CI, Ec, 'scr_amp_local_bc');
bad = JE.scr_amp_local_bc < LOWER_SCR | JE.scr_amp_local_bc > UPPER_SCR;
fprintf('EDA hard-bound exclusions: %d / %d (%.2f%%)\n', sum(bad), height(JE), 100*mean(bad));
JE = JE(~bad & isfinite(JE.scr_amp_local_bc),:);
offset_scr = abs(min(JE.scr_amp_local_bc)) + 0.01;
JE.y = log(JE.scr_amp_local_bc + offset_scr);
fprintf('SCR log-transform offset: %.4f\n', offset_scr);

JP = local_join(T_CI, Yc, 'pupil_response_norm');
JP = JP(isfinite(JP.pupil_response_norm),:);
JP.y = JP.pupil_response_norm;

signals = {'EDA',   JE, sprintf('log(SCR + %.3f)',offset_scr);
           'Pupil', JP, 'pupil response (norm.)'};

blocks = {};
for lv = 1:5, blocks(end+1,:) = {sprintf('L%d',lv),'training',lv}; end %#ok<SAGROW>
for ph = {'Baseline1','Baseline2','Test1','Test2'}, blocks(end+1,:) = {ph{1},'transfer',NaN}; end %#ok<SAGROW>

%% Analysis
rowsB = {}; rowsM = {}; rowsO = {}; rowsE = {}; cellList = {};
for s = 1:size(signals,1)
    sig = signals{s,1}; J = signals{s,2};
    J = J(~ismember(J.subject, EXCLUDE_SUBJECTS),:);
    fprintf('\n===== %s: %d collisions, %d subjects =====\n', sig, height(J), numel(unique(J.subject)));

    for k = 1:size(blocks,1)
        name = blocks{k,1}; bset = blocks{k,2};
        if strcmp(bset,'training')
            D = J(strcmp(J.phase_type,'training') & J.level==blocks{k,3},:);
        else
            D = J(strcmp(J.phase,name),:);
        end
        if height(D) < 20 || numel(unique(D.subject)) < 6
            fprintf('  %s: too little data (%d collisions) - skipped\n', name, height(D)); continue;
        end

        % Bins on both groups pooled
        edges = quantile(D.peak_accel_g_nidaq, qp);
        if any(diff(edges) <= 0)
            warning('%s %s: tied quantile edges, block skipped.', sig, name); continue;
        end
        D.bin = discretize(D.peak_accel_g_nidaq, [-Inf edges(2:4) Inf]);
        rowsE(end+1,:) = {sig,bset,name,edges(1),edges(2),edges(3),edges(4),edges(5),height(D)}; %#ok<SAGROW>

        % One row per subject x bin
        G = groupsummary(D, {'subject','haptic','bin'}, {'mean','std','median'}, {'y','peak_accel_g_nidaq'});
        G.signal = repmat({sig},height(G),1); G.block_set = repmat({bset},height(G),1); G.block = repmat({name},height(G),1);
        cellList{end+1} = G; %#ok<SAGROW>

        for b = 1:4
            g = G(G.bin==b,:);
            okM = g.GroupCount >= MIN_COLL_MEAN; okS = g.GroupCount >= MIN_COLL_SD;
            mN = g.mean_y(okM & ~g.haptic);  mH = g.mean_y(okM & g.haptic);
            sN = g.std_y(okS & ~g.haptic);   sH = g.std_y(okS & g.haptic);
            aN = g.median_peak_accel_g_nidaq(okM & ~g.haptic); aH = g.median_peak_accel_g_nidaq(okM & g.haptic);
            % Original collision-level tests, for comparison only
            xN = D.y(D.bin==b & ~D.haptic); xH = D.y(D.bin==b & D.haptic);
            p_naive_mean = local_welch(xH,xN); p_naive_lev = local_bf(xN,xH);
            % Subject-level tests
            [p_mean,dif,lo,hi] = local_welch(mH,mN);
            rowsB(end+1,:) = {sig,bset,name,b,edges(b),edges(b+1), ...
                numel(xN),numel(xH),p_naive_mean,p_naive_lev, ...
                numel(mN),numel(mH),mean(mN),mean(mH),dif,lo,hi,local_hedges(mH,mN),p_mean,local_rank(mH,mN), ...
                std(mN),std(mH),local_bf(mN,mH), ...
                numel(sN),numel(sH),median(sN),median(sH),local_rank(sH,sN), ...
                median(aN),median(aH),local_rank(aH,aN)}; %#ok<SAGROW>
        end

        % Mixed model on all collisions, nesting respected
        Dm = D;
        Dm.bin_cat  = categorical(Dm.bin);
        Dm.subj_bin = categorical(strcat(string(Dm.subject),'_b',string(Dm.bin)));
        re = ' + (1|subject_cat) + (1|subj_bin)';
        if numel(unique(Dm.trial_id)) > numel(unique(Dm.subject)), re = [re ' + (1|trial_id)']; end %#ok<AGROW>
        try
            mdl = fitlme(Dm, ['y ~ haptic_num*bin_cat' re], 'FitMethod','REML');
            nm = mdl.CoefficientNames; beta = fixedEffects(mdl); V = mdl.CoefficientCovariance;
            H = zeros(4,numel(beta));
            for b = 1:4
                H(b,local_idx(nm,'haptic_num')) = 1;
                if b > 1, H(b,local_idx(nm,sprintf('bin_cat_%d:haptic_num',b))) = 1; end
            end
            Hs = [H; mean(H,1)];
            labels = {'1','2','3','4','avg'};
            for r = 1:5
                est = Hs(r,:)*beta; se = sqrt(Hs(r,:)*V*Hs(r,:)');
                [p,~,~,df2] = coefTest(mdl,Hs(r,:),0,'DFMethod','satterthwaite');
                rowsM(end+1,:) = {sig,bset,name,labels{r},est,se,df2,p}; %#ok<SAGROW>
            end
            a = anova(mdl,'DFMethod','satterthwaite'); tn = cellstr(a.Term);
            ii = find(contains(tn,'haptic_num') & contains(tn,'bin_cat'),1);
            rowsO(end+1,:) = {sig,bset,name,height(Dm),numel(unique(Dm.subject)),strtrim(re),a.FStat(ii),a.DF2(ii),a.pValue(ii)}; %#ok<SAGROW>
        catch ME
            warning('%s %s: model failed (%s).', sig, name, ME.message);
        end
        fprintf('  %s done (%d collisions, %d subjects)\n', name, height(D), numel(unique(D.subject)));
    end
end

%% Tables and FDR
TB = cell2table(rowsB,'VariableNames',{'signal','block_set','block','bin','g_low','g_high', ...
    'n_coll_N','n_coll_H','p_naive_mean','p_naive_levene', ...
    'n_subj_N','n_subj_H','mean_N','mean_H','diff_H_minus_N','ci_low','ci_high','hedges_g','p_subj_mean','p_subj_mean_rank', ...
    'sd_of_subject_means_N','sd_of_subject_means_H','p_between_person_spread', ...
    'n_subj_sd_N','n_subj_sd_H','median_within_sd_N','median_within_sd_H','p_within_person_sd', ...
    'median_g_N','median_g_H','p_intensity_check'});
gid = findgroups(TB.signal, TB.block_set);
for c = {'p_naive_mean','p_naive_levene','p_subj_mean','p_subj_mean_rank','p_between_person_spread','p_within_person_sd'}
    TB.([c{1} '_fdr']) = local_fdr(TB.(c{1}), gid);
end
TM = cell2table(rowsM,'VariableNames',{'signal','block_set','block','bin','diff_H_minus_N','se','df','p'});
isb = ~strcmp(TM.bin,'avg'); TM.p_fdr = nan(height(TM),1);
g2 = findgroups(TM.signal(isb), TM.block_set(isb)); TM.p_fdr(isb) = local_fdr(TM.p(isb), g2);
TO = cell2table(rowsO,'VariableNames',{'signal','block_set','block','n_coll','n_subj','random_effects','F_haptic_x_bin','df2','p_haptic_x_bin'});
TE = cell2table(rowsE,'VariableNames',{'signal','block_set','block','g_min','q25','q50','q75','g_max','n_coll'});
TC = vertcat(cellList{:});

writetable(TB,fullfile(out_dir,'bins_subject_level_tests.csv'));
writetable(TM,fullfile(out_dir,'bins_model_group_difference.csv'));
writetable(TO,fullfile(out_dir,'bins_model_haptic_x_bin.csv'));
writetable(TE,fullfile(out_dir,'bin_edges.csv'));
writetable(TC,fullfile(out_dir,'subject_bin_cells.csv'));
save(fullfile(out_dir,'collision_bins_subject_level.mat'),'TB','TM','TO','TE','TC','offset_scr','EXCLUDE_SUBJECTS','MIN_COLL_MEAN','MIN_COLL_SD');

%% Console summary
for s = 1:size(signals,1)
    sig = signals{s,1};
    fprintf('\n=== %s: HF vs NHF per level x bin (subjects as unit) ===\n', sig);
    fprintf('%-10s %3s %11s %6s %8s %8s %8s %8s %8s %8s %8s\n','block','bin','g range','nN/nH','diff','g','p_mean','p_fdr','p_within','p_betw','p_g');
    T = TB(strcmp(TB.signal,sig),:);
    for i = 1:height(T)
        fprintf('%-10s %3d %5.2f-%5.2f %3d/%-2d %8.3f %8.2f %8.4f %8.4f %8.4f %8.4f %8.3f\n', T.block{i}, T.bin(i), T.g_low(i), T.g_high(i), ...
            T.n_subj_N(i), T.n_subj_H(i), T.diff_H_minus_N(i), T.hedges_g(i), T.p_subj_mean(i), T.p_subj_mean_fdr(i), ...
            T.p_within_person_sd(i), T.p_between_person_spread(i), T.p_intensity_check(i));
    end
    O = TO(strcmp(TO.signal,sig),:);
    fprintf('Haptic x Bin (mixed model): ');
    for i = 1:height(O), fprintf('%s p=%.3f  ', O.block{i}, O.p_haptic_x_bin(i)); end
    fprintf('\n');
end
fprintf(['\nColumns: diff = HF - NHF in mean subject response; p_mean = Welch on subject means; ' ...
    'p_within = rank-sum on subject SDs; p_betw = Brown-Forsythe on subject means; ' ...
    'p_g = intensity check (should be large).\n']);

%% Figures
for s = 1:size(signals,1)
    sig = signals{s,1}; ylab = signals{s,3};
    C = TC(strcmp(TC.signal,sig),:); T = TB(strcmp(TB.signal,sig),:);

    % 1. Training: subject means, rows = bins, columns = levels
    f = figure('Position',[50 50 1700 1000]);
    tl = tiledlayout(4,5,'TileSpacing','compact','Padding','compact');
    title(tl,sprintf('%s - training: one dot per subject (mean response in the cell), bins pooled across groups',sig),'FontWeight','bold');
    for b = 1:4
        for lv = 1:5
            nexttile((b-1)*5+lv);
            nm = sprintf('L%d',lv);
            c = C(strcmp(C.block,nm) & C.bin==b & C.GroupCount>=MIN_COLL_MEAN,:);
            r = T(strcmp(T.block,nm) & T.bin==b,:);
            local_panel(c.mean_y(~c.haptic), c.mean_y(c.haptic), CN, CH);
            if ~isempty(r)
                title(sprintf('%s Bin%d [%.2f-%.2f g]\np=%s, p_{FDR}=%s, g=%.2f', nm, b, r.g_low, r.g_high, ...
                    local_pstr(r.p_subj_mean), local_pstr(r.p_subj_mean_fdr), r.hedges_g),'FontSize',7);
            end
            if lv == 1, ylabel(ylab,'FontSize',7); end
        end
    end
    exportgraphics(f,fullfile(fig_dir,sprintf('%s_training_subject_means.png',lower(sig))),'Resolution',180);

    % 2. Training: within-person SD, same layout
    f = figure('Position',[50 50 1700 1000]);
    tl = tiledlayout(4,5,'TileSpacing','compact','Padding','compact');
    title(tl,sprintf('%s - training: within-person SD (one dot per subject with >= %d collisions in the cell)',sig,MIN_COLL_SD),'FontWeight','bold');
    for b = 1:4
        for lv = 1:5
            nexttile((b-1)*5+lv);
            nm = sprintf('L%d',lv);
            c = C(strcmp(C.block,nm) & C.bin==b & C.GroupCount>=MIN_COLL_SD,:);
            r = T(strcmp(T.block,nm) & T.bin==b,:);
            local_panel(c.std_y(~c.haptic), c.std_y(c.haptic), CN, CH);
            if ~isempty(r)
                title(sprintf('%s Bin%d\np=%s, p_{FDR}=%s', nm, b, local_pstr(r.p_within_person_sd), local_pstr(r.p_within_person_sd_fdr)),'FontSize',7);
            end
            if lv == 1, ylabel('within-person SD','FontSize',7); end
        end
    end
    exportgraphics(f,fullfile(fig_dir,sprintf('%s_training_within_person_sd.png',lower(sig))),'Resolution',180);

    % 3. Group difference with 95% CI across bins, one panel per level
    f = figure('Position',[50 50 1600 380]);
    tl = tiledlayout(1,5,'TileSpacing','compact','Padding','compact');
    title(tl,sprintf('%s - HF minus NHF (subject means, Welch 95%% CI) by intensity bin',sig),'FontWeight','bold');
    for lv = 1:5
        nexttile; hold on;
        r = T(strcmp(T.block,sprintf('L%d',lv)),:);
        if ~isempty(r)
            errorbar(r.bin, r.diff_H_minus_N, r.diff_H_minus_N - r.ci_low, r.ci_high - r.diff_H_minus_N, 'o-', ...
                'Color',CH,'MarkerFaceColor',CH,'LineWidth',1.5);
        end
        yline(0,'k--'); xlim([0.5 4.5]); xticks(1:4); xlabel('intensity bin (pooled quartile)');
        if lv == 1, ylabel('HF - NHF'); end
        title(sprintf('L%d',lv)); grid on; box on;
    end
    exportgraphics(f,fullfile(fig_dir,sprintf('%s_training_group_difference.png',lower(sig))),'Resolution',180);

    % 4. Baseline and Test phases, levels pooled
    f = figure('Position',[50 50 1400 1000]);
    tl = tiledlayout(4,4,'TileSpacing','compact','Padding','compact');
    title(tl,sprintf('%s - Baseline and Test (levels pooled): one dot per subject',sig),'FontWeight','bold');
    phs = {'Baseline1','Baseline2','Test1','Test2'};
    for b = 1:4
        for ip = 1:4
            nexttile((b-1)*4+ip);
            c = C(strcmp(C.block,phs{ip}) & C.bin==b & C.GroupCount>=MIN_COLL_MEAN,:);
            r = T(strcmp(T.block,phs{ip}) & T.bin==b,:);
            local_panel(c.mean_y(~c.haptic), c.mean_y(c.haptic), CN, CH);
            if ~isempty(r)
                title(sprintf('%s Bin%d\np=%s, p_{FDR}=%s (n=%d/%d)', phs{ip}, b, local_pstr(r.p_subj_mean), ...
                    local_pstr(r.p_subj_mean_fdr), r.n_subj_N, r.n_subj_H),'FontSize',7);
            else
                title(sprintf('%s Bin%d\nno data',phs{ip},b),'FontSize',7);
            end
            if ip == 1, ylabel(ylab,'FontSize',7); end
        end
    end
    exportgraphics(f,fullfile(fig_dir,sprintf('%s_transfer_subject_means.png',lower(sig))),'Resolution',180);
end
fprintf('\nSaved to %s\n', out_dir);

%% Local functions
function J = local_join(T_CI, Tc, var)
% Same two joins as Gsr_h2_per_level_bins.m: training on repetition, Baseline/Test on acquisition.
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
function [p,d,lo,hi] = local_welch(x,y)
% Welch t-test of x vs y; d and CI are for mean(x) - mean(y).
    x = x(isfinite(x)); y = y(isfinite(y));
    if numel(x) < 2 || numel(y) < 2, p = NaN; d = NaN; lo = NaN; hi = NaN; return; end
    [~,p,ci] = ttest2(x,y,'Vartype','unequal'); d = mean(x) - mean(y); lo = ci(1); hi = ci(2);
end
function p = local_rank(x,y)
    x = x(isfinite(x)); y = y(isfinite(y));
    if numel(x) < 2 || numel(y) < 2, p = NaN; return; end
    p = ranksum(x,y);
end
function p = local_bf(x,y)
% Brown-Forsythe test for equal spread.
    x = x(isfinite(x)); y = y(isfinite(y));
    if numel(x) < 2 || numel(y) < 2, p = NaN; return; end
    p = vartestn([x(:); y(:)], [zeros(numel(x),1); ones(numel(y),1)], 'TestType','BrownForsythe','Display','off');
end
function g = local_hedges(x,y)
% Hedges g for mean(x) - mean(y).
    x = x(isfinite(x)); y = y(isfinite(y)); nx = numel(x); ny = numel(y);
    if nx < 2 || ny < 2, g = NaN; return; end
    sp = sqrt(((nx-1)*var(x) + (ny-1)*var(y)) / (nx+ny-2));
    g = (mean(x) - mean(y)) / sp * (1 - 3/(4*(nx+ny-2) - 1));
end
function q = local_fdr(p, gid)
% Benjamini-Hochberg within each group id.
    q = nan(size(p));
    for g = unique(gid(:))'
        ix = find(gid == g & isfinite(p));
        if isempty(ix), continue; end
        [ps,o] = sort(p(ix)); m = numel(ps);
        a = ps .* m ./ (1:m)'; a = min(cummin(a,'reverse'),1);
        q(ix(o)) = a;
    end
end
function ix = local_idx(names, name)
% Coefficient index, ignoring the order of the parts of an interaction name.
    want = sort(strsplit(name,':'));
    ix = find(cellfun(@(n) isequal(sort(strsplit(n,':')), want), names), 1);
    if isempty(ix), error('Coefficient %s not found.', name); end
end
function local_panel(vN, vH, CN, CH)
    hold on;
    vals = {vN(isfinite(vN)), vH(isfinite(vH))}; cols = {CN, CH};
    for k = 1:2
        v = vals{k};
        if isempty(v), continue; end
        scatter(k + (rand(numel(v),1)-0.5)*0.25, v, 14, cols{k}, 'filled', 'MarkerFaceAlpha',0.5);
        if numel(v) >= 2
            ci = tinv(0.975, numel(v)-1) * std(v) / sqrt(numel(v));
            errorbar(k + 0.25, mean(v), ci, 'o', 'Color',cols{k}, 'MarkerFaceColor',cols{k}, 'LineWidth',1.5, 'MarkerSize',5);
        end
    end
    xlim([0.5 2.6]); xticks([1 2]); xticklabels({'NHF','HF'}); grid on; box on;
end
function s = local_pstr(p)
    if isnan(p), s = 'n/a'; elseif p < 0.001, s = sprintf('%.1e',p); else, s = sprintf('%.3f',p); end
end
