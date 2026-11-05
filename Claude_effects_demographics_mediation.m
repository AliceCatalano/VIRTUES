%% Claude_effects_demographics_mediation.m
% Three linked analyses on the corrected data. New script; replaces nothing.
% Writes ONLY to <output_root>/Claude_outputs/effects.
%  A. Group effects with 95% and 90% CIs, Hedges g, JZS Bayes factors, and the detectable effect size.
%  B. Demographic sensitivity check on the corrected models (cf. run_covariate_sensitivity_check.m).
%  C. Mediation on subject means, and gaze-arousal coupling (cf. run_mediation_analysis.m).
% Run after Claude_eye_extract_features_v2.m.

clear; clc; cfg = config(); rng(20261105);
out_dir = fullfile(cfg.output_root,'Claude_outputs','effects'); if ~exist(out_dir,'dir'), mkdir(out_dir); end
E = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); E = E.T;
Y = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T'); Y = Y.T;
P = load(fullfile(cfg.output_root,'perf_features.mat'),'T');   P = P.T;
F = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); F = F.T;
V = load(fullfile(cfg.output_root,'Claude_outputs','eye','eye_features_claude.mat'),'T'); V = V.T;
F.tssf(F.tssf<=0)=NaN; F.tssv(F.tssv<=0)=NaN; F.log_tssf=log(F.tssf); F.log_tssv=log(F.tssv);
jobs = {'Performance','duration_s',P; 'Performance','n_collisions',P; 'Performance','log_tssf',F; 'Performance','log_tssv',F; ...
        'EDA','scl_mean_bc',E; 'EDA','scr_freq',E; 'EDA','scr_mean_amp_bc',E; ...
        'Eye','pupil_mean_norm',Y; 'Eye','gaze_entropy',Y; 'Eye','gaze_entropy_fixed',V; 'Eye','fixation_rate',V; 'Eye','saccade_rate',V};

%% A. Effect sizes
rows = {};
for j = 1:size(jobs,1)
    oc = jobs{j,2}; T = jobs{j,3};
    % Elastic-task and Peg Transfer change
    [d,h] = local_change(T,oc,'Baseline1','Baseline2'); rows(end+1,:) = [{jobs{j,1},oc,'Elastic change (post - pre)'}, local_effect(d,h)]; %#ok<AGROW>
    [d,h] = local_change(T,oc,'Test1','Test2');         rows(end+1,:) = [{jobs{j,1},oc,'Peg Transfer change (post - pre)'}, local_effect(d,h)]; %#ok<AGROW>
    % Learning rate: each subject's slope per repetition, with level means removed
    [d,h] = local_slope(T,oc); rows(end+1,:) = [{jobs{j,1},oc,'Learning rate (per repetition)'}, local_effect(d,h)]; %#ok<AGROW>
    % Change with level: L5 - L1 and L4 - L1
    for lv = [4 5]
        [d,h] = local_level(T,oc,lv); rows(end+1,:) = [{jobs{j,1},oc,sprintf('Change L%d - L1',lv)}, local_effect(d,h)]; %#ok<AGROW>
    end
end
TA = cell2table(rows,'VariableNames',{'family','outcome','comparison','n_N','n_H','mean_N','mean_H','diff_H_minus_N','ci95_lo','ci95_hi','ci90_lo','ci90_hi','p_welch','hedges_g','g_ci95_lo','g_ci95_hi','BF01','detectable_d_80pct'});
writetable(TA,fullfile(out_dir,'group_effects_with_ci.csv'));
fprintf('A_DONE\n');

%% Group balance
D = readtable(fullfile(cfg.data_root,'demographics.csv'),'TextType','string');
keep = ismember(D.subject,string(cfg.all_subjects)); fprintf('Demographics: %d rows, %d study subjects, missing %s\n',height(D),sum(keep),strjoin(setdiff(string(cfg.all_subjects),D.subject),' '));
D = D(keep,:); D.h = endsWith(D.subject,'H');
rowsB = {};
for v = {'age','gaming_experience','robotic_experience','handedness_LQ'}
    x = D.(v{1}); rowsB(end+1,:) = {v{1},mean(x(~D.h),'omitnan'),std(x(~D.h),'omitnan'),mean(x(D.h),'omitnan'),std(x(D.h),'omitnan'),ranksum(x(D.h),x(~D.h))}; %#ok<AGROW>
end
TB = cell2table(rowsB,'VariableNames',{'variable','mean_N','sd_N','mean_H','sd_H','p_rank'});
writetable(TB,fullfile(out_dir,'group_balance.csv'));
fprintf('Gender N: %s; H: %s\n',strjoin(string(groupcounts(categorical(D.gender(~D.h))))','/'),strjoin(string(groupcounts(categorical(D.gender(D.h))))','/'));

%% B. Demographic sensitivity on corrected models
D.gender_c = categorical(D.gender); D.hand_right = double(D.handedness=="Right");
Dj = D(:,{'subject','age','gender_c','hand_right','gaming_experience','robotic_experience'});
cov = ' + age + gender_c + hand_right + gaming_experience + robotic_experience';
rowsS = {};
for j = 1:size(jobs,1)
    oc = jobs{j,2}; if strcmp(oc,'saccade_rate')||strcmp(oc,'gaze_entropy_fixed')||strcmp(oc,'scr_mean_amp_bc'), continue; end
    T = jobs{j,3}; A0 = T(strcmp(T.phase_type,'training')&isfinite(T.(oc)),:);
    if iscell(A0.subject), A0.subject = string(A0.subject); end
    A0 = innerjoin(A0,Dj,'Keys','subject'); A0 = local_prep(A0);
    fe = sprintf('%s ~ haptic_num*level_cat + haptic_num*repetition',oc); re = ' + (1+repetition|subject_cat) + (1|subj_level)';
    isP = strcmp(oc,'n_collisions');
    m0 = local_fit(A0,[fe re],isP); m1 = local_fit(A0,[fe cov re],isP);
    terms = {'repetition:haptic_num','level_cat_4:haptic_num','level_cat_5:haptic_num'};
    for t = 1:numel(terms)
        [b0,se0,p0] = local_term(m0,terms{t},~isP); [b1,se1,p1] = local_term(m1,terms{t},~isP);
        rowsS(end+1,:) = {oc,terms{t},b0,se0,p0,b1,se1,p1,abs(b1-b0)/se0}; %#ok<AGROW>
    end
    B = T(strcmp(T.phase_type,'baseline')&ismember(T.phase,{'Baseline1','Baseline2'})&isfinite(T.(oc)),:);
    if iscell(B.subject), B.subject = string(B.subject); end
    B = innerjoin(B,Dj,'Keys','subject'); B = local_prep(B); B.phase_post = double(strcmp(B.phase,'Baseline2'));
    fe = sprintf('%s ~ phase_post*haptic_num + level_cat',oc); re = ' + (1+phase_post|subject_cat)';
    m0 = local_fit(B,[fe re],isP); m1 = local_fit(B,[fe cov re],isP);
    [b0,se0,p0] = local_term(m0,'phase_post:haptic_num',~isP); [b1,se1,p1] = local_term(m1,'phase_post:haptic_num',~isP);
    rowsS(end+1,:) = {oc,'phase_post:haptic_num (elastic)',b0,se0,p0,b1,se1,p1,abs(b1-b0)/se0}; %#ok<AGROW>
    fprintf('covariates %s done\n',oc);
end
TS = cell2table(rowsS,'VariableNames',{'outcome','term','beta_unadjusted','se_unadjusted','p_unadjusted','beta_adjusted','se_adjusted','p_adjusted','shift_in_SE'});
writetable(TS,fullfile(out_dir,'demographic_sensitivity.csv'));

%% C. Mediation on subject means (training), and gaze-arousal coupling
PT = P(strcmp(P.phase_type,'training'),:);
meds = {'Tonic SCL',E,'scl_mean_bc'; 'SCR frequency',E,'scr_freq'; 'Pupil',Y,'pupil_mean_norm'; 'Entropy, per-trial grid',Y,'gaze_entropy'; 'Entropy, fixed grid',V,'gaze_entropy_fixed'; 'Fixation rate, corrected',V,'fixation_rate'};
outs = {'duration_s','n_collisions'};
rowsM = {};
for m = 1:size(meds,1)
    [um,xm] = local_submean(meds{m,2},meds{m,3});
    for o = 1:2
        [uy,yy] = local_submean(PT,outs{o});
        [u,ia,ib] = intersect(um,uy);
        x = xm(ia); y = yy(ib); h = double(endsWith(u,'H')); keep = isfinite(x)&isfinite(y); x = x(keep); y = y(keep); h = h(keep);
        [a,sa,pa] = local_ols(x,h,1);
        [b,sb,pb,c] = local_ols(y,[x h],1);
        mc = normrnd(a,sa,20000,1).*normrnd(b,sb,20000,1);
        n = numel(y); bs = nan(5000,1);
        for k = 1:5000
            idx = randi(n,n,1); bs(k) = local_ols(x(idx),h(idx),1)*local_ols(y(idx),[x(idx) h(idx)],1);
        end
        rowsM(end+1,:) = {meds{m,1},outs{o},n,a,pa,b,pb,c,a*b,prctile(mc,2.5),prctile(mc,97.5),prctile(bs,2.5),prctile(bs,97.5)}; %#ok<AGROW>
    end
end
TM = cell2table(rowsM,'VariableNames',{'mediator','outcome','n','path_a','p_a','path_b','p_b','direct','indirect','mc_lo','mc_hi','boot_lo','boot_hi'});
writetable(TM,fullfile(out_dir,'mediation_subject_level.csv'));

K = {'subject','level','repetition'};
ET = E(strcmp(E.phase_type,'training'),[K {'scl_mean_bc'}]);
VT = V(strcmp(V.phase_type,'training'),[K {'gaze_entropy_orig','gaze_entropy_fixed','fixation_rate'}]);
J = innerjoin(VT,ET,'Keys',K); J = J(isfinite(J.scl_mean_bc),:);
rowsH = {};
for pr = {'gaze_entropy_orig','gaze_entropy_fixed','fixation_rate'}
    T = J(isfinite(J.(pr{1})),:); T.subject_cat = categorical(T.subject); T.level_cat = categorical(T.level); T.haptic_num = double(endsWith(string(T.subject),'H'));
    [g,~] = findgroups(string(T.subject)); mb = splitapply(@mean,T.(pr{1}),g); T.pw = T.(pr{1})-mb(g); sdw = std(T.pw); T.pz = T.pw/sdw; T.pb = (mb(g)-mean(mb(g)))/sdw;
    M = fitlme(T,'scl_mean_bc ~ pz*haptic_num + pb*haptic_num + level_cat*haptic_num + (1+pz|subject_cat)','FitMethod','REML');
    [b,se,p,df] = local_term(M,'pz',true); [bx,sex,px,dfx] = local_term(M,'pz:haptic_num',true);
    rowsH(end+1,:) = {pr{1},height(T),b,se,df,p,bx,sex,dfx,px}; %#ok<AGROW>
end
TH = cell2table(rowsH,'VariableNames',{'predictor','n_obs','beta_per_SD','se','df','p','beta_group_diff','se_diff','df_diff','p_diff'});
writetable(TH,fullfile(out_dir,'gaze_arousal_coupling.csv'));
save(fullfile(out_dir,'effects_results.mat'),'TA','TB','TS','TM','TH');
fprintf('EFFECTS_DONE\n');

%% Local functions
function [d,h] = local_change(T,oc,p1,p2)
    T = T(ismember(T.phase,{p1,p2}) & isfinite(T.(oc)),:);
    u = unique(string(T.subject)); d = nan(numel(u),1); s = string(T.subject);
    for i = 1:numel(u)
        ix = s==u(i); a = T.acquisition(ix&strcmp(T.phase,p1)); b = T.acquisition(ix&strcmp(T.phase,p2)); sh = intersect(a,b);
        in = ismember(T.acquisition,sh);
        d(i) = mean(T.(oc)(ix&strcmp(T.phase,p2)&in))-mean(T.(oc)(ix&strcmp(T.phase,p1)&in));
    end
    h = endsWith(u,'H');
end
function [d,h] = local_slope(T,oc)
    T = T(strcmp(T.phase_type,'training') & isfinite(T.(oc)),:);
    u = unique(string(T.subject)); d = nan(numel(u),1); s = string(T.subject);
    for i = 1:numel(u)
        X = T(s==u(i),:); y = X.(oc); r = double(X.repetition); [g,~] = findgroups(X.level);
        my = splitapply(@mean,y,g); mr = splitapply(@mean,r,g); yy = y-my(g); rr = r-mr(g);
        if sum(rr.^2)>0, d(i) = sum(rr.*yy)/sum(rr.^2); end
    end
    h = endsWith(u,'H');
end
function [d,h] = local_level(T,oc,lv)
    T = T(strcmp(T.phase_type,'training') & isfinite(T.(oc)),:);
    u = unique(string(T.subject)); d = nan(numel(u),1); s = string(T.subject);
    for i = 1:numel(u)
        X = T(s==u(i),:); d(i) = mean(X.(oc)(X.level==lv))-mean(X.(oc)(X.level==1));
    end
    h = endsWith(u,'H');
end
function r = local_effect(d,h)
    h = h(isfinite(d)); d = d(isfinite(d)); a = d(~h); b = d(h); n1 = numel(a); n2 = numel(b);
    se = sqrt(var(a)/n1+var(b)/n2); df = se^4/((var(a)/n1)^2/(n1-1)+(var(b)/n2)^2/(n2-1)); df2 = mean(b)-mean(a);
    t95 = tinv(.975,df); t90 = tinv(.95,df); [~,p] = ttest2(b,a,'Vartype','unequal');
    sp = sqrt(((n1-1)*var(a)+(n2-1)*var(b))/(n1+n2-2)); J = 1-3/(4*(n1+n2-2)-1); g = J*df2/sp;
    seg = sqrt((n1+n2)/(n1*n2)+g^2/(2*(n1+n2)));
    t = df2/(sp*sqrt(1/n1+1/n2));
    mde = sampsizepwr('t2',[0 1],[],.8,min(n1,n2),'Ratio',max(n1,n2)/min(n1,n2));
    r = {n1,n2,mean(a),mean(b),df2,df2-t95*se,df2+t95*se,df2-t90*se,df2+t90*se,p,g,g-1.96*seg,g+1.96*seg,1/local_bf10(t,n1,n2),mde};
end
function bf = local_bf10(t,n1,n2)
    % JZS Bayes factor for two independent groups, r = sqrt(2)/2 (Rouder et al., 2009)
    n = n1*n2/(n1+n2); v = n1+n2-2; r2 = 0.5;
    f = @(g) (1+n*r2*g).^(-1/2).*(1+t^2./((1+n*r2*g)*v)).^(-(v+1)/2).*(2*pi)^(-1/2).*g.^(-3/2).*exp(-1./(2*g));
    bf = integral(f,0,Inf,'RelTol',1e-8)/(1+t^2/v)^(-(v+1)/2);
end
function D = local_prep(D)
    D.subject_cat = categorical(string(D.subject)); D.level_cat = categorical(D.level);
    D.haptic_num = double(endsWith(string(D.subject),'H'));
    if ismember('repetition',D.Properties.VariableNames), D.repetition = double(D.repetition); end
    D.subj_level = categorical(strcat(string(D.subject),'_',string(D.level)));
end
function m = local_fit(D,f,isP)
    if isP, m = fitglme(D,f,'Distribution','poisson','FitMethod','Laplace'); else, m = fitlme(D,f,'FitMethod','REML'); end
end
function [b,se,p,df] = local_term(m,name,satt)
    if satt
        [~,~,st] = fixedEffects(m,'DFMethod','satterthwaite'); nm = st.Name; est = st.Estimate; s = st.SE; pv = st.pValue; d = st.DF;
    else
        c = m.Coefficients; nm = cellstr(c.Name); est = double(c.Estimate); s = double(c.SE); pv = double(c.pValue); d = double(c.DF);
    end
    want = sort(strsplit(name,':')); ix = cellfun(@(n) isequal(sort(strsplit(n,':')),want),nm);
    if ~any(ix), error('Term %s not found.',name); end
    b = est(ix); se = s(ix); p = pv(ix); df = d(ix);
end
function [u,x] = local_submean(T,oc)
    T = T(strcmp(T.phase_type,'training')&isfinite(T.(oc)),:);
    s = string(T.subject); u = unique(s); x = arrayfun(@(k) mean(T.(oc)(s==k)),u);
end
function [b,se,p,c] = local_ols(y,X,col)
    % OLS of y on X plus intercept. Returns the coefficient of column col, and the last column's coefficient as c.
    A = [ones(numel(y),1) X]; bb = A\y; res = y-A*bb; df = numel(y)-size(A,2); V = (res'*res/df)*inv(A'*A); %#ok<MINV>
    b = bb(col+1); se = sqrt(V(col+1,col+1)); p = 2*tcdf(-abs(b/se),df); c = bb(end);
end
