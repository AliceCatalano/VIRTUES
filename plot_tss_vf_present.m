%% tssv_tssf_supervisor_presentation_plots.m
% Complete visual presentation of TSSV and TSSF results.
% Structure:
%   Part 0: Data quality — show what good vs bad signal looks like
%   Part 1: Single-subject signal walkthrough (2 good subjects)
%   Part 2: Cohort-level raw distributions
%   Part 3: Within-group BL1→BL2 change
%   Part 4: Between-group comparisons across all phases
%   Part 5: Collision-level intensity analysis

clear; clc; close all; cfg = config();
CN = [64 96 179]/255; CH = [139 82 168]/255;
fig_dir = fullfile(cfg.output_root,'figures','supervisor_tss');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

FV = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); FV=FV.T;
CI = load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact'); CI=CI.T_impact;

BP_LOW=80; BP_HIGH=1000; SENS=cfg.accel_sensitivity_ms2_per_V;
THR=cfg.tssv_noise_threshold_ms2;

fprintf('All figures will be saved to:\n  %s\n\n',fig_dir);

%% PART 0: Signal quality — one good, one excluded subject side by side

fprintf('--- Part 0: Signal quality ---\n');

cases = {'subject_s40H','level_L3','rep_05','GOOD (s03H, L3r5)'
    'subject_s11N','level_L3','rep_05','EXCLUDED — noise (s11N, L3r5)'};

fig0=figure('Position',[2000 2000 1800 1900]);
tl0=tiledlayout(2,3,'TileSpacing','compact','Padding','compact');
title(tl0,'Part 0 — Signal quality: good signal vs excluded noise signal','FontWeight','bold','FontSize',12);

for ci=1:2
    subj=cases{ci,1}; phase=cases{ci,2}; acq=cases{ci,3}; lbl=cases{ci,4};
    acq_dir=fullfile(cfg.data_root,subj,phase,acq);
    if ~isfolder(acq_dir), nexttile; nexttile; nexttile; continue; end
    ev_path=fullfile(acq_dir,'events.mat'); ac_path=fullfile(acq_dir,'accel.mat');
    if ~isfile(ev_path)||~isfile(ac_path), nexttile; nexttile; nexttile; continue; end
    [t_start,t_end]=safe_trial_window(ev_path);
    LA=load(ac_path,'ACCEL'); t_a=LA.ACCEL.time_rel(:); fs=LA.ACCEL.fs_nominal; dt=1/fs;
    
    rv=LA.ACCEL.data;
    
    bm=t_a>=(t_start-1.0)&t_a<t_start;
    if sum(bm)<3, bm=t_a<(t_a(1)+1.0); end
    
    bias_a = mean(rv(bm,:),1,'omitnan');
    rv_ms2=(rv-bias_a)*SENS;
    tm=t_a>=t_start&t_a<=t_end; t_win=t_a(tm); seg=rv_ms2(tm,:);
    seg_bp=seg;
    if fs/2>BP_HIGH
        [b,a_f]=butter(4,[BP_LOW BP_HIGH]/(fs/2),'bandpass');
        for c=1:6, seg_bp(:,c)=filtfilt(b,a_f,double(seg(:,c))); end
    end
    A_left=sum(seg_bp(:,1:3),2); 
    A_right=sum(seg_bp(:,4:6),2);
    A_left(abs(A_left)<THR)=0; 
    A_right(abs(A_right)<THR)=0;
    A_comb=A_left+A_right;
    tssv=sum(A_comb.^2)*dt; % separate 
    col=local_ternary(ci==1,[0.2 0.6 0.2],[0.8 0.2 0.2]);

    nexttile; plot(t_win-t_win(1),seg(:,1),'Color',[0.6 0.6 0.6],'LineWidth',0.5);
    xlabel('Time (s)'); ylabel('m/s²'); title(sprintf('%s\nRaw Lx channel',lbl),'FontSize',8,'Interpreter','none'); grid on;

    nexttile; plot(t_win-t_win(1),A_left,'Color',col,'LineWidth',0.7);
    xlabel('Time (s)'); ylabel('m/s²'); title(sprintf('Bandpassed 80–1000 Hz\nn\_unique=%.0f  rms=%.4f m/s²',...
        mean(arrayfun(@(c)numel(unique(rv(tm,c))),1:6)),mean(sqrt(mean(seg_bp.^2,1)))),'FontSize',8); grid on;

    nexttile; hold on;
    plot(t_win-t_win(1),A_comb,'Color',col,'LineWidth',0.9);
    yline(THR,'r--','LineWidth',1,'DisplayName',sprintf('threshold %.4f m/s²',THR));
    yline(-THR,'r--','LineWidth',1,'HandleVisibility','off');
    xlabel('Time (s)'); ylabel('m/s²');
    title(sprintf('Combined A_{left+right}\nTSSV=%.4f (m/s²)²*s',tssv),'FontSize',8); legend('FontSize',7); grid on;
end
exportgraphics(fig0,fullfile(fig_dir,'P0_signal_quality.png'),'Resolution',150);
fprintf('  Saved P0_signal_quality.png\n');


%% PART 1: Single-subject signal walkthrough — 2 subjects, all training levels

fprintf('--- Part 1: Single-subject walkthrough ---\n');

demo_subjects = {
    'subject_s41H', 'HF — example subject (s41H)'
    'subject_s46N', 'NHF — example subject (s46N)'
};

for di=1:2
    subj=demo_subjects{di,1}; subj_lbl=demo_subjects{di,2};
    Ts=FV(strcmp(FV.subject,subj)&strcmp(FV.phase_type,'training')&isfinite(FV.tssv)&FV.tssv>0,:);
    Tf=FV(strcmp(FV.subject,subj)&strcmp(FV.phase_type,'training')&isfinite(FV.tssf)&FV.tssf>0,:);

    fig1=figure('Position',[2000 2000 1800 1900]);
    tl1=tiledlayout(2,5,'TileSpacing','compact','Padding','compact');
    title(tl1,sprintf('Part 1 — %s: TSSV (top) and TSSF (bottom) rep-by-rep across all training levels',subj_lbl),...
        'FontWeight','bold','FontSize',11);

    for lv=1:5
        nexttile; hold on;
        Tl=Ts(Ts.level==lv,:);
        if ~isempty(Tl)
            plot(Tl.repetition,log(Tl.tssv),'o-','Color',local_ternary(di==1,CH,CN),...
                'LineWidth',1.5,'MarkerFaceColor',local_ternary(di==1,CH,CN),'MarkerSize',6);
        end
        xlabel('Repetition'); ylabel('log-TSSV','FontSize',8);
        title(sprintf('Level %d',lv),'FontSize',10); set(gca,'XTick',1:10,'FontSize',7); grid on; box on;
        ylim([-3.5 2.5]);xlim([1 10]);
    end
    for lv=1:5
        nexttile; hold on;
        Tl=Tf(Tf.level==lv,:);
        if ~isempty(Tl)
            plot(Tl.repetition,log(Tl.tssf),'s-','Color',local_ternary(di==1,CH,CN),...
                'LineWidth',1.5,'MarkerFaceColor',local_ternary(di==1,CH,CN),'MarkerSize',6);
        end
        xlabel('Repetition'); ylabel('log-TSSF','FontSize',8);
        title(sprintf('Level %d',lv),'FontSize',10); set(gca,'XTick',1:10,'FontSize',7); grid on; box on;
        ylim([8.5 15]);xlim([1 10]);
    end
    fname=sprintf('P1_single_subject_%s.png',strrep(subj,'subject_',''));
    exportgraphics(fig1,fullfile(fig_dir,fname),'Resolution',150);
    fprintf('  Saved %s\n',fname);
end


%% PART 2: Cohort distributions — raw data before any analysis

fprintf('--- Part 2: Cohort distributions ---\n');

fig2=figure('Position',[2000 2000 1800 1900]);
tl2=tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
title(tl2,'Part 2 — Cohort-level distributions: raw log-TSSV and log-TSSF (training phase, all subjects)','FontWeight','bold','FontSize',11);

TR_tssv=FV(strcmp(FV.phase_type,'training')&isfinite(FV.tssv)&FV.tssv>0,:);
TR_tssf=FV(strcmp(FV.phase_type,'training')&isfinite(FV.tssf)&FV.tssf>0,:);

% nexttile; hold on;
% histogram(log(TR_tssv.tssv(~TR_tssv.haptic)),40,'FaceColor',CN,'EdgeColor','none','FaceAlpha',0.6,'Normalization','probability','DisplayName','NHF');
% histogram(log(TR_tssv.tssv( TR_tssv.haptic)),40,'FaceColor',CH,'EdgeColor','none','FaceAlpha',0.6,'Normalization','probability','DisplayName','HF');
% xlabel('log-TSSV (log (m s^{-2})^2 s)'); ylabel('Proportion'); title('TSSV distribution (all training)','FontSize',10);
% legend('FontSize',9); grid on;
% 
% nexttile; hold on;
% histogram(log(TR_tssf.tssf(~TR_tssf.haptic)),40,'FaceColor',CN,'EdgeColor','none','FaceAlpha',0.6,'Normalization','probability','DisplayName','NHF');
% histogram(log(TR_tssf.tssf( TR_tssf.haptic)),40,'FaceColor',CH,'EdgeColor','none','FaceAlpha',0.6,'Normalization','probability','DisplayName','HF');
% xlabel('log-TSSF (log N^2)'); ylabel('Proportion'); title('TSSF distribution (all training)','FontSize',10);
% legend('FontSize',9); grid on;
% 
% nexttile;
% subj_list=unique(TR_tssv.subject);
% subj_med=cellfun(@(s)median(log(TR_tssv.tssv(strcmp(TR_tssv.subject,s))),'omitnan'),subj_list);
% is_H_s=cellfun(@(s)any(TR_tssv.haptic(strcmp(TR_tssv.subject,s))),subj_list);
% [~,ord]=sort(subj_med);
% hold on;
% for si=1:numel(subj_list)
%     col=local_ternary(is_H_s(ord(si)),CH,CN);
%     scatter(si,subj_med(ord(si)),30,col,'filled','HandleVisibility','off');
% end
% plot(nan,nan,'o','Color',CN,'MarkerFaceColor',CN,'DisplayName','NHF');
% plot(nan,nan,'o','Color',CH,'MarkerFaceColor',CH,'DisplayName','HF');
% set(gca,'XTick',1:numel(subj_list),'XTickLabel',strrep(subj_list(ord),'subject_',''),'XTickLabelRotation',90,'FontSize',5);
% xlabel('Subject (sorted by median)'); ylabel('Median log-TSSV');
% title('Per-subject median TSSV','FontSize',10); legend('FontSize',8); grid on;

nexttile; hold on;
for lv=1:5
    vN=log(TR_tssv.tssv(~TR_tssv.haptic&TR_tssv.level==lv));
    vH=log(TR_tssv.tssv( TR_tssv.haptic&TR_tssv.level==lv));
    scatter(lv-0.15+randn(numel(vN),1)*0.03,vN,6,CN,'filled','MarkerFaceAlpha',0.15,'HandleVisibility','off');
    scatter(lv+0.15+randn(numel(vH),1)*0.03,vH,6,CH,'filled','MarkerFaceAlpha',0.15,'HandleVisibility','off');
    errorbar(lv-0.15,mean(vN,'omitnan'),std(vN,'omitnan')/sqrt(numel(vN))*1.96,'o','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',7,'HandleVisibility','off');
    errorbar(lv+0.15,mean(vH,'omitnan'),std(vH,'omitnan')/sqrt(numel(vH))*1.96,'o','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',7,'HandleVisibility','off');
end
plot(nan,nan,'o','Color',CN,'MarkerFaceColor',CN,'DisplayName','NHF');
plot(nan,nan,'o','Color',CH,'MarkerFaceColor',CH,'DisplayName','HF');
set(gca,'XTick',1:5,'XTickLabel',{'L1','L2','L3','L4','L5'},'FontSize',9);
xlabel('Training level'); ylabel('log-TSSV'); title('TSSV by level (dots=individual collisions, line=mean±95%CI)','FontSize',9);
legend('FontSize',9); grid on;

nexttile; hold on;
for lv=1:5
    vN=log(TR_tssf.tssf(~TR_tssf.haptic&TR_tssf.level==lv));
    vH=log(TR_tssf.tssf( TR_tssf.haptic&TR_tssf.level==lv));
    errorbar(lv-0.15,mean(vN,'omitnan'),std(vN,'omitnan')/sqrt(numel(vN))*1.96,'o','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',7,'HandleVisibility','off');
    errorbar(lv+0.15,mean(vH,'omitnan'),std(vH,'omitnan')/sqrt(numel(vH))*1.96,'o','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',7,'HandleVisibility','off');
end
plot(nan,nan,'o','Color',CN,'MarkerFaceColor',CN,'DisplayName','NHF');
plot(nan,nan,'o','Color',CH,'MarkerFaceColor',CH,'DisplayName','HF');
set(gca,'XTick',1:5,'XTickLabel',{'L1','L2','L3','L4','L5'},'FontSize',9);
xlabel('Training level'); ylabel('log-TSSF (log N^2)'); title('TSSF by level (mean±95%CI)','FontSize',9);
legend('FontSize',9); grid on;

nexttile; hold on;
% replace the two scatter lines in Part 2 Panel 6 with:

% find trials with both valid TSSV and TSSF
both_valid = isfinite(FV.tssv) & FV.tssv>0 & isfinite(FV.tssf) & FV.tssf>0 & strcmp(FV.phase_type,'training');
TV = FV(both_valid,:);

scatter(log(TV.tssv(~TV.haptic)), log(TV.tssf(~TV.haptic)), 8, CN,'filled','MarkerFaceAlpha',0.2,'DisplayName','NHF');
scatter(log(TV.tssv( TV.haptic)), log(TV.tssf( TV.haptic)), 8, CH,'filled','MarkerFaceAlpha',0.2,'DisplayName','HF');
r_N = corr(log(TV.tssv(~TV.haptic)), log(TV.tssf(~TV.haptic)),'Rows','complete');
r_H = corr(log(TV.tssv( TV.haptic)), log(TV.tssf( TV.haptic)),'Rows','complete');
r_all = corr(log(TV.tssv), log(TV.tssf),'Rows','complete');
xlabel('log-TSSV (log (m s^{-2})^2 s)','FontSize',9);
ylabel('log-TSSF (log N^2)','FontSize',9);
title(sprintf('TSSV vs TSSF per trial (training)\nr=%.3f all  NHF=%.3f  HF=%.3f',r_all,r_N,r_H),'FontSize',9);
legend('FontSize',9); grid on; box on;
exportgraphics(fig2,fullfile(fig_dir,'P2_cohort_distributions.png'),'Resolution',150);
fprintf('  Saved P2_cohort_distributions.png\n');


%% PART 3: Within-group BL1→BL2 change

fprintf('--- Part 3: Within-group BL1→BL2 change ---\n');
res=load(fullfile(cfg.output_root,'tssf_tssv_baseline_ancova.mat'),'all_results'); res=res.all_results;

fig3=figure('Position',[2000 2000 1800 1900]);
tl3=tiledlayout(2,3,'TileSpacing','compact','Padding','compact');
title(tl3,'Part 3 — Within-group change: Baseline1 → Baseline2 (training effect on elastic task)',...
    'FontWeight','bold','FontSize',11);

for mi=1:2
    oc=local_ternary(mi==1,'tssv','tssf');
    yl=local_ternary(mi==1,'log-TSSV','log-TSSF (log N^2)');

    subj_list2=unique(FV.subject);
    bl1_N=nan(numel(subj_list2),1); bl2_N=nan(numel(subj_list2),1);
    bl1_H=nan(numel(subj_list2),1); bl2_H=nan(numel(subj_list2),1);
    is_H2=false(numel(subj_list2),1);
    for si=1:numel(subj_list2)
        s=subj_list2{si}; Ts=FV(strcmp(FV.subject,s),:);
        is_H2(si)=any(Ts.haptic);
        v1=Ts.(oc)(strcmp(Ts.phase,'Baseline1')&isfinite(Ts.(oc))&Ts.(oc)>0);
        v2=Ts.(oc)(strcmp(Ts.phase,'Baseline2')&isfinite(Ts.(oc))&Ts.(oc)>0);
        if ~isempty(v1), bl1=mean(log(v1),'omitnan'); if is_H2(si), bl1_H(si)=bl1; else, bl1_N(si)=bl1; end; end
        if ~isempty(v2), bl2=mean(log(v2),'omitnan'); if is_H2(si), bl2_H(si)=bl2; else, bl2_N(si)=bl2; end; end
    end

    for grp=1:2
        if grp==1, pre=bl1_N; post=bl2_N; col=CN; glbl='NHF';
        else,      pre=bl1_H; post=bl2_H; col=CH; glbl='HF'; end
        keep=isfinite(pre)&isfinite(post); pre=pre(keep); post=post(keep);
        r=res.(oc).within.(glbl);

        nexttile; hold on;
        jx=1+(rand(numel(pre),1)-0.5)*0.1;
        for k=1:numel(pre)
            col_line=[col 0.2];
            plot([jx(k) jx(k)+1],[pre(k) post(k)],'-','Color',col_line,'LineWidth',0.8,'HandleVisibility','off');
        end
        scatter(jx,pre,20,col,'filled','MarkerFaceAlpha',0.5,'HandleVisibility','off');
        scatter(jx+1,post,20,col,'filled','MarkerFaceAlpha',0.5,'HandleVisibility','off');
        errorbar([1 2],[mean(pre) mean(post)],[std(pre)/sqrt(numel(pre)) std(post)/sqrt(numel(post))]*1.96,...
            '-o','Color',col,'LineWidth',2.5,'MarkerFaceColor',col,'MarkerSize',9,'DisplayName',glbl);
        yrange=max([pre;post])-min([pre;post]);
        ymax=max([pre;post])+0.1*yrange;
        text(1.5,ymax,sprintf('paired p=%.4f\nd=%.3f',r.p_paired,r.d),...
            'HorizontalAlignment','center','FontSize',9,'Color',[0.2 0.2 0.2]);
        if r.p_paired<0.05, text(1.5,ymax+0.08*yrange,'*','HorizontalAlignment','center','FontSize',16,'Color','k'); end
        xticks([1 2]); xticklabels({'Baseline1','Baseline2'}); ylabel(yl,'FontSize',9);
        title(sprintf('%s — %s\nBL1→BL2 change',upper(oc),glbl),'FontSize',10,'Interpreter','none');
        legend('FontSize',9,'Location','best'); grid on; box on;
    end

    nexttile; hold on;
    dN=res.(oc).within.NHF.delta; dH=res.(oc).within.HF.delta;
    scatter(ones(numel(dN),1)+(rand(numel(dN),1)-0.5)*0.2,dN,25,CN,'filled','MarkerFaceAlpha',0.6,'HandleVisibility','off');
    scatter(2*ones(numel(dH),1)+(rand(numel(dH),1)-0.5)*0.2,dH,25,CH,'filled','MarkerFaceAlpha',0.6,'HandleVisibility','off');
    errorbar(1,mean(dN,'omitnan'),std(dN,'omitnan')/sqrt(numel(dN))*1.96,'o','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',9,'DisplayName','NHF');
    errorbar(2,mean(dH,'omitnan'),std(dH,'omitnan')/sqrt(numel(dH))*1.96,'o','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',9,'DisplayName','HF');
    yline(0,'k--','LineWidth',1.2,'HandleVisibility','off');
    r_b=res.(oc).between_delta;
    text(1.5,max([dN;dH])+0.1,sprintf('NvsH p=%.4f\nd=%.3f',r_b.p_ttest,r_b.d),'HorizontalAlignment','center','FontSize',9,'Color',[0.3 0.3 0.3]);
    xticks([1 2]); xticklabels({'NHF','HF'});
    ylabel(sprintf('Δ log-%s (BL2−BL1)',upper(oc)),'FontSize',9,'Interpreter','none');
    title(sprintf('%s — BL1→BL2 delta comparison',upper(oc)),'FontSize',10,'Interpreter','none');
    legend('FontSize',9); grid on; box on;
end
exportgraphics(fig3,fullfile(fig_dir,'P3_within_group_bl_change.png'),'Resolution',150);
fprintf('  Saved P3_within_group_bl_change.png\n');


%% PART 4: Between-group across all phases

fprintf('--- Part 4: Between-group across all phases ---\n');

phases_ord={'Baseline1','Test1','level_L1','level_L2','level_L3','level_L4','level_L5','Baseline2','Test2'};
xlabels   ={'BL1','T1','L1','L2','L3','L4','L5','BL2','T2'};
n_ph=numel(phases_ord);

fig4=figure('Position',[2000 2000 1800 1900]);
tl4=tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
title(tl4,'Part 4 — Between-group comparison across all phases (subject means ± 95% CI)',...
    'FontWeight','bold','FontSize',12);

for mi=1:2
    oc=local_ternary(mi==1,'tssv','tssf');
    yl=local_ternary(mi==1,'log-TSSV (log (m s^{-2})^2 s)','log-TSSF (log N^2)');
    mu_N=nan(1,n_ph); mu_H=nan(1,n_ph); se_N=nan(1,n_ph); se_H=nan(1,n_ph);

    nexttile; hold on;
    for pi=1:n_ph
        ph=phases_ord{pi};
        if startsWith(ph,'level_')
            lv=str2double(regexp(ph,'\d+','match','once'));
            Tph=FV(strcmp(FV.phase_type,'training')&FV.level==lv&isfinite(FV.(oc))&FV.(oc)>0,:);
        else
            Tph=FV(strcmp(FV.phase,ph)&isfinite(FV.(oc))&FV.(oc)>0,:);
        end
        if isempty(Tph), continue; end
        Tph.log_m=log(Tph.(oc));
        subj=unique(Tph.subject); xs=nan(numel(subj),1); ihs=false(numel(subj),1);
        for si=1:numel(subj)
            s=subj{si}; xs(si)=mean(Tph.log_m(strcmp(Tph.subject,s)),'omitnan');
            ihs(si)=any(Tph.haptic(strcmp(Tph.subject,s)));
        end
        xN=xs(~ihs&isfinite(xs)); xH=xs(ihs&isfinite(xs));
        mu_N(pi)=mean(xN); mu_H(pi)=mean(xH);
        se_N(pi)=std(xN)/sqrt(numel(xN)); se_H(pi)=std(xH)/sqrt(numel(xH));
        % individual subject dots (small, transparent)
        scatter(repmat(pi-0.15,numel(xN),1)+(rand(numel(xN),1)-0.5)*0.05,xN,8,CN,'filled','MarkerFaceAlpha',0.2,'HandleVisibility','off');
        scatter(repmat(pi+0.15,numel(xH),1)+(rand(numel(xH),1)-0.5)*0.05,xH,8,CH,'filled','MarkerFaceAlpha',0.2,'HandleVisibility','off');
    end
    x=1:n_ph;
    fill([x fliplr(x)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    fill([x fliplr(x)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    plot(x,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',8,'DisplayName','NHF');
    plot(x,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',8,'DisplayName','HF');
    xline(1.5,'k:','LineWidth',1,'HandleVisibility','off');
    xline(6.5,'k:','LineWidth',1,'HandleVisibility','off');
    yall=max([mu_N+1.96*se_N mu_H+1.96*se_H],[],'omitnan');
    text(1,yall*1.05,'Pre','FontSize',9,'HorizontalAlignment','center','Color',[0.4 0.4 0.4]);
    text(3.5,yall*1.05,'Training (L1–L5)','FontSize',9,'HorizontalAlignment','center','Color',[0.4 0.4 0.4]);
    text(7.5,yall*1.05,'Post','FontSize',9,'HorizontalAlignment','center','Color',[0.4 0.4 0.4]);
    set(gca,'XTick',1:n_ph,'XTickLabel',xlabels,'FontSize',10);
    xlabel('Phase'); ylabel(yl,'FontSize',10);
    legend('Location','best','FontSize',10); grid on; box on;
    title(sprintf('%s — NHF vs HF (small dots=individual subjects, line=mean±95%%CI)',upper(oc)),'FontSize',11,'Interpreter','none');
end
exportgraphics(fig4,fullfile(fig_dir,'P4_between_group_all_phases.png'),'Resolution',150);
fprintf('  Saved P4_between_group_all_phases.png\n');


%% PART 5: Rep-by-rep learning curves per level

fprintf('--- Part 5: Rep-by-rep learning curves ---\n');

for mi=1:2
    oc=local_ternary(mi==1,'tssv','tssf');
    yl=local_ternary(mi==1,'log-TSSV','log-TSSF (log N^2)');
    T_tr=FV(strcmp(FV.phase_type,'training')&isfinite(FV.(oc))&FV.(oc)>0,:);

    fig5=figure('Position',[2000 2000 1800 1900]);
    tl5=tiledlayout(1,5,'TileSpacing','compact','Padding','compact');
    title(tl5,sprintf('Part 5 — %s: rep-by-rep learning curves within each training level (mean±SE + individual subject lines)',upper(oc)),...
        'FontWeight','bold','FontSize',11);

    for lv=1:5
        Tlv=T_tr(T_tr.level==lv,:);
        subj_u=unique(Tlv.subject);
        mat_N=nan(numel(subj_u),10); mat_H=nan(numel(subj_u),10); is_H_l=false(numel(subj_u),1);
        for si=1:numel(subj_u)
            s=subj_u{si}; Ts=Tlv(strcmp(Tlv.subject,s),:); is_H_l(si)=any(Ts.haptic);
            for ri=1:10
                v=log(Ts.(oc)(Ts.repetition==ri&Ts.(oc)>0));
                if ~isempty(v)
                    if is_H_l(si), mat_H(si,ri)=mean(v,'omitnan');
                    else,          mat_N(si,ri)=mean(v,'omitnan'); end
                end
            end
        end
        mu_lN=mean(mat_N,'omitnan'); se_lN=std(mat_N,'omitnan')./sqrt(sum(isfinite(mat_N)));
        mu_lH=mean(mat_H,'omitnan'); se_lH=std(mat_H,'omitnan')./sqrt(sum(isfinite(mat_H)));
        nexttile; hold on;
        for si=1:numel(subj_u)
            if is_H_l(si), plot(1:10,mat_H(si,:),'-','Color',[CH 0.12],'LineWidth',0.5,'HandleVisibility','off');
            else,          plot(1:10,mat_N(si,:),'-','Color',[CN 0.12],'LineWidth',0.5,'HandleVisibility','off'); end
        end
        fill([1:10 fliplr(1:10)],[mu_lN+se_lN fliplr(mu_lN-se_lN)],CN,'FaceAlpha',0.2,'EdgeColor','none','HandleVisibility','off');
        fill([1:10 fliplr(1:10)],[mu_lH+se_lH fliplr(mu_lH-se_lH)],CH,'FaceAlpha',0.2,'EdgeColor','none','HandleVisibility','off');
        plot(1:10,mu_lN,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',5,'DisplayName','NHF');
        plot(1:10,mu_lH,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',5,'DisplayName','HF');
        set(gca,'XTick',1:10,'FontSize',8); xlabel('Repetition'); ylabel(yl,'FontSize',8);
        title(sprintf('Level %d',lv),'FontSize',11); grid on; box on;
        if lv==1, legend('Location','best','FontSize',8); end
    end
    all_ax=findobj(fig5,'Type','Axes');
    yl_all=cell2mat(arrayfun(@(a)ylim(a),all_ax,'UniformOutput',false)');
    for a=all_ax', ylim(a,[min(yl_all(:,1)) max(yl_all(:,2))]); end
    exportgraphics(fig5,fullfile(fig_dir,sprintf('P5_%s_rep_by_rep.png',oc)),'Resolution',150);
    fprintf('  Saved P5_%s_rep_by_rep.png\n',oc);
end


%% PART 6: Collision-level intensity distributions

fprintf('--- Part 6: Collision-level distributions ---\n');

CI_tr=CI(strcmp(CI.phase_type,'training')&isfinite(CI.peak_accel_g_nidaq),:);

fig6=figure('Position',[2000 2000 1800 1900]);
tl6=tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
title(tl6,'Part 6 — Collision-level: intensity distributions and group differences (training phase)',...
    'FontWeight','bold','FontSize',11);

nexttile; hold on;
[fN,xN_d]=ksdensity(CI_tr.peak_accel_g_nidaq(~CI_tr.haptic),'NumPoints',200,'BoundaryCorrection','reflection');
[fH,xH_d]=ksdensity(CI_tr.peak_accel_g_nidaq( CI_tr.haptic),'NumPoints',200,'BoundaryCorrection','reflection');
plot(xN_d,fN,'Color',CN,'LineWidth',2,'DisplayName',sprintf('NHF (n=%d)',sum(~CI_tr.haptic)));
plot(xH_d,fH,'Color',CH,'LineWidth',2,'DisplayName',sprintf('HF (n=%d)',sum(CI_tr.haptic)));
xline(median(CI_tr.peak_accel_g_nidaq(~CI_tr.haptic)),'--','Color',CN,'LineWidth',1.2,'HandleVisibility','off');
xline(median(CI_tr.peak_accel_g_nidaq( CI_tr.haptic)),'--','Color',CH,'LineWidth',1.2,'HandleVisibility','off');
[~,p_ks]=kstest2(CI_tr.peak_accel_g_nidaq(~CI_tr.haptic),CI_tr.peak_accel_g_nidaq(CI_tr.haptic));
xlabel('Peak acceleration (g)','FontSize',9); ylabel('Density');
title(sprintf('Collision intensity distribution\nKS test p=%.2e (dashed=median)',p_ks),'FontSize',10);
legend('FontSize',9); grid on; xlim([0 2]);

nexttile; hold on;
for lv=1:5
    vN=CI_tr.peak_accel_g_nidaq(~CI_tr.haptic&CI_tr.level==lv);
    vH=CI_tr.peak_accel_g_nidaq( CI_tr.haptic&CI_tr.level==lv);
    errorbar(lv-0.15,median(vN),iqr(vN)/2,'o','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');
    errorbar(lv+0.15,median(vH),iqr(vH)/2,'o','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');
end
plot(nan,nan,'o','Color',CN,'MarkerFaceColor',CN,'DisplayName','NHF (median±IQR/2)');
plot(nan,nan,'o','Color',CH,'MarkerFaceColor',CH,'DisplayName','HF (median±IQR/2)');
set(gca,'XTick',1:5,'XTickLabel',{'L1','L2','L3','L4','L5'},'FontSize',9);
xlabel('Training level'); ylabel('Peak acceleration (g)');
title('Collision intensity by level','FontSize',10); legend('FontSize',9); grid on;

nexttile; hold on;
CI_tr2=CI_tr(isfinite(CI_tr.impact_tssv)&CI_tr.impact_tssv>0&isfinite(CI_tr.impact_tssf)&CI_tr.impact_tssf>0,:);
scatter(log10(CI_tr2.peak_accel_g_nidaq(~CI_tr2.haptic)),log10(CI_tr2.impact_tssv(~CI_tr2.haptic)),6,CN,'filled','MarkerFaceAlpha',0.15,'DisplayName','NHF');
scatter(log10(CI_tr2.peak_accel_g_nidaq( CI_tr2.haptic)),log10(CI_tr2.impact_tssv( CI_tr2.haptic)),6,CH,'filled','MarkerFaceAlpha',0.15,'DisplayName','HF');
r=corr(log10(CI_tr2.peak_accel_g_nidaq),log10(CI_tr2.impact_tssv),'Rows','complete');
xlabel('log_{10}(peak accel, g)','FontSize',9); ylabel('log_{10}(impact TSSV)','FontSize',9);
title(sprintf('Accel vs impact TSSV\nr=%.3f (all collisions)',r),'FontSize',10);
legend('FontSize',9); grid on; box on;
exportgraphics(fig6,fullfile(fig_dir,'P6_collision_level.png'),'Resolution',150);
fprintf('  Saved P6_collision_level.png\n');

fprintf('\n=== All supervisor presentation figures saved to:\n  %s\n',fig_dir);
fprintf('Files:\n');
files=dir(fullfile(fig_dir,'*.png'));
for fi=1:numel(files), fprintf('  %s\n',files(fi).name); end

function out=local_ternary(c,a,b), if c,out=a; else,out=b; end, end