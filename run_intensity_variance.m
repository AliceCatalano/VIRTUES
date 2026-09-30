clear; clc; close all; cfg = config();
feat_file=fullfile(cfg.output_root,'eda_features_v2.mat');
if ~isfile(feat_file), error('Run gsr_extract_features_v2(cfg) first.'); end
TC=load(feat_file,'T_coll'); TC=TC.T_coll;
CN=[55 138 221]/255; CH=[212 83 126]/255;
fig_dir=fullfile(cfg.output_root,'figures'); if ~exist(fig_dir,'dir'), mkdir(fig_dir); end
TC=TC(strcmp(TC.phase_type,'training')&isfinite(TC.peak_accel_g)&isfinite(TC.scr_amp_local_bc),:);
fprintf('Training collisions: %d  N:%d  H:%d\n',height(TC),sum(~TC.haptic),sum(TC.haptic));

qprobs=[0 0.25 0.50 0.75 1.0];
edges_N=unique(quantile(TC.peak_accel_g(~TC.haptic),qprobs));
edges_H=unique(quantile(TC.peak_accel_g( TC.haptic),qprobs));
fprintf('N quartile edges (g): '); fprintf('%.3f  ',edges_N); fprintf('\n');
fprintf('H quartile edges (g): '); fprintf('%.3f  ',edges_H); fprintf('\n');

[~,~,binN]=histcounts(TC.peak_accel_g(~TC.haptic),edges_N);
[~,~,binH]=histcounts(TC.peak_accel_g( TC.haptic),edges_H);
TC.intensity_bin=zeros(height(TC),1);
TC.intensity_bin(~TC.haptic)=binN; TC.intensity_bin(TC.haptic)=binH;
n_bins=4;

rows_out={};
for b=1:n_bins
    xN=TC.scr_amp_local_bc(~TC.haptic&TC.intensity_bin==b); xN=xN(isfinite(xN));
    xH=TC.scr_amp_local_bc( TC.haptic&TC.intensity_bin==b); xH=xH(isfinite(xH));
    sdN=std(xN); sdH=std(xH); sdP=std([xN;xH]);
    p_lev=local_levene(xN,xH);
    [~,p_mu]=ttest2(xH,xN,'Vartype','unequal');
    try, p_muw=ranksum(xH,xN); catch, p_muw=NaN; end
    lbl_N=sprintf('Q%d [%.2f-%.2f g]',b,edges_N(b),edges_N(b+1));
    lbl_H=sprintf('Q%d [%.2f-%.2f g]',b,edges_H(b),edges_H(b+1));
    fprintf('Bin %d | N:%s (n=%d) | H:%s (n=%d)\n  SD_N=%.4f SD_H=%.4f ratio=%.3f Levene_p=%.4g mean_diff_p=%.4g\n',...
        b,lbl_N,numel(xN),lbl_H,numel(xH),sdN,sdH,sdN/sdH,p_lev,p_mu);
    rows_out(end+1,:)={b,lbl_N,lbl_H,numel(xN),numel(xH),mean(xN,'omitnan'),mean(xH,'omitnan'),sdN,sdH,sdP,sdN/sdH,p_lev,p_mu,p_muw}; %#ok<AGROW>
end
T_res=cell2table(rows_out,'VariableNames',{'bin','bin_label_N','bin_label_H','n_N','n_H','mean_N','mean_H','sd_N','sd_H','sd_pooled','ratio_sdN_sdH','p_levene','p_mean_ttest','p_mean_wilcoxon'});
T_res.p_levene_fdr=local_fdr(T_res.p_levene);
T_res.p_mean_fdr  =local_fdr(T_res.p_mean_ttest);
disp(T_res(:,{'bin','sd_N','sd_H','ratio_sdN_sdH','p_levene','p_levene_fdr','mean_N','mean_H','p_mean_ttest','p_mean_fdr'}));

fig=figure('Name','H2v2 variance by intensity bin','Position',[50 50 1400 500]);
sgtitle('H2 — EDA response variance, group-specific intensity quartiles (training)','FontWeight','bold');
for b=1:n_bins
    subplot(1,n_bins+1,b); hold on;
    xN=TC.scr_amp_local_bc(~TC.haptic&TC.intensity_bin==b); xN=xN(isfinite(xN));
    xH=TC.scr_amp_local_bc( TC.haptic&TC.intensity_bin==b); xH=xH(isfinite(xH));
    local_strip(xN,1,CN); local_strip(xH,2,CH);
    errorbar(1,mean(xN,'omitnan'),std(xN),'s','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');
    errorbar(2,mean(xH,'omitnan'),std(xH),'s','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');
    title(sprintf('Bin %d\nLev p_{FDR}=%.3f\nSD_N=%.3f SD_H=%.3f',b,T_res.p_levene_fdr(b),T_res.sd_N(b),T_res.sd_H(b)),'FontSize',8);
    xticks([1 2]); xticklabels({'NHF','HF'}); if b==1, ylabel('SCR amp (local bc, resting SD units)','FontSize',8); end
    grid on; xlim([0.5 2.5]);
end
subplot(1,n_bins+1,n_bins+1); hold on;
bar(1:n_bins,T_res.ratio_sdN_sdH,0.5,'FaceColor',[0.5 0.5 0.5]);
yline(1,'r--','LineWidth',1.5); xlabel('Quartile bin'); ylabel('SD\_N/SD\_H');
title('Variance ratio','FontSize',8); set(gca,'XTick',1:n_bins); grid on;
exportgraphics(fig,fullfile(fig_dir,'h2_variance_by_intensity_bin_v2.png'),'Resolution',150); close(fig);
save(fullfile(cfg.output_root,'h2_results_v2.mat'),'T_res','edges_N','edges_H');
writetable(T_res,fullfile(cfg.output_root,'h2_results_v2.csv'));
fprintf('Saved h2_results_v2\n');

function p=local_levene(x1,x2)
    if numel(x1)<2||numel(x2)<2, p=NaN; return; end
    [~,p]=ttest2(abs(x1-median(x1)),abs(x2-median(x2)),'Vartype','unequal');
end
function local_strip(x,xpos,col)
    if isempty(x), return; end
    scatter(xpos+(rand(numel(x),1)-0.5)*0.25,x,15,col,'filled','MarkerFaceAlpha',0.35,'HandleVisibility','off');
end
function p_adj=local_fdr(p)
    p=p(:); n=numel(p); p_adj=nan(n,1); valid=find(isfinite(p)); [ps,ix]=sort(p(valid)); m=numel(ps); adj=nan(m,1); prev=1;
    for k=m:-1:1, val=ps(k)*m/k; prev=min(prev,val); adj(k)=prev; end
    p_adj(valid(ix))=min(adj,1);
end