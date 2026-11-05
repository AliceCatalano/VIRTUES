%% Claude_robust_lmms.m
% Refits the primary training, three-way and transfer models with random effects that match the
% tested factor, and with Satterthwaite degrees of freedom. New script; replaces nothing.
% Writes ONLY to <output_root>/Claude_outputs/robust_lmm.
%
% WHY: Barr et al. (2013). A between-subject factor crossed with a within-subject factor needs a
% by-subject random slope for that within-subject factor, or the test is anti-conservative.
%   Transfer, original:  Y ~ phase*haptic + level + (1|subject)
%   Transfer, here:      Y ~ phase*haptic + level + (1+phase|subject)     (elastic task)
%                        Peg Transfer has one row per phase per subject, so a phase slope cannot be
%                        separated from the residual; (1|subject) is already correct there.
%   Training, original:  Y ~ haptic*level + haptic*repetition + (1+repetition|subject)
%   Training, here:      the same fixed effects + (1+repetition|subject) + (1|subject:level)
% (1|subject:level) lets each subject have their own level offsets, under a compound-symmetric
% covariance. It is the less demanding form of a full (level|subject) term.
%
% ORIGINAL df = residual (about 2,000); here = Satterthwaite. Both are reported so that each
% change can be attributed. fitglme has no Satterthwaite option, so collisions stay residual-df.

clear; clc; cfg = config();
out_dir = fullfile(cfg.output_root,'Claude_outputs','robust_lmm'); if ~exist(out_dir,'dir'), mkdir(out_dir); end

E  = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); E = E.T;
Y  = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T'); Y = Y.T;
P  = load(fullfile(cfg.output_root,'perf_features.mat'),'T');   P = P.T;
F  = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); F = F.T;
F.tssf(F.tssf<=0)=NaN; F.tssv(F.tssv<=0)=NaN; F.tssf_log=log(F.tssf); F.tssv_log=log(F.tssv);

jobs = {'EDA','scl_mean_bc',E,'scl_mean'; 'EDA','scr_freq',E,'scr_freq'; 'EDA','scr_mean_amp_bc',E,'scr_mean_amp_bc'; ...
        'EDA','collision_scr_amp_mean_bc',E,''; ...
        'Eye','pupil_mean_norm',Y,'pupil_mean_norm'; 'Eye','gaze_entropy',Y,'gaze_entropy'; 'Eye','fixation_rate',Y,'fixation_rate'; ...
        'Eye','fixation_mean_dur',Y,'fixation_mean_dur'; 'Eye','collision_pupil_response_mean',Y,'collision_pupil_response_mean'; ...
        'Performance','duration_s',P,'duration_s'; 'Performance','n_collisions',P,'n_collisions'; ...
        'Mechanical','tssf_log',F,'tssf_log'; 'Mechanical','tssv_log',F,'tssv_log'};

%% Training models
rows = {};
for j = 1:size(jobs,1)
    fam = jobs{j,1}; oc = jobs{j,2}; T = jobs{j,3};
    D = T(strcmp(T.phase_type,'training') & isfinite(T.(oc)),:);
    D = local_prep(D);
    fe = sprintf('%s ~ haptic_num*level_cat + haptic_num*repetition',oc);
    if strcmp(oc,'n_collisions')
        m0 = fitglme(D,[fe ' + (1+repetition|subject_cat)'],'Distribution','poisson','FitMethod','Laplace');
        m1 = fitglme(D,[fe ' + (1+repetition|subject_cat) + (1|subj_level)'],'Distribution','poisson','FitMethod','Laplace');
        s0 = local_stats(m0,false); s1 = local_stats(m1,false); s0b = s0;
    else
        m0 = fitlme(D,[fe ' + (1+repetition|subject_cat)'],'FitMethod','REML');
        m1 = fitlme(D,[fe ' + (1+repetition|subject_cat) + (1|subj_level)'],'FitMethod','REML');
        s0 = local_stats(m0,false); s0b = local_stats(m0,true); s1 = local_stats(m1,true);
    end
    terms = [{'repetition:haptic_num'}, arrayfun(@(l) sprintf('level_cat_%d:haptic_num',l),2:5,'UniformOutput',false)];
    for t = 1:numel(terms)
        [b0,se0,p0] = local_term(s0,terms{t}); [~,~,p0b] = local_term(s0b,terms{t}); [b1,se1,p1,df1] = local_term(s1,terms{t});
        rows(end+1,:) = {fam,oc,terms{t},height(D),b0,se0,p0,p0b,b1,se1,df1,p1}; %#ok<AGROW>
    end
    fprintf('training %-30s done (subject:level SD %.3g)\n',oc,local_re_sd(m1));
end
TR = cell2table(rows,'VariableNames',{'family','outcome','term','n_obs','beta_orig','se_orig','p_orig','p_orig_satt','beta_robust','se_robust','df_robust','p_robust'});
% Same FDR structure as the originals: Haptic x Repetition per family, and Haptic x Level per family.
TR.p_fdr_orig = nan(height(TR),1); TR.p_fdr_robust = nan(height(TR),1);
isrep = strcmp(TR.term,'repetition:haptic_num');
for f = unique(TR.family)'
    for sel = {isrep, ~isrep}
        ix = strcmp(TR.family,f{1}) & sel{1};
        TR.p_fdr_orig(ix) = local_bh(TR.p_orig(ix)); TR.p_fdr_robust(ix) = local_bh(TR.p_robust(ix));
    end
end
writetable(TR,fullfile(out_dir,'training_haptic_terms_orig_vs_robust.csv'));

%% Three-way models for the outcomes reported as significant, with and without s41H
rows3 = {};
for oc = {'scr_mean_amp_bc','collision_scr_amp_mean_bc'}
    for excl = [false true]
        D = E(strcmp(E.phase_type,'training') & isfinite(E.(oc{1})),:);
        if excl, D = D(~strcmp(D.subject,'subject_s41H'),:); end
        D = local_prep(D);
        fe = sprintf('%s ~ haptic_num*level_cat*repetition',oc{1});
        m0 = fitlme(D,[fe ' + (1+repetition|subject_cat)'],'FitMethod','REML');
        m1 = fitlme(D,[fe ' + (1+repetition|subject_cat) + (1|subj_level)'],'FitMethod','REML');
        a0 = anova(m0); a1 = anova(m1,'DFMethod','satterthwaite');
        r0 = local_3way(a0); r1 = local_3way(a1);
        rows3(end+1,:) = {oc{1},excl,a0.FStat(r0),a0.pValue(r0),a1.FStat(r1),a1.DF2(r1),a1.pValue(r1)}; %#ok<AGROW>
    end
end
T3 = cell2table(rows3,'VariableNames',{'outcome','s41H_excluded','F_orig','p_orig','F_robust','df2_robust','p_robust'});
writetable(T3,fullfile(out_dir,'threeway_orig_vs_robust.csv'));

%% Transfer models
rowsT = {};
for fam = {{'elastic','baseline','Baseline1','Baseline2'},{'peg','test','Test1','Test2'}}
    fm = fam{1};
    for j = 1:size(jobs,1)
        oc = jobs{j,4}; if isempty(oc), continue; end
        T = jobs{j,3};
        D = T(strcmp(T.phase_type,fm{2}) & ismember(T.phase,{fm{3},fm{4}}) & isfinite(T.(oc)),:);
        D = local_prep(D); D.phase_post = double(strcmp(D.phase,fm{4}));
        if strcmp(fm{1},'elastic')
            fe = sprintf('%s ~ phase_post*haptic_num + level_cat',oc);
            frm1 = [fe ' + (1+phase_post|subject_cat)'];
        else
            fe = sprintf('%s ~ phase_post*haptic_num',oc);
            frm1 = [fe ' + (1|subject_cat)'];
        end
        frm0 = [fe ' + (1|subject_cat)'];
        if strcmp(oc,'n_collisions')
            m0 = fitglme(D,frm0,'Distribution','poisson','FitMethod','Laplace');
            m1 = fitglme(D,frm1,'Distribution','poisson','FitMethod','Laplace');
            s0 = local_stats(m0,false); s1 = local_stats(m1,false);
        else
            m0 = fitlme(D,frm0,'FitMethod','REML'); m1 = fitlme(D,frm1,'FitMethod','REML');
            s0 = local_stats(m0,false); s1 = local_stats(m1,true);
        end
        [b0,se0,p0] = local_term(s0,'phase_post:haptic_num'); [b1,se1,p1,df1] = local_term(s1,'phase_post:haptic_num');
        rowsT(end+1,:) = {fm{1},jobs{j,1},oc,height(D),numel(unique(D.subject)),b0,se0,p0,b1,se1,df1,p1}; %#ok<AGROW>
        fprintf('transfer %s %-30s orig p=%.3g robust p=%.3g\n',fm{1},oc,p0,p1);
    end
end
TT = cell2table(rowsT,'VariableNames',{'task','family','outcome','n_obs','n_subjects','beta_orig','se_orig','p_orig','beta_robust','se_robust','df_robust','p_robust'});
TT.p_fdr_orig = nan(height(TT),1); TT.p_fdr_robust = nan(height(TT),1);
for t = unique(TT.task)'
    for f = unique(TT.family)'
        ix = strcmp(TT.task,t{1}) & strcmp(TT.family,f{1});
        TT.p_fdr_orig(ix) = local_bh(TT.p_orig(ix)); TT.p_fdr_robust(ix) = local_bh(TT.p_robust(ix));
    end
end
writetable(TT,fullfile(out_dir,'transfer_orig_vs_robust.csv'));
save(fullfile(out_dir,'robust_lmm_results.mat'),'TR','T3','TT');
fprintf('ROBUST_DONE\n');

function D = local_prep(D)
    D.subject_cat = categorical(D.subject);
    D.level_cat   = categorical(D.level);
    D.haptic_num  = double(D.haptic);
    if ismember('repetition',D.Properties.VariableNames), D.repetition = double(D.repetition); end
    D.subj_level  = categorical(strcat(string(D.subject),'_',string(D.level)));
end
function s = local_stats(m,satt)
    if satt
        [~,~,st] = fixedEffects(m,'DFMethod','satterthwaite');
        s = table(st.Name,st.Estimate,st.SE,st.DF,st.pValue,'VariableNames',{'Name','Estimate','SE','DF','pValue'});
    else
        c = m.Coefficients;
        s = table(cellstr(c.Name),double(c.Estimate),double(c.SE),double(c.DF),double(c.pValue),'VariableNames',{'Name','Estimate','SE','DF','pValue'});
    end
end
function [b,se,p,df] = local_term(s,name)
    want = sort(strsplit(name,':'));
    ix = cellfun(@(n) isequal(sort(strsplit(n,':')),want), s.Name);
    if ~any(ix), error('Term %s not found.',name); end
    b = s.Estimate(ix); se = s.SE(ix); p = s.pValue(ix); df = s.DF(ix);
end
function r = local_3way(a)
    names = cellstr(a.Term);
    r = find(cellfun(@(n) numel(strsplit(n,':'))==3, names),1);
end
function sd = local_re_sd(m)
    try
        psi = covarianceParameters(m); sd = sqrt(psi{end}(1,1));
    catch
        sd = NaN;
    end
end
function q = local_bh(p)
    q = nan(size(p)); v = find(isfinite(p)); [ps,ix] = sort(p(v)); m = numel(ps);
    a = ps.*m./(1:m)'; a = min(cummin(a,'reverse'),1); q(v(ix)) = a;
end
