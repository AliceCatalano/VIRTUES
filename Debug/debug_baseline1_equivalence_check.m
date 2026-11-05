%% baseline1_equivalence_check.m
clear; clc; cfg = config();
T_eda = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); T_eda=T_eda.T;
T_eye = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T'); T_eye=T_eye.T;
T_fv  = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); T_fv=T_fv.T;

metrics = {
    T_eda, 'scl_mean_bc',               'EDA tonic SCL'
    T_eda, 'scr_freq',                   'EDA SCR frequency'
    T_eda, 'scr_mean_amp_bc',            'EDA phasic amplitude'
    T_eda, 'collision_scr_amp_mean_bc',  'EDA ER-SCR amplitude'
    T_eye, 'pupil_mean_norm',            'Pupil dilation'
    T_eye, 'gaze_entropy',              'Gaze entropy'
    T_eye, 'fixation_rate',             'Fixation rate'
    T_eye, 'fixation_mean_dur',         'Fixation duration'
    T_eye, 'collision_pupil_response_mean','Collision pupil'
    T_fv,  'tssv',                       'TSSV'
    T_fv,  'tssf',                       'TSSF'
};

fprintf('%-35s %8s %8s %8s %8s %8s\n','Metric','NHF_mean','HF_mean','diff','t_p','d');
for mi=1:size(metrics,1)
    Tm=metrics{mi,1}; oc=metrics{mi,2}; lbl=metrics{mi,3};
    Tbl=Tm(strcmp(Tm.phase,'Baseline1')&isfinite(Tm.(oc)),:);
    if isempty(Tbl), continue; end
    subjs=unique(Tbl.subject);
    xa=nan(numel(subjs),1); ih=false(numel(subjs),1);
    for si=1:numel(subjs)
        s=subjs{si};
        xa(si)=mean(Tbl.(oc)(strcmp(Tbl.subject,s)),'omitnan');
        ih(si)=any(Tbl.haptic(strcmp(Tbl.subject,s)));
    end
    xN=xa(~ih&isfinite(xa)); xH=xa(ih&isfinite(xa));
    [~,p]=ttest2(xH,xN,'Vartype','unequal');
    sp=sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
    d=(mean(xH)-mean(xN))/sp;
    flag=''; if p<0.05, flag='*SIGNIFICANT*'; elseif p<0.10, flag='(trend)'; end
    fprintf('%-35s %8.4f %8.4f %8.4f %8.4f %8.4f %s\n',lbl,mean(xN),mean(xH),mean(xH)-mean(xN),p,d,flag);
end
%%
%% tssf_scl_coupling_deconfounded.m
clear; clc; cfg = config();
T_fv  = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); T_fv=T_fv.T;
T_eda = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); T_eda=T_eda.T;
T_perf= load(fullfile(cfg.output_root,'perf_features.mat'),'T'); T_perf=T_perf.T;

T_fv_tr  = T_fv(strcmp(T_fv.phase_type,'training'),:);
T_eda_tr = T_eda(strcmp(T_eda.phase_type,'training'),:);
T_perf_tr= T_perf(strcmp(T_perf.phase_type,'training'),:);

T_joined = innerjoin(T_fv_tr, T_eda_tr,'Keys',{'subject','level','repetition'},'RightVariables',{'scl_mean_bc','haptic'});
T_joined2= innerjoin(T_joined, T_perf_tr,'Keys',{'subject','level','repetition'},'RightVariables',{'n_collisions'});
T_joined2.haptic = cellfun(@(s) strcmp(s(end),'H'), T_joined2.subject);

T_joined2.tssf(T_joined2.tssf<=0)=NaN;
T_joined2.tssf_log=log(T_joined2.tssf);

% Compute within-subject z-scores for tssf and n_collisions
subjs=unique(T_joined2.subject);
T_joined2.tssf_z=nan(height(T_joined2),1);
T_joined2.ncoll_z=nan(height(T_joined2),1);
for si=1:numel(subjs)
    s=subjs{si}; idx=strcmp(T_joined2.subject,s);
    v=T_joined2.tssf_log(idx);
    T_joined2.tssf_z(idx)=(v-mean(v,'omitnan'))./(std(v,'omitnan')+1e-12);
    v2=T_joined2.n_collisions(idx);
    T_joined2.ncoll_z(idx)=(v2-mean(v2,'omitnan'))./(std(v2,'omitnan')+1e-12);
end

T_joined2.haptic_cat=categorical(T_joined2.haptic,[false true],{'NHF','HF'});
T_joined2.subject_cat=categorical(T_joined2.subject);
T_joined2.level_cat=categorical(T_joined2.level);
T_joined2=T_joined2(isfinite(T_joined2.tssf_z)&isfinite(T_joined2.scl_mean_bc)&isfinite(T_joined2.ncoll_z),:);

% Model 1: original (no covariates)
lme1=fitlme(T_joined2,'scl_mean_bc ~ tssf_z*haptic_cat + (1|subject_cat)','FitMethod','REML');
% Model 2: controlling for collision count
lme2=fitlme(T_joined2,'scl_mean_bc ~ tssf_z*haptic_cat + ncoll_z + (1|subject_cat)','FitMethod','REML');
% Model 3: controlling for collision count AND difficulty level
lme3=fitlme(T_joined2,'scl_mean_bc ~ tssf_z*haptic_cat + ncoll_z + level_cat + (1|subject_cat)','FitMethod','REML');

fprintf('\n=== Model 1: TSSF -> SCL (no covariates) ===\n');
disp(lme1.Coefficients(:,{'Name','Estimate','SE','tStat','pValue'}));
fprintf('\n=== Model 2: TSSF -> SCL controlling for collision count ===\n');
disp(lme2.Coefficients(:,{'Name','Estimate','SE','tStat','pValue'}));
fprintf('\n=== Model 3: TSSF -> SCL controlling for collisions AND level ===\n');
disp(lme3.Coefficients(:,{'Name','Estimate','SE','tStat','pValue'}));

% Extract the interaction term p-value from all three models
for k=1:3
    m=eval(sprintf('lme%d',k));
    fe=m.Coefficients;
    int_row=cellfun(@(n) isequal(sort(strsplit(n,':')),sort({'tssf_z','haptic_cat_HF'})),fe.Name);
    fprintf('Model %d: TSSF*Haptic interaction beta=%.4f p=%.4f\n',k,fe.Estimate(int_row),fe.pValue(int_row));
end

%%
%% check_s41H_influence.m
clear; clc; cfg = config();
T = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); T=T.T;
T_tr = T(strcmp(T.phase_type,'training'),:);

fprintf('=== Influence of s41H on Level 5 rep1 spike ===\n');
for oc = {'scr_mean_amp_bc','collision_scr_amp_mean_bc'}
    oc = oc{1};
    fprintf('\n--- %s ---\n',oc);
    for lv = 1:5
        Tl = T_tr(T_tr.level==lv & T_tr.haptic==1 & isfinite(T_tr.(oc)),:);
        subj_HF = unique(Tl.subject);
        vH1_all = nan(numel(subj_HF),1);
        vH1_excl = nan(numel(subj_HF),1);
        for si=1:numel(subj_HF)
            s=subj_HF{si};
            v1=Tl.(oc)(strcmp(Tl.subject,s)&Tl.repetition==1);
            if ~isempty(v1), vH1_all(si)=mean(v1,'omitnan'); end
            if ~strcmp(s,'subject_s41H')&&~isempty(v1)
                vH1_excl(si)=mean(v1,'omitnan');
            end
        end
        vH2p = nan(numel(subj_HF),1);
        for si=1:numel(subj_HF)
            s=subj_HF{si};
            v2=Tl.(oc)(strcmp(Tl.subject,s)&Tl.repetition>1);
            if ~isempty(v2), vH2p(si)=mean(v2,'omitnan'); end
        end
        keep=isfinite(vH1_all)&isfinite(vH2p);
        keep_excl=isfinite(vH1_excl)&isfinite(vH2p);
        if sum(keep)>=3, [~,p_all]=ttest(vH1_all(keep),vH2p(keep));
        else, p_all=NaN; end
        if sum(keep_excl)>=3, [~,p_excl]=ttest(vH1_excl(keep_excl),vH2p(keep_excl));
        else, p_excl=NaN; end
        fprintf('L%d: rep1 mean=%.4f (excl s41H: %.4f) | rep2-10 mean=%.4f | p_all=%.3f p_excl=%.3f\n',...
            lv,...
            mean(vH1_all(isfinite(vH1_all)),'omitnan'),...
            mean(vH1_excl(isfinite(vH1_excl)),'omitnan'),...
            mean(vH2p(isfinite(vH2p)),'omitnan'),...
            p_all, p_excl);
    end
end

%% check_s41H_trace.m
clear; clc; close all; cfg = config();
subj = 'subject_s41H'; phase = 'level_L5'; acq = 'rep_01';
acq_dir = fullfile(cfg.data_root, subj, phase, acq);
ev_path = fullfile(acq_dir, 'events.mat');
gsr_path = fullfile(acq_dir, 'gsr.mat');
if ~isfile(gsr_path), error('No GSR file found'); end
[t_start, t_end] = safe_trial_window(ev_path);
proc = gsr_preprocess(gsr_path, cfg, t_start, t_end);
figure('Position',[50 50 1000 500]);
subplot(2,1,1);
plot(proc.time, proc.tonic, 'b-', 'LineWidth', 1.5);
xlabel('Time (s)'); ylabel('Tonic SCL (\muS)');
title('s41H Level 5 Rep 1 - Tonic'); grid on;
subplot(2,1,2);
plot(proc.time, proc.phasic, 'r-', 'LineWidth', 1.5);
xlabel('Time (s)'); ylabel('Phasic SCR');
title('s41H Level 5 Rep 1 - Phasic'); grid on;
%% threeway_sensitivity_excl_s41H.m
clear; clc; cfg = config();
T_eda = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); T_eda=T_eda.T;
T_excl = T_eda(~strcmp(T_eda.subject,'subject_s41H'),:);

outcomes_3way = {'scr_mean_amp_bc','collision_scr_amp_mean_bc'};
fprintf('=== Three-way LMM sensitivity: excluding s41H ===\n');
for oi = 1:2
    oc = outcomes_3way{oi};
    r = gsr_training_lmm_3way(T_excl, oc);
    fprintf('\n%s: 3-way omnibus F=%.3f p=%.4f\n', oc, r.three_way_omnibus_F, r.three_way_omnibus_p);
    fprintf('Rep slopes at L5:\n');
    rs = r.repetition_slopes;
    for j=1:height(rs)
        if strcmp(rs.level{j},'5')
            fprintf('  L5 %s: beta=%.4f SE=%.4f p=%.4f\n', rs.group{j}, rs.beta(j), rs.se(j), rs.p(j));
        end
    end
end