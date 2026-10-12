%% cross_modality_analyses.m
clear; clc; close all;
cfg = config();
CN=[64 96 179]/255; CH=[139 82 168]/255;
fig_dir=fullfile(cfg.output_root,'figures'); if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

E=load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T_coll','T'); Ec=E.T_coll; Eb=E.T;
Y=load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T_coll','T'); Yc=Y.T_coll; Yb=Y.T;

% --- inner join on per-collision keys ---
J=innerjoin(Ec,Yc,'Keys',{'subject','phase','repetition','collision_idx'},...
    'RightVariables',{'pupil_response_norm'});
J=J(strcmp(J.phase_type,'training')&isfinite(J.scr_amp_local_bc)&isfinite(J.pupil_response_norm),:);
fprintf('Joined training collisions: %d (N=%d H=%d)\n',height(J),sum(~J.haptic),sum(J.haptic));

all_results=struct();

%% === Analysis 1: within-subject pupil-EDA correlation per collision ===
fprintf('\n=== A1: Within-subject pupil-EDA correlation ===\n');
subj_list=unique(J.subject); ns=numel(subj_list);
r_vals=nan(ns,1); p_vals=nan(ns,1); is_h=false(ns,1);
for si=1:ns
    s=subj_list{si}; Js=J(strcmp(J.subject,s),:);
    is_h(si)=any(Js.haptic);
    if height(Js)<5, continue; end
    [r_vals(si),p_vals(si)]=corr(Js.scr_amp_local_bc,Js.pupil_response_norm,'type','Spearman','rows','complete');
end
rN=r_vals(~is_h&isfinite(r_vals)); rH=r_vals(is_h&isfinite(r_vals));
[~,p12]=ttest2(rH,rN,'Vartype','unequal');
[p1w]=ranksum(rH,rN);
sp=sqrt(((numel(rN)-1)*var(rN)+(numel(rH)-1)*var(rH))/(numel(rN)+numel(rH)-2));
d1=(mean(rH)-mean(rN))/sp*(1-3/(4*(numel(rN)+numel(rH)-2)-1));
fprintf('NHF: n=%d mean_r=%.3f SD=%.3f\n',numel(rN),mean(rN),std(rN));
fprintf('HF:  n=%d mean_r=%.3f SD=%.3f\n',numel(rH),mean(rH),std(rH));
fprintf('NHF vs HF: t=%.3f p=%.4f W_p=%.4f d=%.3f\n',(mean(rH)-mean(rN))/sqrt(var(rH)/numel(rH)+var(rN)/numel(rN)),p12,p1w,d1);
% one-sample vs zero
[~,p1N0]=ttest(rN); [~,p1H0]=ttest(rH);
fprintf('NHF r vs 0: mean=%.3f t=%.3f p=%.4f\n',mean(rN),mean(rN)/(std(rN)/sqrt(numel(rN))),p1N0);
fprintf('HF  r vs 0: mean=%.3f t=%.3f p=%.4f\n',mean(rH),mean(rH)/(std(rH)/sqrt(numel(rH))),p1H0);
all_results.A1=table(subj_list,r_vals,p_vals,is_h,'VariableNames',{'subject','r_pupil_eda','p_corr','haptic'});

fig=figure('Position',[50 50 600 450]);
hold on;
xN=ones(numel(rN),1); xH=2*ones(numel(rH),1);
scatter(xN+randn(numel(rN),1)*0.05,rN,40,CN,'filled','MarkerFaceAlpha',0.6);
scatter(xH+randn(numel(rH),1)*0.05,rH,40,CH,'filled','MarkerFaceAlpha',0.6);
errorbar([1 2],[mean(rN) mean(rH)],[std(rN)/sqrt(numel(rN)) std(rH)/sqrt(numel(rH))],'k.','LineWidth',2,'MarkerSize',20);
yline(0,'--k','LineWidth',1);
xticks([1 2]); xticklabels({'NHF','HF'}); ylabel('Spearman r (pupil-EDA per collision)');
title(sprintf('A1: Pupil-EDA coupling | NHF vs HF t-test p=%.3f d=%.2f',p12,d1));
if p12<0.05, text(1.5,max([rN;rH])*0.95,'*','FontSize',18,'HorizontalAlignment','center'); end
saveas(fig,fullfile(fig_dir,'A1_pupil_eda_coupling.png')); 

%% === Analysis 2: CV concordance across modalities ===
fprintf('\n=== A2: CV concordance (pupil vs EDA) ===\n');
cv_eda=nan(ns,1); cv_pup=nan(ns,1);
for si=1:ns
    s=subj_list{si}; Js=J(strcmp(J.subject,s),:);
    if height(Js)<5, continue; end
    x=Js.scr_amp_local_bc; y=Js.pupil_response_norm;
    if mean(abs(x),'omitnan')>0, cv_eda(si)=std(x,'omitnan')/mean(abs(x),'omitnan'); end
    if mean(abs(y),'omitnan')>0, cv_pup(si)=std(y,'omitnan')/mean(abs(y),'omitnan'); end
end
ok=isfinite(cv_eda)&isfinite(cv_pup);
[r2,p2]=corr(cv_eda(ok),cv_pup(ok),'type','Spearman');
fprintf('Overall CV correlation: rho=%.3f p=%.4f n=%d\n',r2,p2,sum(ok));
[r2N,p2N]=corr(cv_eda(ok&~is_h),cv_pup(ok&~is_h),'type','Spearman');
[r2H,p2H]=corr(cv_eda(ok&is_h),cv_pup(ok&is_h),'type','Spearman');
fprintf('NHF: rho=%.3f p=%.4f | HF: rho=%.3f p=%.4f\n',r2N,p2N,r2H,p2H);
cvN_e=cv_eda(~is_h&ok); cvH_e=cv_eda(is_h&ok);
cvN_p=cv_pup(~is_h&ok); cvH_p=cv_pup(is_h&ok);
[~,p2ge]=ttest2(cvH_e,cvN_e,'Vartype','unequal');
[~,p2gp]=ttest2(cvH_p,cvN_p,'Vartype','unequal');
fprintf('CV_EDA NHF=%.3f HF=%.3f p=%.4f\n',mean(cvN_e),mean(cvH_e),p2ge);
fprintf('CV_pup NHF=%.3f HF=%.3f p=%.4f\n',mean(cvN_p),mean(cvH_p),p2gp);

fig=figure('Position',[50 50 600 500]);
hold on;
scatter(cv_eda(ok&~is_h),cv_pup(ok&~is_h),60,CN,'filled','MarkerFaceAlpha',0.7);
scatter(cv_eda(ok&is_h),cv_pup(ok&is_h),60,CH,'filled','MarkerFaceAlpha',0.7);
lfit=polyfit(cv_eda(ok),cv_pup(ok),1);
xl=xlim; xr=linspace(xl(1),xl(2),100);
plot(xr,polyval(lfit,xr),'k--','LineWidth',1.5);
xlabel('CV EDA (collision response)'); ylabel('CV Pupil (collision response)');
legend({'NHF','HF','overall fit'},'Location','northwest');
title(sprintf('A2: CV concordance | rho=%.3f p=%.3f',r2,p2));
saveas(fig,fullfile(fig_dir,'A2_cv_concordance.png'));

%% === Analysis 3: saccade rate predicts EDA (block level) ===
fprintf('\n=== A3: Saccade rate -> EDA (LMM, training phase) ===\n');
% join block-level tables on subject+phase+repetition
Ytr=Yb(strcmp(Yb.phase_type,'training')&isfinite(Yb.saccade_rate),:);
Etr=Eb(strcmp(Eb.phase_type,'training')&isfinite(Eb.scl_mean_bc),:);
B=innerjoin(Etr,Ytr,'Keys',{'subject','phase','repetition'},'RightVariables',{'saccade_rate','gaze_entropy','fixation_rate','fixation_mean_dur'});
B=B(isfinite(B.saccade_rate)&isfinite(B.scl_mean_bc),:);
fprintf('Block-level joined rows (training): %d\n',height(B));
% z-score saccade_rate within subject to get within-person effect
subj_u=unique(B.subject);
B.saccade_rate_z=nan(height(B),1);
for si=1:numel(subj_u)
    idx=strcmp(B.subject,subj_u{si});
    B.saccade_rate_z(idx)=(B.saccade_rate(idx)-mean(B.saccade_rate(idx),'omitnan'))/std(B.saccade_rate(idx),'omitnan');
end
try
    lme3=fitlme(B,'scl_mean_bc ~ saccade_rate_z * haptic + (1|subject)');
    disp(lme3.Coefficients(:,{'Name','Estimate','SE','tStat','pValue'}));
    all_results.A3_lme=lme3;
catch ME, fprintf('LMM failed: %s\n',ME.message); end

% scatter: saccade_rate_z vs scl_mean_bc per group
fig=figure('Position',[50 50 700 450]);
hold on;
bN=B(~B.haptic,:); bH=B(B.haptic,:);
scatter(bN.saccade_rate_z,bN.scl_mean_bc,20,CN,'filled','MarkerFaceAlpha',0.3);
scatter(bH.saccade_rate_z,bH.scl_mean_bc,20,CH,'filled','MarkerFaceAlpha',0.3);
fN=polyfit(bN.saccade_rate_z(isfinite(bN.scl_mean_bc)),bN.scl_mean_bc(isfinite(bN.scl_mean_bc)),1);
fH=polyfit(bH.saccade_rate_z(isfinite(bH.scl_mean_bc)),bH.scl_mean_bc(isfinite(bH.scl_mean_bc)),1);
xl=[-3 3]; plot(xl,polyval(fN,xl),'-','Color',CN,'LineWidth',2);
plot(xl,polyval(fH,xl),'-','Color',CH,'LineWidth',2);
xlabel('Saccade rate (within-subject z-score, saccades/min)');
ylabel('Tonic SCL above resting (\muS)');
legend({'NHF data','HF data','NHF fit','HF fit'},'Location','northwest');
title('A3: Saccade rate vs tonic EDA by group');
saveas(fig,fullfile(fig_dir,'A3_saccade_eda.png')); 

%% === Analysis 4: gaze entropy predicts pupil diameter (block level) ===
fprintf('\n=== A4: Gaze entropy -> pupil (LMM, training phase) ===\n');
Ytr2=Yb(strcmp(Yb.phase_type,'training')&isfinite(Yb.gaze_entropy)&isfinite(Yb.pupil_mean_bc),:);
Ytr2.entropy_z=nan(height(Ytr2),1);
for si=1:numel(subj_u)
    idx=strcmp(Ytr2.subject,subj_u{si});
    if sum(idx)<2, continue; end
    Ytr2.entropy_z(idx)=(Ytr2.gaze_entropy(idx)-mean(Ytr2.gaze_entropy(idx),'omitnan'))/std(Ytr2.gaze_entropy(idx),'omitnan');
end
Ytr2=Ytr2(isfinite(Ytr2.entropy_z),:);
fprintf('Block rows for A4: %d\n',height(Ytr2));
try
    lme4=fitlme(Ytr2,'pupil_mean_bc ~ entropy_z * haptic + (1|subject)');
    disp(lme4.Coefficients(:,{'Name','Estimate','SE','tStat','pValue'}));
    all_results.A4_lme=lme4;
catch ME, fprintf('LMM failed: %s\n',ME.message); end

fig=figure('Position',[50 50 700 450]);
hold on;
yN=Ytr2(~Ytr2.haptic,:); yH=Ytr2(Ytr2.haptic,:);
scatter(yN.entropy_z,yN.pupil_mean_bc,20,CN,'filled','MarkerFaceAlpha',0.3);
scatter(yH.entropy_z,yH.pupil_mean_bc,20,CH,'filled','MarkerFaceAlpha',0.3);
fN4=polyfit(yN.entropy_z(isfinite(yN.pupil_mean_bc)),yN.pupil_mean_bc(isfinite(yN.pupil_mean_bc)),1);
fH4=polyfit(yH.entropy_z(isfinite(yH.pupil_mean_bc)),yH.pupil_mean_bc(isfinite(yH.pupil_mean_bc)),1);
xl4=[-3 3]; plot(xl4,polyval(fN4,xl4),'-','Color',CN,'LineWidth',2);
plot(xl4,polyval(fH4,xl4),'-','Color',CH,'LineWidth',2);
xlabel('Gaze entropy (within-subject z-score, bits)');
ylabel('Normalized pupil diameter above resting (a.u.)');
legend({'NHF data','HF data','NHF fit','HF fit'},'Location','northwest');
title('A4: Gaze entropy vs pupil diameter by group');
saveas(fig,fullfile(fig_dir,'A4_entropy_pupil.png')); 

%% === Analysis 5: collision response time course pupil vs EDA ===
fprintf('\n=== A5: Collision response trajectories across levels ===\n');
levels=1:5; lnames={'L1','L2','L3','L4','L5'};
mu_eda_N=nan(5,1); mu_eda_H=nan(5,1); se_eda_N=nan(5,1); se_eda_H=nan(5,1);
mu_pup_N=nan(5,1); mu_pup_H=nan(5,1); se_pup_N=nan(5,1); se_pup_H=nan(5,1);
for li=1:5
    lv=sprintf('Training_L%d',li);
    jl=J(strcmp(J.phase,lv),:);
    xN=jl.scr_amp_local_bc(~jl.haptic); xH=jl.scr_amp_local_bc(jl.haptic);
    yN=jl.pupil_response_norm(~jl.haptic); yH=jl.pupil_response_norm(jl.haptic);
    xN=xN(isfinite(xN)); xH=xH(isfinite(xH));
    yN=yN(isfinite(yN)); yH=yH(isfinite(yH));
    mu_eda_N(li)=mean(xN); mu_eda_H(li)=mean(xH);
    se_eda_N(li)=std(xN)/sqrt(numel(xN)); se_eda_H(li)=std(xH)/sqrt(numel(xH));
    mu_pup_N(li)=mean(yN); mu_pup_H(li)=mean(yH);
    se_pup_N(li)=std(yN)/sqrt(numel(yN)); se_pup_H(li)=std(yH)/sqrt(numel(yH));
    [~,pe]=ttest2(xH,xN,'Vartype','unequal');
    [~,pp]=ttest2(yH,yN,'Vartype','unequal');
    fprintf('L%d | EDA NHF=%.4f HF=%.4f p=%.4f | Pupil NHF=%.4f HF=%.4f p=%.4f\n',li,mean(xN),mean(xH),pe,mean(yN),mean(yH),pp);
end

fig=figure('Position',[50 50 1000 420]);
subplot(1,2,1); hold on;
errorbar(levels,mu_eda_N,se_eda_N,'-o','Color',CN,'LineWidth',2,'MarkerFaceColor',CN);
errorbar(levels,mu_eda_H,se_eda_H,'-o','Color',CH,'LineWidth',2,'MarkerFaceColor',CH);
xticks(levels); xticklabels(lnames);
xlabel('Training level'); ylabel('EDA collision response (fraction of resting tonic SCL)');
legend({'NHF','HF'},'Location','best'); title('A5a: EDA collision response by level');

subplot(1,2,2); hold on;
errorbar(levels,mu_pup_N,se_pup_N,'-o','Color',CN,'LineWidth',2,'MarkerFaceColor',CN);
errorbar(levels,mu_pup_H,se_pup_H,'-o','Color',CH,'LineWidth',2,'MarkerFaceColor',CH);
xticks(levels); xticklabels(lnames);
xlabel('Training level'); ylabel('Pupil collision response (fraction of resting pupil diameter)');
legend({'NHF','HF'},'Location','best'); title('A5b: Pupil collision response by level');
saveas(fig,fullfile(fig_dir,'A5_collision_trajectories.png'));

%% save
save(fullfile(cfg.output_root,'cross_modality_results.mat'),'all_results');
fprintf('\nSaved cross_modality_results.mat\n');