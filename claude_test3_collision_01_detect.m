%% claude_test3_collision_01_detect.m
% Step 1 of the Test3 collision analysis. See claude_test3_collision_plan.md.
% Detects collisions in Test2 and Test3 with the settings behind the saved collision_results.mat, then checks:
%   - reproduction of the saved Test2 results,
%   - threshold sensitivity and noise floor,
%   - agreement with the independent NIDAQ accelerometer,
%   - audio-to-NIDAQ time lag.
% Writes ONLY to <output_root>/Claude_outputs/test3_collision. Nothing goes into subject folders.

clear; clc; cfg = config(); rng(20261105);
out_dir = fullfile(cfg.output_root,'Claude_outputs','test3_collision'); if ~exist(out_dir,'dir'), mkdir(out_dir); end
subs = cfg.all_subjects; ths = [0.0075 0.01 0.015 0.02 0.03];
ev_rows = {}; q_rows = {};
for si = 1:numel(subs)
    s = subs{si};
    for ph = {'Test2','Test3'}
        d = fullfile(cfg.data_root,s,ph{1});
        q = struct('n',NaN,'dur',NaN,'noise_med',NaN,'noise_p90',NaN,'n_saved',NaN,'n_matched',NaN,'lag_ms',NaN,'xcorr',NaN, ...
            'nidaq_end',NaN,'peak_ratio',NaN,'audio_nidaq_r',NaN);
        counts = nan(size(ths));
        try
            [a,b] = safe_trial_window(fullfile(d,'events.mat')); q.dur = b-a;
            U = load(fullfile(d,'audio.mat')); AU = U.AUDIO;
            [t,env,bp,fsA] = local_audio(AU);
            in = t>=a & t<=b; tt = t(in); ee = env(in);
            mono = tt>[-inf; cummax(tt(1:end-1))]; tt = tt(mono); ee = ee(mono);   % audio timestamps can jump backwards
            q.noise_med = median(ee,'omitnan'); q.noise_p90 = prctile(ee,90);
            for k = 1:numel(ths)
                [~,l] = findpeaks(ee,tt,'MinPeakDistance',0.5,'MinPeakHeight',ths(k)); counts(k) = numel(l);
            end
            [pk,loc] = findpeaks(ee,tt,'MinPeakDistance',0.5,'MinPeakHeight',0.015);
            loc = loc(:); pk = pk(:); q.n = numel(loc);
            % Reproduction of the saved results
            f = fullfile(d,'collision_results.mat');
            if isfile(f)
                C = load(f); sv = C.results.collision_rel(:); q.n_saved = numel(sv);
                if ~isempty(sv)&&~isempty(loc), q.n_matched = sum(min(abs(sv-loc'),[],2)<0.05); else, q.n_matched = 0; end
            end
            % Independent check with the NIDAQ accelerometer, in the part it covers
            pA = fullfile(d,'accel.mat'); nid = nan(size(loc));
            if isfile(pA)
                L = load(pA,'ACCEL'); ta = L.ACCEL.time_rel(:); fs = L.ACCEL.fs_nominal; q.nidaq_end = ta(end);
                pre = ta>=(a-1)&ta<a; if sum(pre)<3, pre = ta<(ta(1)+1); end
                X = (L.ACCEL.data-mean(L.ACCEL.data(pre,:),1,'omitnan'))*cfg.accel_sensitivity_ms2_per_V;
                [bb,aa] = butter(4,[80 1000]/(fs/2),'bandpass'); for c = 1:6, X(:,c) = filtfilt(bb,aa,double(X(:,c))); end
                Am = max(abs(sum(X(:,1:3),2)),abs(sum(X(:,4:6),2)))/9.81;
                pk_at = @(tq) arrayfun(@(u) local_max(Am(ta>=u-0.1&ta<=u+0.1)),tq);
                cov = loc>=ta(1)+0.1 & loc<=ta(end)-0.1;
                nid(cov) = pk_at(loc(cov));
                span = [max(a,ta(1)) min(b,ta(end))];
                if diff(span)>10 && sum(cov)>=3
                    rnd = span(1)+rand(300,1)*diff(span);
                    far = arrayfun(@(u) all(abs(u-loc)>1),rnd); rnd = rnd(far);
                    q.peak_ratio = median(nid(cov),'omitnan')/median(pk_at(rnd),'omitnan');
                    q.audio_nidaq_r = corr(log(pk(cov)),log(nid(cov)),'Type','Spearman','Rows','complete');
                    % Lag: envelope cross-correlation at 100 Hz
                    tg = (span(1):0.01:span(2))';
                    ea = interp1(tt,ee,tg,'linear',0); [~,ua] = unique(ta); en = interp1(ta(ua),movmean(Am(ua),round(fs*0.02)),tg,'linear',0);
                    [xc,lg] = xcorr(ea-mean(ea),en-mean(en),100,'coeff'); [m,ix] = max(xc); q.xcorr = m; q.lag_ms = lg(ix)*10;
                end
            end
            for j = 1:numel(loc)
                ev_rows(end+1,:) = {s,ph{1},j,loc(j),pk(j),nid(j)}; %#ok<AGROW>
            end
        catch ME
            fprintf('FAILED %s %s: %s\n',s,ph{1},ME.message);
        end
        q_rows(end+1,:) = {s,ph{1},q.n,q.dur,q.noise_med,q.noise_p90,counts(1),counts(2),counts(3),counts(4),counts(5),q.n_saved,q.n_matched,q.nidaq_end,q.peak_ratio,q.audio_nidaq_r,q.lag_ms,q.xcorr}; %#ok<AGROW>
    end
    fprintf('%s done\n',s);
end
EV = cell2table(ev_rows,'VariableNames',{'subject','phase','idx','t','audio_peak','nidaq_peak_g'});
QC = cell2table(q_rows,'VariableNames',{'subject','phase','n','dur_s','noise_med','noise_p90','n_t0075','n_t01','n_t015','n_t02','n_t03','n_saved','n_matched','nidaq_end','peak_ratio','audio_nidaq_r','lag_ms','xcorr'});
QC.haptic_trained = endsWith(QC.subject,'H'); QC.rate_min = QC.n./(QC.dur_s/60);
writetable(EV,fullfile(out_dir,'events.csv')); writetable(QC,fullfile(out_dir,'detection_qc.csv'));
save(fullfile(out_dir,'detection.mat'),'EV','QC');
fprintf('DETECT_DONE\n');

function [t,env,bp,fs] = local_audio(AU)
    t = AU.time_rel(:); fs = AU.fs_estimated; names = AU.channel_names;
    a1 = find(ismember(names,{'ch11','ch12','ch13','ch14','ch16','ch17'})); a2 = find(ismember(names,{'ch12','ch13','ch14','ch16','ch17','ch18'}));
    if numel(a1)>=numel(a2), ix = a1; else, ix = a2; end
    if isempty(ix), ix = 1:size(AU.data,2); end
    X = AU.data(:,ix); bp = zeros(size(X,1),1);
    for k = 1:size(X,2)
        c = double(X(:,k)); c = c-mean(c,'omitnan');
        if numel(c)>10*fs, c = bandpass(c,[80 1000],fs); end
        bp = max(bp,abs(c));
    end
    env = sqrt(movmean(bp.^2,max(3,round(fs*0.02))));
end
function m = local_max(v)
    if isempty(v), m = NaN; else, m = max(v); end
end
