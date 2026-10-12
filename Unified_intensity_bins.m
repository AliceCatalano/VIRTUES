%% unified_intensity_bins.m
clear; clc; cfg = config();
CN = [64 96 179]/255; CH = [139 82 168]/255;
fig_dir = fullfile(cfg.output_root,'figures');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

loaded = load(fullfile(cfg.output_root,'collision_impact_features.mat'));
T_impact = loaded.T_impact;
EDA = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T_coll'); Ec=EDA.T_coll;
EYE = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T_coll'); Yc=EYE.T_coll;

CI_tr = T_impact(strcmp(T_impact.phase_type,'training') & isfinite(T_impact.impact_tssv) & T_impact.impact_tssv>0,:);
CI_tr.log_itssv = log(CI_tr.impact_tssv);

fprintf('Training collisions with valid impact_tssv: N=%d  H=%d\n', sum(~CI_tr.haptic), sum(CI_tr.haptic));

%% Step 1: KS test
[~,p_ks]  = kstest2(CI_tr.log_itssv(~CI_tr.haptic), CI_tr.log_itssv(CI_tr.haptic));
p_rs      = ranksum(CI_tr.log_itssv(~CI_tr.haptic), CI_tr.log_itssv(CI_tr.haptic));
fprintf('\nKS test log-impact_tssv NHF vs HF: p=%.4e\n',p_ks);
fprintf('Ranksum test: p=%.4e\n',p_rs);
fprintf('NHF: median=%.3f  IQR=%.3f\n',median(CI_tr.log_itssv(~CI_tr.haptic)),iqr(CI_tr.log_itssv(~CI_tr.haptic)));
fprintf('HF:  median=%.3f  IQR=%.3f\n',median(CI_tr.log_itssv(CI_tr.haptic)), iqr(CI_tr.log_itssv(CI_tr.haptic)));

%% Step 2: canonical bins
qp = [0 0.25 0.50 0.75 1.0];
edges_N = quantile(CI_tr.log_itssv(~CI_tr.haptic), qp);
edges_H = quantile(CI_tr.log_itssv( CI_tr.haptic), qp);

fprintf('\n=== Canonical intensity bin edges (log-impact_tssv) ===\n');
fprintf('NHF edges: '); fprintf('%.3f  ',edges_N); fprintf('\n');
fprintf('HF  edges: '); fprintf('%.3f  ',edges_H); fprintf('\n');
fprintf('\nNHF bin ranges (log):');
for b=1:4, fprintf(' [%.3f,%.3f]',edges_N(b),edges_N(b+1)); end; fprintf('\n');
fprintf('HF  bin ranges (log):');
for b=1:4, fprintf(' [%.3f,%.3f]',edges_H(b),edges_H(b+1)); end; fprintf('\n');
fprintf('\nNHF bin ranges (raw (m/s^2)^2 s):');
for b=1:4, fprintf(' [%.4f,%.4f]',exp(edges_N(b)),exp(edges_N(b+1))); end; fprintf('\n');
fprintf('HF  bin ranges (raw (m/s^2)^2 s):');
for b=1:4, fprintf(' [%.4f,%.4f]',exp(edges_H(b)),exp(edges_H(b+1))); end; fprintf('\n');

%% Step 3: assign bins and save
[~,~,binN] = histcounts(CI_tr.log_itssv(~CI_tr.haptic), edges_N);
[~,~,binH] = histcounts(CI_tr.log_itssv( CI_tr.haptic), edges_H);
CI_tr.intensity_bin = zeros(height(CI_tr),1);
CI_tr.intensity_bin(~CI_tr.haptic) = binN;
CI_tr.intensity_bin( CI_tr.haptic) = binH;

% add columns to full T_impact
T_impact.log_itssv     = nan(height(T_impact),1);
T_impact.intensity_bin = zeros(height(T_impact),1);
tr_idx = strcmp(T_impact.phase_type,'training') & isfinite(T_impact.impact_tssv) & T_impact.impact_tssv>0;
T_impact.log_itssv(tr_idx) = log(T_impact.impact_tssv(tr_idx));

% assign bins to matching rows
[~,~,binN_full] = histcounts(T_impact.log_itssv(tr_idx & ~T_impact.haptic), edges_N);
[~,~,binH_full] = histcounts(T_impact.log_itssv(tr_idx &  T_impact.haptic), edges_H);
idx_N = find(tr_idx & ~T_impact.haptic);
idx_H = find(tr_idx &  T_impact.haptic);
T_impact.intensity_bin(idx_N) = binN_full;
T_impact.intensity_bin(idx_H) = binH_full;

save(fullfile(cfg.output_root,'collision_impact_features_binned.mat'),'T_impact','edges_N','edges_H');
fprintf('\nSaved collision_impact_features_binned.mat\n');

%% Step 4: H2 variance analyses — all outcomes
fprintf('\n=== H2: Variance and mean by canonical impact_tssv bins ===\n');

LOWER_SCR = -0.5; UPPER_SCR = 5.0;
min_scr_raw = min(Ec.scr_amp_local_bc(isfinite(Ec.scr_amp_local_bc) & Ec.scr_amp_local_bc > LOWER_SCR));
offset_scr  = abs(min(Ec.scr_amp_local_bc(isfinite(Ec.scr_amp_local_bc)))) + 0.01;
fprintf('SCR log-transform offset: %.4f\n',offset_scr);

outcomes_h2 = {
    'scr_amp_local_bc',   'log(phasic SCR amplitude + offset)', Ec,  true
    'pupil_response_norm','Pupil dilation (fraction of resting)', Yc, true
    'impact_tssf',        'log-impact TSSF (log N^2)',           [],  false
    'impact_audio_peak',  'Audio peak (a.u.)',                   [],  false
};

all_h2 = struct();

for oi = 1:size(outcomes_h2,1)
    oc       = outcomes_h2{oi,1};
    yl       = outcomes_h2{oi,2};
    src_tbl  = outcomes_h2{oi,3};
    need_log = outcomes_h2{oi,4};

    if isempty(src_tbl)
        J = CI_tr(isfinite(CI_tr.(oc)) & CI_tr.intensity_bin>0,:);
        J.resp = J.(oc);
        J.is_haptic = J.haptic;
    else
        J = innerjoin(CI_tr, src_tbl, ...
            'Keys',{'subject','phase','repetition','collision_idx'}, ...
            'RightVariables',{oc});
        J = J(isfinite(J.(oc)) & J.intensity_bin>0,:);
        J.resp = J.(oc);
        hap_col = local_find_haptic(J);
        J.is_haptic = J.(hap_col);
    end

    % apply hard bounds for SCR
    if strcmp(oc,'scr_amp_local_bc')
        bad = J.resp < LOWER_SCR | J.resp > UPPER_SCR;
        J = J(~bad,:);
        fprintf('\n%s: removed %d hard-bound values\n',oc,sum(bad));
    end

    % log-transform if needed
    if need_log && strcmp(oc,'scr_amp_local_bc')
        J.resp = log(J.resp + offset_scr);
    elseif need_log && strcmp(oc,'pupil_response_norm')
        J.resp = J.resp;   % pupil already normalised, no log needed
    elseif ~isempty(src_tbl) && strcmp(oc,'impact_tssf') && any(J.resp>0)
        J = J(J.resp>0,:);
        J.resp = log(J.resp);
    end

    fprintf('\n--- %s (n=%d) ---\n',oc,height(J));
    rows={};
    for b=1:4
        xN=J.resp(~J.is_haptic & J.intensity_bin==b); xN=xN(isfinite(xN));
        xH=J.resp( J.is_haptic & J.intensity_bin==b); xH=xH(isfinite(xH));
        if numel(xN)<3||numel(xH)<3, continue; end
        sdN=std(xN); sdH=std(xH);
        p_lev=local_levene(xN,xH);
        [~,p_mu]=ttest2(xH,xN,'Vartype','unequal');
        sp=sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
        d=(mean(xH)-mean(xN))/sp*(1-3/(4*(numel(xN)+numel(xH)-2)-1));
        fprintf('Bin%d | N=%d H=%d | SD_N=%.3f SD_H=%.3f ratio=%.3f | Lev_p=%.4g mu_p=%.4g d=%.3f\n',...
            b,numel(xN),numel(xH),sdN,sdH,sdN/sdH,p_lev,p_mu,d);
        rows(end+1,:)={b,numel(xN),numel(xH),mean(xN),mean(xH),sdN,sdH,sdN/sdH,p_lev,p_mu,d};
    end
    if isempty(rows), continue; end
    T_h2=cell2table(rows,'VariableNames',{'bin','n_N','n_H','mean_N','mean_H','sd_N','sd_H','ratio_sd','p_levene','p_mean','cohens_d'});
    T_h2.p_levene_fdr=mafdr(T_h2.p_levene,'BHFDR',true);
    T_h2.p_mean_fdr  =mafdr(T_h2.p_mean,'BHFDR',true);
    all_h2.(oc)=T_h2;
end

%% Step 5: C3/C4 LMMs with canonical bins
fprintf('\n=== C3: log-impact_tssv -> log(SCR+offset) ===\n');
J_eda = innerjoin(CI_tr, Ec,'Keys',{'subject','phase','repetition','collision_idx'},'RightVariables',{'scr_amp_local_bc'});
hap_eda = local_find_haptic(J_eda);
bad_eda = J_eda.scr_amp_local_bc<LOWER_SCR | J_eda.scr_amp_local_bc>UPPER_SCR;
J_eda = J_eda(~bad_eda & isfinite(J_eda.scr_amp_local_bc) & J_eda.intensity_bin>0,:);
J_eda.log_scr = log(J_eda.scr_amp_local_bc + offset_scr);
subj_u=unique(J_eda.subject); J_eda.itssv_z=nan(height(J_eda),1);
for si=1:numel(subj_u)
    s=subj_u{si}; idx=strcmp(J_eda.subject,s); v=J_eda.log_itssv(idx);
    J_eda.itssv_z(idx)=(v-mean(v,'omitnan'))./(std(v,'omitnan')+1e-12);
end
J_eda.haptic_cat=categorical(J_eda.(hap_eda),logical([0 1]),{'N','H'});
J_eda.subject_cat=categorical(J_eda.subject);
lme_c3=fitlme(J_eda,'log_scr ~ itssv_z * haptic_cat + (1|subject_cat)', ...
    'FitMethod','REML','DummyVarCoding','reference','Verbose',false);
disp(lme_c3.Coefficients(:,{'Name','Estimate','SE','tStat','pValue'}));
disp(anova(lme_c3));

fprintf('\n=== C4: log-impact_tssv -> pupil_response_norm ===\n');
J_pup = innerjoin(CI_tr, Yc,'Keys',{'subject','phase','repetition','collision_idx'},'RightVariables',{'pupil_response_norm'});
hap_pup = local_find_haptic(J_pup);
J_pup = J_pup(isfinite(J_pup.pupil_response_norm) & J_pup.intensity_bin>0,:);
subj_u=unique(J_pup.subject); J_pup.itssv_z=nan(height(J_pup),1);
for si=1:numel(subj_u)
    s=subj_u{si}; idx=strcmp(J_pup.subject,s); v=J_pup.log_itssv(idx);
    J_pup.itssv_z(idx)=(v-mean(v,'omitnan'))./(std(v,'omitnan')+1e-12);
end
J_pup.haptic_cat=categorical(J_pup.(hap_pup),logical([0 1]),{'N','H'});
J_pup.subject_cat=categorical(J_pup.subject);
lme_c4=fitlme(J_pup,'pupil_response_norm ~ itssv_z * haptic_cat + (1|subject_cat)', ...
    'FitMethod','REML','DummyVarCoding','reference','Verbose',false);
disp(lme_c4.Coefficients(:,{'Name','Estimate','SE','tStat','pValue'}));
disp(anova(lme_c4));

%% Step 6: Unified H2 figure
fig=figure('Position',[2000 2000 1400 900]);
tl=tiledlayout(size(outcomes_h2,1),5,'TileSpacing','compact','Padding','compact');
title(tl,'H2: All outcomes by canonical impact\_tssv intensity bins (group-specific quartiles)', ...
    'FontWeight','bold','FontSize',11);

for oi=1:size(outcomes_h2,1)
    oc=outcomes_h2{oi,1}; yl=outcomes_h2{oi,2};
    src_tbl=outcomes_h2{oi,3};
    if ~isfield(all_h2,oc), for b=1:5, nexttile; end; continue; end
    T_h2=all_h2.(oc);

    if isempty(src_tbl)
        J=CI_tr(isfinite(CI_tr.(oc))&CI_tr.intensity_bin>0,:); J.resp=J.(oc); J.is_haptic=J.haptic;
    else
        J=innerjoin(CI_tr,src_tbl,'Keys',{'subject','phase','repetition','collision_idx'},'RightVariables',{oc});
        J=J(isfinite(J.(oc))&J.intensity_bin>0,:); J.resp=J.(oc); J.is_haptic=J.(local_find_haptic(J));
    end
    if strcmp(oc,'scr_amp_local_bc')
        bad=J.resp<LOWER_SCR|J.resp>UPPER_SCR; J=J(~bad,:);
        J.resp=log(J.resp+offset_scr);
    elseif strcmp(oc,'impact_tssf') && any(J.resp>0)
        J=J(J.resp>0,:); J.resp=log(J.resp);
    end

    for b=1:4
        nexttile; hold on;
        xN=J.resp(~J.is_haptic&J.intensity_bin==b); xN=xN(isfinite(xN));
        xH=J.resp( J.is_haptic&J.intensity_bin==b); xH=xH(isfinite(xH));
        if numel(xN)<3||numel(xH)<3, title(sprintf('B%d insuff',b),'FontSize',6); continue; end
        local_violin(xN,1,CN); local_violin(xH,2,CH);
        errorbar(1,mean(xN),std(xN)/sqrt(numel(xN))*1.96,'o','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',6,'HandleVisibility','off');
        errorbar(2,mean(xH),std(xH)/sqrt(numel(xH))*1.96,'o','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',6,'HandleVisibility','off');
        ymax=max([xN;xH]); ymin=min([xN;xH]); rng=max(ymax-ymin,1e-9);
        sig=local_stars(T_h2.p_levene_fdr(b));
        if ~isempty(sig)
            yt=ymax+0.05*rng; plot([1 2],[yt yt],'k-','LineWidth',1,'HandleVisibility','off');
            text(1.5,yt+0.03*rng,sig,'HorizontalAlignment','center','FontSize',11);
        end
        xticks([1 2]); xticklabels({'NHF','HF'});
        if b==1, ylabel(yl,'FontSize',7,'Interpreter','none'); end
        title(sprintf('Bin%d\nSD_N=%.3f\nSD_H=%.3f\np_{Lev}=%s',b,std(xN),std(xH),local_pstr(T_h2.p_levene_fdr(b))),'FontSize',6);
        grid on; xlim([0.5 2.5]);
    end
    nexttile; hold on;
    bh=bar(1:4,T_h2.ratio_sd,0.55); bh.FaceColor='flat';
    for b=1:4, bh.CData(b,:)=local_ternary(T_h2.p_levene_fdr(b)<0.05,[0.3 0.6 0.3],[0.7 0.7 0.7]); end
    yline(1,'r--','LineWidth',1.5,'HandleVisibility','off');
    ylabel('SD_{NHF}/SD_{HF}','FontSize',8); xlabel('Bin','FontSize',8);
    title(strrep(oc,'_',' '),'FontSize',7,'Interpreter','none');
    set(gca,'XTick',1:4); grid on;
end
exportgraphics(fig,fullfile(fig_dir,'H2_unified_canonical_bins.png'),'Resolution',180);

save(fullfile(cfg.output_root,'h2_unified_results.mat'),'all_h2','edges_N','edges_H','lme_c3','lme_c4','offset_scr');
fprintf('\nSaved h2_unified_results.mat\n');

function hap_col=local_find_haptic(T)
    for k={'haptic','haptic_x','haptic_y'}
        if ismember(k{1},T.Properties.VariableNames)&&islogical(T.(k{1})), hap_col=k{1}; return; end
    end
    error('No logical haptic column found. Available: %s',strjoin(T.Properties.VariableNames,', '));
end
function p=local_levene(x,y)
    [~,p]=ttest2(abs(x-median(x)),abs(y-median(y)),'Vartype','unequal');
end
function local_violin(x,xpos,col)
    if numel(x)<3,scatter(xpos+(rand(numel(x),1)-0.5)*0.2,x,18,col,'filled','MarkerFaceAlpha',0.4,'HandleVisibility','off'); return; end
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