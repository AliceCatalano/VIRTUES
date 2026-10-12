%% h1_eda_group_comparison.m
clear; clc; close all; cfg = config();
feat_file = fullfile(cfg.output_root,'eda_features_v2.mat');
if ~isfile(feat_file), error('Run gsr_extract_features_v2(cfg) first.'); end
T = load(feat_file,'T'); T = T.T;
outcomes = {'scl_mean_bc','Tonic SCL (\muS, resting-corrected)'; 'scr_mean_amp_bc','Phasic amplitude (resting SD units)'; 'collision_scr_amp_mean_bc','ER-SCR amplitude (resting SD units)'};
CN=[55 138 221]/255; CH=[212 83 126]/255;
fig_dir=fullfile(cfg.output_root,'figures'); if ~exist(fig_dir,'dir'), mkdir(fig_dir); end
all_results=struct();
for oi=1:size(outcomes,1)
    outcome=outcomes{oi,1}; ylab=outcomes{oi,2};
    fprintf('\n=== %s ===\n',outcome);
    rows_out={};
    Ttr=T(strcmp(T.phase_type,'training')&isfinite(T.(outcome)),:);
    subj_list=unique(Ttr.subject); ns=numel(subj_list);
    sbyl=nan(ns,5); is_h=false(ns,1);
    for si=1:ns
        s=subj_list{si}; Ts=Ttr(strcmp(Ttr.subject,s),:); is_h(si)=any(Ts.haptic);
        for lv=1:5, v=Ts.(outcome)(Ts.level==lv); if ~isempty(v), sbyl(si,lv)=mean(v,'omitnan'); end; end
    end
    for lv=1:5
        xN=sbyl(~is_h,lv); xH=sbyl(is_h,lv); xN=xN(isfinite(xN)); xH=xH(isfinite(xH));
        rows_out(end+1,:)=local_cmp(outcome,sprintf('Training_L%d',lv),xN,xH); %#ok<AGROW>
    end
    for ph={'Baseline1','Baseline2','Test1','Test2'}
        Tph=T(strcmp(T.phase,ph{1})&isfinite(T.(outcome)),:);
        sph=unique(Tph.subject); xa=nan(numel(sph),1); ih=false(numel(sph),1);
        for si=1:numel(sph), s=sph{si}; xa(si)=mean(Tph.(outcome)(strcmp(Tph.subject,s)),'omitnan'); ih(si)=any(Tph.haptic(strcmp(Tph.subject,s))); end
        rows_out(end+1,:)=local_cmp(outcome,ph{1},xa(~ih&isfinite(xa)),xa(ih&isfinite(xa))); %#ok<AGROW>
    end
    T_res=cell2table(rows_out,'VariableNames',{'outcome','phase','n_N','n_H','mean_N','mean_H','median_N','median_H','mean_diff_HminusN','t','p_ttest','p_ttest_H_gt_N','p_wilcoxon','cohens_d_hedges'});
    T_res.p_fdr_ttest=local_fdr(T_res.p_ttest); T_res.p_fdr_wilcoxon=local_fdr(T_res.p_wilcoxon);
    lme_res=local_lmm(Ttr,outcome);
    fprintf('LMM haptic main effect: beta=%.4f SE=%.4f t=%.3f p=%.4f\n',lme_res.beta,lme_res.se,lme_res.t,lme_res.p);
    all_results.(outcome).table=T_res; all_results.(outcome).lmm=lme_res;
    local_plot(T,outcome,ylab,is_h,sbyl,T_res,CN,CH,fig_dir);
end
save(fullfile(cfg.output_root,'h1_results.mat'),'all_results');
fn=fieldnames(all_results); combined=table();
for k=1:numel(fn), combined=[combined;all_results.(fn{k}).table]; end %#ok<AGROW>

function row=local_cmp(outcome,ph,xN,xH)
    n1=numel(xN); n2=numel(xH);
    if n1<2||n2<2, row={outcome,ph,n1,n2,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN}; return; end
    mu1=mean(xN,'omitnan'); mu2=mean(xH,'omitnan'); md1=median(xN); md2=median(xH); diff=mu2-mu1;
    [~,p2,~,st]=ttest2(xH,xN,'Vartype','unequal');
    p1=p2/2; if diff<0, p1=1-p1; end
    try, pw=ranksum(xH,xN); catch, pw=NaN; end
    sp=sqrt(((n1-1)*var(xN)+(n2-1)*var(xH))/(n1+n2-2)); d=(mu2-mu1)/sp*(1-3/(4*(n1+n2-2)-1));
    row={outcome,ph,n1,n2,mu1,mu2,md1,md2,diff,st.tstat,p2,p1,pw,d};
end
function r=local_lmm(Ttr,outcome)
    r=struct('beta',NaN,'se',NaN,'t',NaN,'p',NaN);
    if height(Ttr)<10||~any(isfinite(Ttr.(outcome))), return; end
    Ttr.subject_cat=categorical(Ttr.subject); Ttr.level_cat=categorical(Ttr.level);
    Ttr.haptic_num=double(Ttr.haptic); Ttr.repetition=double(Ttr.repetition);
    try
        lme=fitlme(Ttr,sprintf('%s~haptic_num*level_cat+haptic_num*repetition+(1+repetition|subject_cat)',outcome),'FitMethod','REML');
        fe=lme.Coefficients; idx=strcmp(fe.Name,'haptic_num');
        r=struct('beta',fe.Estimate(idx),'se',fe.SE(idx),'t',fe.tStat(idx),'p',fe.pValue(idx));
    catch ME, fprintf('LMM failed: %s\n',ME.message); end
end
function local_plot(T,outcome,ylab,is_h,sbyl,T_res,CN,CH,fig_dir)
    ph_list={'Baseline1','Baseline2','Test1','Test2'};
    fig=figure('Name',sprintf('H1:%s',outcome),'Position',[2000 2000 1600 500]);
    sgtitle(sprintf('H1 — %s',strrep(outcome,'_',' ')),'FontWeight','bold');
    for lv=1:5
        subplot(1,9,lv); hold on;
        xN=sbyl(~is_h,lv); xH=sbyl(is_h,lv); xN=xN(isfinite(xN)); xH=xH(isfinite(xH));
        local_strip(xN,1,CN); local_strip(xH,2,CH);
        errorbar(1,mean(xN,'omitnan'),std(xN,'omitnan')/sqrt(numel(xN))*1.96,'o','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',7,'HandleVisibility','off');
        errorbar(2,mean(xH,'omitnan'),std(xH,'omitnan')/sqrt(numel(xH))*1.96,'o','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',7,'HandleVisibility','off');
        ri=strcmp(T_res.phase,sprintf('Training_L%d',lv));
        title(sprintf('L%d\np_{FDR}=%.3f\nd=%.2f',lv,T_res.p_fdr_ttest(ri),T_res.cohens_d_hedges(ri)),'FontSize',8);
        xticks([1 2]); xticklabels({'N','H'}); if lv==1, ylabel(ylab,'FontSize',8); end
        grid on; xlim([0.5 2.5]);
    end
    for pp=1:4
        ph=ph_list{pp}; subplot(1,9,5+pp); hold on;
        Tph=T(strcmp(T.phase,ph)&isfinite(T.(outcome)),:); sph=unique(Tph.subject);
        xa=nan(numel(sph),1); ih=false(numel(sph),1);
        for si=1:numel(sph), s=sph{si}; xa(si)=mean(Tph.(outcome)(strcmp(Tph.subject,s)),'omitnan'); ih(si)=any(Tph.haptic(strcmp(Tph.subject,s))); end
        xN=xa(~ih&isfinite(xa)); xH=xa(ih&isfinite(xa));
        local_strip(xN,1,CN); local_strip(xH,2,CH);
        errorbar(1,mean(xN,'omitnan'),std(xN,'omitnan')/sqrt(numel(xN))*1.96,'o','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',7,'HandleVisibility','off');
        errorbar(2,mean(xH,'omitnan'),std(xH,'omitnan')/sqrt(numel(xH))*1.96,'o','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',7,'HandleVisibility','off');
        ri=strcmp(T_res.phase,ph);
        title(sprintf('%s\np_{FDR}=%.3f\nd=%.2f',ph,T_res.p_fdr_ttest(ri),T_res.cohens_d_hedges(ri)),'FontSize',8);
        xticks([1 2]); xticklabels({'N','H'}); grid on; xlim([0.5 2.5]);
    end
    subplot(1,9,1); plot(nan,nan,'o','Color',CN,'MarkerFaceColor',CN,'DisplayName','NHF'); plot(nan,nan,'o','Color',CH,'MarkerFaceColor',CH,'DisplayName','HF'); legend('Location','best','FontSize',8);
    exportgraphics(fig,fullfile(fig_dir,sprintf('h1_%s.png',outcome)),'Resolution',150);  
end
function local_strip(x,xpos,col)
    if isempty(x), return; end
    scatter(xpos+(rand(numel(x),1)-0.5)*0.25,x,20,col,'filled','MarkerFaceAlpha',0.4,'HandleVisibility','off');
end
function p_adj=local_fdr(p)
    p=p(:); n=numel(p); p_adj=nan(n,1); valid=find(isfinite(p)); [ps,ix]=sort(p(valid)); m=numel(ps); adj=nan(m,1); prev=1;
    for k=m:-1:1, val=ps(k)*m/k; prev=min(prev,val); adj(k)=prev; end
    p_adj(valid(ix))=min(adj,1);
end