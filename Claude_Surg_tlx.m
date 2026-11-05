%% Claude_Surg_tlx.m
% Corrected, group-aware SURG-TLX analysis based on Surg_tlx.m.
% Writes ONLY to <output_root>/Claude_outputs/surg_tlx. Changes from the original:
%  1. Reads Virtues_Data/SURG_TLX.csv (the original pointed at surgtlx_data.csv, which does not exist).
%  2. Normalises subject IDs (16N and S16N are the same person) and drops pilots S00H and S01H.
%  3. Adds group: Group x Level mixed model, between-group tests on each
%     level and on the change from Level 1, and per-group within-level tests.
%  4. Uses one omnibus test per outcome (Friedman). The original chose ANOVA or Friedman per outcome
%     from a Lilliefors test on small samples, which makes the analysis data-dependent.
%  5. BH correction across subscales and across pairwise tests; the original corrected within each
%     outcome only, with nothing across the six subscales.
%
% KNOWN LIMITATION: ratings are ordinal, so the mixed model is reported with rank-based tests alongside.

clear; clc; close all; cfg = config();
out_dir = fullfile(cfg.output_root,'Claude_outputs','surg_tlx'); if ~exist(out_dir,'dir'), mkdir(out_dir); end
T = readtable(fullfile(cfg.data_root,'SURG_TLX.csv'),'VariableNamingRule','preserve');
names = {'Mental','Physical','Temporal','Complexity','Stress','Distractions'};
v = T.Properties.VariableNames;
mi = find(contains(v,'MENTAL DEMAND','IgnoreCase',true));
nL = numel(mi); if nL~=5, error('Expected 5 level blocks, found %d.',nL); end
ids = upper(strtrim(string(T{:,'Subject ID'})));
ids(~startsWith(ids,'S')) = "S"+ids(~startsWith(ids,'S'));
canon = upper(erase(string(cfg.all_subjects),'subject_'));
keep = ismember(ids,canon);
fprintf('Rows %d; kept %d; dropped: %s\n',height(T),sum(keep),strjoin(ids(~keep),' '));
missing = setdiff(canon,ids); if ~isempty(missing), warning('Missing subjects: %s',strjoin(missing,' ')); end
if numel(unique(ids(keep)))~=sum(keep), error('Duplicate subject IDs in SURG_TLX.csv.'); end
D = nan(height(T),nL,6);
for l = 1:nL
    x = T{:,mi(l):mi(l)+5}; if iscell(x), x = str2double(x); end
    D(:,l,:) = x;
end
D = D(keep,:,:); ids = ids(keep); H = endsWith(ids,'H');
C = mean(D,3,'omitnan');
measures = [{'Composite'},names];

rowsO = {}; rowsB = {}; rowsP = {}; rowsC = {};
for m = 1:numel(measures)
    if m==1, X = C; else, X = D(:,:,m-1); end
    % Omnibus, per group
    rowsO(end+1,:) = {measures{m},friedman(X,1,'off'),friedman(X(~H,:),1,'off'),friedman(X(H,:),1,'off')}; %#ok<AGROW>
    % Between groups, each level
    for l = 1:nL
        rowsB(end+1,:) = {measures{m},l,mean(X(~H,l)),std(X(~H,l)),median(X(~H,l)),mean(X(H,l)),std(X(H,l)),median(X(H,l)),ranksum(X(H,l),X(~H,l))}; %#ok<AGROW>
    end
    % Change from Level 1, by group and between groups
    for l = 2:nL
        d = X(:,l)-X(:,1);
        rowsC(end+1,:) = {measures{m},l,mean(d(~H)),signrank(d(~H)),mean(d(H)),signrank(d(H)),ranksum(d(H),d(~H))}; %#ok<AGROW>
    end
    % Mixed model
    L = table(X(:),repmat(categorical(ids),nL,1),repmat(double(H),nL,1),categorical(reshape(repmat(1:nL,numel(ids),1),[],1)),'VariableNames',{'y','s','h','l'});
    mdl = fitlme(L,'y ~ h*l + (1|s)','FitMethod','REML');
    a = anova(mdl,'DFMethod','satterthwaite');
    r = @(nm) find(strcmp(cellstr(a.Term),nm));
    rowsP(end+1,:) = {measures{m},a.FStat(r('h')),a.DF2(r('h')),a.pValue(r('h')),a.FStat(r('l')),a.pValue(r('l')),a.FStat(r('h:l')),a.DF2(r('h:l')),a.pValue(r('h:l'))}; %#ok<AGROW>
end
TO = cell2table(rowsO,'VariableNames',{'measure','p_friedman_all','p_friedman_N','p_friedman_H'});
TB = cell2table(rowsB,'VariableNames',{'measure','level','mean_N','sd_N','median_N','mean_H','sd_H','median_H','p_rank'});
TC = cell2table(rowsC,'VariableNames',{'measure','level','change_N','p_N','change_H','p_H','p_between'});
TP = cell2table(rowsP,'VariableNames',{'measure','F_group','df_group','p_group','F_level','p_level','F_interaction','df_interaction','p_interaction'});
isS = ~strcmp(TP.measure,'Composite');
TP.p_interaction_fdr = nan(height(TP),1); TP.p_interaction_fdr(isS) = local_bh(TP.p_interaction(isS));
TP.p_group_fdr = nan(height(TP),1); TP.p_group_fdr(isS) = local_bh(TP.p_group(isS));
TP.p_level_fdr = nan(height(TP),1); TP.p_level_fdr(isS) = local_bh(TP.p_level(isS));
TB.p_rank_fdr = local_bh(TB.p_rank);
TC.p_between_fdr = local_bh(TC.p_between);
writetable(TO,fullfile(out_dir,'tlx_omnibus.csv')); writetable(TB,fullfile(out_dir,'tlx_by_level.csv'));
writetable(TC,fullfile(out_dir,'tlx_change_from_L1.csv')); writetable(TP,fullfile(out_dir,'tlx_models.csv'));
save(fullfile(out_dir,'tlx_results.mat'),'TO','TB','TC','TP','D','C','ids','H');
disp(TO); disp(TP); disp(TC(strcmp(TC.measure,'Composite'),:));

CN = [64 96 179]/255; CH = [139 82 168]/255;
fig = figure('Position',[2000 2000 1100 620]);
tl = tiledlayout(2,4,'TileSpacing','compact','Padding','compact');
title(tl,'SURG-TLX by training level, mean \pm 95% CI (NHF n = 24, HF n = 23)','FontWeight','bold');
for m = 1:numel(measures)
    nexttile; hold on;
    if m==1, X = C; else, X = D(:,:,m-1); end
    for g = [false true]
        col = CN; if g, col = CH; end
        Xg = X(H==g,:); mu = mean(Xg); ci = 1.96*std(Xg)/sqrt(size(Xg,1));
        errorbar((1:nL)+(g-0.5)*0.08,mu,ci,'o-','Color',col,'MarkerFaceColor',col,'LineWidth',1.5);
    end
    title(measures{m}); xlim([0.6 nL+0.4]); xticks(1:nL); ylim([0 14]); grid on; box on;
    if m==1, legend({'NHF','HF'},'Location','northwest'); ylabel('Score'); end
end
exportgraphics(fig,fullfile(out_dir,'tlx_by_level.png'),'Resolution',180);
fprintf('TLX_DONE\n');

function q = local_bh(p)
    q = nan(size(p)); v = find(isfinite(p)); [ps,ix] = sort(p(v)); m = numel(ps);
    a = ps.*m./(1:m)'; a = min(cummin(a,'reverse'),1); q(v(ix)) = a;
end
