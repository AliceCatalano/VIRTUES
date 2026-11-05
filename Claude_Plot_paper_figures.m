%% Claude_Plot_paper_figures.m
% Corrected copy of Plot_paper_figures.m. Reads the saved results; writes ONLY to
% <output_root>/Claude_outputs/figures/paper. Changes from the original:
%  Fig 7   title: SCL rises more in HF, SCR frequency FALLS LESS in HF (it fell in both groups).
%  Fig 8   panel 1 is now really the full sample (the original plotted s41H-excluded twice).
%  Fig 9   plots gaze_entropy (the original plotted results{1} = pupil_mean_norm).
%  Fig 10  plots fixation_rate (the original plotted results{3} = saccade_rate).
%  Fig 5/6/11 models are looked up by outcome name instead of by position.
%  Fig 14/15 legends no longer attach raw-unit model betas to z-scored axes.
%  Fig 15  HF slope SE uses var(b0+b1) with the covariance term, not var(b0)+var(b1).
%  Fig 16  computed from the saved results (the original was hard-coded, mixed betas with d,
%          and starred the wrong cells).
%  Fig 17  computed from corrected Haptic x Level terms as beta/SE (the original was hard-coded,
%          mixed units, and coloured a negative NHF simple effect as "NHF higher").
% Second revision, after the re-analysis:
%  Figs 5, 6, 9, 10, 11: bands are subject-level (Lk - L1) mean +/- 95% CI, and stars come from
%          Claude_robust_lmms.m. Run that script and Claude_run_eye_lmms.m first.
%  Fig 10  uses the corrected fixation detector. The "reversal" is not present in corrected data.
%  Figs 4, 7, 12: pre and post means use only levels valid in both phases.
%  Fig 12  uses corrected gaze features and corrected transfer tests.
%  Figs 14, 15: titles and text updated; Fig 15 right panel shows the sequential covariate results.
%  Figs 16, 17: use corrected models and corrected gaze features.
clear; clc; close all;
cfg = config();
CN = [64 96 179]/255;
CH = [139 82 168]/255;
fig_dir = fullfile(cfg.output_root,'Claude_outputs','figures','paper');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end
tr_perf = load(fullfile(cfg.output_root,'performance_transfer_lmm_results.mat'));

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
c_dir = fullfile(cfg.output_root,'Claude_outputs');
ROB = load(fullfile(c_dir,'robust_lmm','robust_lmm_results.mat'));
EYEC = load(fullfile(c_dir,'eye','eye_lmm_claude.mat'));
T_eyeC = load(fullfile(c_dir,'eye','eye_features_claude.mat'),'T'); T_eyeC = T_eyeC.T;
FRC = readtable(fullfile(c_dir,'collision_coupling','force_coupling_robustness.csv'));

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
    T4=local_match(T4,'Baseline1','Baseline2');
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
se5=local_model(lmm_eda,'scl_mean_bc').simple_effects;
mu_N=zeros(1,5); se_N=zeros(1,5); mu_H=zeros(1,5); se_H=zeros(1,5);
for lv=2:5
    rN=se5(strcmp(se5.effect,sprintf('level %d vs level 1',lv))&strcmp(se5.group,'N'),:);
    rH=se5(strcmp(se5.effect,sprintf('level %d vs level 1',lv))&strcmp(se5.group,'H'),:);
    if ~isempty(rN), mu_N(lv)=rN.beta; se_N(lv)=rN.se; end
    if ~isempty(rH), mu_H(lv)=rH.beta; se_H(lv)=rH.se; end
end
[mu_N,se_N,mu_H,se_H]=local_level_change(T_eda,'scl_mean_bc');
fill([levels fliplr(levels)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
fill([levels fliplr(levels)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
plot(levels,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
plot(levels,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
p_fdr=lmm_eda.lh_p_fdr; lh_t=lmm_eda.lh_term; lh_o=lmm_eda.lh_outcome;
for lv=2:5
    pr=local_rob(ROB.TR,'scl_mean_bc',lv);
    if pr<0.05
        yp=max(mu_H(lv)+1.96*se_H(lv),mu_N(lv)+1.96*se_N(lv))+0.05;
        text(lv,yp,local_stars(pr),'HorizontalAlignment','center','FontSize',14);
    end
end
set(gca,'XTick',1:5,'XTickLabel',lnames);
xlabel('Training difficulty level'); ylabel('Tonic SCL difference from Level 1 (\muS)');
legend('Location','northwest','FontSize',10);
title({'Fig 5 — Tonic SCL rises with level in both groups','Group difference n.s. after correction (subject-level 95% CI)'});
grid on; box on;
exportgraphics(fig5,fullfile(fig_dir,'fig5_scl_by_level.png'),'Resolution',180);


%% FIG 6: SCR frequency dissociation at Level 5

fig6=figure('Position',[2000 2000 1000 420]);
subplot(1,2,1); hold on;
se6=local_model(lmm_eda,'scr_freq').simple_effects;
mu_N=zeros(1,5); se_N=zeros(1,5); mu_H=zeros(1,5); se_H=zeros(1,5);
for lv=2:5
    rN=se6(strcmp(se6.effect,sprintf('level %d vs level 1',lv))&strcmp(se6.group,'N'),:);
    rH=se6(strcmp(se6.effect,sprintf('level %d vs level 1',lv))&strcmp(se6.group,'H'),:);
    if ~isempty(rN), mu_N(lv)=rN.beta; se_N(lv)=rN.se; end
    if ~isempty(rH), mu_H(lv)=rH.beta; se_H(lv)=rH.se; end
end
[mu_N,se_N,mu_H,se_H]=local_level_change(T_eda,'scr_freq');
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
b=bar(x_bar,[mu_N(5) mu_H(5)],0.5);
b.FaceColor='flat'; b.CData(1,:)=CN; b.CData(2,:)=CH;
errorbar(x_bar,[mu_N(5) mu_H(5)],[se_N(5)*1.96 se_H(5)*1.96],'k.','LineWidth',1.5,'HandleVisibility','off');
yline(0,'k--','LineWidth',1,'HandleVisibility','off');
pr6=ROB.TR(strcmp(ROB.TR.outcome,'scr_freq')&strcmp(ROB.TR.term,'level_cat_5:haptic_num'),:);
text(1.5,0.9*max(ylim),sprintf('Haptic x L5: p=%.3f, p_{FDR}=%.2f',pr6.p_robust,pr6.p_fdr_robust),'HorizontalAlignment','center','FontSize',9);
set(gca,'XTick',1:2,'XTickLabel',groups_bar);
ylabel('SCR frequency at L5 vs L1 (SCR/min)');
title('Level 5 vs Level 1 simple effect');
grid on; box on;
sgtitle('Fig 6 — SCR frequency by level: L5 difference is nominal only after correction','FontWeight','bold');
exportgraphics(fig6,fullfile(fig_dir,'fig6_scr_freq_dissociation.png'),'Resolution',180);


%% FIG 7: EDA transfer paired plots

fig7=figure('Position',[2000 2000 1100 420]);
outcomes7={'scl_mean','scr_freq'}; ylabs7={'Tonic SCL (\muS)','SCR frequency (SCR/min)'};
pvals7=[ROB.TT.p_fdr_robust(strcmp(ROB.TT.task,'elastic')&strcmp(ROB.TT.outcome,'scl_mean')) ROB.TT.p_fdr_robust(strcmp(ROB.TT.task,'elastic')&strcmp(ROB.TT.outcome,'scr_freq'))];
for oi=1:2
    subplot(1,2,oi); hold on;
    oc=outcomes7{oi};
    T7=T_eda(ismember(T_eda.phase,{'Baseline1','Baseline2'})&isfinite(T_eda.(oc)),:);
    T7=local_match(T7,'Baseline1','Baseline2');
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
    text(1.5,max(ylim)*0.97,sprintf('Haptic x Phase p_{FDR}=%.2f',pvals7(oi)),'HorizontalAlignment','center','FontSize',9);
    set(gca,'XTick',[1 2],'XTickLabel',{'Baseline1','Baseline2'});
    ylabel(ylabs7{oi},'FontSize',9); title(sprintf('%s: pre→post transfer',strrep(outcomes7{oi},'_',' ')));
    legend('Location','best','FontSize',9); grid on; box on;
end
sgtitle('Fig 7 — EDA transfer BL1→BL2: no group difference after correction','FontWeight','bold');
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
    if panel==1, T8=T_tr; ttl='full sample'; else, T8=T_excl; ttl='s41H excluded'; end
    oc_name=oc{1}; oc_lab=oc{2};
    T5=T8(T8.level==5&isfinite(T8.(oc_name)),:);
    ax8=nexttile; ax8.Toolbar.Visible='off'; hold on;
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
exportgraphics(fig,fullfile(fig_dir,'fig8_sensitivity_s41H.png'),'Resolution',180);

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
exportgraphics(fig,fullfile(fig_dir,'fig8_all_levels_rep1_check.png'),'Resolution',150);
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
se9=local_model(lmm_eye,'gaze_entropy').simple_effects;
mu_N=zeros(1,5); se_N=zeros(1,5); mu_H=zeros(1,5); se_H=zeros(1,5);
for lv=2:5
    rN=se9(strcmp(se9.effect,sprintf('level %d vs level 1',lv))&strcmp(se9.group,'N'),:);
    rH=se9(strcmp(se9.effect,sprintf('level %d vs level 1',lv))&strcmp(se9.group,'H'),:);
    if ~isempty(rN), mu_N(lv)=rN.beta; se_N(lv)=rN.se; end
    if ~isempty(rH), mu_H(lv)=rH.beta; se_H(lv)=rH.se; end
end
[mu_N,se_N,mu_H,se_H]=local_level_change(T_eye,'gaze_entropy');
fill([levels fliplr(levels)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
fill([levels fliplr(levels)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
plot(levels,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
plot(levels,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
yline(0,'k--','LineWidth',1,'HandleVisibility','off');
p_fdr_eye=lmm_eye.lh_p_fdr; lh_t_eye=lmm_eye.lh_term; lh_o_eye=lmm_eye.lh_outcome;
for lv=[4 5]
    pr=local_rob(ROB.TR,'gaze_entropy',lv);
    if pr<0.05
        yp=max(mu_H(lv)+1.96*se_H(lv),mu_N(lv)+1.96*se_N(lv))+0.02;
        text(lv,yp,local_stars(pr),'HorizontalAlignment','center','FontSize',14);
    end
end
set(gca,'XTick',1:5,'XTickLabel',lnames);
xlabel('Training difficulty level'); ylabel('Gaze entropy vs Level 1 (bits)');
legend('Location','northwest','FontSize',10);
title({'Fig 9 — Gaze entropy (per-trial grid) by level','L4 and L5 differences do not pass FDR after correction'});
grid on; box on;
exportgraphics(fig9,fullfile(fig_dir,'fig9_gaze_entropy.png'),'Resolution',180);


%% FIG 10: Fixation rate reversal

fig10=figure('Position',[2000 2000 1100 420]);
subplot(1,2,1); hold on;
se10=local_model(lmm_eye,'fixation_rate').simple_effects;
mu_N=zeros(1,5); se_N=zeros(1,5); mu_H=zeros(1,5); se_H=zeros(1,5);
for lv=2:5
    rN=se10(strcmp(se10.effect,sprintf('level %d vs level 1',lv))&strcmp(se10.group,'N'),:);
    rH=se10(strcmp(se10.effect,sprintf('level %d vs level 1',lv))&strcmp(se10.group,'H'),:);
    if ~isempty(rN), mu_N(lv)=rN.beta; se_N(lv)=rN.se; end
    if ~isempty(rH), mu_H(lv)=rH.beta; se_H(lv)=rH.se; end
end
[mu_N,se_N,mu_H,se_H]=local_level_change(T_eyeC,'fixation_rate');
fill([levels fliplr(levels)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
fill([levels fliplr(levels)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
plot(levels,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
plot(levels,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
yline(0,'k--','LineWidth',1,'HandleVisibility','off');
set(gca,'XTick',1:5,'XTickLabel',lnames);
xlabel('Training level'); ylabel('Fixation rate vs L1 (fix/min)');
legend('Location','southwest','FontSize',9); title('Fixation rate: change from Level 1');
grid on; box on;

subplot(1,2,2); hold on;
x_lvls=2:5; bar_w=0.35;
mu_N_all=mu_N(2:5); mu_H_all=mu_H(2:5); se_N_all=se_N(2:5); se_H_all=se_H(2:5);
bar((1:4)-bar_w/2, mu_N_all, bar_w,'FaceColor',CN,'EdgeColor','none','DisplayName','NHF');
bar((1:4)+bar_w/2, mu_H_all, bar_w,'FaceColor',CH,'EdgeColor','none','DisplayName','HF');
errorbar((1:4)-bar_w/2,mu_N_all,se_N_all*1.96,'k.','LineWidth',1.2,'HandleVisibility','off');
errorbar((1:4)+bar_w/2,mu_H_all,se_H_all*1.96,'k.','LineWidth',1.2,'HandleVisibility','off');
yline(0,'k-','LineWidth',1,'HandleVisibility','off');
set(gca,'XTick',1:4,'XTickLabel',{'L2','L3','L4','L5'});
ylabel('Fixation rate simple effect (fix/min)');
title('Change from Level 1 (subject-level 95% CI)');
legend('Location','best','FontSize',9); grid on; box on;
sgtitle('Fig 10 — Corrected fixation rate rises with level in both groups, no group difference','FontWeight','bold');
exportgraphics(fig10,fullfile(fig_dir,'fig10_fixation_rate_reversal.png'),'Resolution',180);


%% FIG 11: Collision-locked pupil response by level

fig11=figure('Position',[2000 2000 700 420]); hold on;
se11=local_model(lmm_eye,'collision_pupil_response_mean').simple_effects;
mu_N=zeros(1,5); se_N=zeros(1,5); mu_H=zeros(1,5); se_H=zeros(1,5);
for lv=2:5
    rN=se11(strcmp(se11.effect,sprintf('level %d vs level 1',lv))&strcmp(se11.group,'N'),:);
    rH=se11(strcmp(se11.effect,sprintf('level %d vs level 1',lv))&strcmp(se11.group,'H'),:);
    if ~isempty(rN), mu_N(lv)=rN.beta; se_N(lv)=rN.se; end
    if ~isempty(rH), mu_H(lv)=rH.beta; se_H(lv)=rH.se; end
end
[mu_N,se_N,mu_H,se_H]=local_level_change(T_eye,'collision_pupil_response_mean');
fill([levels fliplr(levels)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
fill([levels fliplr(levels)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
plot(levels,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
plot(levels,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
yline(0,'k--','LineWidth',1,'HandleVisibility','off');
set(gca,'XTick',1:5,'XTickLabel',lnames);
xlabel('Training difficulty level'); ylabel('Collision pupil response vs L1 (fraction of resting)');
legend('Location','northwest','FontSize',10);
title({'Fig 11 — Collision-locked pupil by level','No group difference after correction; pupil samples are sparse'});
grid on; box on;
exportgraphics(fig11,fullfile(fig_dir,'fig11_collision_pupil.png'),'Resolution',180);


%% FIG 12: Eye tracking transfer paired plots

fig12=figure('Position',[2000 2000 1000 420]);
outcomes12={'fixation_rate','fixation_mean_dur'}; ylabs12={'Fixation rate (fix/min)','Mean fixation duration (s)'};
pvals12=[EYEC.TT.p(strcmp(EYEC.TT.task,'elastic')&strcmp(EYEC.TT.outcome,'fixation_rate')) EYEC.TT.p(strcmp(EYEC.TT.task,'elastic')&strcmp(EYEC.TT.outcome,'log_fix_dur'))];
for oi=1:2
    subplot(1,2,oi); hold on;
    oc=outcomes12{oi};
    T12=T_eyeC(ismember(T_eyeC.phase,{'Baseline1','Baseline2'})&isfinite(T_eyeC.(oc)),:);
    T12=local_match(T12,'Baseline1','Baseline2');
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
    text(1.5,max(ylim)*0.97,sprintf('Haptic x Phase p=%.2f',pvals12(oi)),'HorizontalAlignment','center','FontSize',9,'Color',[0.5 0 0]);
    set(gca,'XTick',[1 2],'XTickLabel',{'Baseline1','Baseline2'});
    ylabel(ylabs12{oi},'FontSize',9); title(strrep(outcomes12{oi},'_',' '));
    legend('Location','northeast','FontSize',9); grid on; box on;
end
sgtitle('Fig 12 — Corrected fixation measures BL1→BL2: no group difference','FontWeight','bold');
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
    plot(xl,polyval(p,xl),'-','Color',col,'LineWidth',2.5,'DisplayName',[lbl ' (descriptive fit)']);
end
xlabel('Pupil dilation (within-subj z-score)'); ylabel('Completion time (s)');
title('Pupil → Completion time'); legend('Location','northeast','FontSize',9);
text(0.05,0.97,'Within level: p=.67', ...
    'Units','normalized','VerticalAlignment','top','FontSize',8);
grid on; box on;

subplot(1,2,2); hold on;
for grp=[false true]
    col=local_col(grp,CN,CH); lbl=local_lbl(grp);
    mask=T_eyep.haptic==grp&isfinite(T_eyep.ent_z)&isfinite(T_eyep.duration_s_perf);
    x=T_eyep.ent_z(mask); y=T_eyep.duration_s_perf(mask);
    scatter(x,y,6,col,'filled','MarkerFaceAlpha',0.15,'HandleVisibility','off');
    p=polyfit(x,y,1); xl=[min(x) max(x)];
    plot(xl,polyval(p,xl),'-','Color',col,'LineWidth',2.5,'DisplayName',[lbl ' (descriptive fit)']);
end
xlabel('Gaze entropy (within-subj z-score)'); ylabel('Completion time (s)');
title('Gaze entropy → Completion time'); legend('Location','northwest','FontSize',9);
text(0.05,0.97,'Within level: sign reverses (-1.8 s per SD)', ...
    'Units','normalized','VerticalAlignment','top','FontSize',8);
grid on; box on;
sgtitle('Fig 14 — Pooled across levels: these slopes change or reverse once level is modelled','FontWeight','bold');
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
    plot(xl,polyval(p,xl),'-','Color',col,'LineWidth',2.5,'DisplayName',[lbl ' (descriptive fit)']);
end
xlabel('log(TSSF) (within-subject z-score)'); ylabel('Tonic SCL (\muS)');
title('TSSF → Tonic SCL, pooled across levels');
legend('Location','northwest','FontSize',9);
grid on; box on;

subplot(1,2,2); hold on;
rf=FRC(strcmp(FRC.predictor,'log_tssf'),:);
bar(1:height(rf),-log10(rf.p_interaction),0.6,'FaceColor',[0.6 0.6 0.6],'EdgeColor','none');
yline(-log10(0.05),'k--','p = .05');
set(gca,'XTick',1:height(rf),'XTickLabel',rf.model,'XTickLabelRotation',25);
ylabel('-log_{10} p, HF vs NHF slope difference');
title('Group difference across sequential models');
grid on; box on;
sgtitle('Fig 15 — TSSF-SCL: main effect is a difficulty effect; no robust group difference','FontWeight','bold');
exportgraphics(fig15,fullfile(fig_dir,'fig15_tssf_scl_coupling.png'),'Resolution',180);


%% FIG 16: Evidence overview computed from the saved results
% Value = -log10(p_FDR), using each family's own saved correction. Blank = not tested.
hm_lab={'Tonic SCL','SCR frequency','SCR amplitude','Collision SCR','Pupil','Gaze entropy (per-trial grid)','Collision pupil','Completion time','Collisions','log TSSF','log TSSV'};
hm_oc ={'scl_mean_bc','scr_freq','scr_mean_amp_bc','collision_scr_amp_mean_bc','pupil_mean_norm','gaze_entropy','collision_pupil_response_mean','duration_s','n_collisions','tssf_log','tssv_log'};
hm_trn={'scl_mean','scr_freq','scr_mean_amp_bc','','pupil_mean_norm','gaze_entropy','collision_pupil_response_mean','duration_s','n_collisions','tssf_log','tssv_log'};
tests_hm={'H×Rep','H×L2','H×L3','H×L4','H×L5','Transfer elastic','Transfer peg'};
P_hm=nan(numel(hm_oc),numel(tests_hm));
for oi=1:numel(hm_oc)
    r0=ROB.TR(strcmp(ROB.TR.outcome,hm_oc{oi}),:);
    P_hm(oi,1)=r0.p_fdr_robust(strcmp(r0.term,'repetition:haptic_num'));
    for lv=2:5, P_hm(oi,lv)=r0.p_fdr_robust(strcmp(r0.term,sprintf('level_cat_%d:haptic_num',lv))); end
    if ~isempty(hm_trn{oi})
        k=strcmp(ROB.TT.task,'elastic')&strcmp(ROB.TT.outcome,hm_trn{oi}); P_hm(oi,6)=ROB.TT.p_fdr_robust(k);
        k=strcmp(ROB.TT.task,'peg')&strcmp(ROB.TT.outcome,hm_trn{oi}); P_hm(oi,7)=ROB.TT.p_fdr_robust(k);
    end
end
fig16=figure('Position',[2000 2000 900 560]);
h=imagesc(-log10(P_hm)); set(h,'AlphaData',isfinite(P_hm)); colormap(flipud(gray)); clim([0 3]);
cb=colorbar; cb.Label.String='-log_{10}(p_{FDR}), capped at 3'; hold on;
[rr,cc]=find(P_hm<0.05);
for k=1:numel(rr), text(cc(k),rr(k),'*','HorizontalAlignment','center','VerticalAlignment','middle','FontSize',16,'Color',[0.8 0 0],'FontWeight','bold'); end
set(gca,'XTick',1:numel(tests_hm),'XTickLabel',tests_hm,'XTickLabelRotation',35,'FontSize',9,'YTick',1:numel(hm_lab),'YTickLabel',hm_lab);
title('Fig 16 — Group effects in corrected models (red * = p_{FDR}<.05, blank = not tested)','FontSize',10);
exportgraphics(fig16,fullfile(fig_dir,'fig16_effect_heatmap.png'),'Resolution',180);
writetable(array2table(P_hm,'VariableNames',matlab.lang.makeValidName(tests_hm),'RowNames',hm_oc),fullfile(fileparts(fileparts(fig_dir)),'fig16_p_fdr_table.csv'),'WriteRowNames',true);

%% FIG 17: Dissociation summary from saved Haptic x Level terms (beta/SE, so units are comparable)
d17={'Completion time, L4','duration_s',4;'Collisions, L4','n_collisions',4; ...
     'Tonic SCL, L5','scl_mean_bc',5;'SCR frequency, L5','scr_freq',5; ...
     'Entropy (per-trial grid), L4','gaze_entropy',4;'Fixation rate (corrected), L3','FIX',3};
fig17=figure('Position',[2000 2000 900 480]); hold on;
for k=1:size(d17,1)
    if strcmp(d17{k,2},'FIX')
        q=EYEC.TR(strcmp(EYEC.TR.outcome,'fixation_rate')&strcmp(EYEC.TR.term,sprintf('level_cat_%d:haptic_num',d17{k,3})),:);
        z=q.beta/q.se; pq=q.p_fdr;
    else
        q=ROB.TR(strcmp(ROB.TR.outcome,d17{k,2})&strcmp(ROB.TR.term,sprintf('level_cat_%d:haptic_num',d17{k,3})),:);
        z=q.beta_robust/q.se_robust; pq=q.p_fdr_robust;
    end
    if pq>=0.05, col=[0.7 0.7 0.7]; elseif z>0, col=CH; else, col=CN; end
    bar(k,z,0.6,'FaceColor',col,'EdgeColor','none');
    text(k,z+sign(z+eps)*0.2,sprintf('p_{FDR}=%.2f',pq),'HorizontalAlignment','center','FontSize',8);
end
yline(0,'k-','LineWidth',1.5);
set(gca,'XTick',1:size(d17,1),'XTickLabel',d17(:,1),'XTickLabelRotation',20,'FontSize',9);
ylabel('Haptic \times Level effect, \beta / SE (positive = larger rise in HF than NHF)');
ylim([-3.5 3.5]);
title('Fig 17 — No Haptic x Level effect passes FDR after correction','FontSize',10);
text(0.02,0.97,'Grey = n.s. after FDR','Units','normalized','VerticalAlignment','top','FontSize',8);
grid on; box on;
exportgraphics(fig17,fullfile(fig_dir,'fig17_dissociation_summary.png'),'Resolution',180);

fprintf('Figures saved to %s\n',fig_dir);

%% Local helper functions
function [mN,sN,mH,sH]=local_level_change(T,oc)
    % Subject-level change from Level 1. Returns means and SEs for both groups, with L1 = 0.
    D=T(strcmp(T.phase_type,'training')&isfinite(T.(oc)),:);
    u=unique(D.subject); M=nan(numel(u),5); isH=false(numel(u),1);
    for i=1:numel(u)
        ix=strcmp(D.subject,u{i}); isH(i)=u{i}(end)=='H';
        for l=1:5, M(i,l)=mean(D.(oc)(ix&D.level==l),'omitnan'); end
    end
    d=M-M(:,1);
    mN=mean(d(~isH,:),'omitnan'); sN=std(d(~isH,:),'omitnan')./sqrt(sum(isfinite(d(~isH,:))));
    mH=mean(d(isH,:),'omitnan');  sH=std(d(isH,:),'omitnan')./sqrt(sum(isfinite(d(isH,:))));
end
function p=local_rob(TR,oc,lv)
    p=TR.p_fdr_robust(strcmp(TR.outcome,oc)&strcmp(TR.term,sprintf('level_cat_%d:haptic_num',lv)));
end
function T=local_match(T,p1,p2)
    % Keep, per subject, only acquisitions valid in both phases.
    keep=false(height(T),1); u=unique(T.subject);
    for i=1:numel(u)
        ix=strcmp(T.subject,u{i});
        a=T.acquisition(ix&strcmp(T.phase,p1)); b=T.acquisition(ix&strcmp(T.phase,p2));
        keep=keep|(ix&ismember(T.acquisition,intersect(a,b)));
    end
    T=T(keep,:);
end
function r=local_model(S,name)
    % Look a model up by outcome name so a reordered results file cannot mislabel a figure.
    ix=find(strcmp(S.outcomes,name),1);
    if isempty(ix), error('Outcome %s not in results file.',name); end
    r=S.results{ix};
    if ~strcmp(r.outcome,name), error('Model %d is %s, expected %s.',ix,r.outcome,name); end
end
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