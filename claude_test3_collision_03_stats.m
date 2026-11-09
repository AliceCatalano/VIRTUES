%% claude_test3_collision_03_stats.m
% Step 3. Tests Q1 to Q4 of claude_test3_collision_plan.md, with subjects as the unit of inference.
% Group labels: NHF had feedback ON in Test3, HF had it OFF. Group and condition are fully confounded.
% Writes ONLY to <output_root>/Claude_outputs/test3_collision.

clear; clc; cfg = config(); rng(20261105);
out_dir = fullfile(cfg.output_root,'Claude_outputs','test3_collision'); fig_dir = fullfile(out_dir,'figures'); if ~exist(fig_dir,'dir'), mkdir(fig_dir); end
L = load(fullfile(out_dir,'extracted.mat')); T = L.T; SS = L.SS; KE = L.KE; KP = L.KP; BE = L.BE; BP = L.BP;
T.haptic = double(endsWith(string(T.subject),'H')); SS.haptic = endsWith(string(SS.subject),'H');
S3 = SS(strcmp(SS.phase,'Test3'),:); S2 = SS(strcmp(SS.phase,'Test2'),:);
E3 = T(strcmp(T.phase,'Test3'),:);
rows = {};  % question, test, primary, n, estimate, lo, hi, p, effect, BF01

%% Q1. Above chance?
S5 = S3(S3.n_events>=5,:);
ms = {'eda','EDA response (driver, 1-4 s)';'pupil','Pupil response (mm)';'sac','Saccade-rate change (per s)';'disp','Gaze-dispersion change (px)'};
for m = 1:4
    d = S5.([ms{m,1} '_obs'])-S5.([ms{m,1} '_null']); d = d(isfinite(d));
    [est,lo,hi,p,dz] = local_onesample(d);
    rows(end+1,:) = {'Q1',['Above chance: ' ms{m,2}],true,numel(d),est,lo,hi,p,dz,NaN}; %#ok<AGROW>
end
%% Q2. EDA-pupil coupling beyond background
S8 = S3(S3.n_events>=8&isfinite(S3.r_obs),:);
d = S8.r_obs-S8.r_null; [est,lo,hi,p,dz] = local_onesample(d);
rows(end+1,:) = {'Q2','Within-subject EDA-pupil r, observed minus shifted',true,numel(d),est,lo,hi,p,dz,NaN};
[est,lo,hi,p,dz] = local_onesample(S8.r_obs); rows(end+1,:) = {'Q2','Within-subject EDA-pupil r, observed',false,height(S8),est,lo,hi,p,dz,NaN};
[est,lo,hi,p,dz] = local_onesample(S8.r_null); rows(end+1,:) = {'Q2','Within-subject EDA-pupil r, shifted times (background)',false,height(S8),est,lo,hi,p,dz,NaN};
% Mixed model at event level
M = local_prep(E3); ME = M(isfinite(M.eda_z)&isfinite(M.pupil_w)&isfinite(M.log_audio_w)&isfinite(M.ici_z)&isfinite(M.base_w),:);
mq2 = fitlme(ME,'eda_z ~ pupil_w*haptic + log_audio_w + time_z + ici_z + base_w + (1+pupil_w|subj)','FitMethod','REML');
[b,se,p,df] = local_term(mq2,'pupil_w'); rows(end+1,:) = {'Q2','Mixed model: pupil within-subject slope on EDA (NHF)',true,numel(unique(ME.subj)),b,b-tinv(.975,df)*se,b+tinv(.975,df)*se,p,NaN,NaN};
[b,se,p,df] = local_term(mq2,'pupil_w:haptic'); rows(end+1,:) = {'Q3','Mixed model: group difference in pupil slope (HF off - NHF on)',true,numel(unique(ME.subj)),b,b-tinv(.975,df)*se,b+tinv(.975,df)*se,p,NaN,NaN};
[b,se,p,df] = local_term(mq2,'log_audio_w'); rows(end+1,:) = {'Q4','Same model: audio intensity on EDA',false,numel(unique(ME.subj)),b,b-tinv(.975,df)*se,b+tinv(.975,df)*se,p,NaN,NaN};
% Between subjects
kBetween = isfinite(S5.eda_obs)&isfinite(S5.pupil_obs); ax = S5.eda_obs(kBetween)-S5.eda_null(kBetween); ay = S5.pupil_obs(kBetween)-S5.pupil_null(kBetween);
[r,p] = corr(ax,ay,'Type','Spearman'); z = atanh(r); se = 1.06/sqrt(sum(kBetween)-3);
rows(end+1,:) = {'Q2','Between subjects: mean EDA vs mean pupil response (Spearman)',false,sum(kBetween),r,tanh(z-1.96*se),tanh(z+1.96*se),p,NaN,NaN};
% Secondary gaze
for g = {'sac_w','disp_w'}
    X = M(isfinite(M.eda_z)&isfinite(M.(g{1}))&isfinite(M.log_audio_w)&isfinite(M.ici_z),:);
    mg = fitlme(X,sprintf('eda_z ~ %s*haptic + log_audio_w + time_z + ici_z + (1+%s|subj)',g{1},g{1}),'FitMethod','REML');
    [b,se,p,df] = local_term(mg,g{1}); rows(end+1,:) = {'Q2 secondary',['Mixed model: ' g{1} ' on EDA (NHF)'],false,numel(unique(X.subj)),b,b-tinv(.975,df)*se,b+tinv(.975,df)*se,p,NaN,NaN}; %#ok<AGROW>
    [b,se,p,df] = local_term(mg,[g{1} ':haptic']); rows(end+1,:) = {'Q2 secondary',['Mixed model: group difference, ' g{1}],false,numel(unique(X.subj)),b,b-tinv(.975,df)*se,b+tinv(.975,df)*se,p,NaN,NaN}; %#ok<AGROW>
end
%% Q3. Group contrasts in Test3 and in the Test2 to Test3 change
hf = S5.haptic;
for m = 1:4
    d = S5.([ms{m,1} '_obs'])-S5.([ms{m,1} '_null']); rows(end+1,:) = [{'Q3',['HF off - NHF on: ' ms{m,2}],m<=2}, local_group(d,hf)]; %#ok<AGROW>
end
rows(end+1,:) = [{'Q3','HF off - NHF on: EDA-pupil r, observed minus shifted',true}, local_group(S8.r_obs-S8.r_null,S8.haptic)];
rows(end+1,:) = [{'Q3','HF off - NHF on: collision rate (per min), all subjects',true}, local_group(S3.n_events./(S3.dur_s/60),S3.haptic)];
% Change from Test2, using the same pipeline. s16N is removed because of its Test2 detection artifact.
[~,ia,ib] = intersect(string(S3.subject),string(S2.subject)); A3 = S3(ia,:); A2 = S2(ib,:);
keep = A3.n_events>=5&A2.n_events>=5&~strcmp(A3.subject,'subject_s16N');
for m = 1:2
    d = (A3.([ms{m,1} '_obs'])-A3.([ms{m,1} '_null']))-(A2.([ms{m,1} '_obs'])-A2.([ms{m,1} '_null']));
    rows(end+1,:) = [{'Q3',['Test3 minus Test2, HF - NHF: ' ms{m,2}],true}, local_group(d(keep),A3.haptic(keep))]; %#ok<AGROW>
end
%% Q4. Impact strength and time on task
for o = {'eda_z','pupil_z'}
    X = M(isfinite(M.(o{1}))&isfinite(M.log_audio_w),:);
    m4 = fitlme(X,sprintf('%s ~ log_audio_w*haptic + time_z*haptic + (1+log_audio_w+time_z|subj)',o{1}),'FitMethod','REML');
    for tn = {'log_audio_w','log_audio_w:haptic','time_z','haptic:time_z'}
        [b,se,p,df] = local_term(m4,tn{1}); rows(end+1,:) = {'Q4',[o{1} ': ' tn{1}],true,numel(unique(X.subj)),b,b-tinv(.975,df)*se,b+tinv(.975,df)*se,p,NaN,NaN}; %#ok<AGROW>
    end
end
R = cell2table(rows,'VariableNames',{'question','test','primary','n','estimate','lo','hi','p','effect','BF01'});
R.p_fdr = nan(height(R),1); R.p_fdr(R.primary) = local_bh(R.p(R.primary));
writetable(R,fullfile(out_dir,'results_primary.csv'));
fprintf('Saved primary\n');

%% Group-specific chance tests, descriptive
rg = {};
for g = [false true]
    for m = 1:4
        d = S5.([ms{m,1} '_obs'])-S5.([ms{m,1} '_null']); d = d(S5.haptic==g&isfinite(d)); [est,lo,hi,p,dz] = local_onesample(d);
        rg(end+1,:) = {local_lbl(g),ms{m,2},numel(d),est,lo,hi,p,dz}; %#ok<AGROW>
    end
    d = S8.r_obs-S8.r_null; d = d(S8.haptic==g); [est,lo,hi,p,dz] = local_onesample(d); rg(end+1,:) = {local_lbl(g),'EDA-pupil r, observed minus shifted',numel(d),est,lo,hi,p,dz}; %#ok<AGROW>
end
writetable(cell2table(rg,'VariableNames',{'group','measure','n','estimate','lo','hi','p','dz'}),fullfile(out_dir,'results_by_group.csv'));

%% Sensitivity
sens = {};
short = S3.dur_s<170; sub = S3(~short&S3.n_events>=8&isfinite(S3.r_obs),:);
[est,lo,hi,p] = local_onesample(sub.r_obs-sub.r_null); sens(end+1,:) = {'Full-length windows only: r minus shifted',height(sub),est,lo,hi,p};
s5 = S3(~short&S3.n_events>=5,:);
for m = 1:2, d = s5.([ms{m,1} '_obs'])-s5.([ms{m,1} '_null']); d = d(isfinite(d)); [est,lo,hi,p] = local_onesample(d); sens(end+1,:) = {['Full-length windows only: ' ms{m,2}],numel(d),est,lo,hi,p}; end %#ok<AGROW>
ME.eda_rank = local_rankz(ME.eda_resp,ME.subj);
mr = fitlme(ME,'eda_rank ~ pupil_w*haptic + log_audio_w + time_z + ici_z + base_w + (1+pupil_w|subj)','FitMethod','REML');
[b,se,p,df] = local_term(mr,'pupil_w'); sens(end+1,:) = {'Rank-transformed EDA: pupil slope',numel(unique(ME.subj)),b,b-tinv(.975,df)*se,b+tinv(.975,df)*se,p};
[b,se,p,df] = local_term(mr,'pupil_w:haptic'); sens(end+1,:) = {'Rank-transformed EDA: group difference',numel(unique(ME.subj)),b,b-tinv(.975,df)*se,b+tinv(.975,df)*se,p};
Iso = ME(ME.ici_prev>=5,:);
mi = fitlme(Iso,'eda_z ~ pupil_w*haptic + log_audio_w + time_z + base_w + (1+pupil_w|subj)','FitMethod','REML');
[b,se,p,df] = local_term(mi,'pupil_w'); sens(end+1,:) = {'Isolated collisions (previous at least 5 s): pupil slope',numel(unique(Iso.subj)),b,b-tinv(.975,df)*se,b+tinv(.975,df)*se,p};
[b,se,p,df] = local_term(mi,'pupil_w:haptic'); sens(end+1,:) = {'Isolated collisions: group difference',numel(unique(Iso.subj)),b,b-tinv(.975,df)*se,b+tinv(.975,df)*se,p};
Nd = M(isfinite(M.nidaq_w)&isfinite(M.eda_z)&isfinite(M.pupil_w)&isfinite(M.ici_z)&isfinite(M.base_w),:);
mn = fitlme(Nd,'eda_z ~ pupil_w*haptic + nidaq_w + time_z + ici_z + base_w + (1+pupil_w|subj)','FitMethod','REML');
[b,se,p,df] = local_term(mn,'pupil_w'); sens(end+1,:) = {'NIDAQ intensity: pupil slope',numel(unique(Nd.subj)),b,b-tinv(.975,df)*se,b+tinv(.975,df)*se,p};
[b,se,p,df] = local_term(mn,'nidaq_w'); sens(end+1,:) = {'NIDAQ intensity: intensity on EDA',numel(unique(Nd.subj)),b,b-tinv(.975,df)*se,b+tinv(.975,df)*se,p};
writetable(cell2table(sens,'VariableNames',{'check','n','estimate','lo','hi','p'}),fullfile(out_dir,'results_sensitivity.csv'));

%% FIR time courses, cluster-based sign-flip tests
CN = [64 96 179]/255; CH = [139 82 168]/255;
[KEm,he] = local_kernels(KE,'Test3'); [KPm,hp] = local_kernels(KP,'Test3');
tE = BE+0.25; tP = BP+0.25;
cl = {};
for sig = {{'EDA phasic',KEm,he,tE},{'Pupil',KPm,hp,tP}}
    nm = sig{1}{1}; K = sig{1}{2}; h = sig{1}{3}; t_ = sig{1}{4}; k = all(isfinite(K),2); K = K(k,:); h = h(k);
    [cs,ps] = local_cluster(K,false(size(h)),t_,0); for c = 1:numel(ps), cl(end+1,:) = {nm,'All vs pre-collision',size(K,1),cs(c,1),cs(c,2),ps(c)}; end %#ok<AGROW>
    [cs,ps] = local_cluster(K,h,t_,1); for c = 1:numel(ps), cl(end+1,:) = {nm,'HF off vs NHF on',size(K,1),cs(c,1),cs(c,2),ps(c)}; end %#ok<AGROW>
end
if isempty(cl), cl = {'none','none',0,NaN,NaN,NaN}; end
writetable(cell2table(cl,'VariableNames',{'signal','contrast','n','t_start','t_end','p_cluster'}),fullfile(out_dir,'results_fir_clusters.csv'));

fig = figure('Position',[100 100 1100 420]);
subplot(1,2,1); hold on; local_band(tE,KEm(he==0,:),CN,'NHF, feedback on'); local_band(tE,KEm(he==1,:),CH,'HF, feedback off'); xline(0,'k--','HandleVisibility','off'); yline(0,'k:','HandleVisibility','off');
xlabel('Time from collision (s)'); ylabel('Phasic EDA (\muS)'); title('EDA, overlap-corrected'); legend('Location','best'); grid on; box on;
subplot(1,2,2); hold on; local_band(tP,KPm(hp==0,:),CN,'NHF, feedback on'); local_band(tP,KPm(hp==1,:),CH,'HF, feedback off'); xline(0,'k--','HandleVisibility','off'); yline(0,'k:','HandleVisibility','off');
xlabel('Time from collision (s)'); ylabel('Pupil (mm)'); title('Pupil, overlap-corrected'); legend('Location','best'); grid on; box on;
sgtitle('Test3: responses to collisions (FIR, mean \pm 95% CI across subjects)','FontWeight','bold');
exportgraphics(fig,fullfile(fig_dir,'test3_fir_time_courses.png'),'Resolution',180);

fig = figure('Position',[100 100 900 420]);
subplot(1,2,1); hold on; [~,o] = sort(S8.r_obs-S8.r_null); dd = S8.r_obs-S8.r_null;
for i = 1:height(S8), c = CN; if S8.haptic(o(i)), c = CH; end; plot(i,dd(o(i)),'o','MarkerFaceColor',c,'MarkerEdgeColor',c); end
yline(0,'k-'); ylabel('r observed - r shifted times'); xlabel('Subject, sorted'); title('Within-subject EDA-pupil coupling'); grid on; box on;
subplot(1,2,2); hold on; scatter(ax(hf(kBetween)==0),ay(hf(kBetween)==0),40,CN,'filled'); scatter(ax(hf(kBetween)==1),ay(hf(kBetween)==1),40,CH,'filled');
xline(0,'k:'); yline(0,'k:'); xlabel('EDA response above chance'); ylabel('Pupil response above chance (mm)'); title('Between subjects'); legend({'NHF on','HF off'},'Location','best'); grid on; box on;
exportgraphics(fig,fullfile(fig_dir,'test3_eda_pupil_coupling.png'),'Resolution',180);
save(fullfile(out_dir,'results.mat'),'R','S3','S2');
fprintf('STATS_DONE\n');

function M = local_prep(T)
    M = T; M.subj = categorical(string(M.subject)); [g,~] = findgroups(string(M.subject));
    M.eda_z = local_w(M.eda_resp,g,true); M.pupil_z = local_w(M.pupil_resp,g,true);
    M.pupil_w = M.pupil_z; M.base_w = local_w(M.pupil_base,g,true); M.sac_w = local_w(M.sac_diff,g,true); M.disp_w = local_w(M.disp_diff,g,true);
    la = log(M.audio_peak); la(~isfinite(la)) = NaN; M.log_audio_w = local_w(la,g,true);
    ln = log(M.nidaq_peak_g); ln(~isfinite(ln)) = NaN; M.nidaq_w = local_w(ln,g,true);
    M.time_z = local_w(M.time_in_task,g,true);
    li = log(M.ici_prev); M.ici_z = local_w(li,g,true);
end
function z = local_w(x,g,scale)
    z = nan(size(x));
    for k = unique(g)'
        i = g==k; v = x(i); m = mean(v,'omitnan'); s = std(v,'omitnan');
        if scale, if isfinite(s)&&s>0, z(i) = (v-m)/s; end; else, z(i) = v-m; end
    end
end
function r = local_rankz(x,subj)
    r = nan(size(x)); [g,~] = findgroups(subj);
    for k = unique(g)', i = g==k; v = tiedrank(x(i)); r(i) = (v-mean(v))/std(v); end
end
function [est,lo,hi,p,dz] = local_onesample(d)
    d = d(isfinite(d)); n = numel(d); est = mean(d); se = std(d)/sqrt(n); t = tinv(.975,n-1); lo = est-t*se; hi = est+t*se; dz = est/std(d);
    nP = 20000; s = sign(rand(n,nP)-.5); nullT = mean(s.*d,1)./(std(s.*d,0,1)/sqrt(n)); obs = est/se; p = (sum(abs(nullT)>=abs(obs))+1)/(nP+1);
end
function r = local_group(d,h)
    a = d(~h&isfinite(d)); b = d(h&isfinite(d)); n1 = numel(a); n2 = numel(b); se = sqrt(var(a)/n1+var(b)/n2); df = se^4/((var(a)/n1)^2/(n1-1)+(var(b)/n2)^2/(n2-1)); dd = mean(b)-mean(a);
    [~,p] = ttest2(b,a,'Vartype','unequal'); sp = sqrt(((n1-1)*var(a)+(n2-1)*var(b))/(n1+n2-2)); g = (1-3/(4*(n1+n2-2)-1))*dd/sp; t = dd/(sp*sqrt(1/n1+1/n2));
    r = {n1+n2,dd,dd-tinv(.975,df)*se,dd+tinv(.975,df)*se,p,g,1/local_bf(t,n1,n2)};
end
function bf = local_bf(t,n1,n2)
    n = n1*n2/(n1+n2); v = n1+n2-2; f = @(g) (1+n*.5*g).^(-1/2).*(1+t^2./((1+n*.5*g)*v)).^(-(v+1)/2).*(2*pi)^(-1/2).*g.^(-3/2).*exp(-1./(2*g));
    bf = integral(f,0,Inf)/(1+t^2/v)^(-(v+1)/2);
end
function [b,se,p,df] = local_term(m,name)
    [~,~,st] = fixedEffects(m,'DFMethod','satterthwaite'); want = sort(strsplit(name,':')); ix = cellfun(@(n) isequal(sort(strsplit(n,':')),want),st.Name);
    if ~any(ix), error('Term %s not found.',name); end
    b = st.Estimate(ix); se = st.SE(ix); p = st.pValue(ix); df = st.DF(ix);
end
function [K,h] = local_kernels(C,ph)
    i = strcmp(C(:,2),ph); K = cell2mat(C(i,3)); h = endsWith(string(C(i,1)),'H');
end
function [cs,ps] = local_cluster(K,h,t_,mode)
    % mode 0: sign flip against zero; mode 1: label permutation for group difference. Cluster-forming p < .05, cluster mass.
    n = size(K,1); nP = 5000; tv = local_t(K,h,mode); df = n-1-mode; th = tinv(.975,df); [cl,ms] = local_clusters(tv,th);
    nullM = zeros(nP,1);
    for q = 1:nP
        if mode==0, tq = local_t(K.*sign(rand(n,1)-.5),h,0); else, tq = local_t(K,h(randperm(n)),1); end
        [~,mq] = local_clusters(tq,th); if ~isempty(mq), nullM(q) = max(abs(mq)); end
    end
    cs = zeros(numel(ms),2); ps = zeros(numel(ms),1);
    for c = 1:numel(ms), cs(c,:) = [t_(cl(c,1)) t_(cl(c,2))]; ps(c) = (sum(nullM>=abs(ms(c)))+1)/(nP+1); end
end
function tv = local_t(K,h,mode)
    if mode==0, tv = mean(K,1)./(std(K,0,1)/sqrt(size(K,1)));
    else, a = K(~h,:); b = K(h,:); n1 = size(a,1); n2 = size(b,1); sp = sqrt(((n1-1)*var(a,0,1)+(n2-1)*var(b,0,1))/(n1+n2-2)); tv = (mean(b,1)-mean(a,1))./(sp*sqrt(1/n1+1/n2)); end
end
function [cl,ms] = local_clusters(tv,th)
    cl = zeros(0,2); ms = [];
    for sgn = [1 -1]
        d = diff([0 sgn*tv>th 0]); st = find(d==1); en = find(d==-1)-1;
        for k = 1:numel(st), cl(end+1,:) = [st(k) en(k)]; ms(end+1,1) = sum(tv(st(k):en(k))); end %#ok<AGROW>
    end
end
function local_band(t_,K,c,lab)
    K = K(all(isfinite(K),2),:); m = mean(K,1); e = tinv(.975,size(K,1)-1)*std(K,0,1)/sqrt(size(K,1));
    fill([t_ fliplr(t_)],[m+e fliplr(m-e)],c,'FaceAlpha',.15,'EdgeColor','none','HandleVisibility','off');
    plot(t_,m,'-','Color',c,'LineWidth',2,'DisplayName',sprintf('%s (n=%d)',lab,size(K,1)));
end
function s = local_lbl(g), if g, s = 'HF, feedback off'; else, s = 'NHF, feedback on'; end, end
function q = local_bh(p)
    q = nan(size(p)); v = find(isfinite(p)); [ps,ix] = sort(p(v)); m = numel(ps); a = ps.*m./(1:m)'; a = min(cummin(a,'reverse'),1); q(v(ix)) = a;
end
