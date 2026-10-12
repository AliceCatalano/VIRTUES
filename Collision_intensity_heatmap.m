%% collision_intensity_heatmap.m
clear; clc; close all; cfg = config();
CN = [64 96 179]/255; CH = [139 82 168]/255;
fig_dir = fullfile(cfg.output_root,'figures');
CI = load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact'); CI=CI.T_impact;

% assign canonical bins using unified impact_tssv quartiles
CI_tr = CI(strcmp(CI.phase_type,'training') & isfinite(CI.impact_tssv) & CI.impact_tssv>0,:);
CI_tr.log_itssv = log(CI_tr.impact_tssv);
qp=[0 0.25 0.50 0.75 1.0];
eN=quantile(CI_tr.log_itssv(~CI_tr.haptic),qp);
eH=quantile(CI_tr.log_itssv( CI_tr.haptic),qp);
[~,~,bN]=histcounts(CI_tr.log_itssv(~CI_tr.haptic),eN);
[~,~,bH]=histcounts(CI_tr.log_itssv( CI_tr.haptic),eH);
CI_tr.bin=zeros(height(CI_tr),1);
CI_tr.bin(~CI_tr.haptic)=bN; CI_tr.bin(CI_tr.haptic)=bH;

% Figure 1: stacked bar — collision count per level, coloured by intensity bin
fig1=figure('Position',[50 50 900 420]);
tl=tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
title(tl,'Collision count per training level by intensity bin (Q1=lightest, Q4=heaviest)', ...
    'FontWeight','bold','FontSize',11);
bin_cols = [0.35 0.75 0.35; 0.98 0.76 0.15; 0.85 0.43 0.10; 0.65 0.10 0.10];

for grp=[false true]
    col_str=local_ternary(grp,'HF','NHF');
    nexttile; hold on;
    Tg=CI_tr(CI_tr.haptic==grp,:);
    counts=nan(5,4);
    for lv=1:5
        for b=1:4
            counts(lv,b)=sum(Tg.level==lv & Tg.bin==b);
        end
    end
    bh=bar(1:5,counts,'stacked');
    for b=1:4, bh(b).FaceColor=bin_cols(b,:); bh(b).DisplayName=sprintf('Q%d',b); end
    set(gca,'XTick',1:5,'XTickLabel',{'L1','L2','L3','L4','L5'},'FontSize',9);
    xlabel('Training level'); ylabel('Number of collisions');
    title(sprintf('%s — collisions per level by intensity quartile',col_str),'FontSize',10);
    legend('Location','northeast','FontSize',8); grid on; box on;
end
exportgraphics(fig1,fullfile(fig_dir,'collision_count_by_level_and_bin.png'),'Resolution',180);

% Figure 2: per-subject collision count heatmap
subj_list = unique(CI_tr.subject);
mat_N=nan(numel(subj_list),5); mat_H=nan(numel(subj_list),5); is_H=false(numel(subj_list),1);
for si=1:numel(subj_list)
    s=subj_list{si}; Ts=CI_tr(strcmp(CI_tr.subject,s),:);
    is_H(si)=any(Ts.haptic);
    for lv=1:5, count=sum(Ts.level==lv); if is_H(si), mat_H(si,lv)=count; else, mat_N(si,lv)=count; end; end
end

fig2=figure('Position',[50 50 1000 500]);
tl=tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
title(tl,'Per-subject collision count by training level','FontWeight','bold','FontSize',11);
for grp=[false true]
    mat=local_ternary(grp,mat_H,mat_N); subj_g=subj_list(is_H==grp);
    [~,ord]=sort(mean(mat,'omitnan'),'descend');
    nexttile;
    imagesc(mat(is_H==grp,:));
    colormap(parula); colorbar;
    set(gca,'XTick',1:5,'XTickLabel',{'L1','L2','L3','L4','L5'},'FontSize',8);
    yt=strrep(subj_g,'subject_',''); set(gca,'YTick',1:numel(yt),'YTickLabel',yt,'FontSize',7);
    xlabel('Training level'); ylabel('Subject');
    title(local_ternary(grp,'HF','NHF'),'FontSize',10); grid on;
end
exportgraphics(fig2,fullfile(fig_dir,'collision_count_heatmap_per_subject.png'),'Resolution',180);
fprintf('Figures saved.\n');

function out=local_ternary(c,a,b), if c, out=a; else, out=b; end, end