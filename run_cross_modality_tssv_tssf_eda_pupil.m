function results = cross_modality_tssv_tssf_eda_pupil(cfg)

CN = [64 96 179]/255; CH = [139 82 168]/255;
fig_dir = fullfile(cfg.output_root,'figures');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

FV  = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); FV=FV.T;
EDA = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T','T_coll'); Eb=EDA.T; Ec=EDA.T_coll;
EYE = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T_coll'); Yc=EYE.T_coll;
CI  = load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact'); CI=CI.T_impact;

results = struct();

%% C1 + C2
fprintf('\n=== C1/C2: whole-trial mechanical -> tonic SCL ===\n');
FV_tr = FV(strcmp(FV.phase_type,'training'),:);
Eb_tr = Eb(strcmp(Eb.phase_type,'training') & isfinite(Eb.scl_mean_bc),:);
J_bl  = innerjoin(FV_tr, Eb_tr,'Keys',{'subject','phase','repetition'},'RightVariables',{'scl_mean_bc'});
J_bl  = J_bl(isfinite(J_bl.scl_mean_bc),:);
fprintf('Block-level joined rows: %d\n',height(J_bl));

for mi = 1:2
    oc  = local_ternary(mi==1,'tssv','tssf');
    lbl = local_ternary(mi==1,'log-TSSV','log-TSSF');
    Jm  = J_bl(isfinite(J_bl.(oc)) & J_bl.(oc)>0,:);
    Jm.log_mech = log(Jm.(oc));
    subj_u=unique(Jm.subject); Jm.mech_z=nan(height(Jm),1);
    for si=1:numel(subj_u)
        s=subj_u{si}; idx=strcmp(Jm.subject,s); v=Jm.log_mech(idx);
        Jm.mech_z(idx)=(v-mean(v,'omitnan'))./(std(v,'omitnan')+1e-12);
    end
    Jm.haptic_cat=categorical(Jm.group,{'N','H'}); Jm.subject_cat=categorical(Jm.subject);
    fprintf('\n--- C%d: %s -> tonic SCL ---\n',mi,lbl);
    lme=fitlme(Jm,'scl_mean_bc ~ mech_z * haptic_cat + (1|subject_cat)', ...
        'FitMethod','REML','DummyVarCoding','reference','Verbose',false);
    disp(lme.Coefficients(:,{'Name','Estimate','SE','tStat','pValue'})); disp(anova(lme));
    rho_N=nan(numel(subj_u),1); rho_H=nan(numel(subj_u),1); is_H=false(numel(subj_u),1);
    for si=1:numel(subj_u)
        s=subj_u{si}; Js=Jm(strcmp(Jm.subject,s),:); is_H(si)=any(Js.haptic);
        if height(Js)<5, continue; end
        r=corr(Js.log_mech,Js.scl_mean_bc,'Type','Spearman','Rows','complete');
        if is_H(si), rho_H(si)=r; else, rho_N(si)=r; end
    end
    rN=rho_N(~is_H&isfinite(rho_N)); rH=rho_H(is_H&isfinite(rho_H));
    [~,p_rN0]=ttest(rN); [~,p_rH0]=ttest(rH); [~,p_rNH]=ttest2(rN,rH,'Vartype','unequal');
    fprintf('NHF: n=%d mean_rho=%.3f p_vs0=%.4f\n',numel(rN),mean(rN),p_rN0);
    fprintf('HF:  n=%d mean_rho=%.3f p_vs0=%.4f\n',numel(rH),mean(rH),p_rH0);
    fprintf('NHF vs HF: p=%.4f\n',p_rNH);
    results.(sprintf('C%d',mi))=struct('lme',lme,'rho_N',rN,'rho_H',rH,'p_rN0',p_rN0,'p_rH0',p_rH0,'p_rNH',p_rNH);

    fig=figure('Position',[50 50 1100 440]);
    tl=tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
    title(tl,sprintf('C%d: %s vs tonic SCL (within-subject z-scored)',mi,lbl),'FontWeight','bold','FontSize',11);
    nexttile; hold on;
    for grp=[false true]
        Jg=Jm(Jm.haptic==grp,:); col=local_ternary(grp,CH,CN); lg=local_ternary(grp,'HF','NHF');
        scatter(Jg.mech_z,Jg.scl_mean_bc,8,col,'filled','MarkerFaceAlpha',0.12,'HandleVisibility','off');
        ok=isfinite(Jg.mech_z)&isfinite(Jg.scl_mean_bc);
        plot([-3 3],polyval(polyfit(Jg.mech_z(ok),Jg.scl_mean_bc(ok),1),[-3 3]),'-','Color',col,'LineWidth',2,'DisplayName',lg);
    end
    xlabel(sprintf('%s (within-subject z)',lbl),'FontSize',9); ylabel('Tonic SCL above resting (\muS)','FontSize',9);
    legend('Location','best','FontSize',9); grid on; box on;
    nexttile; hold on;
    scatter(ones(numel(rN),1)+(rand(numel(rN),1)-0.5)*0.2,rN,25,CN,'filled','MarkerFaceAlpha',0.5,'HandleVisibility','off');
    scatter(2*ones(numel(rH),1)+(rand(numel(rH),1)-0.5)*0.2,rH,25,CH,'filled','MarkerFaceAlpha',0.5,'HandleVisibility','off');
    errorbar(1,mean(rN),std(rN)/sqrt(numel(rN))*1.96,'o','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',9,'DisplayName','NHF');
    errorbar(2,mean(rH),std(rH)/sqrt(numel(rH))*1.96,'o','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',9,'DisplayName','HF');
    yline(0,'k--','LineWidth',1,'HandleVisibility','off');
    xticks([1 2]); xticklabels({'NHF','HF'});
    ylabel('Spearman \rho per subject','FontSize',9);
    title(sprintf('NHF vs0 p=%.3f  HF vs0 p=%.3f  NvsH p=%.3f',p_rN0,p_rH0,p_rNH),'FontSize',8);
    grid on; xlim([0.5 2.5]);
    nexttile; hold on;
    fe=dataset2table(lme.Coefficients); ests=fe.Estimate; ses=fe.SE; pvals=fe.pValue;
    for ki=1:numel(ests)
        col=local_ternary(pvals(ki)<0.05,[0.8 0.2 0.2],[0.5 0.5 0.5]);
        errorbar(ki,ests(ki),1.96*ses(ki),'o','Color',col,'MarkerFaceColor',col,'LineWidth',1.8,'MarkerSize',7,'HandleVisibility','off');
        sig=local_stars(pvals(ki));
        if ~isempty(sig), text(ki,ests(ki)+1.96*ses(ki)+0.003,sig,'HorizontalAlignment','center','FontSize',12,'Color',col); end
    end
    yline(0,'k--','LineWidth',1,'HandleVisibility','off');
    set(gca,'XTick',1:numel(ests),'XTickLabel',strrep(fe.Name,'_',' '),'XTickLabelRotation',45,'FontSize',7);
    ylabel('Estimate (\muS)','FontSize',9); title('LMM fixed effects','FontSize',9); grid on; box on;
    exportgraphics(fig,fullfile(fig_dir,sprintf('C%d_%s_vs_SCL.png',mi,oc)),'Resolution',180);
end

%% C3 + C4
CI_tr = CI(strcmp(CI.phase_type,'training'),:);

% detect haptic column name in CI after possible rename by innerjoin
hap_col_ci = local_find_haptic_col(CI_tr);
fprintf('\nUsing haptic column in CI: %s\n', hap_col_ci);

%% C3: impact_tssv -> EDA
fprintf('\n=== C3: impact_tssv -> EDA collision response ===\n');
J_eda = innerjoin(CI_tr, Ec,'Keys',{'subject','phase','repetition','collision_idx'},'RightVariables',{'scr_amp_local_bc'});
J_eda = J_eda(isfinite(J_eda.impact_tssv)&J_eda.impact_tssv>0&isfinite(J_eda.scr_amp_local_bc),:);
J_eda.log_itssv = log(J_eda.impact_tssv);
hap_c3 = local_find_haptic_col(J_eda);
fprintf('Joined rows: %d  haptic col: %s\n',height(J_eda),hap_c3);

[T_c3,J_eda] = local_variance_bins(J_eda,'log_itssv','scr_amp_local_bc',hap_c3,'bin_c3');
disp(T_c3(:,{'bin','n_N','n_H','mean_N','mean_H','sd_N','sd_H','ratio_sd','p_levene_fdr','p_mean_fdr','cohens_d'}));
results.C3.variance_table=T_c3;

subj_u=unique(J_eda.subject); J_eda.itssv_z=nan(height(J_eda),1);
for si=1:numel(subj_u)
    s=subj_u{si}; idx=strcmp(J_eda.subject,s); v=J_eda.log_itssv(idx);
    J_eda.itssv_z(idx)=(v-mean(v,'omitnan'))./(std(v,'omitnan')+1e-12);
end
J_eda.haptic_cat=categorical(J_eda.(hap_c3),logical([0 1]),{'N','H'}); J_eda.subject_cat=categorical(J_eda.subject);
fprintf('\n--- C3 LMM ---\n');
lme_c3=fitlme(J_eda,'scr_amp_local_bc ~ itssv_z * haptic_cat + (1|subject_cat)', ...
    'FitMethod','REML','DummyVarCoding','reference','Verbose',false);
disp(lme_c3.Coefficients(:,{'Name','Estimate','SE','tStat','pValue'})); disp(anova(lme_c3));
results.C3.lme=lme_c3;
local_plot_bins(J_eda,'bin_c3',hap_c3,'scr_amp_local_bc',T_c3, ...
    'EDA collision response (fraction of resting tonic SCL)', ...
    'C3: impact\_tssv -> EDA (group-specific intensity bins)', ...
    'Intensity bin (impact\_tssv)', lme_c3, CN, CH, fig_dir,'C3_impact_tssv_vs_EDA.png');

%% C4: impact_tssf -> pupil
fprintf('\n=== C4: impact_tssf -> pupil dilation ===\n');
J_pup = innerjoin(CI_tr, Yc,'Keys',{'subject','phase','repetition','collision_idx'},'RightVariables',{'pupil_response_norm'});
J_pup = J_pup(isfinite(J_pup.impact_tssf)&J_pup.impact_tssf>0&isfinite(J_pup.pupil_response_norm),:);
J_pup.log_itssf = log(J_pup.impact_tssf);
hap_c4 = local_find_haptic_col(J_pup);
fprintf('Joined rows: %d  haptic col: %s\n',height(J_pup),hap_c4);

[T_c4,J_pup] = local_variance_bins(J_pup,'log_itssf','pupil_response_norm',hap_c4,'bin_c4');
disp(T_c4(:,{'bin','n_N','n_H','mean_N','mean_H','sd_N','sd_H','ratio_sd','p_levene_fdr','p_mean_fdr','cohens_d'}));
results.C4.variance_table=T_c4;

subj_u=unique(J_pup.subject); J_pup.itssf_z=nan(height(J_pup),1);
for si=1:numel(subj_u)
    s=subj_u{si}; idx=strcmp(J_pup.subject,s); v=J_pup.log_itssf(idx);
    J_pup.itssf_z(idx)=(v-mean(v,'omitnan'))./(std(v,'omitnan')+1e-12);
end
J_pup.haptic_cat=categorical(J_pup.(hap_c4),logical([0 1]),{'N','H'}); J_pup.subject_cat=categorical(J_pup.subject);
fprintf('\n--- C4 LMM ---\n');
lme_c4=fitlme(J_pup,'pupil_response_norm ~ itssf_z * haptic_cat + (1|subject_cat)', ...
    'FitMethod','REML','DummyVarCoding','reference','Verbose',false);
disp(lme_c4.Coefficients(:,{'Name','Estimate','SE','tStat','pValue'})); disp(anova(lme_c4));
results.C4.lme=lme_c4;
local_plot_bins(J_pup,'bin_c4',hap_c4,'pupil_response_norm',T_c4, ...
    'Pupil dilation (fraction of resting diameter)', ...
    'C4: impact\_tssf -> pupil (group-specific intensity bins)', ...
    'Intensity bin (impact\_tssf)', lme_c4, CN, CH, fig_dir,'C4_impact_tssf_vs_pupil.png');

save(fullfile(cfg.output_root,'cross_modality_tssv_tssf_results.mat'),'results');
fprintf('\nSaved cross_modality_tssv_tssf_results.mat\n');
end

% -------------------------------------------------------------------------
function hap_col = local_find_haptic_col(T)
    candidates = {'haptic','haptic_x','haptic_y'};
    hap_col = '';
    for k = 1:numel(candidates)
        if ismember(candidates{k},T.Properties.VariableNames) && islogical(T.(candidates{k}))
            hap_col = candidates{k}; return;
        end
    end
    % fallback: any logical column with haptic in name
    vn = T.Properties.VariableNames;
    for k = 1:numel(vn)
        if contains(vn{k},'haptic') && islogical(T.(vn{k}))
            hap_col = vn{k}; return;
        end
    end
    error('Cannot find logical haptic column in table. Available: %s', strjoin(T.Properties.VariableNames,', '));
end

function [T_out,J] = local_variance_bins(J, pred_col, resp_col, hap_col, bin_col_name)
    qp=[0 0.25 0.50 0.75 1.0];
    edges_N=quantile(J.(pred_col)(~J.(hap_col)),qp);
    edges_H=quantile(J.(pred_col)( J.(hap_col)),qp);
    [~,~,binN]=histcounts(J.(pred_col)(~J.(hap_col)),edges_N);
    [~,~,binH]=histcounts(J.(pred_col)( J.(hap_col)),edges_H);
    J.(bin_col_name)=zeros(height(J),1);
    J.(bin_col_name)(~J.(hap_col))=binN;
    J.(bin_col_name)( J.(hap_col))=binH;
    rows={};
    for b=1:4
        xN=J.(resp_col)(~J.(hap_col)&J.(bin_col_name)==b); xN=xN(isfinite(xN));
        xH=J.(resp_col)( J.(hap_col)&J.(bin_col_name)==b); xH=xH(isfinite(xH));
        sdN=std(xN); sdH=std(xH);
        p_lev=local_levene(xN,xH);
        [~,p_mu]=ttest2(xH,xN,'Vartype','unequal');
        sp=sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
        d=(mean(xH)-mean(xN))/sp*(1-3/(4*(numel(xN)+numel(xH)-2)-1));
        rows(end+1,:)={b,numel(xN),numel(xH),mean(xN),mean(xH),sdN,sdH,sdN/sdH,p_lev,p_mu,d};
    end
    T_out=cell2table(rows,'VariableNames',{'bin','n_N','n_H','mean_N','mean_H','sd_N','sd_H','ratio_sd','p_levene','p_mean','cohens_d'});
    T_out.p_levene_fdr=mafdr(T_out.p_levene,'BHFDR',true);
    T_out.p_mean_fdr  =mafdr(T_out.p_mean,'BHFDR',true);
end

function local_plot_bins(J, bin_col, hap_col, resp_col, T_bins, ylabel_str, title_str, xlabel_str, lme, CN, CH, fig_dir, fname)
    fig=figure('Position',[50 50 1300 480]);
    tl=tiledlayout(1,5,'TileSpacing','compact','Padding','compact');
    title(tl,title_str,'FontWeight','bold','FontSize',11,'Interpreter','none');
    for b=1:4
        nexttile; hold on;
        xN=J.(resp_col)(~J.(hap_col)&J.(bin_col)==b); xN=xN(isfinite(xN));
        xH=J.(resp_col)( J.(hap_col)&J.(bin_col)==b); xH=xH(isfinite(xH));
        local_violin(xN,1,CN); local_violin(xH,2,CH);
        errorbar(1,mean(xN),std(xN)/sqrt(numel(xN))*1.96,'o','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',7,'HandleVisibility','off');
        errorbar(2,mean(xH),std(xH)/sqrt(numel(xH))*1.96,'o','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',7,'HandleVisibility','off');
        ymax=max([xN;xH]); ymin=min([xN;xH]); rng=max(ymax-ymin,1e-6);
        sig=local_stars(T_bins.p_levene_fdr(b));
        if ~isempty(sig)
            yt=ymax+0.05*rng; plot([1 2],[yt yt],'k-','LineWidth',1,'HandleVisibility','off');
            text(1.5,yt+0.03*rng,sig,'HorizontalAlignment','center','FontSize',13);
        end
        xticks([1 2]); xticklabels({'NHF','HF'}); ylabel(ylabel_str,'FontSize',7);
        title(sprintf('Bin %d\nSD_N=%.3f SD_H=%.3f\np_{Lev}=%s',b,std(xN),std(xH),local_pstr(T_bins.p_levene_fdr(b))),'FontSize',7);
        grid on; xlim([0.5 2.5]);
    end
    nexttile; hold on;
    bh=bar(1:4,T_bins.ratio_sd,0.55); bh.FaceColor='flat';
    for b=1:4, bh.CData(b,:)=local_ternary(T_bins.p_levene_fdr(b)<0.05,[0.3 0.6 0.3],[0.7 0.7 0.7]); end
    yline(1,'r--','LineWidth',1.5,'HandleVisibility','off');
    for b=1:4
        sig=local_stars(T_bins.p_levene_fdr(b));
        if ~isempty(sig), text(b,T_bins.ratio_sd(b)+0.02,sig,'HorizontalAlignment','center','FontSize',12); end
    end
    ylabel('SD_{NHF}/SD_{HF}','FontSize',9); xlabel(xlabel_str,'FontSize',9,'Interpreter','none');
    title('SD ratio','FontSize',9); set(gca,'XTick',1:4); grid on;
    exportgraphics(fig,fullfile(fig_dir,fname),'Resolution',180);
end

function p=local_levene(x,y)
    [~,p]=ttest2(abs(x-median(x)),abs(y-median(y)),'Vartype','unequal');
end
function local_violin(x,xpos,col)
    if numel(x)<3, scatter(xpos+(rand(numel(x),1)-0.5)*0.2,x,18,col,'filled','MarkerFaceAlpha',0.4,'HandleVisibility','off'); return; end
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