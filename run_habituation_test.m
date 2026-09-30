%% h3_habituation_test.m
clear; clc; close all; cfg = config();
MIN_COLL=1;
feat_file=fullfile(cfg.output_root,'eda_features_v2.mat');
if ~isfile(feat_file), error('Run gsr_extract_features_v2(cfg) first.'); end
T=load(feat_file,'T'); T=T.T;
CN=[55 138 221]/255; CH=[212 83 126]/255;
fig_dir=fullfile(cfg.output_root,'figures'); if ~exist(fig_dir,'dir'), mkdir(fig_dir); end
outcomes={'collision_scr_amp_mean_bc','ER-SCR amplitude (resting SD units)'; 'collision_response_rate','SCR response rate (proportion)'};
all_results=struct();

fprintf('\n=== 3a: Post-training snapshot ===\n');
rows_3a={};
for oi=1:size(outcomes,1)
    outcome=outcomes{oi,1}; ylab=outcomes{oi,2};
    for ph={'Baseline2','Test2'}
        Tph=T(strcmp(T.phase,ph{1})&isfinite(T.(outcome))&T.n_collisions>=MIN_COLL,:);
        sph=unique(Tph.subject); xa=nan(numel(sph),1); ih=false(numel(sph),1);
        for si=1:numel(sph), s=sph{si}; xa(si)=mean(Tph.(outcome)(strcmp(Tph.subject,s)),'omitnan'); ih(si)=any(Tph.haptic(strcmp(Tph.subject,s))); end
        xN=xa(~ih&isfinite(xa)); xH=xa(ih&isfinite(xa));
        fprintf('\n%s — %s (n_N=%d n_H=%d)\n',outcome,ph{1},numel(xN),numel(xH));
        [~,pN0,~,stN]=ttest(xN); fprintf('  N vs 0: mean=%.4f t=%.3f p=%.4f\n',mean(xN,'omitnan'),stN.tstat,pN0);
        [~,pH0,~,stH]=ttest(xH); fprintf('  H vs 0: mean=%.4f t=%.3f p=%.4f\n',mean(xH,'omitnan'),stH.tstat,pH0);
        [~,p2,~,st2]=ttest2(xH,xN,'Vartype','unequal');
        try, pw=ranksum(xH,xN); catch, pw=NaN; end
        sp=sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
        d=(mean(xH,'omitnan')-mean(xN,'omitnan'))/sp*(1-3/(4*(numel(xN)+numel(xH)-2)-1));
        fprintf('  N vs H: diff=%.4f t=%.3f p=%.4f W_p=%.4f d=%.3f\n',mean(xH,'omitnan')-mean(xN,'omitnan'),st2.tstat,p2,pw,d);
        rows_3a(end+1,:)={outcome,ph{1},numel(xN),numel(xH),mean(xN,'omitnan'),mean(xH,'omitnan'),stN.tstat,pN0,stH.tstat,pH0,st2.tstat,p2,pw,d}; %#ok<AGROW>
        local_plot_snap(xN,xH,outcome,ph{1},ylab,p2,d,CN,CH,fig_dir);
    end
end
T_3a=cell2table(rows_3a,'VariableNames',{'outcome','phase','n_N','n_H','mean_N','mean_H','t_N_vs0','p_N_vs0','t_H_vs0','p_H_vs0','t_NvsH','p_NvsH','p_wilcoxon','cohens_d'});
T_3a.p_fdr=local_fdr(T_3a.p_NvsH); all_results.snapshot=T_3a;

fprintf('\n=== 3b: Pre->post change ===\n');
rows_3b={};
pairs={'baseline','Baseline1','Baseline2'; 'test','Test1','Test2'};
for oi=1:size(outcomes,1)
    outcome=outcomes{oi,1}; ylab=outcomes{oi,2};
    for tp=1:size(pairs,1)
        pt=pairs{tp,1}; pp=pairs{tp,2}; ppost=pairs{tp,3};
        Tph=T(strcmp(T.phase_type,pt)&isfinite(T.(outcome))&T.n_collisions>=MIN_COLL&ismember(T.phase,{pp,ppost}),:);
        sl=unique(Tph.subject); pre=nan(numel(sl),1); post=nan(numel(sl),1); ihs=false(numel(sl),1);
        for si=1:numel(sl), s=sl{si}; pre(si)=mean(Tph.(outcome)(strcmp(Tph.subject,s)&strcmp(Tph.phase,pp)),'omitnan'); post(si)=mean(Tph.(outcome)(strcmp(Tph.subject,s)&strcmp(Tph.phase,ppost)),'omitnan'); ihs(si)=any(Tph.haptic(strcmp(Tph.subject,s))); end
        keep=isfinite(pre)&isfinite(post); pre=pre(keep); post=post(keep); ihs=ihs(keep); delta=post-pre;
        fprintf('\n%s — %s->%s (n_N=%d n_H=%d)\n',outcome,pp,ppost,sum(~ihs),sum(ihs));
        [~,pNp,~,stN]=ttest(post(~ihs),pre(~ihs)); [~,pHp,~,stH]=ttest(post(ihs),pre(ihs));
        fprintf('  N paired: t=%.3f p=%.4f | H paired: t=%.3f p=%.4f\n',stN.tstat,pNp,stH.tstat,pHp);
        [~,pd,~,std2]=ttest2(delta(ihs),delta(~ihs),'Vartype','unequal');
        try, pdw=ranksum(delta(ihs),delta(~ihs)); catch, pdw=NaN; end
        fprintf('  Delta N vs H: t=%.3f p=%.4f W_p=%.4f\n',std2.tstat,pd,pdw);
        rows_3b(end+1,:)={outcome,pp,ppost,sum(~ihs),sum(ihs),stN.tstat,pNp,stH.tstat,pHp,std2.tstat,pd,pdw}; %#ok<AGROW>
        local_plot_transfer(pre,post,ihs,outcome,pp,ppost,ylab,CN,CH,fig_dir);
    end
end
T_3b=cell2table(rows_3b,'VariableNames',{'outcome','phase_pre','phase_post','n_N','n_H','t_N_paired','p_N_paired','t_H_paired','p_H_paired','t_delta','p_delta','p_delta_wilcoxon'});
T_3b.p_fdr=local_fdr(T_3b.p_delta); all_results.transfer=T_3b;

save(fullfile(cfg.output_root,'h3_results.mat'),'all_results');
writetable(T_3a,fullfile(cfg.output_root,'h3_snapshot_results.csv'));
writetable(T_3b,fullfile(cfg.output_root,'h3_transfer_results.csv'));
fprintf('Saved h3_results\n');

function local_plot_snap(xN,xH,outcome,ph,ylab,p2,d,CN,CH,fig_dir)
    fig=figure('Name',sprintf('H3a:%s %s',outcome,ph),'Position',[50 50 500 480],'Visible','off');
    hold on; jit=@(n)(rand(n,1)-0.5)*0.25;
    scatter(1+jit(numel(xN)),xN,22,CN,'filled','MarkerFaceAlpha',0.45,'HandleVisibility','off');
    scatter(2+jit(numel(xH)),xH,22,CH,'filled','MarkerFaceAlpha',0.45,'HandleVisibility','off');
    errorbar(1,mean(xN,'omitnan'),std(xN,'omitnan')/sqrt(numel(xN))*1.96,'o','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');
    errorbar(2,mean(xH,'omitnan'),std(xH,'omitnan')/sqrt(numel(xH))*1.96,'o','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');
    yline(0,'k--','LineWidth',1.2,'HandleVisibility','off');
    xticks([1 2]); xticklabels({'NHF','HF'}); ylabel(ylab,'FontSize',9); grid on; xlim([0.5 2.5]);
    title(sprintf('%s — %s\np=%.4f d=%.2f',strrep(outcome,'_',' '),ph,p2,d),'FontSize',9);
    exportgraphics(fig,fullfile(fig_dir,sprintf('h3_snapshot_%s_%s.png',outcome,ph)),'Resolution',150);   
end
function local_plot_transfer(pre,post,ihs,outcome,pp,ppost,ylab,CN,CH,fig_dir)
    fig=figure('Name',sprintf('H3b:%s %s->%s',outcome,pp,ppost),'Position',[50 50 520 480],'Visible','off');
    hold on; jx=@(base,n)base+(rand(n,1)-0.5)*0.10;
    for grp=[false true]
        idx=find(ihs==grp); if isempty(idx), continue; end
        col=local_tern(grp,CH,CN); x1=jx(1,numel(idx)); x2=x1+1;
        for k=1:numel(idx), plot([x1(k) x2(k)],[pre(idx(k)) post(idx(k))],'-','Color',[col 0.2],'LineWidth',0.8,'HandleVisibility','off'); end
        mu=[mean(pre(idx),'omitnan') mean(post(idx),'omitnan')]; sem=[std(pre(idx),'omitnan') std(post(idx),'omitnan')]./sqrt(numel(idx))*1.96;
        errorbar([1 2]+local_tern(grp,0.08,-0.08),mu,sem,'-o','Color',col,'LineWidth',2,'MarkerFaceColor',col,'MarkerSize',7,'DisplayName',local_tern(grp,'HF','NHF'));
    end
    yline(0,'k--','LineWidth',1,'HandleVisibility','off');
    xlim([0.5 2.5]); xticks([1 2]); xticklabels({pp,ppost}); ylabel(ylab,'FontSize',9); grid on; legend('Location','best','FontSize',8);
    title(sprintf('%s\n%s->%s',strrep(outcome,'_',' '),pp,ppost),'FontSize',9);
    exportgraphics(fig,fullfile(fig_dir,sprintf('h3_transfer_%s_%s_%s.png',outcome,pp,ppost)),'Resolution',150);   
end
function out=local_tern(c,a,b), if c, out=a; else, out=b; end, end
function p_adj=local_fdr(p)
    p=p(:); n=numel(p); p_adj=nan(n,1); valid=find(isfinite(p)); [ps,ix]=sort(p(valid)); m=numel(ps); adj=nan(m,1); prev=1;
    for k=m:-1:1, val=ps(k)*m/k; prev=min(prev,val); adj(k)=prev; end
    p_adj(valid(ix))=min(adj,1);
end