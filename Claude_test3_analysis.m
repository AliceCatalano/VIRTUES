%% Claude_test3_analysis.m
% Replacement section 1 and the Test3 part of section 8 in Claude_exploratory_analysis_plan.md.
% Test3: final peg-transfer, fixed time, opposite condition to training (HF feedback off, NHF feedback on).
% Group and feedback condition are fully confounded, so this compares "newly on" with "newly off".
% Does not call gsr_preprocess or eye_preprocess_v2, so nothing is written to subject folders.
% Writes ONLY to <output_root>/Claude_outputs/test3.
% Repetitions: put them in <data_root>/Test3_repetitions.csv with columns subject,repetitions, using IDs
% like subject_s02N. Those tests are skipped until that file exists.

clear; clc; cfg = config();
out_dir = fullfile(cfg.output_root,'Claude_outputs','test3'); if ~exist(out_dir,'dir'), mkdir(out_dir); end
subs = string(cfg.all_subjects)'; isH = endsWith(subs,'H'); n = numel(subs);
C_force = load_ati_cal(cfg.force_cal_path);
EX = load(fullfile(cfg.output_root,'accel_exclusion_lists.mat'));
P = load(fullfile(cfg.output_root,'perf_features.mat'),'T'); P = P.T;
F = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); F = F.T;
E = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); E = E.T;
V = load(fullfile(cfg.output_root,'Claude_outputs','eye','eye_features_claude.mat'),'T'); V = V.T;
vars = {'dur_s','tssf_min','tssv_min','scl_raw','saccade_rate','fixation_rate','dup_frac','flag_force','flag_accel','scl_fail','tssf_min75','tssv_min75','nidaq_s'};
A = nan(n,numel(vars));
for i = 1:n
    d = fullfile(cfg.data_root,char(subs(i)),'Test3');
    [a,b] = safe_trial_window(fullfile(d,'events.mat')); A(i,1) = b-a;
    [A(i,2),A(i,8),A(i,13)] = local_force(fullfile(d,'force.mat'),a,b,cfg,C_force);
    [A(i,3),A(i,9)] = local_accel(fullfile(d,'accel.mat'),a,b,cfg);
    if b-a>=75   % never read past the end of the task
        A(i,11) = local_force(fullfile(d,'force.mat'),a,a+75,cfg,C_force);
        A(i,12) = local_accel(fullfile(d,'accel.mat'),a,a+75,cfg);
    end
    [A(i,4),A(i,10)] = local_scl(fullfile(d,'gsr.mat'),a,b,cfg);
    try
        L = load(fullfile(d,'eye.mat'),'EYE'); r = local_trial(L.EYE,a,b); A(i,5) = r(2); A(i,6) = r(5); A(i,7) = r(9);
    catch ME
        fprintf('eye skip %s: %s\n',subs(i),ME.message);
    end
    fprintf('%s done\n',subs(i));
end
T3 = [table(subs,isH,'VariableNames',{'subject','haptic_trained'}) array2table(A,'VariableNames',vars)];
xF = ismember(T3.subject,string(EX.tssf_subj_excl)); xV = ismember(T3.subject,string(EX.tssv_subj_excl));
T3.tssf_min(T3.flag_force==1|xF) = NaN; T3.tssv_min(T3.flag_accel==1|xV) = NaN; T3.tssf_min75(xF) = NaN; T3.tssv_min75(xV) = NaN;
T3.log_tssf = local_log(T3.tssf_min); T3.log_tssv = local_log(T3.tssv_min); T3.log_tssf75 = local_log(T3.tssf_min75); T3.log_tssv75 = local_log(T3.tssv_min75);
% Tonic SCL relative to the same resting reference as the other phases
rest = nan(n,1); s = string(E.subject);
for i = 1:n, ix = find(s==subs(i)&isfinite(E.scl_mean)&isfinite(E.scl_mean_bc),1); if ~isempty(ix), rest(i) = E.scl_mean(ix)-E.scl_mean_bc(ix); end; end
T3.scl_bc = T3.scl_raw-rest;
% Same measures in Test2
t2 = @(Tb,oc) arrayfun(@(k) mean(Tb.(oc)(string(Tb.subject)==k&strcmp(Tb.phase,'Test2')),'omitnan'),subs);
dur2 = t2(P,'duration_s'); T3.dur2 = dur2;
T3.log_tssf2 = local_log(t2(F,'tssf')./(dur2/60)); T3.log_tssv2 = local_log(t2(F,'tssv')./(dur2/60));
T3.scl_bc2 = t2(E,'scl_mean_bc'); T3.sac2 = t2(V,'saccade_rate'); T3.fix2 = t2(V,'fixation_rate');
rep_file = fullfile(cfg.data_root,'Test3_repetitions.csv');
hasReps = isfile(rep_file);
if hasReps
    R = readtable(rep_file,'TextType','string'); [~,loc] = ismember(subs,R.subject); T3.reps = nan(n,1); T3.reps(loc>0) = R.repetitions(loc(loc>0));
end
jobs = {'log_tssf','log_tssf2'; 'log_tssv','log_tssv2'; 'scl_bc','scl_bc2'; 'fixation_rate','fix2'; 'saccade_rate','sac2'};
sens = {'log_tssf75','log_tssf2'; 'log_tssv75','log_tssv2'};
if hasReps, jobs = [{'reps','dur2'}; jobs]; end
rows = {};
for j = 1:size(jobs,1)
    y = T3.(jobs{j,1}); x = T3.(jobs{j,2}); ok = isfinite(y)&isfinite(x);
    a0 = y(ok&~isH); b0 = y(ok&isH);
    [~,pw] = ttest2(b0,a0,'Vartype','unequal'); pr = ranksum(b0,a0);
    sp = sqrt(((numel(a0)-1)*var(a0)+(numel(b0)-1)*var(b0))/(numel(a0)+numel(b0)-2)); g = (1-3/(4*(numel(a0)+numel(b0)-2)-1))*(mean(b0)-mean(a0))/sp;
    D = [ones(sum(ok),1) double(isH(ok)) x(ok)-mean(x(ok))]; yy = y(ok); bb = D\yy; res = yy-D*bb; df = sum(ok)-3; Vv = (res'*res/df)*inv(D'*D); se = sqrt(Vv(2,2)); %#ok<MINV>
    pa = 2*tcdf(-abs(bb(2)/se),df); tc = tinv(.975,df);
    rows(end+1,:) = {jobs{j,1},numel(a0),numel(b0),mean(a0),std(a0),mean(b0),std(b0),g,pw,pr,bb(2),bb(2)-tc*se,bb(2)+tc*se,pa,bb(3)}; %#ok<AGROW>
end
TR = cell2table(rows,'VariableNames',{'outcome','n_N','n_H','mean_N_on','sd_N','mean_H_off','sd_H','hedges_g','p_welch','p_rank','adj_diff_H_minus_N','adj_lo','adj_hi','p_adjusted','slope_test2'});
TR.p_fdr = local_bh(TR.p_adjusted);
rows = {};
for j = 1:2
    y = T3.(sens{j,1}); x = T3.(sens{j,2}); ok = isfinite(y)&isfinite(x); D = [ones(sum(ok),1) double(isH(ok)) x(ok)-mean(x(ok))]; yy = y(ok); bb = D\yy; res = yy-D*bb; df = sum(ok)-3; Vv = (res'*res/df)*inv(D'*D); se = sqrt(Vv(2,2)); %#ok<MINV>
    rows(end+1,:) = {sens{j,1},sum(ok&~isH),sum(ok&isH),bb(2),bb(2)-tinv(.975,df)*se,bb(2)+tinv(.975,df)*se,2*tcdf(-abs(bb(2)/se),df)}; %#ok<AGROW>
end
writetable(cell2table(rows,'VariableNames',{'outcome','n_N','n_H','adj_diff_H_minus_N','adj_lo','adj_hi','p_adjusted'}),fullfile(out_dir,'test3_first75s_sensitivity.csv'));
writetable(TR,fullfile(out_dir,'test3_group_results.csv')); writetable(T3,fullfile(out_dir,'test3_subject_values.csv'));
save(fullfile(out_dir,'test3_results.mat'),'T3','TR');

% Perceived support vs measured performance, within each group
Sv = readcell(fullfile(cfg.data_root,'ClosingSurvey.csv'),'Delimiter',',','TextType','string');
hdr = string(Sv(1,:)); ids = regexprep(upper(strtrim(string(Sv(2:end,strcmp(hdr,'Subject ID'))))),'^S?(\d+)[NH]$','$1');
raw = strtrim(string(Sv(2:end,find(contains(hdr,'supported my performance'),1))));
scale = containers.Map({'Strongly Disagree','Disagree','Somewhat Disagree','Neither Agree Nor Disagree','Somewhat Agree','Agree','Strongly Agree'},1:7);
num = regexprep(extractAfter(subs,'subject_s'),'[NH]$',''); rate = nan(n,1);
for i = 1:n, ix = find(ids==num(i)); if ~isempty(ix)&&isKey(scale,char(raw(ix(end)))), rate(i) = scale(char(raw(ix(end)))); end; end
imp = nan(n,1); bs = string(P.subject);
for i = 1:n
    ix = bs==subs(i); sh = intersect(P.acquisition(ix&strcmp(P.phase,'Baseline1')),P.acquisition(ix&strcmp(P.phase,'Baseline2')));
    in = ismember(P.acquisition,sh); imp(i) = mean(P.duration_s(ix&strcmp(P.phase,'Baseline1')&in),'omitnan')-mean(P.duration_s(ix&strcmp(P.phase,'Baseline2')&in),'omitnan');
end
rowsC = {};
for g = [false true]
    k = isH==g&isfinite(rate)&isfinite(imp); [r,p] = corr(rate(k),imp(k),'Type','Spearman'); rowsC(end+1,:) = {'g',g,'BL1 to BL2 improvement in time',sum(k),r,p}; %#ok<AGROW>
    if hasReps, k = isH==g&isfinite(rate)&isfinite(T3.reps); [r,p] = corr(rate(k),T3.reps(k),'Type','Spearman'); rowsC(end+1,:) = {'g',g,'Repetitions in Test3',sum(k),r,p}; end %#ok<AGROW>
end
TC = cell2table(rowsC,'VariableNames',{'label','haptic_trained','measure','n','spearman_r','p'}); TC.label = []; TC.p_fdr = local_bh(TC.p);
writetable(TC,fullfile(out_dir,'perceived_vs_measured.csv'));
fprintf('TEST3_DONE hasReps=%d\n',hasReps);

function y = local_log(x), x(x<=0) = NaN; y = log(x); end
function [v,flag,covered] = local_force(p,a,b,cfg,C)
    % Rate over the time actually recorded inside [a,b]. Requires at least 60 s when used for the whole task.
    v = NaN; flag = 1; covered = 0; L = load(p,'FORCE'); t = L.FORCE.time_rel(:); X = L.FORCE.data; w = t>=a&t<=b;
    if sum(w)<10, return; end
    covered = t(find(w,1,'last'))-t(find(w,1)); 
    if covered<60, return; end
    if mean(arrayfun(@(c) numel(unique(X(w,c))),1:size(X,2)))<50, return; end
    pre = t>=(a-1)&t<a; 
    if sum(pre)<3, pre = t<(t(1)+1); end
    bias = mean(X(pre,:),1,'omitnan'); 
    Fb = (C*(X(pre,:)-bias)')'; 
    mb = sqrt(sum(Fb(:,1:3).^2,2)); 
    nf = median(mb)+cfg.force_noise_k_mad*mad(mb,1);
    Fc = (C*(X(w,:)-bias)')'; 
    m = sqrt(sum(Fc(:,1:3).^2,2));
    m(m<nf) = 0; v = (sum(m.^2)*covered/sum(w))/(covered/60); flag = 0;
end
function [v,flag] = local_accel(p,a,b,cfg)
    v = NaN; flag = 1; L = load(p,'ACCEL'); t = L.ACCEL.time_rel(:); fs = L.ACCEL.fs_nominal; X = L.ACCEL.data; w = t>=a&t<=b;
    if sum(w)<10, return; end
    covered = t(find(w,1,'last'))-t(find(w,1)); if covered<60, return; end
    if mean(arrayfun(@(c) numel(unique(X(w,c))),1:6))<50, return; end
    pre = t>=(a-1)&t<a; if sum(pre)<3, pre = t<(t(1)+1); end
    bias = mean(X(pre,:),1,'omitnan'); S = (X(w,:)-bias)*cfg.accel_sensitivity_ms2_per_V;
    [bb,aa] = butter(4,[80 1000]/(fs/2),'bandpass'); for c = 1:6, S(:,c) = filtfilt(bb,aa,double(S(:,c))); end
    if mean(sqrt(mean(S.^2,1)))<0.01, return; end
    l = sqrt(sum(S(:,1:3).^2,2)); r = sqrt(sum(S(:,4:6).^2,2)); th = cfg.tssv_noise_threshold_ms2; l(l<th) = 0; r(r<th) = 0;
    v = ((sum(l.^2)+sum(r.^2))*covered/sum(w))/(covered/60); flag = 0;
end
function [v,fail] = local_scl(p,a,b,cfg)
    % gsr_preprocess.m steps without its save() into the subject folder
    v = NaN; fail = 1;
    try
        L = load(p,'GSR'); t = L.GSR.time_rel; raw = L.GSR.GSR_ohm; ok = isfinite(raw)&raw>0; t = t(ok); us = 1e3./raw(ok); w = t>=a&t<=b; t = t(w); us = us(w);
        if numel(t)<20 || max(diff(t))>cfg.max_gap_s, return; end
        fs = cfg.fs_target; tu = (t(1):1/fs:t(end))'; g = interp1(t,us,tu,'nearest'); [bb,aa] = butter(4,3/(fs/2),'low'); g = max(filtfilt(bb,aa,g),1e-6);
        [~,~,tonic] = cvxEDA(g(:),1/fs); v = mean(tonic); fail = 0;
    catch ME
        fprintf('scl skip %s: %s\n',p,ME.message);
    end
end
function q = local_bh(p)
    q = nan(size(p)); v = find(isfinite(p)); [ps,ix] = sort(p(v)); m = numel(ps);
    a = ps.*m./(1:m)'; a = min(cummin(a,'reverse'),1); q(v(ix)) = a;
end
function r = local_trial(E,a,b)
    PX_PER_DEG = 15.5; FLOOR_DEG = 30; LAMBDA = 6; DT = 0.005;
    MIN_SAC = 0.015; MERGE = 0.020; MIN_FIX = 0.100; MAX_INTERP = 0.020;
    ch = E.channel_names; t = E.time_rel(:); D = E.data;
    w = t>=a & t<=b; t = t(w); D = D(w,:); [t,o] = sort(t); D = D(o,:);
    c = @(nm) D(:,strcmp(ch,nm));
    x = c('x'); y = c('y'); bl = c('blink')==1;
    devS = c('saccade'); devF = c('fixation');
    pl = c('pupil_diameter_left'); pr = c('pupil_diameter_right');
    raw_hz = numel(t)/max(t(end)-t(1),eps);
    isdup = [false; diff(x)==0 & diff(y)==0];
    dup_frac = mean(isdup);
    t = t(~isdup); x = x(~isdup); y = y(~isdup); bl = bl(~isdup); devS = devS(~isdup); devF = devF(~isdup); pl = pl(~isdup); pr = pr(~isdup);
    unique_hz = numel(t)/max(t(end)-t(1),eps);
    % Uniform grid. A grid point is valid only if both neighbours are non-blink and close enough.
    tg = (t(1):DT:t(end))';
    gd = ~bl & isfinite(x) & isfinite(y);
    tv = t(gd); xv = x(gd); yv = y(gd);
    ix = interp1(tv,xv,tg,'linear'); iy = interp1(tv,yv,tg,'linear');
    prevI = discretize(tg,[tv; inf]);
    okgrid = false(size(tg));
    has = ~isnan(prevI) & prevI<numel(tv);
    okgrid(has) = (tv(prevI(has)+1)-tv(prevI(has))) <= MAX_INTERP;
    ix(~okgrid) = NaN; iy(~okgrid) = NaN;
    valid_s = sum(okgrid)*DT;
    % Engbert & Kliegl velocity
    k = [1 1 0 -1 -1]/(6*DT);
    vx = conv(ix,k,'same'); vy = conv(iy,k,'same');
    vx([1 2 end-1 end]) = NaN; vy([1 2 end-1 end]) = NaN;
    sx = sqrt(max(median(vx.^2,'omitnan')-median(vx,'omitnan')^2,0));
    sy = sqrt(max(median(vy.^2,'omitnan')-median(vy,'omitnan')^2,0));
    floorpx = FLOOR_DEG*PX_PER_DEG;
    rx = max(LAMBDA*sx,floorpx); ry = max(LAMBDA*sy,floorpx);
    above = (vx./rx).^2 + (vy./ry).^2 > 1;
    above(isnan(vx)|isnan(vy)) = false;
    % Merge short gaps, then require a minimum duration
    [st,en] = local_runs(above);
    if numel(st)>1
        close_gap = (st(2:end)-en(1:end-1)-1)*DT < MERGE;
        for g = find(close_gap(:))', above(en(g):st(g+1)) = true; end
        [st,en] = local_runs(above);
    end
    durs = (en-st+1)*DT;
    keepS = durs >= MIN_SAC;
    st = st(keepS); en = en(keepS);
    sac = false(size(above));
    pk = nan(numel(st),1);
    speed = hypot(vx,vy)/PX_PER_DEG;
    for q = 1:numel(st), sac(st(q):en(q)) = true; pk(q) = max(speed(st(q):en(q))); end
    % Fixations: valid, non-saccade runs of at least MIN_FIX
    [fs,fe] = local_runs(okgrid & ~sac);
    fd = (fe-fs+1)*DT; fd = fd(fd>=MIN_FIX);
    mins = max(valid_s,eps)/60;
    % Fixed-grid entropy
    gx = xv; gy = yv;
    H = histcounts2(gx,gy,0:100:1600,0:100:1200); P = H(:)/max(sum(H(:)),1); P = P(P>0);
    ent = -sum(P.*log2(P));
    % The device's own event channels, as a reference. Counted as onsets.
    dS = sum(diff([0; devS(:)>0])==1)/mins; dF = sum(diff([0; devF(:)>0])==1)/mins;
    % Share of pupil samples the original 3 mm/s rule would remove on de-duplicated data
    p = mean([pl pr],2,'omitnan'); p(bl) = NaN; p(p<2|p>8) = NaN;
    sp = [0; abs(diff(p)./max(diff(t),eps))];
    rem = sum(sp>3)/max(sum(isfinite(p)),1);
    thr_deg = hypot(rx,ry)/sqrt(2)/PX_PER_DEG;
    r = [numel(st), numel(st)/mins, median(pk,'omitnan'), numel(fd), numel(fd)/mins, local_mean(fd), ent, valid_s, dup_frac, raw_hz, unique_hz, mean(okgrid), dS, dF, rem, thr_deg];
end
function [st,en] = local_runs(b)
    d = diff([0; b(:); 0]); st = find(d==1); en = find(d==-1)-1;
end
function m = local_mean(v)
    if isempty(v), m = NaN; else, m = mean(v); end
end
