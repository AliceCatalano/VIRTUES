%% tssv_threshold_sensitivity.m
% Sweeps cfg.tssv_noise_threshold_ms2 across a range of candidate values
% and recomputes TSSV for each, so you can see whether your current
% datasheet-derived threshold (0.0714 m/s^2, 3-sigma from the ADXL356
% noise density) is actually where the result stabilizes, or whether
% it's cutting into real signal / leaving in real noise.
%
% Step 1: candidate thresholds -- 0 (no thresholding), 1-sigma, 2-sigma,
% your current 3-sigma, and a few higher values, so you can see both
% directions (lowering AND raising it).
% Step 2: for each threshold, recompute TSSV for every training trial
% (same bandpass/dt pipeline as the real extractor).
% Step 3: for each threshold, report: % of bandpassed samples zeroed
% out by that threshold, resulting group means, and the NHF-vs-HF
% Welch t-test p-value (pooled across all training trials) -- so you
% can see directly whether your statistical conclusions change.
% Step 4: plot TSSV (median, with IQR band) vs threshold, one line per
% group, so the stabilization point is visible.

clear; clc; cfg = config();
BP_LOW = 80; BP_HIGH = 1000;
tssv_known_bad = {'subject_s09N','subject_s10H','subject_s11N','subject_s12H', ...
                   'subject_s23H','subject_s44N','subject_s02N','subject_s48N','subject_s05N'};

% 1-sigma = 0.0714/3, 2-sigma = 0.0714*2/3, 3-sigma = current value.
sigma1 = cfg.tssv_noise_threshold_ms2 / 3;
thresholds = [0, sigma1, 2*sigma1, cfg.tssv_noise_threshold_ms2, ...
              1.5*cfg.tssv_noise_threshold_ms2, 2*cfg.tssv_noise_threshold_ms2, ...
              3*cfg.tssv_noise_threshold_ms2];
thr_labels = {'0 (none)','1\sigma','2\sigma','3\sigma (current)','4.5\sigma','6\sigma','9\sigma'};

%% ---- Step 2: recompute TSSV per trial for EVERY threshold at once ----
% One pass over the raw data, computing A_left/A_right ONCE per trial,
% then applying every candidate threshold to the same bandpassed signal
% -- avoids re-reading/re-filtering the raw files once per threshold.
all_phases = cfg.training_levels;   % training only -- this is where group comparisons matter most
rows = {};   % subject, group, haptic, A_left (cell), A_right (cell), fs

for si = 1:numel(cfg.all_subjects)
    subj = cfg.all_subjects{si};
    if ismember(subj, tssv_known_bad), continue; end
    group = subj(end); haptic = strcmp(group,'H');
    subj_dir = fullfile(cfg.data_root, subj);

    for ph_idx = 1:numel(all_phases)
        phase = all_phases{ph_idx};
        phase_dir = fullfile(subj_dir, phase);
        if ~isfolder(phase_dir), continue; end
        acquisitions = arrayfun(@(k) sprintf('rep_%02d',k), 1:cfg.n_training_reps, 'UniformOutput', false);

        for ai = 1:numel(acquisitions)
            acq = acquisitions{ai};
            acq_dir = fullfile(phase_dir, acq);
            if ~isfolder(acq_dir)
                if isfolder([acq_dir '_R']), acq_dir = [acq_dir '_R']; else, continue; end
            end
            ev_path = fullfile(acq_dir,'events.mat'); accel_path = fullfile(acq_dir,'accel.mat');
            if ~isfile(ev_path) || ~isfile(accel_path), continue; end
            [t_start,t_end] = safe_trial_window(ev_path);
            if isnan(t_start) || isnan(t_end), continue; end

            L = load(accel_path,'ACCEL');
            t_a = L.ACCEL.time_rel(:);
            dt_win = diff(t_a(t_a>=t_start & t_a<=t_end));
            if isempty(dt_win), continue; end
            fs = 1/median(dt_win(dt_win>0));

            bm = t_a>=(t_start-1.0) & t_a<t_start;
            if sum(bm)<3, bm = t_a<(t_a(1)+1.0); end
            bias = mean(L.ACCEL.data(bm,:),1,'omitnan');
            raw_ms2 = (L.ACCEL.data - bias) * cfg.accel_sensitivity_ms2_per_V;

            tm = t_a>=t_start & t_a<=t_end;
            if sum(tm) < 10, continue; end
            seg = raw_ms2(tm,:);
            if fs/2 > BP_HIGH
                [b,a_f] = butter(4,[BP_LOW BP_HIGH]/(fs/2),'bandpass');
                for c=1:6, seg(:,c) = filtfilt(b,a_f,double(seg(:,c))); end
            end

            A_left  = sum(seg(:,1:3),2);
            A_right = sum(seg(:,4:6),2);
            rows(end+1,:) = {subj, group, haptic, A_left, A_right, fs}; %#ok<AGROW>
        end
    end
    fprintf('Processed %s\n', subj);
end
Traw = cell2table(rows,'VariableNames',{'subject','group','haptic','A_left','A_right','fs'});
fprintf('\nCollected %d trials. Applying %d candidate thresholds...\n', height(Traw), numel(thresholds));

%% ---- Step 3: apply each threshold, compute per-trial TSSV ------------
n_thr = numel(thresholds);
tssv_by_thr = nan(height(Traw), n_thr);
pct_zeroed  = nan(1, n_thr);
for ti = 1:n_thr
    thr = thresholds(ti);
    n_total_samp = 0; n_zero_samp = 0;
    for i = 1:height(Traw)
        AL = Traw.A_left{i}; AR = Traw.A_right{i};
        zl = abs(AL) < thr; zr = abs(AR) < thr;
        n_total_samp = n_total_samp + numel(AL) + numel(AR);
        n_zero_samp  = n_zero_samp  + sum(zl) + sum(zr);
        AL(zl) = 0; AR(zr) = 0;
        tssv_by_thr(i,ti) = sum((AL+AR).^2) * (1/Traw.fs(i));
    end
    pct_zeroed(ti) = 100 * n_zero_samp / n_total_samp;
end

%% ---- Step 4: report and plot -----------------------------------------
fprintf('\n%-14s %10s %12s %12s %10s\n','Threshold','%zeroed','median_N','median_H','p_welch');
mu_N = nan(1,n_thr); mu_H = nan(1,n_thr);
iq_N = nan(2,n_thr); iq_H = nan(2,n_thr);
for ti = 1:n_thr
    vN = tssv_by_thr(~Traw.haptic, ti); vN = vN(isfinite(vN) & vN>0);
    vH = tssv_by_thr( Traw.haptic, ti); vH = vH(isfinite(vH) & vH>0);
    mu_N(ti) = median(vN); mu_H(ti) = median(vH);
    iq_N(:,ti) = quantile(vN,[0.25 0.75]); iq_H(:,ti) = quantile(vH,[0.25 0.75]);
    [~,p] = ttest2(log(vN), log(vH), 'Vartype','unequal');
    fprintf('%-14s %10.2f %12.4g %12.4g %10.4f\n', thr_labels{ti}, pct_zeroed(ti), mu_N(ti), mu_H(ti), p);
end

figure('Position',[100 100 800 500]); hold on;
x = 1:n_thr;
fill([x fliplr(x)], [iq_N(1,:) fliplr(iq_N(2,:))], [0.25 0.38 0.70], 'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
fill([x fliplr(x)], [iq_H(1,:) fliplr(iq_H(2,:))], [0.55 0.20 0.66], 'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
plot(x, mu_N, 'o-', 'Color',[0.25 0.38 0.70], 'LineWidth',2, 'MarkerFaceColor',[0.25 0.38 0.70], 'DisplayName','NHF (median)');
plot(x, mu_H, 'o-', 'Color',[0.55 0.20 0.66], 'LineWidth',2, 'MarkerFaceColor',[0.55 0.20 0.66], 'DisplayName','HF (median)');
xline(find(thresholds==cfg.tssv_noise_threshold_ms2), 'k:', 'LineWidth',1.2, 'DisplayName','current threshold');
xticks(x); xticklabels(thr_labels); xlabel('Candidate noise threshold'); ylabel('TSSV (raw, median \pm IQR)');
title('TSSV sensitivity to noise threshold choice'); legend('Location','best'); grid on; box on;
saveas(gcf, fullfile(cfg.output_root,'figures','tssv_threshold_sensitivity.png'));

save(fullfile(cfg.output_root,'tssv_threshold_sensitivity.mat'), 'thresholds','thr_labels','tssv_by_thr','Traw','pct_zeroed');
fprintf('\nSaved tssv_threshold_sensitivity.mat\n');
