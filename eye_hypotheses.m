%% eye_hypotheses.m
clear; clc; close all; cfg = config();
CN=[64 96 179]/255; CH=[139 82 168]/255;
fig_dir=fullfile(cfg.output_root,'figures'); if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

feat_file=fullfile(cfg.output_root,'eye_features_v2.mat');
if ~isfile(feat_file), error('Run eye_extract_features_v2(cfg) first.'); end
T=load(feat_file,'T'); T=T.T;
TC=load(feat_file,'T_coll'); TC=TC.T_coll;

efficiency_outcomes={'fixation_rate','Fixation rate (fixations/min)'; 'fixation_mean_dur','Mean fixation duration (s)'; 'saccade_rate','Saccade rate (saccades/min)'; 'gaze_entropy','Gaze entropy (bits)'};
pupil_outcomes={'pupil_mean_norm','Normalised pupil diameter ((pupil-baseline)/baseline)'; 'collision_pupil_response_mean','Collision-locked pupil dilation ((peak-baseline)/baseline)'};

all_results=struct();

% ════════════════════════════════════════════════════════════════
% H1: learning curve within training — efficiency changes rep 1→10
% and pre→post training (Baseline1 vs Baseline2), per group
% ════════════════════════════════════════════════════════════════
fprintf('\n=== H1: Gaze efficiency learning curve ===\n');
h1_rows={}; h1_lm_rows={};
for oi=1:size(efficiency_outcomes,1)
    oc=efficiency_outcomes{oi,1}; yl=efficiency_outcomes{oi,2};
    Ttr=T(strcmp(T.phase_type,'training')&isfinite(T.(oc)),:);
    for grp=[false true]
        glabel=local_ternary(grp,'HF','NHF');
        Tg=Ttr(Ttr.haptic==grp,:);
        % Within-training: Spearman correlation of repetition vs outcome (pooled across levels)
        [rho,prho]=corr(double(Tg.repetition),Tg.(oc),'Type','Spearman','Rows','complete');
        fprintf('  %s %s vs rep: rho=%.3f p=%.4f\n',oc,glabel,rho,prho);
        h1_lm_rows(end+1,:)={oc,glabel,'within_training_spearman',rho,prho}; %#ok<AGROW>
        % Paired first-3 vs last-3 reps
        subj_l=unique(Tg.subject); early=nan(numel(subj_l),1); late=nan(numel(subj_l),1);
        for si=1:numel(subj_l)
            s=subj_l{si}; Ts=Tg(strcmp(Tg.subject,s),:);
            early(si)=mean(Ts.(oc)(Ts.repetition<=3),'omitnan');
            late(si)=mean(Ts.(oc)(Ts.repetition>=8),'omitnan');
        end
        keep=isfinite(early)&isfinite(late); early=early(keep); late=late(keep);
        [~,p_pair,~,st]=ttest(late,early);
        d=(mean(late,'omitnan')-mean(early,'omitnan'))/std(late-early,'omitnan');
        fprintf('  %s %s early vs late: t=%.3f p=%.4f d=%.3f\n',oc,glabel,st.tstat,p_pair,d);
        h1_rows(end+1,:)={oc,glabel,'early_vs_late_training',numel(early),mean(early,'omitnan'),mean(late,'omitnan'),st.tstat,p_pair,d}; %#ok<AGROW>
    end
    % Pre vs post: Baseline1 vs Baseline2 per group
    for grp=[false true]
        glabel=local_ternary(grp,'HF','NHF');
        Tb1=T(strcmp(T.phase,'Baseline1')&isfinite(T.(oc))&T.haptic==grp,:);
        Tb2=T(strcmp(T.phase,'Baseline2')&isfinite(T.(oc))&T.haptic==grp,:);
        sl=intersect(unique(Tb1.subject),unique(Tb2.subject));
        pre=nan(numel(sl),1); post=nan(numel(sl),1);
        for si=1:numel(sl), s=sl{si}; pre(si)=mean(Tb1.(oc)(strcmp(Tb1.subject,s)),'omitnan'); post(si)=mean(Tb2.(oc)(strcmp(Tb2.subject,s)),'omitnan'); end
        keep=isfinite(pre)&isfinite(post); pre=pre(keep); post=post(keep);
        if numel(pre)<2, continue; end
        [~,p_pair,~,st]=ttest(post,pre);
        d=(mean(post,'omitnan')-mean(pre,'omitnan'))/std(post-pre,'omitnan');
        fprintf('  %s %s BL1 vs BL2: t=%.3f p=%.4f d=%.3f\n',oc,glabel,st.tstat,p_pair,d);
        h1_rows(end+1,:)={oc,glabel,'Baseline1_vs_Baseline2',numel(pre),mean(pre,'omitnan'),mean(post,'omitnan'),st.tstat,p_pair,d}; %#ok<AGROW>
    end
end
T_h1=cell2table(h1_rows,'VariableNames',{'outcome','group','comparison','n','mean_early_pre','mean_late_post','t','p','cohens_d'});
T_h1.p_fdr=local_fdr(T_h1.p); all_results.H1=T_h1;
disp(T_h1);

% Learning curve figure
fig=figure('Position',[50 50 1400 900]);
sgtitle('H1 — Gaze efficiency learning curve across training repetitions','FontWeight','bold');
for oi=1:size(efficiency_outcomes,1)
    oc=efficiency_outcomes{oi,1}; yl=efficiency_outcomes{oi,2};
    Ttr=T(strcmp(T.phase_type,'training')&isfinite(T.(oc)),:);
    subplot(size(efficiency_outcomes,1),1,oi); hold on;
    for grp=[false true]
        col=local_ternary(grp,CH,CN); glabel=local_ternary(grp,'HF','NHF');
        Tg=Ttr(Ttr.haptic==grp,:); sl=unique(Tg.subject);
        sbyr=nan(numel(sl),10);
        for si=1:numel(sl), s=sl{si}; Ts=Tg(strcmp(Tg.subject,s),:); for r=1:10, v=Ts.(oc)(Ts.repetition==r); if ~isempty(v), sbyr(si,r)=mean(v,'omitnan'); end; end; end
        mu=mean(sbyr,1,'omitnan'); sem=std(sbyr,0,1,'omitnan')./sqrt(sum(isfinite(sbyr),1));
        fill([1:10 10:-1:1],[mu+1.96*sem fliplr(mu-1.96*sem)],col,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
        plot(1:10,mu,'o-','Color',col,'LineWidth',2,'MarkerFaceColor',col,'MarkerSize',6,'DisplayName',glabel);
    end
    set(gca,'XTick',1:10); xlabel('Repetition (pooled across levels)'); ylabel(yl,'FontSize',8); legend('Location','best','FontSize',8); grid on;
end
exportgraphics(fig,fullfile(fig_dir,'eye_H1_learning_curve.png'),'Resolution',150); close(fig);

% ════════════════════════════════════════════════════════════════
% H2: HF shows higher gaze efficiency across all phases
% ════════════════════════════════════════════════════════════════
fprintf('\n=== H2: HF vs NHF gaze efficiency across all phases ===\n');
phases_ord={'Baseline1','Training_L1','Training_L2','Training_L3','Training_L4','Training_L5','Baseline2','Test1','Test2'};
xlabels={'BL1','Tr-L1','Tr-L2','Tr-L3','Tr-L4','Tr-L5','BL2','T1','T2'};
h2_rows={};
for oi=1:size(efficiency_outcomes,1)
    oc=efficiency_outcomes{oi,1}; yl=efficiency_outcomes{oi,2};
    mu_N=nan(1,9); mu_H=nan(1,9); se_N=nan(1,9); se_H=nan(1,9); pfdr_v=nan(1,9); d_v=nan(1,9);
    for k=1:9
        ph=phases_ord{k};
        if startsWith(ph,'Training'), lv=str2double(ph(end)); Tsub=T(strcmp(T.phase_type,'training')&T.level==lv&isfinite(T.(oc)),:);
        else, Tsub=T(strcmp(T.phase,ph)&isfinite(T.(oc)),:); end
        sl=unique(Tsub.subject); xa=nan(numel(sl),1); ih=false(numel(sl),1);
        for si=1:numel(sl), s=sl{si}; xa(si)=mean(Tsub.(oc)(strcmp(Tsub.subject,s)),'omitnan'); ih(si)=any(Tsub.haptic(strcmp(Tsub.subject,s))); end
        xN=xa(~ih&isfinite(xa)); xH=xa(ih&isfinite(xa));
        mu_N(k)=mean(xN,'omitnan'); mu_H(k)=mean(xH,'omitnan');
        se_N(k)=std(xN,'omitnan')/sqrt(numel(xN)); se_H(k)=std(xH,'omitnan')/sqrt(numel(xH));
        if numel(xN)>=2&&numel(xH)>=2
            [~,p2,~,st2]=ttest2(xH,xN,'Vartype','unequal');
            sp=sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
            d_v(k)=(mean(xH,'omitnan')-mean(xN,'omitnan'))/sp*(1-3/(4*(numel(xN)+numel(xH)-2)-1));
            h2_rows(end+1,:)={oc,ph,numel(xN),numel(xH),mu_N(k),mu_H(k),st2.tstat,p2,d_v(k)}; %#ok<AGROW>
        end
    end
    T_h2_tmp=cell2table(h2_rows(strcmp(cellfun(@(r)r,h2_rows(:,1),'UniformOutput',false),oc),:),'VariableNames',{'outcome','phase','n_N','n_H','mean_N','mean_H','t','p','cohens_d'});
    if height(T_h2_tmp)>0, pfdr_v_tmp=local_fdr(T_h2_tmp.p); else, pfdr_v_tmp=[]; end

    fig=figure('Position',[50 50 1100 380]);
    hold on;
    fill([1:9 9:-1:1],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    fill([1:9 9:-1:1],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    plot(1:9,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
    plot(1:9,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
    xline(1.5,'k:','LineWidth',1,'HandleVisibility','off'); xline(6.5,'k:','LineWidth',1,'HandleVisibility','off');
    for k=1:9
        if numel(pfdr_v_tmp)>=k, sig=local_stars(pfdr_v_tmp(k)); else, sig=''; end
        if ~isempty(sig), ypos=max(mu_N(k)+1.96*se_N(k),mu_H(k)+1.96*se_H(k)); text(k,ypos*1.05,sig,'HorizontalAlignment','center','FontSize',12); end
        text(k,min(mu_N(k)-1.96*se_N(k),mu_H(k)-1.96*se_H(k))*0.95,sprintf('d=%.2f',d_v(k)),'HorizontalAlignment','center','FontSize',7,'Color',[0.4 0.4 0.4]);
    end
    set(gca,'XTick',1:9,'XTickLabel',xlabels,'FontSize',9); ylabel(yl,'FontSize',9); xlabel('Phase'); legend('Location','best','FontSize',9); grid on; box on;
    title(sprintf('H2 — %s: NHF vs HF across all phases',strrep(oc,'_',' ')),'FontSize',10);
    exportgraphics(fig,fullfile(fig_dir,sprintf('eye_H2_%s.png',oc)),'Resolution',150); close(fig);
end
T_h2=cell2table(h2_rows,'VariableNames',{'outcome','phase','n_N','n_H','mean_N','mean_H','t','p','cohens_d'});
T_h2.p_fdr=local_fdr(T_h2.p); all_results.H2=T_h2; disp(T_h2);

% ════════════════════════════════════════════════════════════════
% H3: pupil collision response variance less variable in HF
% (direct pupil analogue of EDA H2)
% ════════════════════════════════════════════════════════════════
fprintf('\n=== H3: Pupil collision response variance by intensity bin ===\n');
TC_tr=TC(strcmp(TC.phase_type,'training')&isfinite(TC.peak_accel_g)&isfinite(TC.pupil_response_norm),:);
fprintf('Training collisions (pupil+intensity valid): N=%d  H=%d\n',sum(~TC_tr.haptic),sum(TC_tr.haptic));
eN=unique(quantile(TC_tr.peak_accel_g(~TC_tr.haptic),[0 0.25 0.50 0.75 1.0]));
eH=unique(quantile(TC_tr.peak_accel_g( TC_tr.haptic),[0 0.25 0.50 0.75 1.0]));
[~,~,bvN]=histcounts(TC_tr.peak_accel_g(~TC_tr.haptic),eN);
[~,~,bvH]=histcounts(TC_tr.peak_accel_g( TC_tr.haptic),eH);
TC_tr.bv=zeros(height(TC_tr),1); TC_tr.bv(~TC_tr.haptic)=bvN; TC_tr.bv(TC_tr.haptic)=bvH;
h3_rows={};
for b=1:4
    xN=TC_tr.pupil_response_norm(~TC_tr.haptic&TC_tr.bv==b); xN=xN(isfinite(xN));
    xH=TC_tr.pupil_response_norm( TC_tr.haptic&TC_tr.bv==b); xH=xH(isfinite(xH));
    sdN=std(xN); sdH=std(xH); p_lev=local_levene(xN,xH);
    [~,p_mu]=ttest2(xH,xN,'Vartype','unequal');
    try, p_muw=ranksum(xH,xN); catch, p_muw=NaN; end
    fprintf('Bin %d: n_N=%d n_H=%d SD_N=%.4f SD_H=%.4f ratio=%.3f Levene_p=%.4g mean_p=%.4g\n',b,numel(xN),numel(xH),sdN,sdH,sdN/sdH,p_lev,p_mu);
    h3_rows(end+1,:)={b,numel(xN),numel(xH),mean(xN,'omitnan'),mean(xH,'omitnan'),sdN,sdH,sdN/sdH,p_lev,p_mu,p_muw}; %#ok<AGROW>
end
T_h3=cell2table(h3_rows,'VariableNames',{'bin','n_N','n_H','mean_N','mean_H','sd_N','sd_H','ratio_sdN_sdH','p_levene','p_mean_ttest','p_mean_wilcoxon'});
T_h3.p_levene_fdr=local_fdr(T_h3.p_levene); T_h3.p_mean_fdr=local_fdr(T_h3.p_mean_ttest);
all_results.H3=T_h3; disp(T_h3);

fig=figure('Position',[50 50 1200 480]);
sgtitle('H3 — Pupil collision response variance by intensity quartile (group-specific bins)','FontWeight','bold');
for b=1:4
    xN=TC_tr.pupil_response_norm(~TC_tr.haptic&TC_tr.bv==b); xN=xN(isfinite(xN));
    xH=TC_tr.pupil_response_norm( TC_tr.haptic&TC_tr.bv==b); xH=xH(isfinite(xH));
    subplot(1,5,b); hold on;
    local_violin(xN,1,CN); local_violin(xH,2,CH);
    errorbar(1,mean(xN,'omitnan'),std(xN),'s','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');
    errorbar(2,mean(xH,'omitnan'),std(xH),'s','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');
    yall=[xN;xH]; yrng=max(yall)-min(yall);
    sig=local_stars(T_h3.p_levene_fdr(b));
    if ~isempty(sig), yt=max(yall)+0.1*yrng; plot([1 2],[yt yt],'k-','LineWidth',1,'HandleVisibility','off'); text(1.5,yt+0.05*yrng,sig,'HorizontalAlignment','center','FontSize',13); end
    title(sprintf('Bin %d\nLev p_{FDR}=%s\nSD_N=%.3f SD_H=%.3f',b,local_pstr(T_h3.p_levene_fdr(b)),T_h3.sd_N(b),T_h3.sd_H(b)),'FontSize',8);
    xticks([1 2]); xticklabels({'NHF','HF'}); if b==1, ylabel('Pupil dilation ((peak-baseline)/baseline)','FontSize',8); end
    grid on; xlim([0.5 2.5]);
end
subplot(1,5,5); hold on;
bh=bar(1:4,T_h3.ratio_sdN_sdH,0.55); bh.FaceColor='flat';
for b=1:4, bh.CData(b,:)=local_ternary(T_h3.p_levene_fdr(b)<0.05,[0.3 0.5 0.3],[0.7 0.7 0.7]); end
yline(1,'r--','LineWidth',1.8); ylabel('SD_{NHF}/SD_{HF}'); xlabel('Intensity bin'); title('Variance ratio','FontSize',9); set(gca,'XTick',1:4); ylim([0 1.4]); grid on;
exportgraphics(fig,fullfile(fig_dir,'eye_H3_pupil_variance.png'),'Resolution',150); close(fig);

% ════════════════════════════════════════════════════════════════
% H4: pupil collision response NHF vs HF across phases
% (mirror of EDA H1 for pupil)
% ════════════════════════════════════════════════════════════════
fprintf('\n=== H4: Pupil collision response NHF vs HF across phases ===\n');
h4_rows={};
mu_N4=nan(1,9); mu_H4=nan(1,9); se_N4=nan(1,9); se_H4=nan(1,9); pfdr4=nan(1,9); d4=nan(1,9);
oc='collision_pupil_response_mean'; yl='Collision-locked pupil dilation ((peak-baseline)/baseline)';
for k=1:9
    ph=phases_ord{k};
    if startsWith(ph,'Training'), lv=str2double(ph(end)); Tsub=T(strcmp(T.phase_type,'training')&T.level==lv&isfinite(T.(oc))&T.n_collisions>=1,:);
    else, Tsub=T(strcmp(T.phase,ph)&isfinite(T.(oc))&T.n_collisions>=1,:); end
    sl=unique(Tsub.subject); xa=nan(numel(sl),1); ih=false(numel(sl),1);
    for si=1:numel(sl), s=sl{si}; xa(si)=mean(Tsub.(oc)(strcmp(Tsub.subject,s)),'omitnan'); ih(si)=any(Tsub.haptic(strcmp(Tsub.subject,s))); end
    xN=xa(~ih&isfinite(xa)); xH=xa(ih&isfinite(xa));
    mu_N4(k)=mean(xN,'omitnan'); mu_H4(k)=mean(xH,'omitnan');
    se_N4(k)=std(xN,'omitnan')/sqrt(numel(xN)); se_H4(k)=std(xH,'omitnan')/sqrt(numel(xH));
    if numel(xN)>=2&&numel(xH)>=2
        [~,p2,~,st2]=ttest2(xH,xN,'Vartype','unequal');
        sp=sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
        d4(k)=(mean(xH,'omitnan')-mean(xN,'omitnan'))/sp*(1-3/(4*(numel(xN)+numel(xH)-2)-1));
        pfdr4(k)=p2;
        h4_rows(end+1,:)={ph,numel(xN),numel(xH),mu_N4(k),mu_H4(k),st2.tstat,p2,d4(k)}; %#ok<AGROW>
    end
end
T_h4=cell2table(h4_rows,'VariableNames',{'phase','n_N','n_H','mean_N','mean_H','t','p','cohens_d'});
T_h4.p_fdr=local_fdr(T_h4.p); all_results.H4=T_h4; disp(T_h4);

fig=figure('Position',[50 50 1100 400]);
hold on;
fill([1:9 9:-1:1],[mu_N4+1.96*se_N4 fliplr(mu_N4-1.96*se_N4)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
fill([1:9 9:-1:1],[mu_H4+1.96*se_H4 fliplr(mu_H4-1.96*se_H4)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
plot(1:9,mu_N4,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
plot(1:9,mu_H4,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
xline(1.5,'k:','LineWidth',1,'HandleVisibility','off'); xline(6.5,'k:','LineWidth',1,'HandleVisibility','off');
fdr_vec=T_h4.p_fdr;
for k=1:min(9,numel(fdr_vec))
    sig=local_stars(fdr_vec(k));
    if ~isempty(sig), ypos=max(mu_N4(k)+1.96*se_N4(k),mu_H4(k)+1.96*se_H4(k)); text(k,ypos*1.05,sig,'HorizontalAlignment','center','FontSize',12); end
    text(k,min(mu_N4(k)-1.96*se_N4(k),mu_H4(k)-1.96*se_H4(k))*0.95,sprintf('d=%.2f',d4(k)),'HorizontalAlignment','center','FontSize',7,'Color',[0.4 0.4 0.4]);
end
set(gca,'XTick',1:9,'XTickLabel',xlabels,'FontSize',9); ylabel(yl,'FontSize',9); xlabel('Phase'); legend('Location','best','FontSize',9); grid on; box on;
title('H4 — Collision-locked pupil dilation: NHF vs HF across all phases','FontSize',10);
exportgraphics(fig,fullfile(fig_dir,'eye_H4_pupil_collision.png'),'Resolution',150); close(fig);

save(fullfile(cfg.output_root,'eye_hypothesis_results.mat'),'all_results');
writetable(T_h1,fullfile(cfg.output_root,'eye_H1_results.csv'));
writetable(T_h2,fullfile(cfg.output_root,'eye_H2_results.csv'));
writetable(T_h3,fullfile(cfg.output_root,'eye_H3_results.csv'));
writetable(T_h4,fullfile(cfg.output_root,'eye_H4_results.csv'));
fprintf('Saved eye_hypothesis_results\n');

% ── LOCAL FUNCTIONS ────────────────────────────────────────────
function p=local_levene(x1,x2)
    if numel(x1)<2||numel(x2)<2, p=NaN; return; end
    [~,p]=ttest2(abs(x1-median(x1)),abs(x2-median(x2)),'Vartype','unequal');
end
function local_violin(x,xpos,col)
    if numel(x)<3, scatter(xpos+(rand(numel(x),1)-0.5)*0.2,x,18,col,'filled','MarkerFaceAlpha',0.4,'HandleVisibility','off'); return; end
    [f,xi]=ksdensity(x,'NumPoints',100,'BoundaryCorrection','reflection'); f=f/max(f)*0.35;
    patch([xpos+f fliplr(xpos-f)],[xi fliplr(xi)],col,'FaceAlpha',0.25,'EdgeColor',col,'LineWidth',0.8,'HandleVisibility','off');
    scatter(xpos+(rand(numel(x),1)-0.5)*0.15,x,10,col,'filled','MarkerFaceAlpha',0.3,'HandleVisibility','off');
end
function s=local_stars(p), if isnan(p)||p>0.05, s=''; elseif p>0.01, s='*'; elseif p>0.001, s='**'; else, s='***'; end, end
function s=local_pstr(p), if isnan(p), s='n/a'; elseif p<0.001, s=sprintf('%.2e',p); else, s=sprintf('%.3f',p); end, end
function out=local_ternary(c,a,b), if c, out=a; else, out=b; end, end
function p_adj=local_fdr(p)
    p=p(:); n=numel(p); p_adj=nan(n,1); valid=find(isfinite(p)); [ps,ix]=sort(p(valid)); m=numel(ps); adj=nan(m,1); prev=1;
    for k=m:-1:1, val=ps(k)*m/k; prev=min(prev,val); adj(k)=prev; end
    p_adj(valid(ix))=min(adj,1);
end