%% generate_all_paper_figures.m
clear; clc; close all;
cfg = config();
CN = [64 96 179]/255;
CH = [139 82 168]/255;
fig_dir = fullfile(cfg.output_root,'figures','paper');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

% Load all tables
T_perf = load(fullfile(cfg.output_root,'perf_features.mat'),'T'); T_perf = T_perf.T;
T_eda  = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); T_eda = T_eda.T;
T_eye  = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T'); T_eye = T_eye.T;
T_fv   = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); T_fv = T_fv.T;

% Load all LMM results
lmm_eda  = load(fullfile(cfg.output_root,'training_lmm_results.mat'));
lmm_eye  = load(fullfile(cfg.output_root,'eye_lmm_results.mat'));
lmm_perf = load(fullfile(cfg.output_root,'performance_lmm_results.mat'));
lmm_tss  = load(fullfile(cfg.output_root,'lmm_tssv_tssf_results.mat'));
xmod     = load(fullfile(cfg.output_root,'cross_modal_correlation_results.mat'));
tr_eda   = load(fullfile(cfg.output_root,'transfer_lmm_results.mat'));
tr_eye   = load(fullfile(cfg.output_root,'eye_transfer_lmm_results.mat'));
tr_tss   = load(fullfile(cfg.output_root,'force_vibration_transfer_lmm_results.mat'));
threeway = load(fullfile(cfg.output_root,'training_lmm_3way_results.mat'));

levels = 1:5; lnames = {'L1','L2','L3','L4','L5'};

%% Rebuild joined tables for scatter plots
T_eda_tr  = T_eda(strcmp(T_eda.phase_type,'training'),:);
T_eye_tr  = T_eye(strcmp(T_eye.phase_type,'training'),:);
T_fv_tr   = T_fv(strcmp(T_fv.phase_type,'training'),:);
T_perf_tr = T_perf(strcmp(T_perf.phase_type,'training'),:);
T_perf_tr.Properties.VariableNames{'duration_s'}   = 'duration_s_perf';
T_perf_tr.Properties.VariableNames{'n_collisions'} = 'n_collisions_perf';

T_ep = innerjoin(T_eda_tr, T_perf_tr,'Keys',{'subject','level','repetition'}, ...
    'RightVariables',{'duration_s_perf','n_collisions_perf'});
T_eyep = innerjoin(T_eye_tr, T_perf_tr,'Keys',{'subject','level','repetition'}, ...
    'RightVariables',{'duration_s_perf','n_collisions_perf'});
T_fv_eda = innerjoin(T_fv_tr, T_eda_tr,'Keys',{'subject','level','repetition'}, ...
    'RightVariables',{'scl_mean_bc','haptic'});
T_fv_eda.haptic = cellfun(@(s) strcmp(s(end),'H'), T_fv_eda.subject);
T_fv_eda.tssf(T_fv_eda.tssf<=0)=NaN; T_fv_eda.tssf_log=log(T_fv_eda.tssf);
T_fv_eda.tssv(T_fv_eda.tssv<=0)=NaN; T_fv_eda.tssv_log=log(T_fv_eda.tssv);


T_ep      = add_within_z(T_ep,     'scl_mean_bc',  'scl_z');
T_ep      = add_within_z(T_ep,     'scr_mean_amp_bc','scr_z');
T_eyep    = add_within_z(T_eyep,   'pupil_mean_norm','pup_z');
T_eyep    = add_within_z(T_eyep,   'gaze_entropy',  'ent_z');
T_eyep    = add_within_z(T_eyep,   'saccade_rate',  'sac_z');
T_fv_eda  = add_within_z(T_fv_eda, 'tssf_log',      'tssf_z');
T_fv_eda  = add_within_z(T_fv_eda, 'tssv_log',      'tssv_z');


%% FIG 1: Completion time learning curve

fig1=figure('Position',[2000 2000 700 420]); hold on;
T_tr=T_perf(strcmp(T_perf.phase_type,'training'),:);
for grp=[false true]
    col=local_col(grp,CN,CH); lbl=local_lbl(grp);
    Tg=T_tr(T_tr.haptic==grp,:);
    subjs=unique(Tg.subject); mu=nan(1,10); se=nan(1,10);
    for r=1:10
        v=arrayfun(@(s) mean(Tg.duration_s(strcmp(Tg.subject,s{1})&Tg.repetition==r),'omitnan'),subjs);
        v=v(isfinite(v)); mu(r)=mean(v); se(r)=std(v)/sqrt(numel(v));
    end
    fill([1:10 10:-1:1],[mu+1.96*se fliplr(mu-1.96*se)],col,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    plot(1:10,mu,'o-','Color',col,'LineWidth',2,'MarkerFaceColor',col,'MarkerSize',6,'DisplayName',lbl);
end
xlabel('Repetition within level (pooled)'); ylabel('Completion time (s)');
legend('Location','northeast','FontSize',10); title('Fig 1 — Completion time: within-level learning curve');
grid on; box on;
exportgraphics(fig1,fullfile(fig_dir,'fig1_completion_time_curve.png'),'Resolution',180);


%% FIG 2: Collision count by level and group

fig2=figure('Position',[2000 2000 700 420]); hold on;
T_tr=T_perf(strcmp(T_perf.phase_type,'training'),:);
for grp=[false true]
    col=local_col(grp,CN,CH); lbl=local_lbl(grp);
    Tg=T_tr(T_tr.haptic==grp,:);
    subjs=unique(Tg.subject); mu=nan(1,5); se=nan(1,5);
    for lv=1:5
        v=arrayfun(@(s) mean(Tg.n_collisions(strcmp(Tg.subject,s{1})&Tg.level==lv),'omitnan'),subjs);
        v=v(isfinite(v)); mu(lv)=mean(v); se(lv)=std(v)/sqrt(numel(v));
    end
    fill([levels fliplr(levels)],[mu+1.96*se fliplr(mu-1.96*se)],col,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    plot(levels,mu,'o-','Color',col,'LineWidth',2,'MarkerFaceColor',col,'MarkerSize',7,'DisplayName',lbl);
end
set(gca,'XTick',1:5,'XTickLabel',lnames);
xlabel('Training difficulty level'); ylabel('Mean collision count per trial');
legend('Location','northwest','FontSize',10); title('Fig 2 — Collision count by level (no group difference)');
grid on; box on;
exportgraphics(fig2,fullfile(fig_dir,'fig2_collision_count.png'),'Resolution',180);


%% FIG 3: TSSV and TSSF by level (LMM means, start vs end)

fig3=figure('Position',[2000 2000 1000 420]);
metrics3={'tssv','tssf'}; ylabs3={'log(TSSV) [(m/s^2)^2 s]','log(TSSF) [N^2]'};
for mi=1:2
    subplot(1,2,mi); hold on;
    oc=metrics3{mi};
    Ttr=T_fv(strcmp(T_fv.phase_type,'training')&isfinite(T_fv.(oc))&T_fv.(oc)>0,:);
    Ttr.log_m=log(Ttr.(oc));
    for grp=[false true]
        col=local_col(grp,CN,CH); lbl=local_lbl(grp);
        Tg=Ttr(Ttr.haptic==grp,:);
        subjs=unique(Tg.subject);
        mu_s=nan(1,5); se_s=nan(1,5); mu_e=nan(1,5); se_e=nan(1,5);
        for lv=1:5
            vs=arrayfun(@(s) mean(Tg.log_m(strcmp(Tg.subject,s{1})&Tg.level==lv&Tg.repetition<=3),'omitnan'),subjs);
            ve=arrayfun(@(s) mean(Tg.log_m(strcmp(Tg.subject,s{1})&Tg.level==lv&Tg.repetition>=8),'omitnan'),subjs);
            vs=vs(isfinite(vs)); ve=ve(isfinite(ve));
            mu_s(lv)=mean(vs); se_s(lv)=std(vs)/sqrt(numel(vs));
            mu_e(lv)=mean(ve); se_e(lv)=std(ve)/sqrt(numel(ve));
        end
        plot(levels,mu_s,'o--','Color',col,'LineWidth',1.5,'MarkerFaceColor','w','MarkerSize',6,'HandleVisibility','off');
        plot(levels,mu_e,'o-','Color',col,'LineWidth',2,'MarkerFaceColor',col,'MarkerSize',7,'DisplayName',sprintf('%s end',lbl));
    end
    set(gca,'XTick',1:5,'XTickLabel',lnames);
    xlabel('Training level'); ylabel(ylabs3{mi},'FontSize',9);
    title(sprintf('%s by level (solid=end, dashed=start)',upper(oc)));
    legend('Location','northwest','FontSize',8); grid on; box on;
end
sgtitle('Fig 3 — TSSV and TSSF by difficulty level','FontWeight','bold');
exportgraphics(fig3,fullfile(fig_dir,'fig3_tssv_tssf_by_level.png'),'Resolution',180);


%% FIG 4: TSSV and TSSF pre-post paired lines

fig4=figure('Position',[2000 2000 1000 420]);
metrics4={'tssv','tssf'}; ylabs4={'log(TSSV)','log(TSSF)'};
for mi=1:2
    subplot(1,2,mi); hold on;
    oc=metrics4{mi};
    T4=T_fv(ismember(T_fv.phase,{'Baseline1','Baseline2'})&isfinite(T_fv.(oc))&T_fv.(oc)>0,:);
    T4.log_m=log(T4.(oc));
    subjs=unique(T4.subject);
    for grp=[false true]
        col=local_col(grp,CN,CH);
        for si=1:numel(subjs)
            s=subjs{si};
            if T_fv.haptic(strcmp(T_fv.subject,s),1)~=grp, continue; end
            v1=mean(T4.log_m(strcmp(T4.subject,s)&strcmp(T4.phase,'Baseline1')),'omitnan');
            v2=mean(T4.log_m(strcmp(T4.subject,s)&strcmp(T4.phase,'Baseline2')),'omitnan');
            if isfinite(v1)&&isfinite(v2)
                plot([1 2],[v1 v2],'-','Color',[col 0.2],'LineWidth',0.8,'HandleVisibility','off');
            end
        end
        mu_pre=nan; mu_post=nan; se_pre=nan; se_post=nan;
        vv=arrayfun(@(s) mean(T4.log_m(strcmp(T4.subject,s{1})&strcmp(T4.phase,'Baseline1')&T4.haptic==grp),'omitnan'),subjs);
        vv=vv(isfinite(vv)); mu_pre=mean(vv); se_pre=std(vv)/sqrt(numel(vv));
        vv=arrayfun(@(s) mean(T4.log_m(strcmp(T4.subject,s{1})&strcmp(T4.phase,'Baseline2')&T4.haptic==grp),'omitnan'),subjs);
        vv=vv(isfinite(vv)); mu_post=mean(vv); se_post=std(vv)/sqrt(numel(vv));
        errorbar([1 2],[mu_pre mu_post],[se_pre*1.96 se_post*1.96],'o-','Color',col,'LineWidth',2.5,'MarkerFaceColor',col,'MarkerSize',8,'DisplayName',local_lbl(grp));
    end
    set(gca,'XTick',[1 2],'XTickLabel',{'Baseline1','Baseline2'});
    ylabel(ylabs4{mi},'FontSize',9); title(sprintf('%s: pre-post change',upper(oc)));
    legend('Location','northeast','FontSize',9); grid on; box on;
end
sgtitle('Fig 4 — TSSV and TSSF: equivalent pre-to-post reduction both groups','FontWeight','bold');
exportgraphics(fig4,fullfile(fig_dir,'fig4_tss_prepost.png'),'Resolution',180);


%% FIG 5: Tonic SCL by level (widening gap)

fig5=figure('Position',[2000 2000 700 420]); hold on;
se5=lmm_eda.results{1}.simple_effects;
mu_N=zeros(1,5); se_N=zeros(1,5); mu_H=zeros(1,5); se_H=zeros(1,5);
for lv=2:5
    rN=se5(strcmp(se5.effect,sprintf('level %d vs level 1',lv))&strcmp(se5.group,'N'),:);
    rH=se5(strcmp(se5.effect,sprintf('level %d vs level 1',lv))&strcmp(se5.group,'H'),:);
    if ~isempty(rN), mu_N(lv)=rN.beta; se_N(lv)=rN.se; end
    if ~isempty(rH), mu_H(lv)=rH.beta; se_H(lv)=rH.se; end
end
fill([levels fliplr(levels)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
fill([levels fliplr(levels)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
plot(levels,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
plot(levels,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
p_fdr=lmm_eda.lh_p_fdr; lh_t=lmm_eda.lh_term; lh_o=lmm_eda.lh_outcome;
for lv=2:5
    idx=find(strcmp(lh_o,'scl_mean_bc')&strcmp(lh_t,sprintf('level_cat_%d:haptic_num',lv)));
    if ~isempty(idx)&&p_fdr(idx)<0.1
        yp=max(mu_H(lv)+1.96*se_H(lv),mu_N(lv)+1.96*se_N(lv))+0.05;
        text(lv,yp,local_stars(p_fdr(idx)),'HorizontalAlignment','center','FontSize',14);
    end
end
set(gca,'XTick',1:5,'XTickLabel',lnames);
xlabel('Training difficulty level'); ylabel('Tonic SCL difference from Level 1 (\muS)');
legend('Location','northwest','FontSize',10);
title('Fig 5 — Tonic SCL: HF-NHF gap widens with difficulty');
grid on; box on;
exportgraphics(fig5,fullfile(fig_dir,'fig5_scl_by_level.png'),'Resolution',180);


%% FIG 6: SCR frequency dissociation at Level 5

fig6=figure('Position',[2000 2000 1000 420]);
subplot(1,2,1); hold on;
se6=lmm_eda.results{2}.simple_effects;
mu_N=zeros(1,5); se_N=zeros(1,5); mu_H=zeros(1,5); se_H=zeros(1,5);
for lv=2:5
    rN=se6(strcmp(se6.effect,sprintf('level %d vs level 1',lv))&strcmp(se6.group,'N'),:);
    rH=se6(strcmp(se6.effect,sprintf('level %d vs level 1',lv))&strcmp(se6.group,'H'),:);
    if ~isempty(rN), mu_N(lv)=rN.beta; se_N(lv)=rN.se; end
    if ~isempty(rH), mu_H(lv)=rH.beta; se_H(lv)=rH.se; end
end
fill([levels fliplr(levels)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
fill([levels fliplr(levels)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
plot(levels,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
plot(levels,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
yline(0,'k--','LineWidth',1,'HandleVisibility','off');
set(gca,'XTick',1:5,'XTickLabel',lnames);
xlabel('Training level'); ylabel('SCR frequency vs Level 1 (SCR/min)');
legend('Location','southwest','FontSize',9); title('SCR frequency by level');
grid on; box on;

subplot(1,2,2); hold on;
groups_bar={'NHF','HF'}; x_bar=[1 2];
lv5_N=se6(strcmp(se6.effect,'level 5 vs level 1')&strcmp(se6.group,'N'),:);
lv5_H=se6(strcmp(se6.effect,'level 5 vs level 1')&strcmp(se6.group,'H'),:);
b=bar(x_bar,[lv5_N.beta lv5_H.beta],0.5);
b.FaceColor='flat'; b.CData(1,:)=CN; b.CData(2,:)=CH;
errorbar(x_bar,[lv5_N.beta lv5_H.beta],[lv5_N.se*1.96 lv5_H.se*1.96],'k.','LineWidth',1.5,'HandleVisibility','off');
yline(0,'k--','LineWidth',1,'HandleVisibility','off');
text(1,lv5_N.beta-0.3*sign(lv5_N.beta),sprintf('p=%.3f',lv5_N.p),'HorizontalAlignment','center','FontSize',9);
text(2,lv5_H.beta+0.3*sign(lv5_H.beta),sprintf('p=%.3f',lv5_H.p),'HorizontalAlignment','center','FontSize',9);
set(gca,'XTick',1:2,'XTickLabel',groups_bar);
ylabel('SCR frequency at L5 vs L1 (SCR/min)');
title('Level 5 vs Level 1 simple effect');
grid on; box on;
sgtitle('Fig 6 — SCR frequency: NHF decreases at L5, HF stable','FontWeight','bold');
exportgraphics(fig6,fullfile(fig_dir,'fig6_scr_freq_dissociation.png'),'Resolution',180);


%% FIG 7: EDA transfer paired plots

fig7=figure('Position',[2000 2000 1100 420]);
outcomes7={'scl_mean','scr_freq'}; ylabs7={'Tonic SCL (\muS)','SCR frequency (SCR/min)'};
pvals7=[tr_eda.all_results.baseline_transfer_elastic.p_fdr(1) tr_eda.all_results.baseline_transfer_elastic.p_fdr(2)];
for oi=1:2
    subplot(1,2,oi); hold on;
    oc=outcomes7{oi};
    T7=T_eda(ismember(T_eda.phase,{'Baseline1','Baseline2'})&isfinite(T_eda.(oc)),:);
    subjs=unique(T7.subject);
    for grp=[false true]
        col=local_col(grp,CN,CH);
        for si=1:numel(subjs)
            s=subjs{si};
            rows=T7(strcmp(T7.subject,s)&T7.haptic==grp,:);
            if isempty(rows), continue; end
            v1=mean(rows.(oc)(strcmp(rows.phase,'Baseline1')),'omitnan');
            v2=mean(rows.(oc)(strcmp(rows.phase,'Baseline2')),'omitnan');
            if isfinite(v1)&&isfinite(v2)
                plot([1 2],[v1 v2],'-','Color',[col 0.2],'LineWidth',0.8,'HandleVisibility','off');
            end
        end
        vv1=arrayfun(@(s) mean(T7.(oc)(strcmp(T7.subject,s{1})&strcmp(T7.phase,'Baseline1')&T7.haptic==grp),'omitnan'),subjs);
        vv2=arrayfun(@(s) mean(T7.(oc)(strcmp(T7.subject,s{1})&strcmp(T7.phase,'Baseline2')&T7.haptic==grp),'omitnan'),subjs);
        vv1=vv1(isfinite(vv1)); vv2=vv2(isfinite(vv2));
        errorbar([1 2],[mean(vv1) mean(vv2)],[std(vv1)/sqrt(numel(vv1))*1.96 std(vv2)/sqrt(numel(vv2))*1.96], ...
            'o-','Color',col,'LineWidth',2.5,'MarkerFaceColor',col,'MarkerSize',8,'DisplayName',local_lbl(grp));
    end
    plot([1.4 1.6],[1 1]*max(ylim)*0.95,'k-','LineWidth',1,'HandleVisibility','off');
    text(1.5,max(ylim)*0.97,local_stars(pvals7(oi)),'HorizontalAlignment','center','FontSize',14);
    set(gca,'XTick',[1 2],'XTickLabel',{'Baseline1','Baseline2'});
    ylabel(ylabs7{oi},'FontSize',9); title(sprintf('%s: pre→post transfer',outcomes7{oi}));
    legend('Location','best','FontSize',9); grid on; box on;
end
sgtitle('Fig 7 — EDA transfer: HF shows greater increase BL1→BL2','FontWeight','bold');
exportgraphics(fig7,fullfile(fig_dir,'fig7_eda_transfer.png'),'Resolution',180);


%% FIG 8: Three-way: HF phasic EDA habituation at Level 5

CN=[64 96 179]/255; CH=[139 82 168]/255;
T=load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); T=T.T;
T_tr=T(strcmp(T.phase_type,'training'),:);
T_excl=T_tr(~strcmp(T_tr.subject,'subject_s41H'),:);

fig=figure('Position',[2000 2000 1400 500]);
tl=tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
sgtitle('Fig 8 — Level 5 within-level trajectory: full sample vs s41H excluded','FontWeight','bold','FontSize',11);

for panel=1:2
    if panel<=2
        oc={'scr_mean_amp_bc','Phasic SCR amp (normalised)'}; 
    else
        oc={'collision_scr_amp_mean_bc','ER-SCR amp (normalised)'}; 
    end
    T8=T_excl; ttl='s41H excluded'; 
    oc_name=oc{1}; oc_lab=oc{2};
    T5=T8(T8.level==5&isfinite(T8.(oc_name)),:);
    nexttile; hold on;
    for grp=[false true]
        col=local_col(grp,CN,CH); lbl=local_lbl(grp);
        Tg=T5(T5.haptic==grp,:);
        subjs=unique(Tg.subject);
        mu=nan(1,10); se=nan(1,10);
        for r=1:10
            v=arrayfun(@(s) mean(Tg.(oc_name)(strcmp(Tg.subject,s{1})&Tg.repetition==r),'omitnan'),subjs);
            v=v(isfinite(v)); mu(r)=mean(v); se(r)=std(v)/sqrt(numel(v));
        end
        fill([1:10 10:-1:1],[mu+1.96*se fliplr(mu-1.96*se)],col,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
        plot(1:10,mu,'o-','Color',col,'LineWidth',2,'MarkerFaceColor',col,'MarkerSize',6,'DisplayName',lbl);
    end
    xlabel('Repetition within Level 5'); ylabel(oc_lab,'FontSize',8);
    title(sprintf('%s\n(%s)',strrep(oc_name,'_',' '),ttl),'FontSize',8);
    legend('Location','northeast','FontSize',8); grid on; box on;
end
exportgraphics(fig,fullfile(cfg.output_root,'figures','paper','fig8_sensitivity_s41H.png'),'Resolution',180);

%% check_rep1_spike_all_levels.m
T = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); T=T.T;
T_tr = T(strcmp(T.phase_type,'training'),:);
outcomes = {'scr_mean_amp_bc','collision_scr_amp_mean_bc'};
levels = 1:5;
fig = figure('Position',[2000 2000 1400 500]);
tl = tiledlayout(2,5,'TileSpacing','compact','Padding','compact');
sgtitle('Rep 1 vs Rep 2-10 mean: does HF spike at every level?','FontWeight','bold');

for oi = 1:2
    oc = outcomes{oi};
    for lv = levels
        nexttile;
        Tl = T_tr(T_tr.level==lv & isfinite(T_tr.(oc)),:);
        reps = 1:10; mu_N=nan(1,10); se_N=nan(1,10); mu_H=nan(1,10); se_H=nan(1,10);
        for r = reps
            vN = arrayfun(@(s) mean(Tl.(oc)(strcmp(Tl.subject,s{1})&Tl.repetition==r&~Tl.haptic),'omitnan'), unique(Tl.subject));
            vH = arrayfun(@(s) mean(Tl.(oc)(strcmp(Tl.subject,s{1})&Tl.repetition==r&Tl.haptic),'omitnan'), unique(Tl.subject));
            vN=vN(isfinite(vN)); vH=vH(isfinite(vH));
            mu_N(r)=mean(vN); se_N(r)=std(vN)/sqrt(numel(vN));
            mu_H(r)=mean(vH); se_H(r)=std(vH)/sqrt(numel(vH));
        end
        hold on;
        fill([reps fliplr(reps)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],[0.25 0.38 0.70],'FaceAlpha',0.15,'EdgeColor','none');
        fill([reps fliplr(reps)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],[0.55 0.32 0.66],'FaceAlpha',0.15,'EdgeColor','none');
        plot(reps,mu_N,'o-','Color',[0.25 0.38 0.70],'LineWidth',1.8,'MarkerFaceColor',[0.25 0.38 0.70],'MarkerSize',5);
        plot(reps,mu_H,'o-','Color',[0.55 0.32 0.66],'LineWidth',1.8,'MarkerFaceColor',[0.55 0.32 0.66],'MarkerSize',5);
        title(sprintf('%s L%d',strrep(oc,'_',' '),lv),'FontSize',7);
        xlabel('Rep'); if r==1, ylabel(oc,'FontSize',6); end
        grid on; box on;
        % Check rep 1 vs rep 2-10 significance within HF
        subj_HF = unique(Tl.subject(Tl.haptic==1));
        vH1 = nan(numel(subj_HF),1);
        vH2plus = nan(numel(subj_HF),1);
        for si = 1:numel(subj_HF)
            s = subj_HF{si};
            v1 = Tl.(oc)(strcmp(Tl.subject,s) & Tl.repetition==1 & Tl.haptic==1);
            v2 = Tl.(oc)(strcmp(Tl.subject,s) & Tl.repetition>1 & Tl.haptic==1);
            if ~isempty(v1), vH1(si) = mean(v1,'omitnan'); end
            if ~isempty(v2), vH2plus(si) = mean(v2,'omitnan'); end
        end
        keep = isfinite(vH1) & isfinite(vH2plus);
        if sum(keep) >= 3
            [~,p_spike] = ttest(vH1(keep), vH2plus(keep));
        else
            p_spike = NaN;
        end
        title(sprintf('L%d (rep1vsrest p=%.3f)',lv,p_spike),'FontSize',7);
                title(sprintf('L%d (rep1vsrest p=%.3f)',lv,p_spike),'FontSize',7);
            end
end
exportgraphics(fig,fullfile(cfg.output_root,'figures','paper','fig8_all_levels_rep1_check.png'),'Resolution',150);
% Check how many HF subjects drive the spike
Tl5_HF = T_tr(T_tr.level==5 & T_tr.repetition==1 & T_tr.haptic==1,:);
subj_vals = arrayfun(@(s) mean(Tl5_HF.scr_mean_amp_bc(strcmp(Tl5_HF.subject,s{1})),'omitnan'), unique(Tl5_HF.subject));
subj_names = unique(Tl5_HF.subject);
fprintf('HF subjects at L5 rep1 (scr_mean_amp_bc):\n');
for si=1:numel(subj_names)
    fprintf('  %s: %.4f\n', subj_names{si}, subj_vals(si));
end
fprintf('Mean=%.4f SD=%.4f\n',mean(subj_vals,'omitnan'),std(subj_vals,'omitnan'));
%% FIG 9: Gaze entropy by level

fig9=figure('Position',[2000 2000 700 420]); hold on;
se9=lmm_eye.results{1}.simple_effects;
mu_N=zeros(1,5); se_N=zeros(1,5); mu_H=zeros(1,5); se_H=zeros(1,5);
for lv=2:5
    rN=se9(strcmp(se9.effect,sprintf('level %d vs level 1',lv))&strcmp(se9.group,'N'),:);
    rH=se9(strcmp(se9.effect,sprintf('level %d vs level 1',lv))&strcmp(se9.group,'H'),:);
    if ~isempty(rN), mu_N(lv)=rN.beta; se_N(lv)=rN.se; end
    if ~isempty(rH), mu_H(lv)=rH.beta; se_H(lv)=rH.se; end
end
fill([levels fliplr(levels)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
fill([levels fliplr(levels)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
plot(levels,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
plot(levels,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
yline(0,'k--','LineWidth',1,'HandleVisibility','off');
p_fdr_eye=lmm_eye.lh_p_fdr; lh_t_eye=lmm_eye.lh_term; lh_o_eye=lmm_eye.lh_outcome;
for lv=[4 5]
    idx=find(strcmp(lh_o_eye,'gaze_entropy')&strcmp(lh_t_eye,sprintf('level_cat_%d:haptic_num',lv)));
    if ~isempty(idx)&&p_fdr_eye(idx)<0.05
        yp=max(mu_H(lv)+1.96*se_H(lv),mu_N(lv)+1.96*se_N(lv))+0.02;
        text(lv,yp,local_stars(p_fdr_eye(idx)),'HorizontalAlignment','center','FontSize',14);
    end
end
set(gca,'XTick',1:5,'XTickLabel',lnames);
xlabel('Training difficulty level'); ylabel('Gaze entropy vs Level 1 (bits)');
legend('Location','northwest','FontSize',10);
title('Fig 9 — Gaze entropy: NHF scans more randomly at high difficulty');
grid on; box on;
exportgraphics(fig9,fullfile(fig_dir,'fig9_gaze_entropy.png'),'Resolution',180);


%% FIG 10: Fixation rate reversal

fig10=figure('Position',[2000 2000 1100 420]);
subplot(1,2,1); hold on;
se10=lmm_eye.results{3}.simple_effects;
mu_N=zeros(1,5); se_N=zeros(1,5); mu_H=zeros(1,5); se_H=zeros(1,5);
for lv=2:5
    rN=se10(strcmp(se10.effect,sprintf('level %d vs level 1',lv))&strcmp(se10.group,'N'),:);
    rH=se10(strcmp(se10.effect,sprintf('level %d vs level 1',lv))&strcmp(se10.group,'H'),:);
    if ~isempty(rN), mu_N(lv)=rN.beta; se_N(lv)=rN.se; end
    if ~isempty(rH), mu_H(lv)=rH.beta; se_H(lv)=rH.se; end
end
fill([levels fliplr(levels)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
fill([levels fliplr(levels)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
plot(levels,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
plot(levels,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
yline(0,'k--','LineWidth',1,'HandleVisibility','off');
set(gca,'XTick',1:5,'XTickLabel',lnames);
xlabel('Training level'); ylabel('Fixation rate vs L1 (fix/min)');
legend('Location','southwest','FontSize',9); title('Fixation rate: complete direction reversal');
grid on; box on;

subplot(1,2,2); hold on;
x_lvls=2:5; bar_w=0.35;
mu_N_all=arrayfun(@(lv) se10.beta(strcmp(se10.effect,sprintf('level %d vs level 1',lv))&strcmp(se10.group,'N')),2:5);
mu_H_all=arrayfun(@(lv) se10.beta(strcmp(se10.effect,sprintf('level %d vs level 1',lv))&strcmp(se10.group,'H')),2:5);
se_N_all=arrayfun(@(lv) se10.se(strcmp(se10.effect,sprintf('level %d vs level 1',lv))&strcmp(se10.group,'N')),2:5);
se_H_all=arrayfun(@(lv) se10.se(strcmp(se10.effect,sprintf('level %d vs level 1',lv))&strcmp(se10.group,'H')),2:5);
bar((1:4)-bar_w/2, mu_N_all, bar_w,'FaceColor',CN,'EdgeColor','none','DisplayName','NHF');
bar((1:4)+bar_w/2, mu_H_all, bar_w,'FaceColor',CH,'EdgeColor','none','DisplayName','HF');
errorbar((1:4)-bar_w/2,mu_N_all,se_N_all*1.96,'k.','LineWidth',1.2,'HandleVisibility','off');
errorbar((1:4)+bar_w/2,mu_H_all,se_H_all*1.96,'k.','LineWidth',1.2,'HandleVisibility','off');
yline(0,'k-','LineWidth',1,'HandleVisibility','off');
set(gca,'XTick',1:4,'XTickLabel',{'L2','L3','L4','L5'});
ylabel('Fixation rate simple effect (fix/min)');
title('Per-level simple effects: NHF negative, HF positive');
legend('Location','best','FontSize',9); grid on; box on;
sgtitle('Fig 10 — Fixation rate reversal: NHF fewer, HF more fixations at harder levels','FontWeight','bold');
exportgraphics(fig10,fullfile(fig_dir,'fig10_fixation_rate_reversal.png'),'Resolution',180);


%% FIG 11: Collision-locked pupil response by level

fig11=figure('Position',[2000 2000 700 420]); hold on;
se11=lmm_eye.results{6}.simple_effects;
mu_N=zeros(1,5); se_N=zeros(1,5); mu_H=zeros(1,5); se_H=zeros(1,5);
for lv=2:5
    rN=se11(strcmp(se11.effect,sprintf('level %d vs level 1',lv))&strcmp(se11.group,'N'),:);
    rH=se11(strcmp(se11.effect,sprintf('level %d vs level 1',lv))&strcmp(se11.group,'H'),:);
    if ~isempty(rN), mu_N(lv)=rN.beta; se_N(lv)=rN.se; end
    if ~isempty(rH), mu_H(lv)=rH.beta; se_H(lv)=rH.se; end
end
fill([levels fliplr(levels)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
fill([levels fliplr(levels)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
plot(levels,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
plot(levels,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
yline(0,'k--','LineWidth',1,'HandleVisibility','off');
idx2=find(strcmp(lh_o_eye,'collision_pupil_response_mean')&strcmp(lh_t_eye,'level_cat_2:haptic_num'));
if ~isempty(idx2)&&p_fdr_eye(idx2)<0.05
    yp=max(mu_H(2)+1.96*se_H(2),mu_N(2)+1.96*se_N(2))+0.001;
    text(2,yp,local_stars(p_fdr_eye(idx2)),'HorizontalAlignment','center','FontSize',14);
end
set(gca,'XTick',1:5,'XTickLabel',lnames);
xlabel('Training difficulty level'); ylabel('Collision pupil response vs L1 (fraction of resting)');
legend('Location','northwest','FontSize',10);
title('Fig 11 — Collision-locked pupil: NHF increases at L2, HF stable');
grid on; box on;
exportgraphics(fig11,fullfile(fig_dir,'fig11_collision_pupil.png'),'Resolution',180);


%% FIG 12: Eye tracking transfer paired plots

fig12=figure('Position',[2000 2000 1000 420]);
outcomes12={'fixation_rate','fixation_mean_dur'}; ylabs12={'Fixation rate (fix/min)','Mean fixation duration (s)'};
pvals12=[tr_eye.all_results.baseline_transfer_elastic.p_fdr(4) tr_eye.all_results.baseline_transfer_elastic.p_fdr(5)];
for oi=1:2
    subplot(1,2,oi); hold on;
    oc=outcomes12{oi};
    T12=T_eye(ismember(T_eye.phase,{'Baseline1','Baseline2'})&isfinite(T_eye.(oc)),:);
    subjs=unique(T12.subject);
    for grp=[false true]
        col=local_col(grp,CN,CH);
        for si=1:numel(subjs)
            s=subjs{si};
            rows=T12(strcmp(T12.subject,s)&T12.haptic==grp,:);
            if isempty(rows), continue; end
            v1=mean(rows.(oc)(strcmp(rows.phase,'Baseline1')),'omitnan');
            v2=mean(rows.(oc)(strcmp(rows.phase,'Baseline2')),'omitnan');
            if isfinite(v1)&&isfinite(v2)
                plot([1 2],[v1 v2],'-','Color',[col 0.2],'LineWidth',0.8,'HandleVisibility','off');
            end
        end
        vv1=arrayfun(@(s) mean(T12.(oc)(strcmp(T12.subject,s{1})&strcmp(T12.phase,'Baseline1')&T12.haptic==grp),'omitnan'),subjs);
        vv2=arrayfun(@(s) mean(T12.(oc)(strcmp(T12.subject,s{1})&strcmp(T12.phase,'Baseline2')&T12.haptic==grp),'omitnan'),subjs);
        vv1=vv1(isfinite(vv1)); vv2=vv2(isfinite(vv2));
        errorbar([1 2],[mean(vv1) mean(vv2)],[std(vv1)/sqrt(numel(vv1))*1.96 std(vv2)/sqrt(numel(vv2))*1.96],'o-', ...
            'Color',col,'LineWidth',2.5,'MarkerFaceColor',col,'MarkerSize',8,'DisplayName',local_lbl(grp));
    end
    text(1.5,max(ylim)*0.97,sprintf('p_{FDR}=%.3f',pvals12(oi)),'HorizontalAlignment','center','FontSize',9,'Color',[0.5 0 0]);
    set(gca,'XTick',[1 2],'XTickLabel',{'Baseline1','Baseline2'});
    ylabel(ylabs12{oi},'FontSize',9); title(outcomes12{oi});
    legend('Location','northeast','FontSize',9); grid on; box on;
end
sgtitle('Fig 12 — Eye tracking transfer: borderline fixation effects BL1→BL2','FontWeight','bold');
exportgraphics(fig12,fullfile(fig_dir,'fig12_eye_transfer.png'),'Resolution',180);


%% FIG 14: Pupil and entropy vs completion time scatter

fig14=figure('Position',[2000 2000 1200 420]);
r_pup=xmod.all_results.eye_perf(1).result;
r_ent=xmod.all_results.eye_perf(2).result;

subplot(1,2,1); hold on;
for grp=[false true]
    col=local_col(grp,CN,CH); lbl=local_lbl(grp);
    mask=T_eyep.haptic==grp&isfinite(T_eyep.pup_z)&isfinite(T_eyep.duration_s_perf);
    x=T_eyep.pup_z(mask); y=T_eyep.duration_s_perf(mask);
    scatter(x,y,6,col,'filled','MarkerFaceAlpha',0.15,'HandleVisibility','off');
    p=polyfit(x,y,1); xl=[min(x) max(x)];
    plot(xl,polyval(p,xl),'-','Color',col,'LineWidth',2.5,'DisplayName', ...
        sprintf('%s (\\beta=%.1f)',lbl,r_pup.within_beta+grp*r_pup.within_haptic_beta));
end
xlabel('Pupil dilation (within-subj z-score)'); ylabel('Completion time (s)');
title('Pupil → Completion time'); legend('Location','northeast','FontSize',9);
text(0.05,0.97,sprintf('Within \\beta=%.1f, p<0.001\nInteraction p=%.3f',r_pup.within_beta,r_pup.within_haptic_p), ...
    'Units','normalized','VerticalAlignment','top','FontSize',8);
grid on; box on;

subplot(1,2,2); hold on;
for grp=[false true]
    col=local_col(grp,CN,CH); lbl=local_lbl(grp);
    mask=T_eyep.haptic==grp&isfinite(T_eyep.ent_z)&isfinite(T_eyep.duration_s_perf);
    x=T_eyep.ent_z(mask); y=T_eyep.duration_s_perf(mask);
    scatter(x,y,6,col,'filled','MarkerFaceAlpha',0.15,'HandleVisibility','off');
    p=polyfit(x,y,1); xl=[min(x) max(x)];
    plot(xl,polyval(p,xl),'-','Color',col,'LineWidth',2.5,'DisplayName', ...
        sprintf('%s (\\beta=%.1f)',lbl,r_ent.within_beta+grp*r_ent.within_haptic_beta));
end
xlabel('Gaze entropy (within-subj z-score)'); ylabel('Completion time (s)');
title('Gaze entropy → Completion time'); legend('Location','northwest','FontSize',9);
text(0.05,0.97,sprintf('Within \\beta=%.1f, p<0.001\nInteraction p=%.3f',r_ent.within_beta,r_ent.within_haptic_p), ...
    'Units','normalized','VerticalAlignment','top','FontSize',8);
grid on; box on;
sgtitle('Fig 14 — Eye metrics predict within-session performance','FontWeight','bold');
exportgraphics(fig14,fullfile(fig_dir,'fig14_eye_perf_scatter.png'),'Resolution',180);


%% FIG 15: TSSF-SCL coupling scatter (group-specific slopes)

fig15=figure('Position',[2000 2000 1200 420]);
r_tssf=xmod.all_results.mech_eda(2).result;
r_tssv=xmod.all_results.mech_eda(1).result;

subplot(1,2,1); hold on;
for grp=[false true]
    col=local_col(grp,CN,CH); lbl=local_lbl(grp);
    mask=T_fv_eda.haptic==grp&isfinite(T_fv_eda.tssf_z)&isfinite(T_fv_eda.scl_mean_bc);
    x=T_fv_eda.tssf_z(mask); y=T_fv_eda.scl_mean_bc(mask);
    scatter(x,y,6,col,'filled','MarkerFaceAlpha',0.15,'HandleVisibility','off');
    p=polyfit(x,y,1); xl=[min(x) max(x)];
    plot(xl,polyval(p,xl),'-','Color',col,'LineWidth',2.5,'DisplayName', ...
        sprintf('%s (\\beta=%.3f)',lbl,r_tssf.within_beta+grp*r_tssf.within_haptic_beta));
end
xlabel('log(TSSF) (within-subject z-score)'); ylabel('Tonic SCL (\muS)');
title('TSSF → Tonic SCL (significant group interaction)');
legend('Location','northwest','FontSize',9);
text(0.05,0.97,sprintf('Interaction p=%.4f',r_tssf.within_haptic_p), ...
    'Units','normalized','VerticalAlignment','top','FontSize',9,'Color',[0.8 0 0],'FontWeight','bold');
grid on; box on;

subplot(1,2,2); hold on;
betas=[r_tssf.within_beta r_tssf.within_beta+r_tssf.within_haptic_beta];
ses=[r_tssf.within_se sqrt(r_tssf.within_se^2+r_tssf.within_haptic_se^2)];
b=bar([1 2],betas,0.5); b.FaceColor='flat'; b.CData(1,:)=CN; b.CData(2,:)=CH;
errorbar([1 2],betas,ses*1.96,'k.','LineWidth',1.5,'HandleVisibility','off');
yline(0,'k--','LineWidth',1);
set(gca,'XTick',[1 2],'XTickLabel',{'NHF','HF'});
ylabel('Within-subject TSSF-SCL slope (\beta)');
title('Force-arousal coupling slope by group');
text(1.5,max(betas)+max(ses)*1.96*1.2,sprintf('p=%.4f',r_tssf.within_haptic_p), ...
    'HorizontalAlignment','center','FontSize',10,'Color',[0.8 0 0],'FontWeight','bold');
grid on; box on;
sgtitle('Fig 15 — TSSF-SCL coupling is significantly stronger in HF','FontWeight','bold');
exportgraphics(fig15,fullfile(fig_dir,'fig15_tssf_scl_coupling.png'),'Resolution',180);


%% FIG 16: Effect size heatmap

outcomes_hm={'scl\_mean\_bc','scr\_freq','scr\_amp\_bc','er\_scr\_bc','pupil\_norm','gaze\_entropy','fix\_rate','coll\_pupil','TSSV','TSSF','duration\_s','n\_collisions'};
tests_hm={'H×Rep','H×L2','H×L3','H×L4','H×L5','Transfer BL','3-way'};
d_vals=[
    0.05  0.14  0.29  0.23  0.41  1.11  0.19
    0.04  0.04  0.15  0.17  0.38  1.64  0.26
    0.07  0.03  0.10  0.19  0.27  0.00  0.29
    0.06  0.05  0.08  0.22  0.18  0.00  0.27
    0.06  0.13  0.24  0.21  0.14  0.08  0.15
    0.05  0.10  0.26  0.75  0.31  0.14  0.09
    0.06  0.28  0.60  0.41  0.22  0.22  0.08
    0.04  0.17  0.15  0.19  0.04  0.14  0.13
    0.04  0.07  0.06  0.05  0.10  0.01  0.06
    0.06  0.05  0.03  0.09  0.09  0.01  0.07
    0.03  0.05  0.04  0.08  0.06  0.49  0.06
    0.04  0.05  0.05  0.04  0.08  0.52  0.27
];
sig_hm=logical([
    0 0 1 0 1  1 0
    0 0 0 0 1  1 0
    0 0 0 0 0  0 1
    0 0 0 0 0  0 1
    0 0 1 0 0  0 0
    0 0 0 1 1  0 0
    0 1 1 1 0  0 0
    0 0 0 0 1  0 0
    0 0 0 0 0  0 0
    0 0 0 0 0  0 0
    0 0 0 0 0  0 0
    0 0 0 0 0  0 0
]);
fig16=figure('Position',[2000 2000 900 580]);
imagesc(d_vals); colormap(flipud(gray)); cb=colorbar; cb.Label.String='Effect size |d|';
hold on;
[rr,cc]=find(sig_hm);
for k=1:numel(rr)
    text(cc(k),rr(k),'*','HorizontalAlignment','center','VerticalAlignment','middle','FontSize',16,'Color',[0.8 0 0],'FontWeight','bold');
end
set(gca,'XTick',1:numel(tests_hm),'XTickLabel',tests_hm,'XTickLabelRotation',35,'FontSize',9);
set(gca,'YTick',1:numel(outcomes_hm),'YTickLabel',outcomes_hm,'FontSize',9);
title('Fig 16 — Effect size overview across all LMM results (red * = FDR p<0.05)','FontSize',10);
exportgraphics(fig16,fullfile(fig_dir,'fig16_effect_heatmap.png'),'Resolution',180);


%% FIG 17: Conceptual dissociation summary bar chart

fig17=figure('Position',[2000 2000 900 480]); hold on;
outcomes17={'Tonic SCL','SCR freq at L5','Gaze entropy at L4','Fixation rate at L3','TSSV','TSSF'};
d17_N=[0 0 0 0 0 0];
d17_H=[0.62 -1.13 -0.16 0.65 -0.10 -0.09];
colors17=[CH; CN; CN; CH; zeros(1,3)+0.6; zeros(1,3)+0.6];
x17=1:numel(outcomes17);
for k=1:numel(outcomes17)
    col=local_col(d17_H(k)>0,CN,CH);
    bar(k,d17_H(k),0.6,'FaceColor',col,'EdgeColor','none');
end
yline(0,'k-','LineWidth',1.5);
set(gca,'XTick',1:numel(outcomes17),'XTickLabel',outcomes17,'XTickLabelRotation',20,'FontSize',9);
ylabel('Effect direction and magnitude (HF vs NHF simple effect at L4/L5)');
title('Fig 17 — Dissociation: HF higher arousal, NHF higher cognitive load metrics','FontSize',10);
text(0.02,0.97,'Violet = HF higher | Indaco = NHF higher | Grey = no difference', ...
    'Units','normalized','VerticalAlignment','top','FontSize',8);
grid on; box on;
exportgraphics(fig17,fullfile(fig_dir,'fig17_dissociation_summary.png'),'Resolution',180);

fprintf('All 17 figures saved to %s\n',fig_dir);

%% Local helper functions
function col=local_col(grp,CN,CH)
    if grp, col=CH; else, col=CN; end
end
function lbl=local_lbl(grp)
    if grp, lbl='HF'; else, lbl='NHF'; end
end
function s=local_stars(p)
    if p>0.05,s=''; elseif p>0.01,s='*'; elseif p>0.001,s='**'; else,s='***'; end
end
function Tout=add_within_z(Tin,col,zcol)
    Tout=Tin; Tout.(zcol)=nan(height(Tin),1);
    subjs=unique(Tin.subject);
    for si=1:numel(subjs)
        idx=strcmp(Tin.subject,subjs{si});
        v=Tin.(col)(idx);
        Tout.(zcol)(idx)=(v-mean(v,'omitnan'))./(std(v,'omitnan')+1e-12);
    end
end