%% claude_test3_collision_02_extract.m
% Step 2. Builds EDA, pupil and gaze signals for Test2 and Test3, event-level responses, shifted-time nulls and FIR
% deconvolved time courses. See claude_test3_collision_plan.md. Requires claude_test3_collision_01_detect.m.
% Writes ONLY to <output_root>/Claude_outputs/test3_collision. Nothing goes into subject folders.

clear; clc; cfg = config(); rng(20261105);
out_dir = fullfile(cfg.output_root,'Claude_outputs','test3_collision');
L = load(fullfile(out_dir,'detection.mat')); EV = L.EV; QC = L.QC;
subs = cfg.all_subjects; NSHIFT = 2000; DT = 0.1;
BE = -2:0.5:9.5; BP = -2:0.5:5.5;   % left bin edges for the FIR terms
evr = {}; sr = {}; KE = {}; KP = {};
for si = 1:numel(subs)
    s = subs{si};
    for ph = {'Test2','Test3'}
        phase = ph{1}; d = fullfile(cfg.data_root,s,phase);
        try
            [a,b] = safe_trial_window(fullfile(d,'events.mat'));
            q = QC(strcmp(QC.subject,s)&strcmp(QC.phase,phase),:);
            ix = strcmp(EV.subject,s)&strcmp(EV.phase,phase);
            tev = EV.t(ix); au = EV.audio_peak(ix); ni = EV.nidaq_peak_g(ix);
            lag = 0; if isfinite(q.xcorr)&&q.xcorr>=0.7&&abs(q.lag_ms)>=50, lag = q.lag_ms/1000; end
            tev = tev-lag;
            tg = (floor(a*10)/10-3:DT:ceil(b*10)/10+11)';    % common 10 Hz grid
            [phasic,driver,edaOK] = local_eda(fullfile(d,'gsr.mat'),tg,cfg);
            [pup,pOK,sacT,gx,gy] = local_eye(fullfile(d,'eye.mat'),tg);
            % Continuous response series, defined at every grid time
            E_ = local_future_sum(driver,edaOK,round(1/DT),round(4/DT))*DT;
            [P_,B_] = local_pupil_resp(pup,pOK,DT);
            S_ = local_sac_diff(sacT,tg);
            G_ = local_disp_diff(gx,gy,DT);
            evIdx = round((tev-tg(1))/DT)+1;
            valid = (1:numel(tg))'; valid = valid(tg>=a&tg<=b); lo = valid(1); hi = valid(end); nV = hi-lo+1;
            ok = tev>=a&tev<=b; evIdx = evIdx(ok); tev = tev(ok); au = au(ok); ni = ni(ok); nE = numel(tev);
            ici = [NaN; diff(tev)];
            for k = 1:nE
                evr(end+1,:) = {s,phase,tev(k),(tev(k)-a),ici(k),au(k),ni(k),E_(evIdx(k)),P_(evIdx(k)),B_(evIdx(k)),S_(evIdx(k)),G_(evIdx(k))}; %#ok<AGROW>
            end
            obs = [mean(E_(evIdx),'omitnan') mean(P_(evIdx),'omitnan') mean(S_(evIdx),'omitnan') mean(G_(evIdx),'omitnan')];
            nullM = nan(NSHIFT,4); nullR = nan(NSHIFT,1); nullRp = nan(NSHIFT,1); rObs = NaN; rObsP = NaN;
            minS = round(10/DT);
            if nE>=1 && nV>2*minS
                for n = 1:NSHIFT
                    sh = minS+randi(nV-2*minS);
                    id = lo+mod(evIdx-lo+sh,nV);
                    nullM(n,:) = [mean(E_(id),'omitnan') mean(P_(id),'omitnan') mean(S_(id),'omitnan') mean(G_(id),'omitnan')];
                    if nE>=8, nullR(n) = local_spear(E_(id),P_(id)); end
                end
                if nE>=8, rObs = local_spear(E_(evIdx),P_(evIdx)); end
            end
            sr(end+1,:) = {s,phase,nE,b-a,mean(edaOK),mean(pOK),sum(isfinite(E_(evIdx))),sum(isfinite(P_(evIdx))),obs(1),obs(2),obs(3),obs(4), ...
                mean(nullM(:,1),'omitnan'),mean(nullM(:,2),'omitnan'),mean(nullM(:,3),'omitnan'),mean(nullM(:,4),'omitnan'), ...
                std(nullM(:,1),'omitnan'),std(nullM(:,2),'omitnan'),rObs,mean(nullR,'omitnan'),std(nullR,'omitnan'),mean(abs(nullR-mean(nullR,'omitnan'))>=abs(rObs-mean(nullR,'omitnan'))),lag}; %#ok<AGROW>
            if nE>=5
                KE(end+1,:) = {s,phase,local_fir(phasic,edaOK,tg,tev,BE,a,b)}; %#ok<AGROW>
                KP(end+1,:) = {s,phase,local_fir(pup,pOK,tg,tev,BP,a,b)}; %#ok<AGROW>
            end
            fprintf('%s %s events %d eda %.2f pupil %.2f\n',s,phase,nE,mean(edaOK),mean(pOK));
        catch ME
            fprintf('FAILED %s %s: %s\n',s,phase,ME.message);
        end
    end
end
T = cell2table(evr,'VariableNames',{'subject','phase','t','time_in_task','ici_prev','audio_peak','nidaq_peak_g','eda_resp','pupil_resp','pupil_base','sac_diff','disp_diff'});
SS = cell2table(sr,'VariableNames',{'subject','phase','n_events','dur_s','eda_valid','pupil_valid','n_eda','n_pupil','eda_obs','pupil_obs','sac_obs','disp_obs','eda_null','pupil_null','sac_null','disp_null','eda_null_sd','pupil_null_sd','r_obs','r_null','r_null_sd','r_p_shift','lag_s'});
writetable(T,fullfile(out_dir,'event_responses.csv')); writetable(SS,fullfile(out_dir,'subject_summary.csv'));
save(fullfile(out_dir,'extracted.mat'),'T','SS','KE','KP','BE','BP');
fprintf('EXTRACT_DONE\n');

function [phasic,driver,ok] = local_eda(p,tg,cfg)
    phasic = nan(size(tg)); driver = phasic; ok = false(size(tg));
    if ~isfile(p), return; end
    L = load(p,'GSR'); t = L.GSR.time_rel(:); R = L.GSR.GSR_ohm(:); k = isfinite(R)&R>0&isfinite(t); t = t(k); us = 1e3./R(k);
    [t,u] = unique(t); us = us(u); if numel(t)<50, return; end
    in = tg>=t(1)&tg<=t(end); g = tg(in);
    y = interp1(t,us,g,'linear');
    % Samples inside gaps over 1 s are masked, not removed, so the whole trial stays usable
    idx = discretize(g,[t; inf]); gapR = nan(size(g)); h = idx<numel(t); gapR(h) = t(idx(h)+1)-t(idx(h));
    bad = gapR>1;
    [bb,aa] = butter(4,3/(cfg.fs_target/2),'low'); y = filtfilt(bb,aa,y); y = max(y,1e-6);
    [r,dr] = cvxEDA(y(:),1/cfg.fs_target);
    phasic(in) = r(:); driver(in) = dr(:); ok(in) = ~bad;
    phasic(~ok) = NaN; driver(~ok) = NaN;
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
