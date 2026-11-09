%% claude_test3_collision_04_controls.m
% Post hoc controls, see Amendment 3 in claude_test3_collision_plan.md.
% A. Injection and recovery in Test3. B. Isolated collisions vs collision-free moments across phases. C. Trial-start reference.
% Writes ONLY to <output_root>/Claude_outputs/test3_collision. Nothing goes into subject folders.

clear; clc; cfg = config(); rng(20261105);
out_dir = fullfile(cfg.output_root,'Claude_outputs','test3_collision');
L = load(fullfile(out_dir,'detection.mat')); EV = L.EV; QC = L.QC;
subs = cfg.all_subjects; DT = 0.1;
AMP_E = [0 0.02 0.05 0.1]; AMP_P = [0 0.02 0.05 0.1]; rowsA = {};

%% A. Injection and recovery
hE = local_bateman(DT); hP = local_hoeks(DT);
inj = cell(numel(subs),1);
for si = 1:numel(subs)
    s = subs{si}; d = fullfile(cfg.data_root,s,'Test3');
    [a,b] = safe_trial_window(fullfile(d,'events.mat'));
    tev = EV.t(strcmp(EV.subject,s)&strcmp(EV.phase,'Test3')); tev = tev(tev>=a&tev<=b);
    if numel(tev)<5, continue; end
    tg = (floor(a*10)/10-3:DT:ceil(b*10)/10+11)'; evI = round((tev-tg(1))/DT)+1; valid = find(tg>=a&tg<=b);
    imp = zeros(size(tg)); imp(evI) = 1;
    train = @(h) conv(imp,h,'full');
    trE = train(hE); trE = trE(1:numel(tg)); trP = train(hP); trP = trP(1:numel(tg));
    res = nan(numel(AMP_E),4);
    for k = 1:numel(AMP_E)
        [~,dr,okE] = local_eda_inj(fullfile(d,'gsr.mat'),tg,cfg,AMP_E(k)*trE);
        E_ = local_future_sum(dr,okE,10,40)*DT; res(k,1) = mean(E_(evI),'omitnan'); res(k,2) = local_null(E_,evI,valid);
    end
    [pup,pOK] = local_eye_only(fullfile(d,'eye.mat'),tg);
    for k = 1:numel(AMP_P)
        [P_,~] = local_pupil_resp(pup+AMP_P(k)*trP,pOK,DT); res(k,3) = mean(P_(evI),'omitnan'); res(k,4) = local_null(P_,evI,valid);
    end
    inj{si} = res; fprintf('inject %s done\n',s);
end
R = cat(3,inj{~cellfun(@isempty,inj)});
for k = 1:numel(AMP_E)
    dE = squeeze(R(k,1,:)-R(k,2,:)); dP = squeeze(R(k,3,:)-R(k,4,:));
    [e,l,h,p,dz,n] = local_one(dE); rowsA(end+1,:) = {'EDA',AMP_E(k),n,e,l,h,p,dz}; %#ok<AGROW>
    [e,l,h,p,dz,n] = local_one(dP); rowsA(end+1,:) = {'Pupil',AMP_P(k),n,e,l,h,p,dz}; %#ok<AGROW>
end
writetable(cell2table(rowsA,'VariableNames',{'signal','injected','n','recovered','lo','hi','p','dz'}),fullfile(out_dir,'control_injection.csv'));
fprintf('A_DONE\n');

%% B and C. Raw signals across phases
phases = {'Test3','Test2','Baseline2','level_L1','level_L2','level_L3','level_L4','level_L5'};
acc = {};
for si = 1:numel(subs)
    s = subs{si};
    for pi_ = 1:numel(phases)
        ph = phases{pi_}; if strcmp(s,'subject_s16N')&&~strcmp(ph,'Test3'), continue; end
        if startsWith(ph,'Test'), dirs = {fullfile(cfg.data_root,s,ph)};
        elseif startsWith(ph,'Baseline'), dirs = arrayfun(@(k) fullfile(cfg.data_root,s,ph,sprintf('Level%d',k)),1:5,'UniformOutput',false);
        else, dirs = arrayfun(@(k) fullfile(cfg.data_root,s,ph,sprintf('rep_%02d',k)),1:10,'UniformOutput',false); end
        for di = 1:numel(dirs)
            d = dirs{di}; if ~isfolder(d)&&isfolder([d '_R']), d = [d '_R']; end
            if ~isfile(fullfile(d,'events.mat')), continue; end
            try
                [a,b] = safe_trial_window(fullfile(d,'events.mat')); if isnan(a)||isnan(b)||b-a<3, continue; end
                if strcmp(ph,'Test3'), c = EV.t(strcmp(EV.subject,s)&strcmp(EV.phase,'Test3'));
                elseif isfile(fullfile(d,'collision_results.mat')), C = load(fullfile(d,'collision_results.mat')); c = C.results.collision_rel(:);
                else, continue; end
                c = c(c>=a&c<=b);
                tg = (floor(a*10)/10-3:DT:ceil(b*10)/10+7)';
                sc = local_sc(fullfile(d,'gsr.mat'),tg);
                [pup,pOK] = local_eye_only(fullfile(d,'eye.mat'),tg);
                [Pr,~] = local_pupil_resp(pup,pOK,DT); Er = local_sc_resp(sc,DT);
                % Isolated collisions
                if numel(c)>=1
                    gapsL = [inf; diff(c)]; gapsR = [diff(c); inf]; iso = c(gapsL>6&gapsR>6&c>=a+1&c<=b-5);
                else, iso = []; end
                % Collision-free moments
                cand = (a+1:0.5:b-5)'; if ~isempty(c), cand = cand(arrayfun(@(u) all(abs(u-c)>=6),cand)); end
                gi = @(t_) round((t_-tg(1))/DT)+1;
                acc(end+1,:) = {s,ph,numel(iso),sum(Er(gi(iso)),'omitnan'),sum(isfinite(Er(gi(iso)))),sum(Pr(gi(iso)),'omitnan'),sum(isfinite(Pr(gi(iso)))), ...
                    sum(Er(gi(cand)),'omitnan'),sum(isfinite(Er(gi(cand)))),sum(Pr(gi(cand)),'omitnan'),sum(isfinite(Pr(gi(cand)))),Er(gi(a)),Pr(gi(a))}; %#ok<AGROW>
            catch ME
                fprintf('skip %s %s: %s\n',s,d(end-10:end),ME.message);
            end
        end
    end
    fprintf('raw %s done\n',s);
end
A = cell2table(acc,'VariableNames',{'subject','phase','n_iso','e_iso_sum','e_iso_n','p_iso_sum','p_iso_n','e_free_sum','e_free_n','p_free_sum','p_free_n','e_start','p_start'});
writetable(A,fullfile(out_dir,'control_raw_trials.csv'));
rowsB = {};
grp = {'Test3',{'Test3'};'Test2',{'Test2'};'Baseline2',{'Baseline2'};'Training all',{'level_L1','level_L2','level_L3','level_L4','level_L5'};'L1',{'level_L1'};'L3',{'level_L3'};'L5',{'level_L5'}};
for g = 1:size(grp,1)
    X = A(ismember(A.phase,grp{g,2}),:); [gg,us] = findgroups(string(X.subject));
    e_i = splitapply(@sum,X.e_iso_sum,gg)./splitapply(@sum,X.e_iso_n,gg); e_f = splitapply(@sum,X.e_free_sum,gg)./splitapply(@sum,X.e_free_n,gg);
    p_i = splitapply(@sum,X.p_iso_sum,gg)./splitapply(@sum,X.p_iso_n,gg); p_f = splitapply(@sum,X.p_free_sum,gg)./splitapply(@sum,X.p_free_n,gg);
    nIso = splitapply(@sum,X.e_iso_n,gg); nP = splitapply(@sum,X.p_iso_n,gg);
    es = splitapply(@(v) mean(v,'omitnan'),X.e_start,gg); ps = splitapply(@(v) mean(v,'omitnan'),X.p_start,gg);
    h = endsWith(us,'H');
    for m = {{'EDA iso minus free',e_i-e_f,nIso>=3},{'Pupil iso minus free',p_i-p_f,nP>=3},{'EDA at trial start',es,true(size(es))},{'Pupil at trial start',ps,true(size(ps))}}
        v = m{1}{2}; v(~m{1}{3}) = NaN; [e,l,hh,p,dz,n] = local_one(v);
        a0 = v(~h&isfinite(v)); b0 = v(h&isfinite(v)); pg = NaN; dg = NaN; if numel(a0)>2&&numel(b0)>2, [~,pg] = ttest2(b0,a0,'Vartype','unequal'); dg = mean(b0)-mean(a0); end
        rowsB(end+1,:) = {grp{g,1},m{1}{1},n,e,l,hh,p,dz,dg,pg}; %#ok<AGROW>
    end
end
writetable(cell2table(rowsB,'VariableNames',{'phase','contrast','n','estimate','lo','hi','p','dz','group_diff_H_minus_N','p_group'}),fullfile(out_dir,'control_raw_summary.csv'));
fprintf('CONTROLS_DONE\n');

function h = local_bateman(DT)
    t_ = (0:DT:20)'; h = exp(-t_/2)-exp(-t_/0.75); h = h/max(h);
end
function h = local_hoeks(DT)
    t_ = (0:DT:4)'; h = t_.^10.1.*exp(-10.1*t_/0.93); h = h/max(h);
end
function [phasic,driver,ok] = local_eda_inj(p,tg,cfg,add)
    phasic = nan(size(tg)); driver = phasic; ok = false(size(tg));
    if ~isfile(p), return; end
    L = load(p,'GSR'); t = L.GSR.time_rel(:); R = L.GSR.GSR_ohm(:); k = isfinite(R)&R>0&isfinite(t); t = t(k); us = 1e3./R(k);
    [t,u] = unique(t); us = us(u); if numel(t)<50, return; end
    in = tg>=t(1)&tg<=t(end); g = tg(in); y = interp1(t,us,g,'linear')+add(in);
    idx = discretize(g,[t; inf]); gapR = nan(size(g)); h = idx<numel(t); gapR(h) = t(idx(h)+1)-t(idx(h)); bad = gapR>1;
    [bb,aa] = butter(4,3/(cfg.fs_target/2),'low'); y = max(filtfilt(bb,aa,y),1e-6);
    [r,dr] = cvxEDA(y(:),1/cfg.fs_target); phasic(in) = r(:); driver(in) = dr(:); ok(in) = ~bad; phasic(~ok) = NaN; driver(~ok) = NaN;
end
function sc = local_sc(p,tg)
    sc = nan(size(tg)); if ~isfile(p), return; end
    L = load(p,'GSR'); t = L.GSR.time_rel(:); R = L.GSR.GSR_ohm(:); k = isfinite(R)&R>0&isfinite(t); t = t(k); us = 1e3./R(k); [t,u] = unique(t); us = us(u); if numel(t)<20, return; end
    in = tg>=t(1)&tg<=t(end); y = interp1(t,us,tg(in),'linear'); idx = discretize(tg(in),[t; inf]); gapR = nan(size(y)); h = idx<numel(t); gapR(h) = t(idx(h)+1)-t(idx(h)); y(gapR>1) = NaN; sc(in) = y;
end
function E_ = local_sc_resp(sc,DT)
    n = numel(sc); E_ = nan(n,1); i0 = round(1/DT); i1 = round(5/DT); b0 = round(1/DT);
    for k = b0+1:n-i1
        B = sc(k-b0:k-1); R = sc(k+i0:k+i1-1); if mean(isfinite(B))>=.5&&mean(isfinite(R))>=.5, E_(k) = mean(R,'omitnan')-mean(B,'omitnan'); end
    end
end
function [pup,ok] = local_eye_only(p,tg)
    [pup,ok] = local_eye(p,tg);
end
function m = local_null(x,evI,valid)
    lo = valid(1); nV = numel(valid); v = nan(200,1); minS = 100; if nV<=2*minS, m = NaN; return; end
    for k = 1:200, id = lo+mod(evI-lo+minS+randi(nV-2*minS),nV); v(k) = mean(x(id),'omitnan'); end
    m = mean(v,'omitnan');
end
function [est,lo,hi,p,dz,n] = local_one(d)
    d = d(isfinite(d)); n = numel(d); est = mean(d); se = std(d)/sqrt(n); t = tinv(.975,n-1); lo = est-t*se; hi = est+t*se; dz = est/std(d); [~,p] = ttest(d);
end
function [pup,ok,sacT,gx,gy] = local_eye(p,tg)
    L = load(p,'EYE'); E = L.EYE; c = E.channel_names; t = E.time_rel(:); D = E.data; [t,o] = sort(t); D = D(o,:);
    col = @(n) D(:,strcmp(c,n)); x = col('x'); y = col('y'); bl = col('blink')==1; pl = col('pupil_diameter_left'); pr = col('pupil_diameter_right');
    dup = [false; diff(x)==0&diff(y)==0]; t = t(~dup); x = x(~dup); y = y(~dup); bl = bl(~dup); pl = pl(~dup); pr = pr(~dup);
    pp = mean([pl pr],2,'omitnan'); pp(pp<2|pp>8) = NaN;
    % 100 ms margin around blinks
    bi = find(bl); mask = bl; for k = bi', mask(t>=t(k)-0.1&t<=t(k)+0.1) = true; end
    pp(mask) = NaN;
    edges = [tg-0.05; tg(end)+0.05]; bin = discretize(t,edges); pup = nan(size(tg)); gx = pup; gy = pup;
    v = ~isnan(bin)&isfinite(pp); if any(v), m = accumarray(bin(v),pp(v),[numel(tg) 1],@median,NaN); pup = m; end
    v = ~isnan(bin)&~bl&isfinite(x)&isfinite(y);
    if any(v), gx = accumarray(bin(v),x(v),[numel(tg) 1],@median,NaN); gy = accumarray(bin(v),y(v),[numel(tg) 1],@median,NaN); end
    % Median-based dilation-speed rule (Kret & Sjak-Shie, 2019)
    d1 = [NaN; abs(diff(pup))/0.1]; d2 = [abs(diff(pup))/0.1; NaN]; sp = max(d1,d2);
    th = median(sp,'omitnan')+16*mad(sp,1); pup(sp>th) = NaN;
    good = isfinite(pup); ok = good;
    if sum(good)<20, pup(:) = NaN; ok(:) = false; sacT = []; return; end
    filled = interp1(tg(good),pup(good),tg,'linear','extrap');
    [st,en] = local_runs(~good); for k = 1:numel(st), if (en(k)-st(k)+1)*0.1<=0.25, ok(st(k):en(k)) = true; end; end
    [bb,aa] = butter(3,4/5,'low'); fil = filtfilt(bb,aa,filled); pup = fil; pup(~ok) = NaN;
    sacT = local_sac(t,x,y,bl);
end
function st0 = local_sac(t,x,y,bl)
    % Corrected detector: Engbert & Kliegl on a uniform 200 Hz grid, floor 30 deg/s at 15.5 px/deg
    DT = 0.005; gd = ~bl&isfinite(x)&isfinite(y); tv = t(gd); xv = x(gd); yv = y(gd); tu = (tv(1):DT:tv(end))';
    ix = interp1(tv,xv,tu); iy = interp1(tv,yv,tu); pi0 = discretize(tu,[tv; inf]); okg = false(size(tu)); h = ~isnan(pi0)&pi0<numel(tv);
    okg(h) = (tv(pi0(h)+1)-tv(pi0(h)))<=0.02; ix(~okg) = NaN; iy(~okg) = NaN;
    kk = [1 1 0 -1 -1]/(6*DT); vx = conv(ix,kk,'same'); vy = conv(iy,kk,'same'); vx([1 2 end-1 end]) = NaN; vy([1 2 end-1 end]) = NaN;
    sx = sqrt(max(median(vx.^2,'omitnan')-median(vx,'omitnan')^2,0)); sy = sqrt(max(median(vy.^2,'omitnan')-median(vy,'omitnan')^2,0));
    rx = max(6*sx,465); ry = max(6*sy,465); ab = (vx./rx).^2+(vy./ry).^2>1; ab(isnan(vx)|isnan(vy)) = false;
    [s1,e1] = local_runs(ab);
    if numel(s1)>1, g = (s1(2:end)-e1(1:end-1)-1)*DT<0.02; for k = find(g(:))', ab(e1(k):s1(k+1)) = true; end; [s1,e1] = local_runs(ab); end
    s1 = s1((e1-s1+1)*DT>=0.015); st0 = tu(s1);
end
function E_ = local_future_sum(x,ok,i0,i1)
    % Sum of x over samples t+i0 ... t+i1-1. NaN if any sample in that span is invalid.
    x2 = x; x2(~ok|~isfinite(x)) = 0; c = [0; cumsum(x2)]; b = [0; cumsum(~ok|~isfinite(x))]; n = numel(x); E_ = nan(n,1);
    for k = 1:n-i1
        if b(k+i1)-b(k+i0)==0, E_(k) = c(k+i1)-c(k+i0); end
    end
end
function [P_,B_] = local_pupil_resp(p,ok,DT)
    n = numel(p); P_ = nan(n,1); B_ = P_; i1 = round(0.5/DT); i2 = round(2.5/DT); b0 = round(0.5/DT); p2 = p; p2(~ok) = NaN;
    for k = b0+1:n-i2
        B = p2(k-b0:k-1); R = p2(k+i1:k+i2-1);
        if mean(isfinite(B))>=0.5&&mean(isfinite(R))>=0.5, B_(k) = mean(B,'omitnan'); P_(k) = mean(R,'omitnan')-B_(k); end
    end
end
function S_ = local_sac_diff(sac,tg)
    S_ = nan(size(tg)); if isempty(sac), return; end
    for k = 1:numel(tg), S_(k) = sum(sac>=tg(k)&sac<tg(k)+1)-sum(sac>=tg(k)-1&sac<tg(k)); end
end
function G_ = local_disp_diff(x,y,DT)
    n = numel(x); G_ = nan(n,1); w = round(2/DT);
    for k = w+1:n-w
        a = [x(k-w:k-1) y(k-w:k-1)]; b = [x(k:k+w-1) y(k:k+w-1)];
        if mean(all(isfinite(a),2))>=0.5&&mean(all(isfinite(b),2))>=0.5
            G_(k) = sqrt(var(b(:,1),'omitnan')+var(b(:,2),'omitnan'))-sqrt(var(a(:,1),'omitnan')+var(a(:,2),'omitnan'));
        end
    end
end
function r = local_spear(a,b)
    k = isfinite(a)&isfinite(b); if sum(k)<8, r = NaN; return; end
    r = corr(tiedrank(a(k)),tiedrank(b(k)));
end
function beta = local_fir(y,ok,tg,tev,B,a,b)
    % FIR deconvolution: overlapping responses share variance across events. Cubic drift terms are included.
    w = tg>=a&tg<=b&ok&isfinite(y); nB = numel(B); X = zeros(numel(tg),nB);
    for j = 1:nB
        for e = tev(:)'
            X(tg>=e+B(j)&tg<e+B(j)+0.5,j) = 1;
        end
    end
    tz = (tg-mean(tg(w)))/std(tg(w)); D = [ones(size(tg)) tz tz.^2 tz.^3];
    A = [X D]; A = A(w,:); yy = y(w);
    if rank(A)<size(A,2), bAll = pinv(A)*yy; else, bAll = A\yy; end
    beta = bAll(1:nB)'; pre = B<0; beta = beta-mean(beta(pre));   % referenced to the pre-collision bins
end
function [st,en] = local_runs(b)
    d = diff([0; b(:); 0]); st = find(d==1); en = find(d==-1)-1;
end
