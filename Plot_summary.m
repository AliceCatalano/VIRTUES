%% summary_plots.m
clear; clc; close all; cfg = config();
CN = [64  96  179] / 255;   % indaco/blue  — NHF
CH = [139  82  168] / 255;  % violet/lilla — HF
fig_dir=fullfile(cfg.output_root,'figures'); if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

T    = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); T=T.T;
TC   = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T_coll'); TC=TC.T_coll;
h1   = load(fullfile(cfg.output_root,'h1_results.mat'),'all_results'); h1=h1.all_results;
h2   = load(fullfile(cfg.output_root,'h2_results_v2.mat'),'T_res','edges_N','edges_H');
h3s  = load(fullfile(cfg.output_root,'h3_results.mat'),'all_results'); h3s=h3s.all_results;

%% ── FIGURE 1: H1 tonic SCL across phases ──────────────────────────────
phases_ord = {'Baseline1','Test1','Training_L1','Training_L2','Training_L3','Training_L4','Training_L5','Baseline2','Test2'};
xlabels    = {'BL1','T1','Tr-L1','Tr-L2','Tr-L3','Tr-L4','Tr-L5','BL2','T2'};
tbl = h1.scl_mean_bc.table;
mu_N=nan(1,9); mu_H=nan(1,9); se_N=nan(1,9); se_H=nan(1,9); pfdr=nan(1,9); d=nan(1,9);
for k=1:9
    row=tbl(strcmp(tbl.phase,phases_ord{k}),:);
    if isempty(row), continue; end
    mu_N(k)=row.mean_N; mu_H(k)=row.mean_H;
    se_N(k)=row.mean_N/sqrt(row.n_N); se_H(k)=row.mean_H/sqrt(row.n_H); % placeholder — recompute below
    pfdr(k)=row.p_fdr_ttest; d(k)=row.cohens_d_hedges;
end
% recompute SE from raw data
for k=1:9
    ph=phases_ord{k};
    if startsWith(ph,'Training')
        lv=str2double(ph(end)); Tsub=T(strcmp(T.phase_type,'training')&T.level==lv&isfinite(T.scl_mean_bc),:);
    else
        Tsub=T(strcmp(T.phase,ph)&isfinite(T.scl_mean_bc),:);
    end
    subj=unique(Tsub.subject); xa=nan(numel(subj),1); ih=false(numel(subj),1);
    for si=1:numel(subj), s=subj{si}; xa(si)=mean(Tsub.scl_mean_bc(strcmp(Tsub.subject,s)),'omitnan'); ih(si)=any(Tsub.haptic(strcmp(Tsub.subject,s))); end
    xN=xa(~ih&isfinite(xa)); xH=xa(ih&isfinite(xa));
    se_N(k)=std(xN,'omitnan')/sqrt(numel(xN)); se_H(k)=std(xH,'omitnan')/sqrt(numel(xH));
end

fig1=figure('Position',[2000 2000 1100 420]);
ax=axes(fig1); hold(ax,'on');
x=1:9;
fill(ax,[x fliplr(x)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
fill(ax,[x fliplr(x)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
plot(ax,x,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
plot(ax,x,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
xline(ax,1.5,'k:','LineWidth',1,'HandleVisibility','off'); xline(ax,6.5,'k:','LineWidth',1,'HandleVisibility','off');
text(ax,1,max([mu_N mu_H]+1.96*max([se_N se_H]))*1.05,'Pre-training','FontSize',8,'HorizontalAlignment','center');
text(ax,4,max([mu_N mu_H]+1.96*max([se_N se_H]))*1.05,'Training','FontSize',8,'HorizontalAlignment','center');
text(ax,8,max([mu_N mu_H]+1.96*max([se_N se_H]))*1.05,'Post-training','FontSize',8,'HorizontalAlignment','center');
for k=1:9
    sig=local_stars(pfdr(k));
    if ~isempty(sig)
        ypos=max(mu_N(k)+1.96*se_N(k),mu_H(k)+1.96*se_H(k))+0.15;
        text(ax,k,ypos,sig,'HorizontalAlignment','center','FontSize',12,'Color','k');
    end
    text(ax,k,min(mu_N(k)-1.96*se_N(k),mu_H(k)-1.96*se_H(k))-0.2,sprintf('d=%.2f',d(k)),'HorizontalAlignment','center','FontSize',7,'Color',[0.4 0.4 0.4]);
end
set(ax,'XTick',1:9,'XTickLabel',xlabels,'FontSize',9);
ylabel(ax,'Tonic SCL above resting (\muS)','FontSize',10);
xlabel(ax,'Phase','FontSize',10);
title(ax,'H1 — Tonic SCL: NHF vs HF across all phases (mean \pm 95% CI)','FontSize',11);
legend(ax,'Location','northwest','FontSize',9);
yline(ax,0,'k--','LineWidth',0.8,'HandleVisibility','off');
grid(ax,'on'); box(ax,'on');
exportgraphics(fig1,fullfile(fig_dir,'summary_H1_scl.png'),'Resolution',180);

% ── FIGURE 2: H1 ER-SCR across phases ─────────────────────────────────
tbl2=h1.collision_scr_amp_mean_bc.table;
mu_N2=nan(1,9); mu_H2=nan(1,9); se_N2=nan(1,9); se_H2=nan(1,9); pfdr2=nan(1,9); d2=nan(1,9);
for k=1:9
    row=tbl2(strcmp(tbl2.phase,phases_ord{k}),:);
    if isempty(row), continue; end
    mu_N2(k)=row.mean_N; mu_H2(k)=row.mean_H; pfdr2(k)=row.p_fdr_ttest; d2(k)=row.cohens_d_hedges;
    ph=phases_ord{k};
    if startsWith(ph,'Training'), lv=str2double(ph(end)); Tsub=T(strcmp(T.phase_type,'training')&T.level==lv&isfinite(T.collision_scr_amp_mean_bc),:);
    else, Tsub=T(strcmp(T.phase,ph)&isfinite(T.collision_scr_amp_mean_bc),:); end
    subj=unique(Tsub.subject); xa=nan(numel(subj),1); ih=false(numel(subj),1);
    for si=1:numel(subj), s=subj{si}; xa(si)=mean(Tsub.collision_scr_amp_mean_bc(strcmp(Tsub.subject,s)),'omitnan'); ih(si)=any(Tsub.haptic(strcmp(Tsub.subject,s))); end
    xN=xa(~ih&isfinite(xa)); xH=xa(ih&isfinite(xa));
    se_N2(k)=std(xN,'omitnan')/sqrt(numel(xN)); se_H2(k)=std(xH,'omitnan')/sqrt(numel(xH));
end
fig2=figure('Position',[2000 2000 1100 420]);
ax=axes(fig2); hold(ax,'on');
fill(ax,[x fliplr(x)],[mu_N2+1.96*se_N2 fliplr(mu_N2-1.96*se_N2)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
fill(ax,[x fliplr(x)],[mu_H2+1.96*se_H2 fliplr(mu_H2-1.96*se_H2)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
plot(ax,x,mu_N2,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
plot(ax,x,mu_H2,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
xline(ax,1.5,'k:','LineWidth',1,'HandleVisibility','off'); xline(ax,6.5,'k:','LineWidth',1,'HandleVisibility','off');
for k=1:9
    sig=local_stars(pfdr2(k));
    if ~isempty(sig)
        ypos=max(mu_N2(k)+1.96*se_N2(k),mu_H2(k)+1.96*se_H2(k))+0.005;
        text(ax,k,ypos,sig,'HorizontalAlignment','center','FontSize',12,'Color','k');
    end
    text(ax,k,min(mu_N2(k)-1.96*se_N2(k),mu_H2(k)-1.96*se_H2(k))-0.006,sprintf('d=%.2f',d2(k)),'HorizontalAlignment','center','FontSize',7,'Color',[0.4 0.4 0.4]);
end
set(ax,'XTick',1:9,'XTickLabel',xlabels,'FontSize',9);
ylabel(ax,'ER-SCR amplitude (fraction of resting tonic SCL, a.u.)','FontSize',10);
xlabel(ax,'Phase','FontSize',10);
title(ax,'H1 — Collision-locked ER-SCR: NHF vs HF across all phases (mean \pm 95% CI)','FontSize',11);
legend(ax,'Location','northwest','FontSize',9);
yline(ax,0,'k--','LineWidth',0.8,'HandleVisibility','off');
grid(ax,'on'); box(ax,'on');
exportgraphics(fig2,fullfile(fig_dir,'summary_H1_erscr.png'),'Resolution',180);

% ── FIGURE 3: H2 variance by intensity bin ─────────────────────────────
T2=h2.T_res; eN=h2.edges_N; eH=h2.edges_H; n_bins=4;
TC_tr=TC(strcmp(TC.phase_type,'training')&isfinite(TC.peak_accel_g)&isfinite(TC.scr_amp_local_bc),:);
qN=[0 0.25 0.50 0.75 1.0]; qH=qN;
binsN=histcounts(TC_tr.peak_accel_g(~TC_tr.haptic),eN); %#ok
[~,~,bvN]=histcounts(TC_tr.peak_accel_g(~TC_tr.haptic),eN);
[~,~,bvH]=histcounts(TC_tr.peak_accel_g( TC_tr.haptic),eH);
TC_tr.bv=zeros(height(TC_tr),1);
TC_tr.bv(~TC_tr.haptic)=bvN; TC_tr.bv(TC_tr.haptic)=bvH;

fig3=figure('Position',[2000 2000 1200 520]);
sgtitle('H2 — EDA response variance by collision intensity quartile (group-specific bins)','FontWeight','bold','FontSize',11);
for b=1:n_bins
    xN=TC_tr.scr_amp_local_bc(~TC_tr.haptic&TC_tr.bv==b); xN=xN(isfinite(xN));
    xH=TC_tr.scr_amp_local_bc( TC_tr.haptic&TC_tr.bv==b); xH=xH(isfinite(xH));
    subplot(1,n_bins+1,b); hold on;
    local_violin(xN,1,CN); local_violin(xH,2,CH);
    errorbar(1,mean(xN,'omitnan'),std(xN),'s','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',9,'HandleVisibility','off');
    errorbar(2,mean(xH,'omitnan'),std(xH),'s','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',9,'HandleVisibility','off');
    ymax=max([xN;xH]); ymin=min([xN;xH]);
    sig=local_stars(T2.p_levene_fdr(b));
    if ~isempty(sig)
        yt=ymax+0.05*(ymax-ymin);
        plot([1 2],[yt yt],'k-','LineWidth',1,'HandleVisibility','off');
        text(1.5,yt+0.03*(ymax-ymin),sig,'HorizontalAlignment','center','FontSize',13);
    end
    lbl_N=sprintf('N: %.2f-%.2fg',eN(b),eN(b+1)); lbl_H=sprintf('H: %.2f-%.2fg',eH(b),eH(b+1));
    title(sprintf('Bin %d\n%s\n%s\nSD_N=%.3f SD_H=%.3f\np_{Lev,FDR}=%s',b,lbl_N,lbl_H,T2.sd_N(b),T2.sd_H(b),local_pstr(T2.p_levene_fdr(b))),'FontSize',7.5);
    xticks([1 2]); xticklabels({'NHF','HF'});
    if b==1, ylabel('SCR amp — local bc (fraction of resting tonic SCL, a.u.)','FontSize',9); end
    grid on; xlim([0.5 2.5]);
end
subplot(1,n_bins+1,n_bins+1); hold on;
bh=bar(1:n_bins,T2.ratio_sdN_sdH,0.55);
bh.FaceColor='flat';
for b=1:n_bins, bh.CData(b,:)=local_ternary(T2.p_levene_fdr(b)<0.05,[0.3 0.6 0.3],[0.7 0.7 0.7]); end
yline(1,'r--','LineWidth',1.8,'DisplayName','equal variance');
for b=1:n_bins
    sig=local_stars(T2.p_levene_fdr(b));
    if ~isempty(sig), text(b,T2.ratio_sdN_sdH(b)+0.02,sig,'HorizontalAlignment','center','FontSize',12); end
end
ylabel('SD_{NHF}/SD_{HF}','FontSize',9); xlabel('Intensity quartile','FontSize',9);
title('Variance ratio','FontSize',9); set(gca,'XTick',1:4); ylim([0 1.2]); grid on;
exportgraphics(fig3,fullfile(fig_dir,'summary_H2_variance.png'),'Resolution',180); 

% ── FIGURE 4: H2 mean EDA by bin (H > N) ──────────────────────────────
fig4=figure('Position',[2000 2000 900 420]);
hold on;
x=1:n_bins;
mu_N_h2=T2.mean_N'; mu_H_h2=T2.mean_H';
bar(x-0.2,mu_N_h2,0.35,'FaceColor',CN,'EdgeColor','none','DisplayName','NHF');
bar(x+0.2,mu_H_h2,0.35,'FaceColor',CH,'EdgeColor','none','DisplayName','HF');
for b=1:n_bins
    sig=local_stars(T2.p_mean_fdr(b));
    if ~isempty(sig)
        yt=max(mu_N_h2(b),mu_H_h2(b))+0.005;
        plot([b-0.2 b+0.2],[yt yt],'k-','LineWidth',1,'HandleVisibility','off');
        text(b,yt+0.002,sig,'HorizontalAlignment','center','FontSize',13);
    end
end
set(gca,'XTick',1:4,'XTickLabel',arrayfun(@(b)sprintf('Q%d',b),1:4,'UniformOutput',false),'FontSize',9);
ylabel('Mean SCR amplitude — local bc (fraction of resting tonic SCL, a.u.)','FontSize',9);
xlabel('Intensity quartile (group-specific)','FontSize',9);
title('H2 — Mean collision-locked EDA by intensity bin: NHF vs HF','FontSize',11);
legend('Location','northwest','FontSize',9); grid on; box on;
exportgraphics(fig4,fullfile(fig_dir,'summary_H2_mean.png'),'Resolution',180); 

% ── FIGURE 5: H3a post-training snapshot ──────────────────────────────
tbl3s=h3s.snapshot;
fig5=figure('Position',[2000 2000 1000 480]);
sgtitle('H3a — Post-training collision EDA: NHF vs HF (mean \pm 95% CI, individual dots)','FontWeight','bold','FontSize',11);
panels={...
    {'collision_scr_amp_mean_bc','Baseline2','ER-SCR amplitude (fraction of resting tonic SCL, a.u.)'},...
    {'collision_scr_amp_mean_bc','Test2',    'ER-SCR amplitude (fraction of resting tonic SCL, a.u.)'},...
    {'collision_response_rate',  'Baseline2','SCR response rate (proportion, 0–1)'},...
    {'collision_response_rate',  'Test2',    'SCR response rate (proportion, 0–1)'}};
for pp=1:4
    oc=panels{pp}{1}; ph=panels{pp}{2}; yl=panels{pp}{3};
    Tph=T(strcmp(T.phase,ph)&isfinite(T.(oc))&T.n_collisions>=1,:);
    subj=unique(Tph.subject); xa=nan(numel(subj),1); ih=false(numel(subj),1);
    for si=1:numel(subj), s=subj{si}; xa(si)=mean(Tph.(oc)(strcmp(Tph.subject,s)),'omitnan'); ih(si)=any(Tph.haptic(strcmp(Tph.subject,s))); end
    xN=xa(~ih&isfinite(xa)); xH=xa(ih&isfinite(xa));
    row=tbl3s(strcmp(tbl3s.outcome,oc)&strcmp(tbl3s.phase,ph),:);
    subplot(1,4,pp); hold on;
    scatter(0.9+(rand(numel(xN),1)-0.5)*0.2,xN,22,CN,'filled','MarkerFaceAlpha',0.45,'HandleVisibility','off');
    scatter(1.9+(rand(numel(xH),1)-0.5)*0.2,xH,22,CH,'filled','MarkerFaceAlpha',0.45,'HandleVisibility','off');
    errorbar(1,mean(xN,'omitnan'),std(xN,'omitnan')/sqrt(numel(xN))*1.96,'o','Color',CN,'MarkerFaceColor',CN,'LineWidth',2.2,'MarkerSize',9,'DisplayName','NHF');
    errorbar(2,mean(xH,'omitnan'),std(xH,'omitnan')/sqrt(numel(xH))*1.96,'o','Color',CH,'MarkerFaceColor',CH,'LineWidth',2.2,'MarkerSize',9,'DisplayName','HF');
    yline(0,'k--','LineWidth',0.8,'HandleVisibility','off');
    ymax=max([xN;xH]); ymin=min([xN;xH]); rng=ymax-ymin;
    if ~isempty(row)
        sig=local_stars(row.p_fdr);
        if ~isempty(sig)
            yt=ymax+0.1*rng; plot([1 2],[yt yt],'k-','LineWidth',1,'HandleVisibility','off');
            text(1.5,yt+0.05*rng,sig,'HorizontalAlignment','center','FontSize',13);
        end
        annotation_str=sprintf('p_{FDR}=%s\nd=%.2f',local_pstr(row.p_fdr),row.cohens_d);
        text(1.5,ymin-0.18*rng,annotation_str,'HorizontalAlignment','center','FontSize',7.5,'Color',[0.3 0.3 0.3]);
        text(1,ymin-0.30*rng,sprintf('p_{vs0}=%s',local_pstr(row.p_N_vs0)),'HorizontalAlignment','center','FontSize',7,'Color',CN);
        text(2,ymin-0.30*rng,sprintf('p_{vs0}=%s',local_pstr(row.p_H_vs0)),'HorizontalAlignment','center','FontSize',7,'Color',CH);
    end
    xticks([1 2]); xticklabels({'NHF','HF'}); ylabel(yl,'FontSize',8);
    title(sprintf('%s\n%s',strrep(oc,'_',' '),ph),'FontSize',8,'Interpreter','none');
    if pp==1, legend('Location','best','FontSize',8); end
    grid on; xlim([0.5 2.5]);
end
exportgraphics(fig5,fullfile(fig_dir,'summary_H3a_snapshot.png'),'Resolution',180); 

% ── FIGURE 6: H3b pre→post paired ─────────────────────────────────────
tbl3t=h3s.transfer;
fig6=figure('Position',[2000 2000 1000 480]);
sgtitle('H3b — Pre\rightarrowPost change in collision EDA (individual lines + group mean \pm 95% CI)','FontWeight','bold','FontSize',11);
panels6={...
    {'collision_scr_amp_mean_bc','baseline','Baseline1','Baseline2','ER-SCR amplitude (fraction of resting tonic SCL, a.u.)'},...
    {'collision_scr_amp_mean_bc','test',    'Test1',    'Test2',    'ER-SCR amplitude (fraction of resting tonic SCL, a.u.)'},...
    {'collision_response_rate',  'baseline','Baseline1','Baseline2','SCR response rate (proportion, 0–1)'},...
    {'collision_response_rate',  'test',    'Test1',    'Test2',    'SCR response rate (proportion, 0–1)'}};
for pp=1:4
    oc=panels6{pp}{1}; pt=panels6{pp}{2}; ppre=panels6{pp}{3}; ppost=panels6{pp}{4}; yl=panels6{pp}{5};
    Tph=T(strcmp(T.phase_type,pt)&isfinite(T.(oc))&T.n_collisions>=1&ismember(T.phase,{ppre,ppost}),:);
    sl=unique(Tph.subject); pre=nan(numel(sl),1); post=nan(numel(sl),1); ihs=false(numel(sl),1);
    for si=1:numel(sl), s=sl{si}; pre(si)=mean(Tph.(oc)(strcmp(Tph.subject,s)&strcmp(Tph.phase,ppre)),'omitnan'); post(si)=mean(Tph.(oc)(strcmp(Tph.subject,s)&strcmp(Tph.phase,ppost)),'omitnan'); ihs(si)=any(Tph.haptic(strcmp(Tph.subject,s))); end
    keep=isfinite(pre)&isfinite(post); pre=pre(keep); post=post(keep); ihs=ihs(keep);
    row=tbl3t(strcmp(tbl3t.outcome,oc)&strcmp(tbl3t.phase_pre,ppre),:);
    subplot(1,4,pp); hold on;
    for grp=[false true]
        idx=find(ihs==grp); if isempty(idx), continue; end
        col=local_ternary(grp,CH,CN);
        jx=1+(rand(numel(idx),1)-0.5)*0.1;
        for k=1:numel(idx), plot([jx(k) jx(k)+1],[pre(idx(k)) post(idx(k))],'-','Color',[col 0.2],'LineWidth',0.8,'HandleVisibility','off'); end
        mu=[mean(pre(idx),'omitnan') mean(post(idx),'omitnan')];
        sem=[std(pre(idx),'omitnan') std(post(idx),'omitnan')]./sqrt(numel(idx))*1.96;
        errorbar([1 2]+local_ternary(grp,0.1,-0.1),mu,sem,'-o','Color',col,'LineWidth',2.2,'MarkerFaceColor',col,'MarkerSize',8,'DisplayName',local_ternary(grp,'HF','NHF'));
    end
    yline(0,'k--','LineWidth',0.8,'HandleVisibility','off');
    allv=[pre;post]; ymax=max(allv(isfinite(allv))); ymin=min(allv(isfinite(allv))); rng=ymax-ymin;
    if ~isempty(row)
        text(1.5,ymax+0.12*rng,sprintf('\\DeltaN vs \\DeltaH\np_{FDR}=%s',local_pstr(row.p_fdr)),'HorizontalAlignment','center','FontSize',7.5,'Color',[0.3 0.3 0.3]);
        if ~isempty(row.p_N_paired)
            text(1,ymin-0.18*rng,sprintf('N: p=%s',local_pstr(row.p_N_paired)),'HorizontalAlignment','center','FontSize',7,'Color',CN);
            text(2,ymin-0.18*rng,sprintf('H: p=%s',local_pstr(row.p_H_paired)),'HorizontalAlignment','center','FontSize',7,'Color',CH);
        end
    end
    xlim([0.5 2.5]); xticks([1 2]); xticklabels({ppre,ppost}); ylabel(yl,'FontSize',8);
    title(sprintf('%s\n%s\x2192%s',strrep(oc,'_',' '),ppre,ppost),'FontSize',8,'Interpreter','none');
    if pp==1, legend('Location','best','FontSize',8); end
    grid on;
end
exportgraphics(fig6,fullfile(fig_dir,'summary_H3b_transfer.png'),'Resolution',180);

fprintf('All summary figures saved to %s\n',fig_dir);
%% ── SECTION: Descriptive plots for force/vibration & collision-impact outputs ──

% ── Load tables ──────────────────────────────────────────────────────────
FV   = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T');   FV = FV.T;
CI   = load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact'); CI = CI.T_impact;

% Convenience colour map
CN_d = CN;   % NHF
CH_d = CH;   % HF

% ── FIG D1: TSSV by phase-type and group (violin + mean±95%CI) ──────────
phase_types = {'baseline','training','test'};
fig_d1 = figure('Position',[2000 2000 1100 440]);
sgtitle('Descriptive — TSSV by phase type and group','FontWeight','bold','FontSize',11);

for pt = 1:numel(phase_types)
    ptype = phase_types{pt};
    Tsub = FV(strcmp(FV.phase_type, ptype) & isfinite(FV.tssf), :);

    % Subject-mean TSSV
    subj = unique(Tsub.subject);
    xs   = nan(numel(subj),1);
    ihs  = false(numel(subj),1);
    for si = 1:numel(subj)
        s       = subj{si};
        xs(si)  = mean(Tsub.tssv(strcmp(Tsub.subject,s)), 'omitnan');
        ihs(si) = any(Tsub.haptic(strcmp(Tsub.subject,s)));
    end
    xN = xs(~ihs & isfinite(xs));
    xH = xs( ihs & isfinite(xs));

    subplot(1, numel(phase_types), pt);
    hold on;
    local_violin(xN, 1, CN_d);
    local_violin(xH, 2, CH_d);
    errorbar(1, mean(xN,'omitnan'), std(xN,'omitnan')/sqrt(numel(xN))*1.96, ...
        'o','Color',CN_d,'MarkerFaceColor',CN_d,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');
    errorbar(2, mean(xH,'omitnan'), std(xH,'omitnan')/sqrt(numel(xH))*1.96, ...
        'o','Color',CH_d,'MarkerFaceColor',CH_d,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');

    % Wilcoxon rank-sum as a quick descriptive comparison
    if numel(xN)>=3 && numel(xH)>=3
        [~, p_rs] = ranksum(xN, xH);
    else
        p_rs = NaN;
    end

    xticks([1 2]); xticklabels({'NHF','HF'});
    ylabel('TSSV ((m s^{-2})^2 s)','FontSize',9);
    title(sprintf('%s\np_{rank-sum}=%s', ptype, local_pstr(p_rs)), 'FontSize',9,'Interpreter','none');
    grid on; xlim([0.5 2.5]);
end
exportgraphics(fig_d1, fullfile(fig_dir,'desc_D1_tssv_by_phasetype.png'), 'Resolution',180);

% ── FIG D2: TSSF by phase-type and group ────────────────────────────
fig_d2 = figure('Position',[2000 2000 1100 440]);
sgtitle('Descriptive — TSSF by phase type and group','FontWeight','bold','FontSize',11);

for pt = 1:numel(phase_types)
    ptype = phase_types{pt};
    Tsub = FV(strcmp(FV.phase_type, ptype) & isfinite(FV.tssf), :);
    subj = unique(Tsub.subject);
    xs   = nan(numel(subj),1);
    ihs  = false(numel(subj),1);
    for si = 1:numel(subj)
        s       = subj{si};
        xs(si) = mean(Tsub.tssf(strcmp(Tsub.subject,s)), 'omitnan');
        ihs(si) = any(Tsub.haptic(strcmp(Tsub.subject,s)));
    end
    xN = xs(~ihs & isfinite(xs));
    xH = xs( ihs & isfinite(xs));

    subplot(1, numel(phase_types), pt);
    hold on;
    local_violin(xN, 1, CN_d);
    local_violin(xH, 2, CH_d);
    errorbar(1, mean(xN,'omitnan'), std(xN,'omitnan')/sqrt(numel(xN))*1.96, ...
        'o','Color',CN_d,'MarkerFaceColor',CN_d,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');
    errorbar(2, mean(xH,'omitnan'), std(xH,'omitnan')/sqrt(numel(xH))*1.96, ...
        'o','Color',CH_d,'MarkerFaceColor',CH_d,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');

    if numel(xN)>=3 && numel(xH)>=3
        [~, p_rs] = ranksum(xN, xH);
    else
        p_rs = NaN;
    end

    xticks([1 2]); xticklabels({'NHF','HF'});
    ylabel('TSSF (N^2, calibrated)','FontSize',9);
    title(sprintf('%s\np_{rank-sum}=%s', ptype, local_pstr(p_rs)), 'FontSize',9,'Interpreter','none');
    grid on; xlim([0.5 2.5]);
end
exportgraphics(fig_d2, fullfile(fig_dir,'desc_D2_tssf_by_phasetype.png'), 'Resolution',180);

% ── FIG D3: TSSV across training levels (learning curve) ────────────────
TR = FV(strcmp(FV.phase_type,'training') & isfinite(FV.tssv), :);
levels = 1:5;
mu_N_tr = nan(1,5); mu_H_tr = nan(1,5);
se_N_tr = nan(1,5); se_H_tr = nan(1,5);

for lv = levels
    Tlv  = TR(TR.level == lv, :);
    subj = unique(Tlv.subject);
    xs   = nan(numel(subj),1); ihs = false(numel(subj),1);
    for si = 1:numel(subj)
        s       = subj{si};
        xs(si)  = mean(Tlv.tssv(strcmp(Tlv.subject,s)), 'omitnan');
        ihs(si) = any(Tlv.haptic(strcmp(Tlv.subject,s)));
    end
    xN = xs(~ihs & isfinite(xs)); xH = xs(ihs & isfinite(xs));
    mu_N_tr(lv) = mean(xN,'omitnan'); se_N_tr(lv) = std(xN,'omitnan')/sqrt(numel(xN));
    mu_H_tr(lv) = mean(xH,'omitnan'); se_H_tr(lv) = std(xH,'omitnan')/sqrt(numel(xH));
end

fig_d3 = figure('Position',[2000 2000 700 400]);
hold on;
fill([levels fliplr(levels)], ...
     [mu_N_tr+1.96*se_N_tr fliplr(mu_N_tr-1.96*se_N_tr)], ...
     CN_d,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
fill([levels fliplr(levels)], ...
     [mu_H_tr+1.96*se_H_tr fliplr(mu_H_tr-1.96*se_H_tr)], ...
     CH_d,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
plot(levels, mu_N_tr,'o-','Color',CN_d,'LineWidth',2,'MarkerFaceColor',CN_d,'MarkerSize',7,'DisplayName','NHF');
plot(levels, mu_H_tr,'o-','Color',CH_d,'LineWidth',2,'MarkerFaceColor',CH_d,'MarkerSize',7,'DisplayName','HF');
xlabel('Training level','FontSize',10); ylabel('TSSV ((m s^{-2})^2 s)','FontSize',10);
title('Descriptive — TSSV learning curve across training levels (mean \pm 95% CI)','FontSize',10);
legend('Location','best','FontSize',9); grid on; box on;
set(gca,'XTick',1:5,'XTickLabel',{'L1','L2','L3','L4','L5'});
exportgraphics(fig_d3, fullfile(fig_dir,'desc_D3_tssv_training_curve.png'), 'Resolution',180);

% ── FIG D4: Per-collision impact_tssv distribution (log scale) ──────────
fig_d4 = figure('Position',[2000 2000 900 420]);
sgtitle('Descriptive — Per-collision impact TSSV distribution by group & phase type', ...
        'FontWeight','bold','FontSize',11);

ptypes_ci = {'baseline','training','test'};
for pt = 1:numel(ptypes_ci)
    ptype = ptypes_ci{pt};
    Csub  = CI(strcmp(CI.phase_type, ptype) & isfinite(CI.impact_tssv) & CI.impact_tssv > 0, :);
    vN = log10(Csub.impact_tssv(~Csub.haptic));
    vH = log10(Csub.impact_tssv( Csub.haptic));

    subplot(1,3,pt); hold on;
    local_violin(vN, 1, CN_d);
    local_violin(vH, 2, CH_d);
    errorbar(1, mean(vN,'omitnan'), std(vN,'omitnan')/sqrt(numel(vN))*1.96, ...
        'o','Color',CN_d,'MarkerFaceColor',CN_d,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');
    errorbar(2, mean(vH,'omitnan'), std(vH,'omitnan')/sqrt(numel(vH))*1.96, ...
        'o','Color',CH_d,'MarkerFaceColor',CH_d,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');

    if numel(vN)>=3 && numel(vH)>=3
        [~, p_rs] = ranksum(vN, vH);
    else
        p_rs = NaN;
    end

    xticks([1 2]); xticklabels({'NHF','HF'});
    ylabel('log_{10}(impact TSSV)','FontSize',9);
    title(sprintf('%s\np_{rank-sum}=%s', ptype, local_pstr(p_rs)), 'FontSize',9,'Interpreter','none');
    grid on; xlim([0.5 2.5]);
end
exportgraphics(fig_d4, fullfile(fig_dir,'desc_D4_impact_tssv_dist.png'), 'Resolution',180);

% ── FIG D5: Per-collision audio peak distribution by group ──────────────
fig_d5 = figure('Position',[2000 2000 900 420]);
sgtitle('Descriptive — Per-collision peak audio by group & phase type', ...
        'FontWeight','bold','FontSize',11);

for pt = 1:numel(ptypes_ci)
    ptype = ptypes_ci{pt};
    Csub  = CI(strcmp(CI.phase_type, ptype) & isfinite(CI.impact_audio_peak), :);
    vN = Csub.impact_audio_peak(~Csub.haptic);
    vH = Csub.impact_audio_peak( Csub.haptic);

    subplot(1,3,pt); hold on;
    local_violin(vN, 1, CN_d);
    local_violin(vH, 2, CH_d);
    errorbar(1, mean(vN,'omitnan'), std(vN,'omitnan')/sqrt(numel(vN))*1.96, ...
        'o','Color',CN_d,'MarkerFaceColor',CN_d,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');
    errorbar(2, mean(vH,'omitnan'), std(vH,'omitnan')/sqrt(numel(vH))*1.96, ...
        'o','Color',CH_d,'MarkerFaceColor',CH_d,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');

    if numel(vN)>=3 && numel(vH)>=3
        [~, p_rs] = ranksum(vN, vH);
    else
        p_rs = NaN;
    end

    xticks([1 2]); xticklabels({'NHF','HF'});
    ylabel('Peak audio amplitude (a.u.)','FontSize',9);
    title(sprintf('%s\np_{rank-sum}=%s', ptype, local_pstr(p_rs)), 'FontSize',9,'Interpreter','none');
    grid on; xlim([0.5 2.5]);
end
exportgraphics(fig_d5, fullfile(fig_dir,'desc_D5_impact_audio_dist.png'), 'Resolution',180);

% ── FIG D6: Collision count per acquisition by level & group ─────────────
fig_d6 = figure('Position',[2000 2000 900 420]);
hold on;
TR_ci = CI(strcmp(CI.phase_type,'training') & isfinite(CI.level), :);

% Aggregate: count collisions per subject-level
subjs_all = unique(TR_ci.subject);
n_coll_mat_N = nan(numel(subjs_all), 5);
n_coll_mat_H = nan(numel(subjs_all), 5);
is_H_subj    = false(numel(subjs_all),1);

for si = 1:numel(subjs_all)
    s       = subjs_all{si};
    is_H_subj(si) = any(TR_ci.haptic(strcmp(TR_ci.subject,s)));
    for lv = 1:5
        n = sum(strcmp(TR_ci.subject,s) & TR_ci.level==lv);
        if is_H_subj(si)
            n_coll_mat_H(si,lv) = n;
        else
            n_coll_mat_N(si,lv) = n;
        end
    end
end

mu_n_N = mean(n_coll_mat_N,'omitnan');
mu_n_H = mean(n_coll_mat_H,'omitnan');
se_n_N = std(n_coll_mat_N,'omitnan') ./ sqrt(sum(isfinite(n_coll_mat_N)));
se_n_H = std(n_coll_mat_H,'omitnan') ./ sqrt(sum(isfinite(n_coll_mat_H)));

fill([levels fliplr(levels)], ...
     [mu_n_N+1.96*se_n_N fliplr(mu_n_N-1.96*se_n_N)], ...
     CN_d,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
fill([levels fliplr(levels)], ...
     [mu_n_H+1.96*se_n_H fliplr(mu_n_H-1.96*se_n_H)], ...
     CH_d,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
plot(levels, mu_n_N,'o-','Color',CN_d,'LineWidth',2,'MarkerFaceColor',CN_d,'MarkerSize',7,'DisplayName','NHF');
plot(levels, mu_n_H,'o-','Color',CH_d,'LineWidth',2,'MarkerFaceColor',CH_d,'MarkerSize',7,'DisplayName','HF');
xlabel('Training level','FontSize',10);
ylabel('Mean collision count per acquisition','FontSize',10);
title('Descriptive — Collision count across training levels (mean \pm 95% CI)','FontSize',10);
legend('Location','best','FontSize',9); grid on; box on;
set(gca,'XTick',1:5,'XTickLabel',{'L1','L2','L3','L4','L5'});
exportgraphics(fig_d6, fullfile(fig_dir,'desc_D6_collision_count_curve.png'), 'Resolution',180);

% ── FIG D7: impact_tssv vs impact_audio_peak scatter (training only) ────
fig_d7 = figure('Position',[2000 2000 620 520]);
hold on;
CI_tr = CI(strcmp(CI.phase_type,'training') & ...
           isfinite(CI.impact_tssv) & CI.impact_tssv > 0 & ...
           isfinite(CI.impact_audio_peak), :);

scatter(log10(CI_tr.impact_tssv(~CI_tr.haptic)), ...
        CI_tr.impact_audio_peak(~CI_tr.haptic), ...
        12, CN_d, 'filled','MarkerFaceAlpha',0.25,'DisplayName','NHF');
scatter(log10(CI_tr.impact_tssv( CI_tr.haptic)), ...
        CI_tr.impact_audio_peak( CI_tr.haptic), ...
        12, CH_d, 'filled','MarkerFaceAlpha',0.25,'DisplayName','HF');

% Overall regression line
xall = log10(CI_tr.impact_tssv);
yall = CI_tr.impact_audio_peak;
p_fit = polyfit(xall, yall, 1);
xrng  = linspace(min(xall), max(xall), 100);
plot(xrng, polyval(p_fit,xrng), 'k--','LineWidth',1.4,'DisplayName','OLS fit');

r_all = corr(xall, yall, 'Rows','complete');
xlabel('log_{10}(impact TSSV)','FontSize',10);
ylabel('Peak audio amplitude (a.u.)','FontSize',10);
title(sprintf('Descriptive — Impact TSSV vs audio peak (training)\nr=%.3f (all collisions)', r_all),'FontSize',10);
legend('Location','best','FontSize',9); grid on; box on;
exportgraphics(fig_d7, fullfile(fig_dir,'desc_D7_tssv_vs_audio_scatter.png'), 'Resolution',180);

% ── FIG D8: Tertile tier breakdown — stacked bar by group ───────────────
fig_d8 = figure('Position',[2000 2000 900 400]);
sgtitle('Descriptive — Impact tier composition by group (training collisions)','FontWeight','bold','FontSize',11);

tier_vars  = {'impact_tier_tssv','impact_tier_tssf','impact_tier_audio'};
tier_labels = {'Low','Mid','High'};
tier_titles = {'Tier: TSSV','Tier: TSSF','Tier: Audio'};
tier_cols   = [0.35 0.75 0.35; 0.98 0.76 0.15; 0.85 0.33 0.10];  % Low/Mid/High

CI_tr2 = CI(strcmp(CI.phase_type,'training'), :);

for tv = 1:numel(tier_vars)
    tvar = tier_vars{tv};
    subplot(1,3,tv); hold on;

    counts = nan(2,3);   % rows: NHF, HF  — cols: Low, Mid, High
    for gr = 1:2
        if gr==1, mask_g = ~CI_tr2.haptic; else, mask_g = CI_tr2.haptic; end
        v = CI_tr2.(tvar)(mask_g);
        for t = 1:3
            counts(gr,t) = sum(v == tier_labels{t});
        end
    end
    pct = counts ./ sum(counts,2) * 100;   % percent within group

    b = bar(pct,'stacked');
    for t = 1:3, b(t).FaceColor = tier_cols(t,:); b(t).DisplayName = tier_labels{t}; end
    xticks([1 2]); xticklabels({'NHF','HF'});
    ylabel('% of collisions','FontSize',9);
    title(tier_titles{tv},'FontSize',9);
    if tv==1, legend(tier_labels,'Location','northeast','FontSize',8); end
    ylim([0 105]); grid on;
end
exportgraphics(fig_d8, fullfile(fig_dir,'desc_D8_tier_composition.png'), 'Resolution',180);

fprintf('Descriptive figures (D1–D8) saved to %s\n', fig_dir);
% ── LOCAL FUNCTIONS ────────────────────────────────────────────────────
function s=local_stars(p)
    if isnan(p)||p>0.05, s=''; elseif p>0.01, s='*'; elseif p>0.001, s='**'; else, s='***'; end
end
function s=local_pstr(p)
    if isnan(p), s='n/a'; elseif p<0.001, s=sprintf('%.2e',p); elseif p<0.01, s=sprintf('%.3f',p); else, s=sprintf('%.3f',p); end
end
function local_violin(x,xpos,col)
    if numel(x)<3, scatter(xpos+(rand(numel(x),1)-0.5)*0.2,x,18,col,'filled','MarkerFaceAlpha',0.4,'HandleVisibility','off'); return; end
    [f,xi]=ksdensity(x,'NumPoints',100,'BoundaryCorrection','reflection');
    f=f/max(f)*0.35; patch([xpos+f fliplr(xpos-f)],[xi fliplr(xi)],col,'FaceAlpha',0.25,'EdgeColor',col,'LineWidth',0.8,'HandleVisibility','off');
    scatter(xpos+(rand(numel(x),1)-0.5)*0.15,x,10,col,'filled','MarkerFaceAlpha',0.3,'HandleVisibility','off');
end
function out=local_ternary(c,a,b), if c, out=a; else, out=b; end, end