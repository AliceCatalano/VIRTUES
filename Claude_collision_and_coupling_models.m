%% Claude_collision_and_coupling_models.m
% Re-tests collision-locked responses and trial-level coupling with subjects as the unit of inference.
% New script based on Gsr_h2_per_level_bins.m, Eye_collBins_groups.m,
% cross_modality_tssv_tssf_eda_pupil.m and run_cross_modal_correlations.m.
% Writes ONLY to <output_root>/Claude_outputs/collision_coupling.
%
% Problems addressed:
%  1. Original per-level t-tests and Levene tests use each collision as an independent observation,
%     although collisions are nested in trials, levels and subjects.
%  2. s16N was excluded from n_collisions as a detection artifact, but its 2,000+ events were still
%     used here, about a third of all NHF collisions. Results are shown with and without s16N.
%  3. Group-specific quartiles compare different impact strengths, so "matched intensity" did not
%     hold. Intensity now enters as a continuous covariate.
%  4. Coupling models had a random intercept only, and no difficulty term although harder levels
%     raise both force and SCL. Here: (1 + predictor_within | subject) plus level.

clear; clc; cfg = config();
out_dir = fullfile(cfg.output_root,'Claude_outputs','collision_coupling'); if ~exist(out_dir,'dir'), mkdir(out_dir); end
CI = load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact'); 
CI = CI.T_impact;
Ec = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T_coll'); Ec = Ec.T_coll;
Yc = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T_coll'); Yc = Yc.T_coll;
CIt = CI(strcmp(CI.phase_type,'training'),:);
keys = {'subject','phase','repetition','collision_idx'};
JE = innerjoin(CIt, Ec(strcmp(Ec.phase_type,'training'),:),'Keys',keys,'RightVariables',{'scr_amp_local_bc'});
JP = innerjoin(CIt, Yc(strcmp(Yc.phase_type,'training'),:),'Keys',keys,'RightVariables',{'pupil_response_norm'});

% Same cleaning as the original: hard SCR bounds, then a log with offset
JE = JE(isfinite(JE.scr_amp_local_bc) & JE.scr_amp_local_bc>=-0.5 & JE.scr_amp_local_bc<=5 & isfinite(JE.peak_accel_g_nidaq) & JE.peak_accel_g_nidaq>0,:);
off = abs(min(JE.scr_amp_local_bc))+0.01;
JE.y = log(JE.scr_amp_local_bc+off);
JP = JP(isfinite(JP.pupil_response_norm) & isfinite(JP.peak_accel_g_nidaq) & JP.peak_accel_g_nidaq>0,:);
JP.y = JP.pupil_response_norm;
fprintf('EDA collisions %d, pupil collisions %d\n',height(JE),height(JP));

rowsL = {}; rowsS = {}; rowsV = {};
sets = {'EDA',JE;'Pupil',JP};
for m = 1:2
    lab = sets{m,1}; J0 = local_prep(sets{m,2});
    for excl = [false true]
        J = J0; 
        if excl, J = J(~strcmp(J.subject,'subject_s16N'),:); end
        J.log_acc = J.log_acc_raw - mean(J.log_acc_raw);
        % --- Group difference at each level ---
        for lv = 1:5
            D = J(J.level==lv,:);
            xN = D.y(~D.haptic); 
            xH = D.y(D.haptic);

            [~,p_naive] = ttest2(xH,xN,'Vartype','unequal');

            sp = sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
            d_naive = (mean(xH)-mean(xN))/sp;
            subjN = groupsummary(D(~D.haptic,:),'subject','mean','y'); 
            subjH = groupsummary(D(D.haptic,:),'subject','mean','y');

            [~,p_subj] = ttest2(subjH.mean_y,subjN.mean_y,'Vartype','unequal');

            p_rank = ranksum(subjH.mean_y,subjN.mean_y);
            mdl = fitlme(D,'y ~ haptic_num + log_acc + (1+log_acc|subject_cat) + (1|trial_id)','FitMethod','REML');
            [b,se,p,df] = local_term(mdl,'haptic_num');
            rowsL(end+1,:) = {lab,excl,lv,numel(xN),numel(xH),d_naive,p_naive,height(subjN),height(subjH),p_subj,p_rank,b,se,df,p}; %#ok<AGROW>
        end
        % --- Does response scale with impact differently by group? ---
        naive = fitlme(J,'y ~ log_acc*haptic_num + (1|subject_cat)','FitMethod','REML');
        [b0,~,p0] = local_term(naive,'log_acc:haptic_num');
        mdl = fitlme(J,'y ~ log_acc*haptic_num + level_cat + (1+log_acc|subject_cat) + (1|subj_level) + (1|trial_id)','FitMethod','REML');
        [b1,se1,p1,df1] = local_term(mdl,'log_acc:haptic_num');
        [bm,sem,pm,dfm] = local_term(mdl,'log_acc');
        rowsS(end+1,:) = {lab,excl,height(J),b0,p0,b1,se1,df1,p1,bm,sem,dfm,pm}; %#ok<AGROW>
        % --- Variability, one SD per subject per level ---
        for lv = 1:5
            D = J(J.level==lv,:);
            G = groupsummary(D,{'subject','haptic'},{'std'},'y'); G = G(G.GroupCount>=5,:);
            xN = D.y(~D.haptic); xH = D.y(D.haptic);
            sN = G.std_y(~G.haptic); sH = G.std_y(G.haptic);
            rowsV(end+1,:) = {lab,excl,lv,numel(sN),numel(sH),std(xN),std(xH),vartestn([xN;xH],[zeros(size(xN));ones(size(xH))],'TestType','BrownForsythe','Display','off'),median(sN),median(sH),ranksum(sH,sN)}; %#ok<AGROW>
        end
        fprintf('%s excl=%d done\n',lab,excl);
    end
end
TL = cell2table(rowsL,'VariableNames',{'signal','s16N_excluded','level','n_coll_N','n_coll_H','d_collision_level','p_collision_level','n_subj_N','n_subj_H','p_subject_welch','p_subject_rank','beta_model','se_model','df_model','p_model'});
TS = cell2table(rowsS,'VariableNames',{'signal','s16N_excluded','n_coll','beta_intercept_only','p_intercept_only','beta_robust','se_robust','df_robust','p_robust','main_slope','main_se','main_df','main_p'});
TV = cell2table(rowsV,'VariableNames',{'signal','s16N_excluded','level','n_subj_N','n_subj_H','sd_pooled_N','sd_pooled_H','p_levene_collision','median_subjSD_N','median_subjSD_H','p_subject_rank'});
TL.p_fdr_model = local_fdr_by(TL.p_model,TL.signal,TL.s16N_excluded);
TL.p_fdr_collision = local_fdr_by(TL.p_collision_level,TL.signal,TL.s16N_excluded);
TV.p_fdr_subject = local_fdr_by(TV.p_subject_rank,TV.signal,TV.s16N_excluded);
writetable(TL,fullfile(out_dir,'collision_group_by_level.csv'));
writetable(TS,fullfile(out_dir,'collision_intensity_slope.csv'));
writetable(TV,fullfile(out_dir,'collision_variability.csv'));

%% Intensity distribution by group, with subject as the unit
D = CIt(isfinite(CIt.peak_accel_g_nidaq) & CIt.peak_accel_g_nidaq>0,:);
rowsI = {};
for excl = [false true]
    E2 = D; 
    if excl, E2 = E2(~strcmp(E2.subject,'subject_s16N'),:); end
    [~,pks] = kstest2(E2.peak_accel_g_nidaq(~E2.haptic),E2.peak_accel_g_nidaq(E2.haptic));
    G = groupsummary(E2,{'subject','haptic'},'median','peak_accel_g_nidaq');
    pr = ranksum(G.median_peak_accel_g_nidaq(G.haptic),G.median_peak_accel_g_nidaq(~G.haptic));
    rowsI(end+1,:) = {excl,median(E2.peak_accel_g_nidaq(~E2.haptic)),median(E2.peak_accel_g_nidaq(E2.haptic)),pks,median(G.median_peak_accel_g_nidaq(~G.haptic)),median(G.median_peak_accel_g_nidaq(G.haptic)),pr}; %#ok<AGROW>
end
TI = cell2table(rowsI,'VariableNames',{'s16N_excluded','median_g_N','median_g_H','p_ks_collision','median_subject_g_N','median_subject_g_H','p_subject_rank'});
writetable(TI,fullfile(out_dir,'collision_intensity_distribution.csv'));

%% Trial-level coupling
EDA = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); EDA = EDA.T; EDA = EDA(strcmp(EDA.phase_type,'training'),:);
EYE = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T'); EYE = EYE.T; EYE = EYE(strcmp(EYE.phase_type,'training'),:);
PF  = load(fullfile(cfg.output_root,'perf_features.mat'),'T'); PF = PF.T; PF = PF(strcmp(PF.phase_type,'training'),:);
FV  = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); FV = FV.T; FV = FV(strcmp(FV.phase_type,'training'),:);
FV.tssf(FV.tssf<=0)=NaN; FV.tssv(FV.tssv<=0)=NaN; FV.log_tssf=log(FV.tssf); FV.log_tssv=log(FV.tssv);
K = {'subject','level','repetition'};
PF2 = PF(:,[K {'duration_s','n_collisions'}]);
PF2.Properties.VariableNames{'n_collisions'} = 'coll_count';
PF2.Properties.VariableNames{'duration_s'} = 'perf_time';
A = innerjoin(EDA,PF2,'Keys',K,'RightVariables',{'perf_time','coll_count'});
EY2 = removevars(EYE,intersect(EYE.Properties.VariableNames,{'n_collisions'}));
B = innerjoin(EY2,PF2,'Keys',K,'RightVariables',{'perf_time','coll_count'});
vfile = fullfile(cfg.output_root,'Claude_outputs','eye','eye_features_claude.mat');
extra = {};
if isfile(vfile)
    Vt = load(vfile,'T'); Vt = Vt.T; Vt = Vt(strcmp(Vt.phase_type,'training'),:);
    Vt.saccade_rate_new = Vt.saccade_rate; Vt.fixation_rate_new = Vt.fixation_rate; Vt.entropy_fixed = Vt.gaze_entropy_fixed;
    B = innerjoin(B,Vt,'Keys',K,'RightVariables',{'saccade_rate_new','fixation_rate_new','entropy_fixed'});
    extra = {B,'saccade_rate_new','perf_time','Saccade rate (corrected) -> time'; B,'fixation_rate_new','perf_time','Fixation rate (corrected) -> time'; B,'entropy_fixed','perf_time','Fixed-grid entropy -> time'; B,'entropy_fixed','coll_count','Fixed-grid entropy -> collisions'};
end
C2 = innerjoin(FV,EDA(:,[K {'scl_mean_bc'}]),'Keys',K);
C2 = innerjoin(C2,PF2,'Keys',K,'RightVariables',{'coll_count'});
pairs = [{A,'scl_mean_bc','perf_time','SCL -> time'; A,'scr_mean_amp_bc','perf_time','SCR amplitude -> time'; A,'scl_mean_bc','coll_count','SCL -> collisions'; ...
          B,'pupil_mean_norm','perf_time','Pupil -> time'; B,'gaze_entropy','perf_time','Entropy -> time'; B,'gaze_entropy','coll_count','Entropy -> collisions'; ...
          C2,'log_tssv','scl_mean_bc','log TSSV -> SCL'; C2,'log_tssf','scl_mean_bc','log TSSF -> SCL'}; extra];
rowsC = {};
for i = 1:size(pairs,1)
    T = pairs{i,1}; pr = pairs{i,2}; oc = pairs{i,3};
    T = T(isfinite(T.(pr)) & isfinite(T.(oc)),:);
    if strcmp(oc,'coll_count') , T = T(~strcmp(T.subject,'subject_s16N'),:); end
    T.subject_cat = categorical(T.subject); T.level_cat = categorical(T.level);
    T.haptic_num = double(cellfun(@(s) s(end)=='H',T.subject));
    [gid,~] = findgroups(T.subject); mb = splitapply(@mean,T.(pr),gid); T.pb = mb(gid); T.pw = T.(pr)-T.pb;
    sd_w = std(T.pw); T.pz = T.pw/sd_w; T.pb_z = (T.pb-mean(T.pb))/sd_w; T.y = T.(oc);
    m0 = fitlme(T,'y ~ pz*haptic_num + pb_z*haptic_num + (1|subject_cat)','FitMethod','REML');
    m1 = fitlme(T,'y ~ pz*haptic_num + pb_z*haptic_num + (1+pz|subject_cat)','FitMethod','REML');
    m2 = fitlme(T,'y ~ pz*haptic_num + pb_z*haptic_num + level_cat*haptic_num + (1+pz|subject_cat)','FitMethod','REML');
    [b0,~,p0] = local_term(m0,'pz',false); [~,~,px0] = local_term(m0,'pz:haptic_num',false);
    [b1,~,p1] = local_term(m1,'pz'); [~,~,px1] = local_term(m1,'pz:haptic_num');
    [b2,se2,p2,df2] = local_term(m2,'pz'); [bx2,sex2,px2] = local_term(m2,'pz:haptic_num'); [bb2,~,pb2] = local_term(m2,'pb_z');
    rowsC(end+1,:) = {pairs{i,4},height(T),numel(unique(T.subject)),sd_w,b0,p0,px0,b1,p1,px1,b2,se2,df2,p2,bx2,sex2,px2,bb2,pb2}; %#ok<AGROW>
    fprintf('coupling %s done\n',pairs{i,4});
end
TC = cell2table(rowsC,'VariableNames',{'pair','n_obs','n_subj','within_sd','b_orig_form','p_orig_form','px_orig_form','b_slope','p_slope','px_slope','b_slope_level','se_slope_level','df','p_slope_level','bx_slope_level','sex_slope_level','px_slope_level','b_between','p_between'});
TC.p_fdr = local_bh(TC.p_slope_level); TC.px_fdr = local_bh(TC.px_slope_level);
writetable(TC,fullfile(out_dir,'coupling_orig_vs_robust.csv'));

%% Force coupling robustness, sequential covariates, after the s16N exclusion
rowsR = {};
for pr = {'log_tssf','log_tssv'}
    T = C2(isfinite(C2.(pr{1})) & isfinite(C2.scl_mean_bc),:);
    T.subject_cat = categorical(T.subject); T.level_cat = categorical(T.level);
    T.haptic_num = double(cellfun(@(s) s(end)=='H',T.subject));
    [gid,~] = findgroups(T.subject); mb = splitapply(@mean,T.(pr{1}),gid); sb = splitapply(@(v) std(v)+1e-12,T.(pr{1}),gid);
    T.z = (T.(pr{1})-mb(gid))./sb(gid);
    forms = {'base (original form)','scl_mean_bc ~ z*haptic_num + (1|subject_cat)'; ...
             '+ collision count','scl_mean_bc ~ z*haptic_num + coll_count + (1|subject_cat)'; ...
             '+ level','scl_mean_bc ~ z*haptic_num + coll_count + level_cat + (1|subject_cat)'; ...
             '+ random slope','scl_mean_bc ~ z*haptic_num + coll_count + level_cat + (1+z|subject_cat)'; ...
             '+ Haptic x Level','scl_mean_bc ~ z*haptic_num + coll_count + level_cat*haptic_num + (1+z|subject_cat)'};
    for f = 1:size(forms,1)
        M = T; if f>=2, M = T(isfinite(T.coll_count),:); end
        m = fitlme(M,forms{f,2},'FitMethod','REML');
        [b,~,p] = local_term(m,'z'); [bx,~,px,dfx] = local_term(m,'z:haptic_num');
        rowsR(end+1,:) = {pr{1},forms{f,1},height(M),b,p,bx,dfx,px}; %#ok<AGROW>
    end
end
TR = cell2table(rowsR,'VariableNames',{'predictor','model','n_obs','beta_within','p_within','beta_interaction','df_interaction','p_interaction'});
writetable(TR,fullfile(out_dir,'force_coupling_robustness.csv'));
save(fullfile(out_dir,'collision_coupling_results.mat'),'TL','TS','TV','TI','TC','TR');
fprintf('COLLISION_DONE\n');

function J = local_prep(J)
    J.log_acc_raw = log(J.peak_accel_g_nidaq);
    J.haptic = logical(J.haptic);
    J.haptic_num = double(J.haptic);
    J.subject_cat = categorical(J.subject);
    J.level_cat = categorical(J.level);
    J.subj_level = categorical(strcat(string(J.subject),'_',string(J.level)));
    J.trial_id = categorical(strcat(string(J.subject),'_',string(J.phase),'_',string(J.repetition)));
end
function [b,se,p,df] = local_term(m,name,satt)
    if nargin<3, satt = true; end
    if satt
        [~,~,st] = fixedEffects(m,'DFMethod','satterthwaite');
        nm = st.Name; est = st.Estimate; s = st.SE; pv = st.pValue; d = st.DF;
    else
        c = m.Coefficients; nm = cellstr(c.Name); est = double(c.Estimate); s = double(c.SE); pv = double(c.pValue); d = double(c.DF);
    end
    want = sort(strsplit(name,':'));
    ix = cellfun(@(n) isequal(sort(strsplit(n,':')),want), nm);
    if ~any(ix), error('Term %s not found.',name); end
    b = est(ix); se = s(ix); p = pv(ix); df = d(ix);
end
function q = local_bh(p)
    q = nan(size(p)); v = find(isfinite(p)); [ps,ix] = sort(p(v)); m = numel(ps);
    a = ps.*m./(1:m)'; a = min(cummin(a,'reverse'),1); q(v(ix)) = a;
end
function q = local_fdr_by(p,a,b)
    q = nan(size(p)); [g,~] = findgroups(string(a),b);
    for k = unique(g)', q(g==k) = local_bh(p(g==k)); end
end
