%% h2_eda_per_level_accel_bins.m
% H2: phasic SCR amplitude variance by peak_accel_g_nidaq intensity bin
% Structure:
%   - Binning variable: peak_accel_g_nidaq (g units, NIDAQ accelerometer)
%   - Per training level (L1-L5 separately — no mixing)
%   - Group-specific quartiles within each level
%   - Same structure applied to Baseline1 and Baseline2 for cross-phase comparison
%   - SCR amplitude: hard bounds only (<-0.5 or >5), log-transform
%   - Bins saved in table for downstream use

clear; clc; close all; cfg = config();
CN = [64 96 179]/255; CH = [139 82 168]/255;
fig_dir = fullfile(cfg.output_root,'figures');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

CI  = load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact'); T_CI = CI.T_impact;
EDA = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T_coll'); Ec = EDA.T_coll;

LOWER_SCR = -0.5; UPPER_SCR = 5.0;
qp = [0 0.25 0.50 0.75 1.0];

% replace the single innerjoin with two separate joins

% Join 1: training (repetition is numeric, join works normally)
T_CI_tr  = T_CI(strcmp(T_CI.phase_type,'training'),:);
Ec_tr    = Ec(strcmp(Ec.phase_type,'training'),:);
J_train  = innerjoin(T_CI_tr, Ec_tr, ...
    'Keys',{'subject','phase','repetition','collision_idx'}, 'RightVariables',{'scr_amp_local_bc'});

% Join 2: baseline and test (repetition is NaN — exclude from keys)
T_CI_bt  = T_CI(~strcmp(T_CI.phase_type,'training'),:);
Ec_bt    = Ec(~strcmp(Ec.phase_type,'training'),:);
J_other  = innerjoin(T_CI_bt, Ec_bt, ...
    'Keys',{'subject','phase','acquisition','collision_idx'}, ...
    'RightVariables',{'scr_amp_local_bc'});

% concatenate — align columns
J_other.repetition = nan(height(J_other),1);   % restore NaN repetition
J_all = [J_train; J_other];

fprintf('Joined rows by phase_type:\n');
for pt={'training','baseline','test'}
    fprintf('  %s: %d\n',pt{1},sum(strcmp(J_all.phase_type,pt{1})));
end
hap_col = local_find_haptic(J_all);

% apply hard bounds
bad = J_all.scr_amp_local_bc < LOWER_SCR | J_all.scr_amp_local_bc > UPPER_SCR;
fprintf('Hard-bound exclusions: %d / %d (%.2f%%)\n', sum(bad), height(J_all), 100*mean(bad));
J_all = J_all(~bad & isfinite(J_all.scr_amp_local_bc) & isfinite(J_all.peak_accel_g_nidaq),:);

% log-transform SCR
offset_scr = abs(min(J_all.scr_amp_local_bc)) + 0.01;
J_all.log_scr = log(J_all.scr_amp_local_bc + offset_scr);
fprintf('SCR log-transform offset: %.4f\n', offset_scr);

all_results = struct();
% After the two joins and concatenation, immediately apply bounds and log-transform:

J_all = [J_train; J_other];

% detect haptic column once on J_all
hap_col = local_find_haptic(J_all);

% hard bounds
bad = J_all.scr_amp_local_bc < LOWER_SCR | J_all.scr_amp_local_bc > UPPER_SCR;
fprintf('Hard-bound exclusions: %d / %d (%.2f%%)\n',sum(bad),height(J_all),100*mean(bad));
J_all = J_all(~bad & isfinite(J_all.scr_amp_local_bc) & isfinite(J_all.peak_accel_g_nidaq),:);

% log-transform — done once, available to all downstream filters
offset_scr = abs(min(J_all.scr_amp_local_bc)) + 0.01;
J_all.log_scr = log(J_all.scr_amp_local_bc + offset_scr);
fprintf('SCR log-transform offset: %.4f\n', offset_scr);
fprintf('Rows in J_all by phase_type after cleaning:\n');
for pt={'training','baseline','test'}
    fprintf('  %s: %d\n',pt{1},sum(strcmp(J_all.phase_type,pt{1})));
end
%% Training: per level
fprintf('\n=== TRAINING: H2 per level ===\n');
levels = 1:5;

fig_tr = figure('Position',[50 50 1800 900]);
tl_tr  = tiledlayout(4,5,'TileSpacing','compact','Padding','compact');
title(tl_tr,'H2 — Training: log(phasic SCR amplitude) variance by peak\_accel\_g bin — per level (group-specific quartiles)', ...
    'FontWeight','bold','FontSize',10);

for lv = levels
    J = J_all(strcmp(J_all.phase_type,'training') & J_all.level==lv,:);
    fprintf('\nL%d: N=%d collisions (NHF=%d HF=%d)\n',lv,height(J),sum(~J.(hap_col)),sum(J.(hap_col)));
    if height(J)<10, fprintf('  Insufficient data — skipping\n'); continue; end

    eN = quantile(J.peak_accel_g_nidaq(~J.(hap_col)), qp);
    eH = quantile(J.peak_accel_g_nidaq( J.(hap_col)), qp);
    [~,~,bN] = histcounts(J.peak_accel_g_nidaq(~J.(hap_col)), eN);
    [~,~,bH] = histcounts(J.peak_accel_g_nidaq( J.(hap_col)), eH);
    J.bin = zeros(height(J),1);
    J.bin(~J.(hap_col)) = bN; J.bin(J.(hap_col)) = bH;

    fprintf('  NHF bin edges (g): '); fprintf('%.3f  ',eN); fprintf('\n');
    fprintf('  HF  bin edges (g): '); fprintf('%.3f  ',eH); fprintf('\n');

    rows = {};
    for b = 1:4
        xN = J.log_scr(~J.(hap_col) & J.bin==b); xN=xN(isfinite(xN));
        xH = J.log_scr( J.(hap_col) & J.bin==b); xH=xH(isfinite(xH));
        if numel(xN)<3||numel(xH)<3
            rows(end+1,:) = {b,numel(xN),numel(xH),NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN};
            nexttile; title(sprintf('L%d B%d\ninsufficient',lv,b),'FontSize',6); continue;
        end
        sdN=std(xN); sdH=std(xH);
        p_lev=local_levene(xN,xH);
        [~,p_mu]=ttest2(xH,xN,'Vartype','unequal');
        sp=sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
        d=(mean(xH)-mean(xN))/sp*(1-3/(4*(numel(xN)+numel(xH)-2)-1));
        fprintf('  Bin%d [N:%.3f-%.3fg H:%.3f-%.3fg] | nN=%d nH=%d | SD_N=%.3f SD_H=%.3f ratio=%.3f | Lev_p=%.4g mu_p=%.4g d=%.3f\n',...
            b,eN(b),eN(b+1),eH(b),eH(b+1),numel(xN),numel(xH),sdN,sdH,sdN/sdH,p_lev,p_mu,d);
        rows(end+1,:) = {b,numel(xN),numel(xH),mean(xN),mean(xH),sdN,sdH,sdN/sdH,p_lev,p_mu,d};

        nexttile; hold on;
        local_violin(xN,1,CN); local_violin(xH,2,CH);
        errorbar(1,mean(xN),std(xN)/sqrt(numel(xN))*1.96,'o','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',6,'HandleVisibility','off');
        errorbar(2,mean(xH),std(xH)/sqrt(numel(xH))*1.96,'o','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',6,'HandleVisibility','off');
        ymax=max([xN;xH]); ymin=min([xN;xH]); rng=max(ymax-ymin,1e-9);
        sig=local_stars(p_lev);
        if ~isempty(sig)
            yt=ymax+0.05*rng; plot([1 2],[yt yt],'k-','LineWidth',1,'HandleVisibility','off');
            text(1.5,yt+0.03*rng,sig,'HorizontalAlignment','center','FontSize',11);
        end
        xticks([1 2]); xticklabels({'NHF','HF'});
        if b==1, ylabel(sprintf('L%d\nlog(SCR+%.3f)',lv,offset_scr),'FontSize',7); end
        title(sprintf('Bin%d\n[N:%.2f-%.2fg]\n[H:%.2f-%.2fg]\nSD_N=%.3f SD_H=%.3f\np_{Lev}=%s', ...
            b,eN(b),eN(b+1),eH(b),eH(b+1),sdN,sdH,local_pstr(p_lev)),'FontSize',5.5);
        grid on; xlim([0.5 2.5]);
    end

    T_h2 = cell2table(rows,'VariableNames',{'bin','n_N','n_H','mean_N','mean_H','sd_N','sd_H','ratio_sd','p_levene','p_mean','cohens_d'});
    valid = isfinite(T_h2.p_levene);
    if any(valid)
        T_h2.p_levene_fdr = nan(4,1); T_h2.p_mean_fdr = nan(4,1);
        T_h2.p_levene_fdr(valid) = mafdr(T_h2.p_levene(valid),'BHFDR',true);
        T_h2.p_mean_fdr(valid)   = mafdr(T_h2.p_mean(valid),'BHFDR',true);
    end
    all_results.training.(sprintf('L%d',lv)) = struct('T',T_h2,'edges_N',eN,'edges_H',eH);
end
exportgraphics(fig_tr,fullfile(fig_dir,'h2_scr_training_per_level.png'),'Resolution',180);

%% Baseline: same level compared across BL1 and BL2
fprintf('\n=== BASELINE: H2 per level, BL1 vs BL2 ===\n');

fig_bl = figure('Position',[50 50 1800 700]);
tl_bl  = tiledlayout(2,5,'TileSpacing','compact','Padding','compact');
title(tl_bl,'H2 — Baseline: log(phasic SCR amplitude) by peak\_accel\_g bin — same level, BL1 vs BL2 (group-specific quartiles per phase)', ...
    'FontWeight','bold','FontSize',10);

for lv = levels
    for bi = 1:2
        bl_phase = sprintf('Baseline%d',bi);
        J = J_all(strcmp(J_all.phase, bl_phase) & J_all.level==lv & isfinite(J_all.peak_accel_g_nidaq),:);
        fprintf('\n%s L%d: N=%d (NHF=%d HF=%d)\n',bl_phase,lv,height(J),sum(~J.(hap_col)),sum(J.(hap_col)));
        if height(J)<10, nexttile; title(sprintf('%s L%d\nno data',bl_phase,lv),'FontSize',7); continue; end

        eN = quantile(J.peak_accel_g_nidaq(~J.(hap_col)), qp);
        eH = quantile(J.peak_accel_g_nidaq( J.(hap_col)), qp);
        [~,~,bN] = histcounts(J.peak_accel_g_nidaq(~J.(hap_col)), eN);
        [~,~,bH] = histcounts(J.peak_accel_g_nidaq( J.(hap_col)), eH);
        J.bin = zeros(height(J),1);
        J.bin(~J.(hap_col)) = bN; J.bin(J.(hap_col)) = bH;

        rows = {};
        for b = 1:4
            xN = J.log_scr(~J.(hap_col) & J.bin==b); xN=xN(isfinite(xN));
            xH = J.log_scr( J.(hap_col) & J.bin==b); xH=xH(isfinite(xH));
            if numel(xN)<3||numel(xH)<3
                rows(end+1,:) = {b,numel(xN),numel(xH),NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN};
                continue;
            end
            sdN=std(xN); sdH=std(xH);
            p_lev=local_levene(xN,xH);
            [~,p_mu]=ttest2(xH,xN,'Vartype','unequal');
            sp=sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
            d=(mean(xH)-mean(xN))/sp*(1-3/(4*(numel(xN)+numel(xH)-2)-1));
            rows(end+1,:) = {b,numel(xN),numel(xH),mean(xN),mean(xH),sdN,sdH,sdN/sdH,p_lev,p_mu,d};
            fprintf('  Bin%d | nN=%d nH=%d | SD_N=%.3f SD_H=%.3f ratio=%.3f | Lev_p=%.4g d=%.3f\n',...
                b,numel(xN),numel(xH),sdN,sdH,sdN/sdH,p_lev,d);
        end

        T_h2=cell2table(rows,'VariableNames',{'bin','n_N','n_H','mean_N','mean_H','sd_N','sd_H','ratio_sd','p_levene','p_mean','cohens_d'});
        valid=isfinite(T_h2.p_levene);
        if any(valid)
            T_h2.p_levene_fdr=nan(4,1); T_h2.p_mean_fdr=nan(4,1);
            T_h2.p_levene_fdr(valid)=mafdr(T_h2.p_levene(valid),'BHFDR',true);
            T_h2.p_mean_fdr(valid)  =mafdr(T_h2.p_mean(valid),'BHFDR',true);
        end
        all_results.baseline.(sprintf('%s_L%d',bl_phase,lv)) = struct('T',T_h2,'edges_N',eN,'edges_H',eH);

        % summary SD ratio panel for this phase x level
        nexttile; hold on;
        ratio_vals = T_h2.ratio_sd;
        fdr_vals   = T_h2.p_levene_fdr;
        bh=bar(1:4,ratio_vals,0.6); bh.FaceColor='flat';
        for b=1:4
            if isnan(ratio_vals(b)), continue; end
            bh.CData(b,:)=local_ternary(~isnan(fdr_vals(b))&&fdr_vals(b)<0.05,[0.3 0.6 0.3],[0.7 0.7 0.7]);
            sig=local_stars(fdr_vals(b));
            if ~isempty(sig), text(b,ratio_vals(b)+0.05,sig,'HorizontalAlignment','center','FontSize',10); end
        end
        yline(1,'r--','LineWidth',1.5,'HandleVisibility','off');
        set(gca,'XTick',1:4,'FontSize',7); xlabel('Bin (peak\_accel\_g quartile)','FontSize',7);
        ylabel('SD_{NHF}/SD_{HF}','FontSize',7);
        title(sprintf('%s L%d\n(green=FDR sig)',bl_phase,lv),'FontSize',8);
        ylim([0 max(2,max(ratio_vals(isfinite(ratio_vals)))+0.3)]); grid on;
    end
end
exportgraphics(fig_bl,fullfile(fig_dir,'h2_scr_baseline_per_level.png'),'Resolution',180);
%% Test phases: H2 per phase (Test1 and Test2 are single acquisitions, no level structure)
fprintf('\n=== TEST PHASES: H2 ===\n');

fig_te = figure('Position',[50 50 1000 500]);
tl_te  = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
title(tl_te,'H2 — Test phases: log(phasic SCR) SD ratio by peak\_accel\_g bin (group-specific quartiles)', ...
    'FontWeight','bold','FontSize',10);

for ti = 1:2
    te_phase = sprintf('Test%d',ti);
    J = J_all(strcmp(J_all.phase,te_phase) & isfinite(J_all.peak_accel_g_nidaq),:);
    fprintf('\n%s: N=%d (NHF=%d HF=%d)\n',te_phase,height(J),sum(~J.(hap_col)),sum(J.(hap_col)));

    if height(J)<10
        nexttile;
        text(0.5,0.5,sprintf('%s\ninsufficient data\nn=%d',te_phase,height(J)), ...
            'HorizontalAlignment','center','Units','normalized','FontSize',10);
        axis off; continue;
    end

    eN = quantile(J.peak_accel_g_nidaq(~J.(hap_col)), qp);
    eH = quantile(J.peak_accel_g_nidaq( J.(hap_col)), qp);
    [~,~,bN] = histcounts(J.peak_accel_g_nidaq(~J.(hap_col)), eN);
    [~,~,bH] = histcounts(J.peak_accel_g_nidaq( J.(hap_col)), eH);
    J.bin = zeros(height(J),1);
    J.bin(~J.(hap_col)) = bN; J.bin(J.(hap_col)) = bH;

    fprintf('  NHF edges (g): '); fprintf('%.3f  ',eN); fprintf('\n');
    fprintf('  HF  edges (g): '); fprintf('%.3f  ',eH); fprintf('\n');

    rows = {};
    for b = 1:4
        xN = J.log_scr(~J.(hap_col) & J.bin==b); xN=xN(isfinite(xN));
        xH = J.log_scr( J.(hap_col) & J.bin==b); xH=xH(isfinite(xH));
        if numel(xN)<3||numel(xH)<3
            rows(end+1,:)={b,numel(xN),numel(xH),NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN};
            fprintf('  Bin%d: insufficient (nN=%d nH=%d)\n',b,numel(xN),numel(xH));
            continue;
        end
        sdN=std(xN); sdH=std(xH);
        p_lev=local_levene(xN,xH);
        [~,p_mu]=ttest2(xH,xN,'Vartype','unequal');
        sp=sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
        d=(mean(xH)-mean(xN))/sp*(1-3/(4*(numel(xN)+numel(xH)-2)-1));
        fprintf('  Bin%d [N:%.3f-%.3fg H:%.3f-%.3fg] | nN=%d nH=%d | SD_N=%.3f SD_H=%.3f ratio=%.3f | Lev_p=%.4g d=%.3f\n',...
            b,eN(b),eN(b+1),eH(b),eH(b+1),numel(xN),numel(xH),sdN,sdH,sdN/sdH,p_lev,d);
        rows(end+1,:)={b,numel(xN),numel(xH),mean(xN),mean(xH),sdN,sdH,sdN/sdH,p_lev,p_mu,d};
    end

    T_h2=cell2table(rows,'VariableNames',{'bin','n_N','n_H','mean_N','mean_H','sd_N','sd_H','ratio_sd','p_levene','p_mean','cohens_d'});
    valid=isfinite(T_h2.p_levene);
    if any(valid)
        T_h2.p_levene_fdr=nan(4,1); T_h2.p_mean_fdr=nan(4,1);
        T_h2.p_levene_fdr(valid)=mafdr(T_h2.p_levene(valid),'BHFDR',true);
        T_h2.p_mean_fdr(valid)  =mafdr(T_h2.p_mean(valid),'BHFDR',true);
    end
    all_results.test.(te_phase) = struct('T',T_h2,'edges_N',eN,'edges_H',eH);

    % SD ratio bar panel
    nexttile; hold on;
    ratio_vals=T_h2.ratio_sd; fdr_vals=T_h2.p_levene_fdr;
    bh=bar(1:4,ratio_vals,0.6); bh.FaceColor='flat';
    for b=1:4
        if isnan(ratio_vals(b)), continue; end
        bh.CData(b,:)=local_ternary(~isnan(fdr_vals(b))&&fdr_vals(b)<0.05,[0.3 0.6 0.3],[0.7 0.7 0.7]);
        sig=local_stars(fdr_vals(b));
        if ~isempty(sig), text(b,ratio_vals(b)+0.05,sig,'HorizontalAlignment','center','FontSize',12); end
    end
    yline(1,'r--','LineWidth',1.5,'HandleVisibility','off');
    set(gca,'XTick',1:4,'FontSize',9);
    xlabel('Bin (peak\_accel\_g quartile)','FontSize',9);
    ylabel('SD_{NHF}/SD_{HF}','FontSize',9);
    title(sprintf('%s — SD ratio per intensity bin\n[NHF edges: %.2f %.2f %.2f %.2f g]\n[HF edges: %.2f %.2f %.2f %.2f g]', ...
        te_phase,eN(1),eN(2),eN(3),eN(4),eH(1),eH(2),eH(3),eH(4)),'FontSize',8);
    yl_max=max(2,max(ratio_vals(isfinite(ratio_vals)),[],'omitnan')+0.3);
    ylim([0 yl_max]); grid on; box on;

    % also print FDR table
    fprintf('  FDR-corrected Levene results:\n');
    for b=1:4
        if isnan(T_h2.p_levene_fdr(b)), continue; end
        fprintf('    Bin%d: ratio=%.3f p_Lev_FDR=%.4f %s\n', ...
            b,T_h2.ratio_sd(b),T_h2.p_levene_fdr(b),local_stars(T_h2.p_levene_fdr(b)));
    end
end
exportgraphics(fig_te,fullfile(fig_dir,'h2_scr_test_phases.png'),'Resolution',180);
%% C3 LMM: peak_accel_g_nidaq intensity slope -> log(SCR)
fprintf('\n=== C3 LMM: peak_accel_g_nidaq (within-subject z) -> log(SCR) ===\n');
J_lmm = J_all(strcmp(J_all.phase_type,'training'),:);
subj_u = unique(J_lmm.subject);
J_lmm.accel_z = nan(height(J_lmm),1);
for si=1:numel(subj_u)
    s=subj_u{si}; idx=strcmp(J_lmm.subject,s); v=J_lmm.peak_accel_g_nidaq(idx);
    J_lmm.accel_z(idx)=(v-mean(v,'omitnan'))./(std(v,'omitnan')+1e-12);
end
J_lmm.haptic_cat  = categorical(J_lmm.(hap_col),logical([0 1]),{'N','H'});
J_lmm.subject_cat = categorical(J_lmm.subject);
lme_c3=fitlme(J_lmm,'log_scr ~ accel_z * haptic_cat + (1|subject_cat)', ...
    'FitMethod','REML','DummyVarCoding','reference','Verbose',false);
fprintf('\nC3: peak_accel_g_nidaq -> log(SCR+offset)\n');
disp(lme_c3.Coefficients(:,{'Name','Estimate','SE','tStat','pValue'}));
disp(anova(lme_c3));

save(fullfile(cfg.output_root,'h2_eda_accel_bins_results.mat'),'all_results','lme_c3','offset_scr');
fprintf('\nSaved h2_eda_accel_bins_results.mat\n');

function hap_col=local_find_haptic(T)
    for k={'haptic','haptic_x','haptic_y'}
        if ismember(k{1},T.Properties.VariableNames)&&islogical(T.(k{1})), hap_col=k{1}; return; end
    end
    error('No logical haptic column. Available: %s',strjoin(T.Properties.VariableNames,', '));
end
function p=local_levene(x,y)
    [~,p]=ttest2(abs(x-median(x)),abs(y-median(y)),'Vartype','unequal');
end
function local_violin(x,xpos,col)
    if numel(x)<3,scatter(xpos+(rand(numel(x),1)-0.5)*0.2,x,18,col,'filled','MarkerFaceAlpha',0.4,'HandleVisibility','off'); return; end
    [f,xi]=ksdensity(x,'NumPoints',100,'BoundaryCorrection','reflection');
    f=f/max(f)*0.35;
    patch([xpos+f fliplr(xpos-f)],[xi fliplr(xi)],col,'FaceAlpha',0.25,'EdgeColor',col,'LineWidth',0.8,'HandleVisibility','off');
    scatter(xpos+(rand(numel(x),1)-0.5)*0.15,x,10,col,'filled','MarkerFaceAlpha',0.3,'HandleVisibility','off');
end
function s=local_stars(p)
    if isnan(p)||p>0.05,s=''; elseif p>0.01,s='*'; elseif p>0.001,s='**'; else,s='***'; end
end
function s=local_pstr(p)
    if isnan(p),s='n/a'; elseif p<0.001,s=sprintf('%.2e',p); else,s=sprintf('%.3f',p); end
end
function out=local_ternary(c,a,b), if c,out=a; else,out=b; end, end