%% Claude_exploratory_angles.m
% Runs sections 2 to 8 of Claude_exploratory_analysis_plan.md exactly as written there. Test3 is deferred.
% All results are exploratory. Writes ONLY to <output_root>/Claude_outputs/exploratory.

clear; clc; cfg = config();
out_dir = fullfile(cfg.output_root,'Claude_outputs','exploratory'); if ~exist(out_dir,'dir'), mkdir(out_dir); end
E = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); E = E.T;
Y = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T'); Y = Y.T;
P = load(fullfile(cfg.output_root,'perf_features.mat'),'T');   P = P.T;
F = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); F = F.T;
V = load(fullfile(cfg.output_root,'Claude_outputs','eye','eye_features_claude.mat'),'T'); V = V.T;
F.tssf(F.tssf<=0)=NaN; F.tssv(F.tssv<=0)=NaN; F.log_tssf=log(F.tssf); F.log_tssv=log(F.tssv);
TL = load(fullfile(cfg.output_root,'Claude_outputs','surg_tlx','tlx_results.mat'),'C','ids','H');
subs = string(cfg.all_subjects)'; isH = endsWith(subs,'H');
perf = {'duration_s',P;'n_collisions',P;'log_tssf',F;'log_tssv',F};
rows = {};

%% 2. Online benefit during training
for k = 1:4
    x = local_sub(perf{k,2},perf{k,1},subs,@(T) strcmp(T.phase_type,'training'));
    rows(end+1,:) = [{'2 Online benefit',perf{k,1},'HF vs NHF, training mean'}, local_g(x,isH)]; %#ok<AGROW>
end

%% 3. Feedback dependence
for k = 1:4
    T = perf{k,2}; oc = perf{k,1}; d = nan(numel(subs),1); s = string(T.subject);
    for i = 1:numel(subs)
        v = nan(5,1);
        for lv = 1:5
            a = T.(oc)(s==subs(i)&strcmp(T.phase_type,'training')&T.level==lv&T.repetition>=8);
            b = T.(oc)(s==subs(i)&strcmp(T.phase,'Baseline2')&T.level==lv);
            a = a(isfinite(a)); b = b(isfinite(b));
            if ~isempty(a)&&~isempty(b), v(lv) = mean(b)-mean(a); end
        end
        d(i) = mean(v,'omitnan');
    end
    rows(end+1,:) = [{'3 Feedback dependence',oc,'HF vs NHF, Baseline2 minus last 3 training reps'}, local_g(d,isH)]; %#ok<AGROW>
end

%% 4. Consistency
PT = P(strcmp(P.phase_type,'training'),:); s = string(PT.subject);
cv = nan(numel(subs),1); sdc = cv;
for i = 1:numel(subs)
    a = nan(5,1); b = a;
    for lv = 1:5
        ix = s==subs(i)&PT.level==lv; t = PT.duration_s(ix); c = PT.n_collisions(ix);
        t = t(isfinite(t)); c = c(isfinite(c));
        if numel(t)>=5, a(lv) = std(t)/mean(t); end
        if numel(c)>=5, b(lv) = std(c); end
    end
    cv(i) = mean(a,'omitnan'); sdc(i) = mean(b,'omitnan');
end
rows(end+1,:) = [{'4 Consistency','duration_s','HF vs NHF, within-subject CV'}, local_g(cv,isH)];
rows(end+1,:) = [{'4 Consistency','n_collisions','HF vs NHF, within-subject SD'}, local_g(sdc,isH)];

%% 5. Workload efficiency
tlx_ids = "subject_" + lower(extractBetween(TL.ids,1,3)) + extractAfter(TL.ids,3);
[found,loc] = ismember(subs,tlx_ids); if ~all(found), warning('TLX missing: %s',strjoin(subs(~found),' ')); end
C = nan(numel(subs),5); C(found,:) = TL.C(loc(found),:);
Tm = nan(numel(subs),5);
for lv = 1:5
    for i = 1:numel(subs), Tm(i,lv) = mean(PT.duration_s(s==subs(i)&PT.level==lv),'omitnan'); end
end
Eff = (-local_z(Tm)-local_z(C))/sqrt(2);
rows(end+1,:) = [{'5 Workload efficiency','time and SURG-TLX','HF vs NHF, mean Paas efficiency'}, local_g(mean(Eff,2,'omitnan'),isH)];

%% 6. Do objective measures track reported workload?
objs = {'duration_s',P;'n_collisions',P;'log_tssf',F;'scl_mean_bc',E;'scr_freq',E;'pupil_mean_norm',Y;'gaze_entropy',Y;'fixation_rate',V};
for k = 1:size(objs,1)
    T = objs{k,2}; oc = objs{k,1}; st = string(T.subject); O = nan(numel(subs),5);
    for lv = 1:5
        for i = 1:numel(subs)
            O(i,lv) = mean(T.(oc)(st==subs(i)&strcmp(T.phase_type,'training')&T.level==lv),'omitnan');
        end
    end
    [r,p,n,df] = local_rmcorr(C,O);
    rows(end+1,:) = {'6 Tracks workload',oc,'Repeated-measures correlation with SURG-TLX',n,NaN,NaN,NaN,r,NaN,NaN,p,df}; %#ok<AGROW>
end

%% 7. Individual differences
D = readtable(fullfile(cfg.data_root,'demographics.csv'),'TextType','string');
[~,loc] = ismember(subs,D.subject);
for oc = {'duration_s','n_collisions'}
    d = local_change(P,oc{1},'Baseline1','Baseline2',subs);
    for mo = {'gaming_experience','robotic_experience'}
        m = D.(mo{1})(loc); z = (m-mean(m,'omitnan'))/std(m,'omitnan');
        [b,se,p,df] = local_interact(d,double(isH),z);
        rows(end+1,:) = {'7 Who benefits',oc{1},['Group x ' mo{1}],sum(isfinite(d)),NaN,NaN,NaN,b,b-tinv(.975,df)*se,b+tinv(.975,df)*se,p,df}; %#ok<AGROW>
    end
end

%% 8. Perceived vs measured benefit (group ratings; the Test3 link is in Claude_test3_analysis.m)
% IDs are matched by number and groups come from the study list: row 20h is s20N with a wrong letter,
% from Response ID order and the unique entry for number 20.
S = readcell(fullfile(cfg.data_root,'ClosingSurvey.csv'),'Delimiter',',','TextType','string');
hdr = string(S(1,:)); ids = upper(strtrim(string(S(2:end,strcmp(hdr,'Subject ID')))));
ids = regexprep(ids,'^S?(\d+)[NH]$','$1'); subnum = regexprep(extractAfter(subs,'subject_s'),'[NH]$','');
scale = containers.Map({'Strongly Disagree','Disagree','Somewhat Disagree','Neither Agree Nor Disagree','Somewhat Agree','Agree','Strongly Agree'},1:7);
for it = {'supported my performance','more aware of the robot'}
    c = find(contains(hdr,it{1}),1); raw = strtrim(string(S(2:end,c))); val = nan(numel(subs),1);
    for i = 1:numel(subs)
        ix = find(ids==subnum(i));
        if isempty(ix), continue; end
        ix = ix(end);   % the researcher confirmed the last entry is correct when an ID repeats (S02)
        if isKey(scale,char(raw(ix))), val(i) = scale(char(raw(ix))); end
    end
    a = val(~isH); b = val(isH); a = a(isfinite(a)); b = b(isfinite(b));
    rows(end+1,:) = {'8 Perceived benefit',it{1},'HF vs NHF rating, 1 to 7',numel(a),numel(b),mean(a),mean(b),mean(b)-mean(a),NaN,NaN,ranksum(b,a),NaN}; %#ok<AGROW>
end
fprintf('Survey subjects matched: %d; missing or excluded: %s\n',sum(isfinite(val)),strjoin(subs(~isfinite(val)),' '));

T = cell2table(rows,'VariableNames',{'section','outcome','test','n1','n2','mean1','mean2','estimate','ci_lo','ci_hi','p','df_or_g'});
T.p_fdr = local_bh(T.p);
writetable(T,fullfile(out_dir,'exploratory_results.csv'));
save(fullfile(out_dir,'exploratory_results.mat'),'T','Eff');
fprintf('EXPLORATORY_DONE\n');

function x = local_sub(T,oc,subs,sel)
    T = T(sel(T)&isfinite(T.(oc)),:); s = string(T.subject); x = nan(numel(subs),1);
    for i = 1:numel(subs), v = T.(oc)(s==subs(i)); if ~isempty(v), x(i) = mean(v); end; end
end
function d = local_change(T,oc,p1,p2,subs)
    T = T(ismember(T.phase,{p1,p2})&isfinite(T.(oc)),:); s = string(T.subject); d = nan(numel(subs),1);
    for i = 1:numel(subs)
        ix = s==subs(i); sh = intersect(T.acquisition(ix&strcmp(T.phase,p1)),T.acquisition(ix&strcmp(T.phase,p2)));
        if isempty(sh), continue; end
        in = ismember(T.acquisition,sh);
        d(i) = mean(T.(oc)(ix&strcmp(T.phase,p2)&in))-mean(T.(oc)(ix&strcmp(T.phase,p1)&in));
    end
end
function r = local_g(x,h)
    a = x(~h&isfinite(x)); b = x(h&isfinite(x)); n1 = numel(a); n2 = numel(b);
    se = sqrt(var(a)/n1+var(b)/n2); df = se^4/((var(a)/n1)^2/(n1-1)+(var(b)/n2)^2/(n2-1)); dd = mean(b)-mean(a); t = tinv(.975,df);
    [~,p] = ttest2(b,a,'Vartype','unequal'); sp = sqrt(((n1-1)*var(a)+(n2-1)*var(b))/(n1+n2-2)); g = (1-3/(4*(n1+n2-2)-1))*dd/sp;
    r = {n1,n2,mean(a),mean(b),dd,dd-t*se,dd+t*se,p,g};
end
function Z = local_z(X)
    Z = (X-mean(X,1,'omitnan'))./std(X,0,1,'omitnan');
end
function [r,p,n,df] = local_rmcorr(A,B)
    ok = isfinite(A)&isfinite(B); A(~ok) = NaN; B(~ok) = NaN;
    a = A-mean(A,2,'omitnan'); b = B-mean(B,2,'omitnan'); v = isfinite(a)&isfinite(b); a = a(v); b = b(v);
    n = sum(any(v,2)); df = numel(a)-n-1; r = sum(a.*b)/sqrt(sum(a.^2)*sum(b.^2));
    t = r*sqrt(df/(1-r^2)); p = 2*tcdf(-abs(t),df);
end
function [b,se,p,df] = local_interact(y,h,z)
    ok = isfinite(y)&isfinite(z); y = y(ok); h = h(ok); z = z(ok);
    A = [ones(size(y)) h z h.*z]; bb = A\y; res = y-A*bb; df = numel(y)-4; V = (res'*res/df)*inv(A'*A); %#ok<MINV>
    b = bb(4); se = sqrt(V(4,4)); p = 2*tcdf(-abs(b/se),df);
end
function q = local_bh(p)
    q = nan(size(p)); v = find(isfinite(p)); [ps,ix] = sort(p(v)); m = numel(ps);
    a = ps.*m./(1:m)'; a = min(cummin(a,'reverse'),1); q(v(ix)) = a;
end
