%% tss_rate_peak_analysis.m
% Separates force/vibration INTENSITY from trial DURATION, and tests HF vs NHF on each.
% Writes ONLY to <output_root>/tss_rate_peak. Reads raw force.mat / accel.mat; writes nothing to them.
%
% WHY
% TSSF = sum(|F|^2) dt and TSSV = sum(|A|^2) dt grow with trial length. Both groups got much
% faster, so a TSSF/TSSV change mixes "shorter trials" with "gentler handling". This script
% recomputes, per acquisition and with exactly the same signal processing as
% Perf_extract_force_vibration_features.m (calibration, bias window, noise floor, band-pass):
%   duration_s           trial window length
%   force_rms            sqrt(TSSF / duration)          N      -> intensity, duration removed
%   force_mean_contact   mean |F| while above noise     N      -> how hard, when touching
%   force_contact_frac   fraction of time above noise   0-1    -> how long in contact
%   force_p99, force_max 99th percentile / maximum |F|  N      -> peaks
%   vib_rms              sqrt(TSSV / duration)          m/s^2
%   vib_p99, vib_max     99th percentile / max of left and right |A|  m/s^2
% Only acquisitions that are finite in force_vibration_features_clean.mat are used, so every
% existing exclusion (whole-subject and per-acquisition) is kept.
%
% TESTS (one score per subject, HF minus NHF, Welch + Hedges g + 95% CI; BH-FDR within each comparison)
%   C1 training mean       : feedback ON for HF. The effect while feedback is active (not tested before).
%                            Subject score = mean over levels of the per-level mean (equal level weight).
%   C2 BL1 -> BL2 change   : feedback OFF for both. Retention. Levels valid in both phases only.
%   C3 learning slope      : repetition slope within level during training.
% Positive measures are analysed on the log scale (differences are ratios); contact fraction raw.
% Also reported: how much of log TSSF/TSSV is explained by log duration within subjects.
% EXPLORATORY: these tests were added after the main results were known.

clear; clc; close all; cfg = config();
CN = [64 96 179]/255; CH = [139 82 168]/255;
BP_LOW = 80; BP_HIGH = 1000;
out_dir = fullfile(cfg.output_root,'tss_rate_peak');
if ~exist(out_dir,'dir'), mkdir(out_dir); end
cache = fullfile(out_dir,'tss_rate_peak_metrics.mat');

%% 1. Per-acquisition metrics (cached: delete the .mat file to recompute)
if isfile(cache)
    L = load(cache,'M'); M = L.M; fprintf('Loaded cached metrics from %s\n', cache);
else
    C_force = load_ati_cal(cfg.force_cal_path);
    CL = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); CL = CL.T;
    key = strcat(string(CL.subject),'|',string(CL.phase),'|',string(CL.acquisition));
    all_phases = [cfg.baseline_phases, cfg.training_levels, cfg.test_phases];
    rows = {};
    for si = 1:numel(cfg.all_subjects)
        subj = cfg.all_subjects{si}; haptic = subj(end)=='H';
        for ph = 1:numel(all_phases)
            phase = all_phases{ph}; phase_dir = fullfile(cfg.data_root,subj,phase);
            if ~isfolder(phase_dir), continue; end
            if ismember(phase,cfg.training_levels)
                ptype = 'training'; lvl = str2double(regexp(phase,'\d+','match','once'));
                acqs = arrayfun(@(k) sprintf('rep_%02d',k),1:cfg.n_training_reps,'UniformOutput',false); reps = 1:cfg.n_training_reps;
            elseif ismember(phase,cfg.baseline_phases)
                ptype = 'baseline'; lvl = NaN;
                acqs = arrayfun(@(k) sprintf('Level%d',k),1:numel(cfg.level_names),'UniformOutput',false); reps = nan(1,numel(acqs));
            else
                ptype = 'test'; lvl = NaN; acqs = {'main'}; reps = NaN;
            end
            for ai = 1:numel(acqs)
                acq = acqs{ai};
                ix = find(key == string(subj)+"|"+string(phase)+"|"+string(acq), 1);
                if isempty(ix), continue; end
                use_f = isfinite(CL.tssf(ix)); use_a = isfinite(CL.tssv(ix));
                if ~use_f && ~use_a, continue; end
                if strcmp(ptype,'test'), acq_dir = phase_dir;
                else
                    acq_dir = fullfile(phase_dir,acq);
                    if ~isfolder(acq_dir) && isfolder([acq_dir '_R']), acq_dir = [acq_dir '_R']; end
                end
                ev = fullfile(acq_dir,'events.mat'); if ~isfile(ev), continue; end
                [t0,t1] = safe_trial_window(ev); if isnan(t0) || isnan(t1), continue; end
                lv = lvl; if strcmp(ptype,'baseline'), lv = ai; end
                fm = nan(1,6); am = nan(1,4);
                if use_f, fm = local_force(fullfile(acq_dir,'force.mat'),t0,t1,cfg,C_force); end
                if use_a, am = local_accel(fullfile(acq_dir,'accel.mat'),t0,t1,cfg,BP_LOW,BP_HIGH); end
                rows(end+1,:) = [{subj,haptic,ptype,phase,acq,lv,reps(ai),t1-t0}, num2cell(fm), num2cell(am)]; %#ok<SAGROW>
            end
        end
        fprintf('Processed %s\n', subj);
    end
    M = cell2table(rows,'VariableNames',{'subject','haptic','phase_type','phase','acquisition','level','repetition','duration_s', ...
        'tssf','force_rms','force_mean_contact','force_contact_frac','force_p99','force_max', ...
        'tssv','vib_rms','vib_p99','vib_max'});
    save(cache,'M');
end
writetable(M, fullfile(out_dir,'tss_rate_peak_metrics.csv'));

%% 2. How much of TSSF / TSSV is just duration? (within subjects, training)
Tr = M(strcmp(M.phase_type,'training'),:);
dur_rows = {};
for v = {'tssf','tssv'}
    ok = isfinite(Tr.(v{1})) & Tr.(v{1}) > 0;
    D = Tr(ok,:); y = log(D.(v{1})); x = log(D.duration_s);
    % centre within subject so only within-person variation is used
    [g,~] = findgroups(D.subject);
    my = splitapply(@mean,y,g); mx = splitapply(@mean,x,g);
    yc = y - my(g); xc = x - mx(g);
    b = xc \ yc; r2 = 1 - sum((yc - b*xc).^2)/sum(yc.^2);
    dur_rows(end+1,:) = {v{1}, b, r2, height(D)}; %#ok<SAGROW>
    fprintf('%s: within-subject log-log slope on duration = %.2f, R^2 = %.2f (%d trials)\n', upper(v{1}), b, r2, height(D));
end
TD = cell2table(dur_rows,'VariableNames',{'metric','loglog_slope_on_duration','within_subject_R2','n_trials'});
writetable(TD, fullfile(out_dir,'duration_share.csv'));

%% 3. Group tests
metrics = {'duration_s','Trial duration (s)',true; 'tssf','TSSF',true; 'force_rms','RMS force (N)',true; ...
    'force_mean_contact','Mean force in contact (N)',true; 'force_contact_frac','Contact fraction',false; ...
    'force_p99','Force p99 (N)',true; 'force_max','Peak force (N)',true; ...
    'tssv','TSSV',true; 'vib_rms','RMS vibration (m/s^2)',true; 'vib_p99','Vibration p99 (m/s^2)',true; 'vib_max','Peak vibration (m/s^2)',true};
rows = {}; plotS = struct();
for k = 1:size(metrics,1)
    v = metrics{k,1}; uselog = metrics{k,3};
    y = M.(v); if uselog, y(y<=0) = NaN; y = log(y); end
    M.y = y;
    subs = unique(M.subject); s1 = nan(numel(subs),1); s2 = s1; s3 = s1; isH = false(numel(subs),1);
    for i = 1:numel(subs)
        S = M(strcmp(M.subject,subs{i}) & isfinite(M.y),:); if isempty(S), continue; end
        isH(i) = S.haptic(1);
        St = S(strcmp(S.phase_type,'training'),:);
        if ~isempty(St)
            lm = splitapply(@mean, St.y, findgroups(St.level)); s1(i) = mean(lm);
            if height(St) >= 15 && numel(unique(St.repetition)) > 2
                Ld = dummyvar(categorical(St.level)); X = [Ld double(St.repetition)];
                b = X \ St.y; s3(i) = b(end);
            end
        end
        a = S(strcmp(S.phase,'Baseline1'),:); c = S(strcmp(S.phase,'Baseline2'),:);
        lv = intersect(a.level, c.level);
        if ~isempty(lv), s2(i) = mean(c.y(ismember(c.level,lv))) - mean(a.y(ismember(a.level,lv))); end
    end
    comps = {'C1 training mean (feedback on for HF)', s1; 'C2 BL1->BL2 change (feedback off)', s2; 'C3 learning slope per repetition', s3};
    for c = 1:3
        x = comps{c,2};
        rows(end+1,:) = [{metrics{k,2}, uselog, comps{c,1}}, local_cmp(x(isH & isfinite(x)), x(~isH & isfinite(x)))]; %#ok<SAGROW>
    end
    plotS.(v) = struct('s1',s1,'isH',isH);
end
R = cell2table(rows,'VariableNames',{'metric','log_scale','comparison','n_H','n_N','mean_H','mean_N','diff_H_minus_N', ...
    'ci_low','ci_high','ratio_H_over_N','hedges_g','p'});
R.ratio_H_over_N(~R.log_scale) = NaN;   % a ratio is only meaningful for log-scale measures
R.p_fdr = nan(height(R),1);
for c = unique(R.comparison)'
    ix = strcmp(R.comparison,c{1}); R.p_fdr(ix) = local_bh(R.p(ix));
end
writetable(R, fullfile(out_dir,'tss_rate_peak_group_tests.csv'));
save(fullfile(out_dir,'tss_rate_peak_results.mat'),'R','TD');

fprintf('\n%-28s %-40s %6s %9s %20s %8s %7s %8s %8s\n','metric','comparison','nH/nN','diff','95% CI','H/N','g','p','p_fdr');
for i = 1:height(R)
    fprintf('%-28s %-40s %3d/%-2d %9.3f [%8.3f, %8.3f] %8.3f %7.2f %8.4f %8.4f\n', R.metric{i}, R.comparison{i}, R.n_H(i), R.n_N(i), ...
        R.diff_H_minus_N(i), R.ci_low(i), R.ci_high(i), R.ratio_H_over_N(i), R.hedges_g(i), R.p(i), R.p_fdr(i));
end
fprintf('\nLog-scale rows: diff is a log difference; ratio_H_over_N = exp(diff), e.g. 0.90 = HF 10%% lower.\n');

%% 4. Figure: C1 (feedback on) subject means for the intensity measures
show = {'force_rms','force_mean_contact','force_max','vib_rms','vib_max','duration_s'};
f = figure('Position',[50 50 1500 420]);
tl = tiledlayout(1,numel(show),'TileSpacing','compact','Padding','compact');
title(tl,'Training phase (feedback on for HF): one dot per subject, log scale','FontWeight','bold');
for k = 1:numel(show)
    nexttile; hold on; P = plotS.(show{k});
    v = {P.s1(~P.isH & isfinite(P.s1)), P.s1(P.isH & isfinite(P.s1))}; cols = {CN,CH};
    for g = 1:2
        scatter(g + (rand(numel(v{g}),1)-0.5)*0.25, v{g}, 22, cols{g}, 'filled', 'MarkerFaceAlpha',0.55);
        if numel(v{g}) > 1
            ci = tinv(0.975,numel(v{g})-1)*std(v{g})/sqrt(numel(v{g}));
            errorbar(g+0.28, mean(v{g}), ci, 'o', 'Color',cols{g}, 'MarkerFaceColor',cols{g}, 'LineWidth',1.6);
        end
    end
    r = R(strcmp(R.metric, metrics{strcmp(metrics(:,1),show{k}),2}) & startsWith(R.comparison,'C1'),:);
    xlim([0.5 2.6]); xticks([1 2]); xticklabels({'NHF','HF'}); grid on; box on;
    title(sprintf('%s\nH/N = %.2f, p = %.3f', r.metric{1}, r.ratio_H_over_N, r.p),'FontSize',8);
end
exportgraphics(f, fullfile(out_dir,'training_intensity_by_group.png'), 'Resolution',200);
fprintf('\nSaved to %s\n', out_dir);

%% Local functions
function m = local_force(path, t0, t1, cfg, C_force)
% Same steps as Perf_extract_force_vibration_features.m, TSSF block.
    m = nan(1,6); if ~isfile(path), return; end
    LF = load(path,'FORCE'); t = LF.FORCE.time_rel(:); V = LF.FORCE.data;
    bm = t >= (t0-1.0) & t < t0; if sum(bm) < 3, bm = t < (t(1)+1.0); end
    bias = mean(V(bm,:),1,'omitnan');
    Fb = (C_force * (V(bm,:) - bias)')'; Fbm = sqrt(sum(Fb(:,1:3).^2,2));
    nf = median(Fbm) + cfg.force_noise_k_mad * mad(Fbm,1);
    tm = t >= t0 & t <= t1; if ~any(tm), return; end
    fs = 1/median(diff(t(tm)));
    F = (C_force * (V(tm,:) - bias)')'; Fm = sqrt(sum(F(:,1:3).^2,2)); Fm(Fm < nf) = 0;
    tssf = sum(Fm.^2)/fs; dur = t1 - t0; on = Fm > 0;
    mc = NaN; if any(on), mc = mean(Fm(on)); end
    m = [tssf, sqrt(tssf/dur), mc, mean(on), prctile(Fm,99), max(Fm)];
end
function m = local_accel(path, t0, t1, cfg, lo, hi)
% Same steps as Perf_extract_force_vibration_features.m, TSSV block.
    m = nan(1,4); if ~isfile(path), return; end
    LA = load(path,'ACCEL'); t = LA.ACCEL.time_rel(:); fs = LA.ACCEL.fs_nominal; dt = 1/fs;
    bm = t >= (t0-1.0) & t < t0; if sum(bm) < 3, bm = t < (t(1)+1.0); end
    bias = mean(LA.ACCEL.data(bm,:),1,'omitnan');
    A = (LA.ACCEL.data - bias) * cfg.accel_sensitivity_ms2_per_V;
    tm = t >= t0 & t <= t1; if sum(tm) <= 2, return; end
    seg = A(tm,:);
    if fs/2 > hi
        [b,a] = butter(4,[lo hi]/(fs/2),'bandpass');
        for c = 1:size(seg,2), seg(:,c) = filtfilt(b,a,double(seg(:,c))); end
    end
    AL = sqrt(sum(seg(:,1:3).^2,2)); AR = sqrt(sum(seg(:,4:6).^2,2));
    thr = cfg.tssv_noise_threshold_ms2; AL(AL < thr) = 0; AR(AR < thr) = 0;
    tssv = (sum(AL.^2) + sum(AR.^2))*dt; dur = t1 - t0;
    m = [tssv, sqrt(tssv/dur), prctile([AL;AR],99), max([AL;AR])];
end
function r = local_cmp(xH, xN)
    nH = numel(xH); nN = numel(xN);
    if nH < 3 || nN < 3, r = num2cell(nan(1,10)); r{1} = nH; r{2} = nN; return; end
    [~,p,ci] = ttest2(xH, xN, 'Vartype','unequal');
    sp = sqrt(((nH-1)*var(xH) + (nN-1)*var(xN))/(nH+nN-2));
    g = (mean(xH)-mean(xN))/sp*(1 - 3/(4*(nH+nN-2)-1));
    d = mean(xH) - mean(xN);
    r = {nH, nN, mean(xH), mean(xN), d, ci(1), ci(2), exp(d), g, p};
end
function q = local_bh(p)
    q = nan(size(p)); v = find(isfinite(p)); [ps,o] = sort(p(v)); m = numel(ps);
    a = min(cummin(ps .* m ./ (1:m)', 'reverse'), 1); q(v(o)) = a;
end
