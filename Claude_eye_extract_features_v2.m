%% Claude_eye_extract_features_v2.m
% Recomputes saccade, fixation and spatial-entropy features with a corrected detector.
% Same trial selection as eye_features_v2.mat. Does NOT call eye_preprocess_v2, so it does not
% overwrite any eye_preprocessed_v2.mat. Writes ONLY to <output_root>/Claude_outputs/eye.
%
% Problems in the original detector (eye_preprocess_v2.m):
%  1. Many recordings log each gaze sample twice about 0.1 ms apart. Half of all velocities are then
%     0, so median = MAD = 0, the threshold = 0, and half the samples become "saccades".
%  2. Velocity is an unsmoothed sample-to-sample difference, so at 200 Hz it is dominated by noise.
%  3. No minimum saccade duration and no merging of fragments.
%  4. Fixations are "everything that is not a saccade", so they inherit 1-3.
%  5. Entropy uses a grid scaled to each trial's min/max, so one outlier changes it and overall
%     gaze spread cannot affect it.
%
% Corrected method:
%  - Drop consecutive samples with identical x and y, then interpolate onto a uniform 200 Hz grid
%    across gaps up to 20 ms. Longer gaps and blinks stay invalid.
%  - Engbert & Kliegl (2003): 5-point velocity, median-based noise estimate per axis, lambda = 6,
%    elliptical threshold, with a floor of 30 deg/s.
%  - Saccades last at least 15 ms; gaps under 20 ms are merged.
%  - Fixations are valid intervals of at least 100 ms between saccades and invalid samples.
%  - gaze_entropy_fixed: fixed 100 px grid in scene-camera coordinates.
% ASSUMPTION: 15.5 px/deg (1600 x 1200 px over about 103 x 77 deg). This affects only the floor.
% LIMITATION: Neon gaze is head-referenced, so head movement can contribute to velocity.

clear; clc; cfg = config();
out_dir = fullfile(cfg.output_root,'Claude_outputs','eye'); if ~exist(out_dir,'dir'), mkdir(out_dir); end
L = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T'); V2 = L.T;
keep = isfinite(V2.valid_duration_s) & V2.valid_duration_s > 0;
V2 = V2(keep,:);
n = height(V2);
vars = {'saccade_count','saccade_rate','saccade_peak_deg_s','fixation_count','fixation_rate','fixation_mean_dur', ...
        'gaze_entropy_fixed','valid_s','dup_frac','raw_hz','unique_hz','grid_valid_frac', ...
        'device_saccade_rate','device_fixation_rate','pupil_speed_removed_frac','thr_deg_s'};
A = nan(n,numel(vars));
fails = 0;
for i = 1:n
    s = V2.subject{i}; ph = V2.phase{i}; acq = V2.acquisition{i};
    if strcmp(V2.phase_type{i},'test')
        d = fullfile(cfg.data_root,s,ph);
    else
        d = fullfile(cfg.data_root,s,ph,acq);
        if ~isfolder(d) && isfolder([d '_R']), d = [d '_R']; end
    end
    try
        [a,b] = safe_trial_window(fullfile(d,'events.mat'));
        E = load(fullfile(d,'eye.mat'),'EYE'); E = E.EYE;
        A(i,:) = local_trial(E,a,b);
    catch
        fails = fails + 1;
    end
    if mod(i,500)==0, fprintf('%d/%d\n',i,n); end
end
fprintf('failed trials: %d\n',fails);
idv = {'subject','group','haptic','phase_type','phase','acquisition','level','repetition'};
T = [V2(:,idv), array2table(A,'VariableNames',vars)];
T.saccade_rate_orig = V2.saccade_rate; T.fixation_rate_orig = V2.fixation_rate;
T.fixation_mean_dur_orig = V2.fixation_mean_dur; T.gaze_entropy_orig = V2.gaze_entropy;
save(fullfile(out_dir,'eye_features_claude.mat'),'T');
writetable(T,fullfile(out_dir,'eye_features_claude.csv'));
fprintf('EYE_DONE\n');

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
