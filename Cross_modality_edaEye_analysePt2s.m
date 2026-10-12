%% A4_A5_complete.m
clear; clc; close all;
cfg = config();
CN=[64 96 179]/255; CH=[139 82 168]/255;
fig_dir=fullfile(cfg.output_root,'figures'); if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

E=load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T_coll'); Ec=E.T_coll;
Y=load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T_coll','T'); Yc=Y.T_coll; Yb=Y.T;

pref={'pupil_mean_bc','pupil_mean_pctchg','pupil_mean_norm','pupil_mean'};
pup_col='';
for k=1:numel(pref)
    if ismember(pref{k},Yb.Properties.VariableNames), pup_col=pref{k}; break; end
end
fprintf('Using pupil column: %s\n',pup_col);

%% A4: gaze entropy -> pupil (LMM)
fprintf('\n=== A4: Gaze entropy -> pupil (LMM) ===\n');
Ytr=Yb(strcmp(Yb.phase_type,'training')&isfinite(Yb.gaze_entropy)&isfinite(Yb.(pup_col)),:);
subj_u=unique(Ytr.subject);
Ytr.entropy_z=nan(height(Ytr),1);
for si=1:numel(subj_u)
    idx=strcmp(Ytr.subject,subj_u{si});
    if sum(idx)<2, continue; end
    Ytr.entropy_z(idx)=(Ytr.gaze_entropy(idx)-mean(Ytr.gaze_entropy(idx),'omitnan'))./std(Ytr.gaze_entropy(idx),'omitnan');
end
Ytr=Ytr(isfinite(Ytr.entropy_z),:);
fprintf('Block rows for A4: %d\n',height(Ytr));
try
    lme4=fitlme(Ytr,sprintf('%s ~ entropy_z * haptic + (1|subject)',pup_col));
    disp(lme4.Coefficients(:,{'Name','Estimate','SE','tStat','pValue'}));
catch ME, fprintf('LMM A4 failed: %s\n',ME.message); end

fig=figure('Position',[50 50 700 450]); hold on;
yN=Ytr(~Ytr.haptic,:); yH=Ytr(Ytr.haptic,:);
scatter(yN.entropy_z,yN.(pup_col),20,CN,'filled','MarkerFaceAlpha',0.3);
scatter(yH.entropy_z,yH.(pup_col),20,CH,'filled','MarkerFaceAlpha',0.3);
okN=isfinite(yN.(pup_col))&isfinite(yN.entropy_z);
okH=isfinite(yH.(pup_col))&isfinite(yH.entropy_z);
fN=polyfit(yN.entropy_z(okN),yN.(pup_col)(okN),1);
fH=polyfit(yH.entropy_z(okH),yH.(pup_col)(okH),1);
xl=[-3 3]; plot(xl,polyval(fN,xl),'-','Color',CN,'LineWidth',2);
plot(xl,polyval(fH,xl),'-','Color',CH,'LineWidth',2);
xlabel('Gaze entropy (within-subject z-score, bits)');
ylabel(sprintf('%s (a.u.)',strrep(pup_col,'_',' ')));
legend({'NHF','HF','NHF fit','HF fit'},'Location','northwest');
title('A4: Gaze entropy vs pupil diameter by group');
saveas(fig,fullfile(fig_dir,'A4_entropy_pupil.png')); close(fig);

%% A5: collision response trajectories
fprintf('\n=== A5: Collision response trajectories ===\n');
J=innerjoin(Ec,Yc,'Keys',{'subject','phase','repetition','collision_idx'},...
    'RightVariables',{'pupil_response_norm'});
J=J(isfinite(J.scr_amp_local_bc)&isfinite(J.pupil_response_norm),:);
Jtr=J(strcmp(J.phase_type,'training'),:);
fprintf('Training rows: %d\n',height(Jtr));

levels=1:5; lnames={'L1','L2','L3','L4','L5'};
mu_eN=nan(5,1); mu_eH=nan(5,1); se_eN=nan(5,1); se_eH=nan(5,1);
mu_pN=nan(5,1); mu_pH=nan(5,1); se_pN=nan(5,1); se_pH=nan(5,1);

for li=1:5
    lv=sprintf('level_L%d',li);
    jl=Jtr(strcmp(Jtr.phase,lv),:);
    fprintf('Level %d (%s): %d rows\n',li,lv,height(jl));
    if isempty(jl), continue; end
    xN=jl.scr_amp_local_bc(~jl.haptic); xH=jl.scr_amp_local_bc(jl.haptic);
    yN=jl.pupil_response_norm(~jl.haptic); yH=jl.pupil_response_norm(jl.haptic);
    xN=xN(isfinite(xN)); xH=xH(isfinite(xH));
    yN=yN(isfinite(yN)); yH=yH(isfinite(yH));
    if isempty(xN)||isempty(xH)||isempty(yN)||isempty(yH), continue; end
    mu_eN(li)=mean(xN); mu_eH(li)=mean(xH);
    se_eN(li)=std(xN)/sqrt(numel(xN)); se_eH(li)=std(xH)/sqrt(numel(xH));
    mu_pN(li)=mean(yN); mu_pH(li)=mean(yH);
    se_pN(li)=std(yN)/sqrt(numel(yN)); se_pH(li)=std(yH)/sqrt(numel(yH));
    [~,pe]=ttest2(xH,xN,'Vartype','unequal');
    [~,pp]=ttest2(yH,yN,'Vartype','unequal');
    fprintf('L%d | EDA NHF=%.4f HF=%.4f p=%.4f | Pupil NHF=%.4f HF=%.4f p=%.4f\n',...
        li,mean(xN),mean(xH),pe,mean(yN),mean(yH),pp);
end
%%
fig=figure('Position',[50 50 1000 420]);
subplot(1,2,1); hold on;
errorbar(levels,mu_eN,se_eN,'-o','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7);
errorbar(levels,mu_eH,se_eH,'-o','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7);
xticks(levels); xticklabels(lnames);
xlabel('Training level'); ylabel('EDA collision response (fraction of resting tonic SCL)');
legend({'NHF','HF'},'Location','best'); title('A5a: EDA collision response by level');

subplot(1,2,2); hold on;
errorbar(levels,mu_pN,se_pN,'-o','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7);
errorbar(levels,mu_pH,se_pH,'-o','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7);
xticks(levels); xticklabels(lnames);
xlabel('Training level'); ylabel('Pupil collision response (fraction of resting pupil diameter)');
legend({'NHF','HF'},'Location','best'); title('A5b: Pupil collision response by level');
saveas(fig,fullfile(fig_dir,'A5_collision_trajectories.png'));
fprintf('Done.\n');