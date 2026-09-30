%% h3_pupil_per_level_accel_bins.m
% Pupil H3: collision-locked pupil dilation variance by peak_accel_g_nidaq bin
% SAME bin structure as EDA H2: per-level, group-specific peak_accel_g_nidaq quartiles

clear; clc; close all; cfg = config();
CN = [64 96 179]/255; CH = [139 82 168]/255;
fig_dir = fullfile(cfg.output_root,'figures');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

CI  = load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact'); T_CI = CI.T_impact;
EYE = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T_coll'); Yc = EYE.T_coll;

qp = [0 0.25 0.50 0.75 1.0];

% Join 1: training
T_CI_tr = T_CI(strcmp(T_CI.phase_type,'training'),:);
Yc_tr   = Yc(strcmp(Yc.phase_type,'training'),:);
J_train = innerjoin(T_CI_tr, Yc_tr, ...
    'Keys',{'subject','phase','repetition','collision_idx'}, ...
    'RightVariables',{'pupil_response_norm'});

% Join 2: baseline and test
T_CI_bt = T_CI(~strcmp(T_CI.phase_type,'training'),:);
Yc_bt   = Yc(~strcmp(Yc.phase_type,'training'),:);
J_other = innerjoin(T_CI_bt, Yc_bt, ...
    'Keys',{'subject','phase','acquisition','collision_idx'}, ...
    'RightVariables',{'pupil_response_norm'});
J_other.repetition = nan(height(J_other),1);

J_all = [J_train; J_other];
hap_col = local_find_haptic(J_all);

fprintf('Joined rows by phase_type:\n');
for pt={'training','baseline','test'}
    fprintf('  %s: %d\n',pt{1},sum(strcmp(J_all.phase_type,pt{1})));
end

J_all = J_all(isfinite(J_all.pupil_response_norm) & isfinite(J_all.peak_accel_g_nidaq),:);
fprintf('After cleaning: %d rows\n',height(J_all));

all_results = struct();
levels = 1:5;

%% Training: per level
fprintf('\n=== TRAINING: Pupil H3 per level ===\n');
fig_tr = figure('Position',[50 50 1800 900]);
tl_tr  = tiledlayout(4,5,'TileSpacing','compact','Padding','compact');
title(tl_tr,'Pupil H3 Training — pupil dilation variance by peak\_accel\_g bin per level (group-specific quartiles)', ...
    'FontWeight','bold','FontSize',10);

for lv = levels
    J = J_all(strcmp(J_all.phase_type,'training') & J_all.level==lv,:);
    fprintf('\nL%d: N=%d (NHF=%d HF=%d)\n',lv,height(J),sum(~J.(hap_col)),sum(J.(hap_col)));
    if height(J)<10, for b=1:4, nexttile; end; continue; end

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
        xN = J.pupil_response_norm(~J.(hap_col) & J.bin==b); xN=xN(isfinite(xN));
        xH = J.pupil_response_norm( J.(hap_col) & J.bin==b); xH=xH(isfinite(xH));
        if numel(xN)<3||numel(xH)<3
            rows(end+1,:)={b,numel(xN),numel(xH),NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN};
            nexttile; title(sprintf('L%d B%d\ninsufficient',lv,b),'FontSize',6); continue;
        end
        sdN=std(xN); sdH=std(xH);
        p_lev=local_levene(xN,xH);
        [~,p_mu]=ttest2(xH,xN,'Vartype','unequal');
        sp=sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
        d=(mean(xH)-mean(xN))/sp*(1-3/(4*(numel(xN)+numel(xH)-2)-1));
        fprintf('  Bin%d [N:%.3f-%.3fg H:%.3f-%.3fg] | nN=%d nH=%d | SD_N=%.3f SD_H=%.3f ratio=%.3f | Lev_p=%.4g mu_p=%.4g d=%.3f\n',...
            b,eN(b),eN(b+1),eH(b),eH(b+1),numel(xN),numel(xH),sdN,sdH,sdN/sdH,p_lev,p_mu,d);
        rows(end+1,:)={b,numel(xN),numel(xH),mean(xN),mean(xH),sdN,sdH,sdN/sdH,p_lev,p_mu,d};

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
        if b==1, ylabel(sprintf('L%d\nPupil dilation\n(fraction of rest)',lv),'FontSize',7); end
        title(sprintf('Bin%d\n[N:%.2f-%.2fg]\n[H:%.2f-%.2fg]\nSD_N=%.3f SD_H=%.3f\np_{Lev}=%s',...
            b,eN(b),eN(b+1),eH(b),eH(b+1),sdN,sdH,local_pstr(p_lev)),'FontSize',5.5);
        grid on; xlim([0.5 2.5]);
    end

    T_h3=cell2table(rows,'VariableNames',{'bin','n_N','n_H','mean_N','mean_H','sd_N','sd_H','ratio_sd','p_levene','p_mean','cohens_d'});
    valid=isfinite(T_h3.p_levene);
    if any(valid)
        T_h3.p_levene_fdr=nan(4,1); T_h3.p_mean_fdr=nan(4,1);
        T_h3.p_levene_fdr(valid)=mafdr(T_h3.p_levene(valid),'BHFDR',true);
        T_h3.p_mean_fdr(valid)  =mafdr(T_h3.p_mean(valid),'BHFDR',true);
    end
    all_results.training.(sprintf('L%d',lv))=struct('T',T_h3,'edges_N',eN,'edges_H',eH);
end
exportgraphics(fig_tr,fullfile(fig_dir,'h3_pupil_training_per_level.png'),'Resolution',180);

%% Baseline: per level
fprintf('\n=== BASELINE: Pupil H3 per level ===\n');
fig_bl = figure('Position',[50 50 1600 600]);
tl_bl  = tiledlayout(2,5,'TileSpacing','compact','Padding','compact');
title(tl_bl,'Pupil H3 Baseline — pupil dilation SD ratio by peak\_accel\_g bin','FontWeight','bold','FontSize',10);

for bi=1:2
    bl_phase=sprintf('Baseline%d',bi);
    for lv=levels
        J=J_all(strcmp(J_all.phase,bl_phase)&J_all.level==lv,:);
        fprintf('\n%s L%d: N=%d (NHF=%d HF=%d)\n',bl_phase,lv,height(J),sum(~J.(hap_col)),sum(J.(hap_col)));
        nexttile; hold on;
        if height(J)<6
            text(0.5,0.5,sprintf('%s L%d\nn=%d',bl_phase,lv,height(J)),'HorizontalAlignment','center','Units','normalized','FontSize',8); axis off; continue;
        end
        eN=quantile(J.peak_accel_g_nidaq(~J.(hap_col)),qp); eH=quantile(J.peak_accel_g_nidaq(J.(hap_col)),qp);
        [~,~,bN]=histcounts(J.peak_accel_g_nidaq(~J.(hap_col)),eN); [~,~,bH]=histcounts(J.peak_accel_g_nidaq(J.(hap_col)),eH);
        J.bin=zeros(height(J),1); J.bin(~J.(hap_col))=bN; J.bin(J.(hap_col))=bH;
        rows={};
        for b=1:4
            xN=J.pupil_response_norm(~J.(hap_col)&J.bin==b); xN=xN(isfinite(xN));
            xH=J.pupil_response_norm(J.(hap_col)&J.bin==b);  xH=xH(isfinite(xH));
            if numel(xN)<3||numel(xH)<3, rows(end+1,:)={b,numel(xN),numel(xH),NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN}; continue; end
            sdN=std(xN); sdH=std(xH); p_lev=local_levene(xN,xH); [~,p_mu]=ttest2(xH,xN,'Vartype','unequal');
            sp=sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
            d=(mean(xH)-mean(xN))/sp*(1-3/(4*(numel(xN)+numel(xH)-2)-1));
            fprintf('  Bin%d | nN=%d nH=%d | SD_N=%.3f SD_H=%.3f ratio=%.3f | Lev_p=%.4g d=%.3f\n',b,numel(xN),numel(xH),sdN,sdH,sdN/sdH,p_lev,d);
            rows(end+1,:)={b,numel(xN),numel(xH),mean(xN),mean(xH),sdN,sdH,sdN/sdH,p_lev,p_mu,d};
        end
        T_h3=cell2table(rows,'VariableNames',{'bin','n_N','n_H','mean_N','mean_H','sd_N','sd_H','ratio_sd','p_levene','p_mean','cohens_d'});
        valid=isfinite(T_h3.p_levene);
        if any(valid)
            T_h3.p_levene_fdr=nan(4,1); T_h3.p_mean_fdr=nan(4,1);
            T_h3.p_levene_fdr(valid)=mafdr(T_h3.p_levene(valid),'BHFDR',true);
            T_h3.p_mean_fdr(valid)  =mafdr(T_h3.p_mean(valid),'BHFDR',true);
        end
        all_results.baseline.(sprintf('%s_L%d',bl_phase,lv))=struct('T',T_h3,'edges_N',eN,'edges_H',eH);
        ratio_vals=T_h3.ratio_sd; fdr_vals=T_h3.p_levene_fdr;
        bh=bar(1:4,ratio_vals,0.6); bh.FaceColor='flat';
        for b=1:4
            if isnan(ratio_vals(b)), continue; end
            bh.CData(b,:)=local_ternary(~isnan(fdr_vals(b))&&fdr_vals(b)<0.05,[0.3 0.6 0.3],[0.7 0.7 0.7]);
            sig=local_stars(fdr_vals(b));
            if ~isempty(sig), text(b,ratio_vals(b)+0.02,sig,'HorizontalAlignment','center','FontSize',10); end
        end
        yline(1,'r--','LineWidth',1.5,'HandleVisibility','off');
        set(gca,'XTick',1:4,'FontSize',7); xlabel('Bin (g)','FontSize',7); ylabel('SD_{NHF}/SD_{HF}','FontSize',7);
        title(sprintf('%s L%d',bl_phase,lv),'FontSize',8);
        yl_max=max(2,max(ratio_vals(isfinite(ratio_vals)),[],'omitnan')+0.3); ylim([0 yl_max]); grid on;
    end
end
exportgraphics(fig_bl,fullfile(fig_dir,'h3_pupil_baseline_per_level.png'),'Resolution',180);

%% Test phases
fprintf('\n=== TEST PHASES: Pupil H3 ===\n');
fig_te=figure('Position',[50 50 1000 500]);
tl_te=tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
title(tl_te,'Pupil H3 Test — pupil dilation SD ratio by peak\_accel\_g bin','FontWeight','bold','FontSize',10);

for ti=1:2
    te_phase=sprintf('Test%d',ti);
    J=J_all(strcmp(J_all.phase,te_phase)&isfinite(J_all.peak_accel_g_nidaq),:);
    fprintf('\n%s: N=%d (NHF=%d HF=%d)\n',te_phase,height(J),sum(~J.(hap_col)),sum(J.(hap_col)));
    nexttile; hold on;
    if height(J)<6
        text(0.5,0.5,sprintf('%s\nn=%d',te_phase,height(J)),'HorizontalAlignment','center','Units','normalized'); axis off; continue;
    end
    eN=quantile(J.peak_accel_g_nidaq(~J.(hap_col)),qp); eH=quantile(J.peak_accel_g_nidaq(J.(hap_col)),qp);
    [~,~,bN]=histcounts(J.peak_accel_g_nidaq(~J.(hap_col)),eN); [~,~,bH]=histcounts(J.peak_accel_g_nidaq(J.(hap_col)),eH);
    J.bin=zeros(height(J),1); J.bin(~J.(hap_col))=bN; J.bin(J.(hap_col))=bH;
    rows={};
    for b=1:4
        xN=J.pupil_response_norm(~J.(hap_col)&J.bin==b); xN=xN(isfinite(xN));
        xH=J.pupil_response_norm(J.(hap_col)&J.bin==b);  xH=xH(isfinite(xH));
        if numel(xN)<3||numel(xH)<3, rows(end+1,:)={b,numel(xN),numel(xH),NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN}; continue; end
        sdN=std(xN); sdH=std(xH); p_lev=local_levene(xN,xH); [~,p_mu]=ttest2(xH,xN,'Vartype','unequal');
        sp=sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
        d=(mean(xH)-mean(xN))/sp*(1-3/(4*(numel(xN)+numel(xH)-2)-1));
        fprintf('  Bin%d [N:%.3f-%.3fg H:%.3f-%.3fg] | nN=%d nH=%d | SD_N=%.3f SD_H=%.3f ratio=%.3f | Lev_p=%.4g d=%.3f\n',...
            b,eN(b),eN(b+1),eH(b),eH(b+1),numel(xN),numel(xH),sdN,sdH,sdN/sdH,p_lev,d);
        rows(end+1,:)={b,numel(xN),numel(xH),mean(xN),mean(xH),sdN,sdH,sdN/sdH,p_lev,p_mu,d};
    end
    T_h3=cell2table(rows,'VariableNames',{'bin','n_N','n_H','mean_N','mean_H','sd_N','sd_H','ratio_sd','p_levene','p_mean','cohens_d'});
    valid=isfinite(T_h3.p_levene);
    if any(valid)
        T_h3.p_levene_fdr=nan(4,1); T_h3.p_mean_fdr=nan(4,1);
        T_h3.p_levene_fdr(valid)=mafdr(T_h3.p_levene(valid),'BHFDR',true);
        T_h3.p_mean_fdr(valid)  =mafdr(T_h3.p_mean(valid),'BHFDR',true);
    end
    all_results.test.(te_phase)=struct('T',T_h3,'edges_N',eN,'edges_H',eH);
    ratio_vals=T_h3.ratio_sd; fdr_vals=T_h3.p_levene_fdr;
    bh=bar(1:4,ratio_vals,0.6); bh.FaceColor='flat';
    for b=1:4
        if isnan(ratio_vals(b)), continue; end
        bh.CData(b,:)=local_ternary(~isnan(fdr_vals(b))&&fdr_vals(b)<0.05,[0.3 0.6 0.3],[0.7 0.7 0.7]);
        sig=local_stars(fdr_vals(b));
        if ~isempty(sig), text(b,ratio_vals(b)+0.02,sig,'HorizontalAlignment','center','FontSize',12); end
    end
    yline(1,'r--','LineWidth',1.5,'HandleVisibility','off');
    set(gca,'XTick',1:4,'FontSize',9); xlabel('Bin (peak\_accel\_g quartile)','FontSize',9); ylabel('SD_{NHF}/SD_{HF}','FontSize',9);
    title(sprintf('%s\n[NHF: %.2f %.2f %.2f %.2f g]\n[HF: %.2f %.2f %.2f %.2f g]',...
        te_phase,eN(1),eN(2),eN(3),eN(4),eH(1),eH(2),eH(3),eH(4)),'FontSize',8);
    yl_max=max(2,max(ratio_vals(isfinite(ratio_vals)),[],'omitnan')+0.3); ylim([0 yl_max]); grid on; box on;
end
exportgraphics(fig_te,fullfile(fig_dir,'h3_pupil_test_phases.png'),'Resolution',180);

save(fullfile(cfg.output_root,'h3_pupil_accel_bins_results.mat'),'all_results');
fprintf('\nSaved h3_pupil_accel_bins_results.mat\n');

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