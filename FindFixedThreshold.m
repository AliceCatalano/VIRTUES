%% FindFixedThreshold.m
%  Scans all subject folders for existing collision_results.mat files, harvests the adaptive threshold used in each acquisition, plots how
%  it varies across subjects/phases, then VALIDATES a set of candidate fixed thresholds by reprocessing the audio envelope for every
%  acquisition and comparing the resulting collision counts against the already-saved (adaptive-threshold-based) counts.
%
%  OUTPUT:
%    - FixedThresholdAnalysis_<timestamp>.txt   (full text report, saved in BASE_FOLDER via diary)
%    - Figures (not saved to disk by default — set SAVE_FIGS = true to export them as PNG into BASE_FOLDER)
%
%  WORKFLOW:
%    1. Edit SUBJECTS_TO_RUN (or leave empty to auto-discover all "subject_*" folders under BASE_FOLDER).
%    2. Run. No prompts, fully automatic.

clear; clc; close all;

%% SECTION 0 — PARAMETERS
BASE_FOLDER = '/home/acatalano/Desktop/Virtues_Data';

SUBJECTS_TO_RUN = {};   % leave empty -> auto-discover ALL subject_* folders
                       
allPhases = {'Baseline1','Baseline2','level_L1','level_L2','level_L3','level_L4','level_L5'};

PEAK_MIN_DIST_SEC = 1;     % must match whatever your detection script used
SAVE_FIGS         = true; % export figures as PNG into BASE_FOLDER

base = BASE_FOLDER;

if isempty(SUBJECTS_TO_RUN)
    d = dir(fullfile(base, 'subject_*'));
    SUBJECTS_TO_RUN = {d([d.isdir]).name};
end


report_file = fullfile(base,'FixedThresholdAnalysis.txt');
if strcmp(get(0,'Diary'), 'on'), diary off; end
diary(report_file);
diary on;

fprintf('Subjects found (%d): %s\n\n', numel(SUBJECTS_TO_RUN), strjoin(SUBJECTS_TO_RUN, ', '));

%% SECTION 1 — HARVEST EXISTING THRESHOLDS 
rows = {};   % subject, phase, acquisition, threshold, n_collisions, duration, acq_folder

for subjIdx = 1:numel(SUBJECTS_TO_RUN)

    subjFolderName = SUBJECTS_TO_RUN{subjIdx};
    SUBJECT = erase(subjFolderName, 'subject_');
    subj_folder = fullfile(base, subjFolderName);

    if ~isfolder(subj_folder), continue; end

    for pIdx = 1:numel(allPhases)

        PHASE = allPhases{pIdx};
        phase_folder = fullfile(subj_folder, PHASE);
        if ~isfolder(phase_folder), continue; end

        if startsWith(PHASE, 'Baseline', 'IgnoreCase', true)
            acquisitions = arrayfun(@(k) sprintf('Level%d', k), 1:5, 'UniformOutput', false);
        else
            acquisitions = arrayfun(@(k) sprintf('rep_%02d', k), 1:10, 'UniformOutput', false);
        end

        for aIdx = 1:numel(acquisitions)

            ACQUISITION = acquisitions{aIdx};
            acq_folder  = fullfile(phase_folder, ACQUISITION);

            if ~isfolder(acq_folder)
                continue;   % no _R / _X fallback — skip if base folder doesn't exist
            end

            collision_file = fullfile(acq_folder, 'collision_results.mat');
            if ~isfile(collision_file), continue; end

            try
                R = load(collision_file, 'results');
                res = R.results;

                thresh = get_threshold_field(res.params);
                if isnan(thresh), continue; end

                rows(end+1,:) = { SUBJECT, PHASE, ACQUISITION, thresh, ...
                    res.n_collisions, res.t_win_end - res.t_win_start, acq_folder }; %#ok<AGROW>

            catch
                continue;   % corrupted/incompatible file — skip silently
            end
        end
    end
end

if isempty(rows)
    error('No collision_results.mat files with a usable threshold field were found.');
end

T = cell2table(rows, 'VariableNames', ...
    {'subject','phase','acquisition','threshold','n_collisions','duration','acq_folder'});

fprintf('Harvested %d acquisitions with saved thresholds across %d subjects.\n\n', ...
    height(T), numel(unique(T.subject)));

%% SECTION 2 — DESCRIPTIVE STATS ON HARVESTED THRESHOLDS
fprintf(' POOLED THRESHOLD STATISTICS (all subjects, all acquisitions)\n');
fprintf('  n        = %d\n', height(T));
fprintf('  min      = %.4f\n', min(T.threshold));
fprintf('  max      = %.4f\n', max(T.threshold));
fprintf('  mean     = %.4f\n', mean(T.threshold));
fprintf('  median   = %.4f\n', median(T.threshold));
fprintf('  std      = %.4f\n', std(T.threshold));
fprintf('  p10/p25/p75/p90 = %.4f / %.4f / %.4f / %.4f\n', ...
    prctile(T.threshold,10), prctile(T.threshold,25), ...
    prctile(T.threshold,75), prctile(T.threshold,90));

% ---- Per-subject median (equal weight per subject, robust to reps-per-subject imbalance) ----
subjList = unique(T.subject, 'stable');
subjMedian = nan(numel(subjList),1);
subjMean   = nan(numel(subjList),1);
subjN      = nan(numel(subjList),1);

for si = 1:numel(subjList)
    mask = strcmp(T.subject, subjList{si});
    subjMedian(si) = median(T.threshold(mask));
    subjMean(si)   = mean(T.threshold(mask));
    subjN(si)      = sum(mask);
end

medianOfMedians = median(subjMedian);
meanOfMedians   = mean(subjMedian);

fprintf(' PER-SUBJECT THRESHOLD SUMMARY\n');
for si = 1:numel(subjList)
    fprintf('  %-10s : median=%.4f  mean=%.4f  n=%d\n', ...
        subjList{si}, subjMedian(si), subjMean(si), subjN(si));
end
fprintf('\n  Median of per-subject medians : %.4f   <-- equal-weight, robust candidate\n', medianOfMedians);
fprintf('  Mean   of per-subject medians : %.4f\n', meanOfMedians);
fprintf('  Spread of per-subject medians : min=%.4f  max=%.4f  std=%.4f\n', ...
    min(subjMedian), max(subjMedian), std(subjMedian));

if std(subjMedian) / medianOfMedians > 0.3
    fprintf('\n  [WARNING] Per-subject median thresholds vary widely (CV=%.1f%%).\n', ...
        100*std(subjMedian)/medianOfMedians);
    fprintf('            A single fixed threshold may not fit all subjects equally well.\n');
end

%% SECTION 3 — PLOTS OF HARVESTED THRESHOLDS
fig1 = figure('Name','Threshold by subject','Units','normalized','Position',[0.05 0.1 0.5 0.6],'Visible','off');
boxplot(T.threshold, T.subject);
ylabel('Adaptive threshold used'); title('Threshold distribution per subject');
xtickangle(45); grid on;
yline(medianOfMedians, 'r--', 'LineWidth',1.5, 'Label','median-of-medians');

fig2 = figure('Name','Threshold by phase','Units','normalized','Position',[0.55 0.1 0.4 0.6],'Visible','off');
boxplot(T.threshold, T.phase);
ylabel('Adaptive threshold used'); title('Threshold distribution per phase');
xtickangle(45); grid on;

fig3 = figure('Name','Pooled threshold histogram','Units','normalized','Position',[0.05 0.1 0.45 0.4],'Visible','off');
histogram(T.threshold, 40, 'FaceColor',[0.2 0.45 0.8]);
hold on;
xline(median(T.threshold), 'r-',  'LineWidth',1.5, 'Label','pooled median');
xline(medianOfMedians,     'g--', 'LineWidth',1.5, 'Label','median-of-medians');
xlabel('Threshold'); ylabel('Count'); title('Pooled threshold distribution (all acquisitions)');
grid on;

fig4 = figure('Name','Per-subject median (sorted)','Units','normalized','Position',[0.55 0.1 0.4 0.4],'Visible','off');
[sortedMed, sortIdx] = sort(subjMedian);
bar(sortedMed, 'FaceColor',[0.6 0.2 0.6]);
set(gca, 'XTick', 1:numel(subjList), 'XTickLabel', subjList(sortIdx));
xtickangle(45); ylabel('Median threshold');
title('Per-subject median threshold (sorted)'); grid on;
yline(medianOfMedians, 'r--', 'LineWidth',1.5);

if SAVE_FIGS
    exportgraphics(fig1, fullfile(base, 'thresh_by_subject.png'), 'Resolution',130);
    exportgraphics(fig2, fullfile(base, 'thresh_by_phase.png'),   'Resolution',130);
    exportgraphics(fig3, fullfile(base, 'thresh_histogram.png'),  'Resolution',130);
    exportgraphics(fig4, fullfile(base, 'thresh_per_subject_sorted.png'), 'Resolution',130);
end

%% SECTION 4 — VALIDATION SWEEP: how well would candidate fixed thresholds
fprintf(' VALIDATION SWEEP — candidate fixed thresholds\n');

candidates = unique([ ...
    prctile(T.threshold,10), prctile(T.threshold,25), median(T.threshold), ...
    prctile(T.threshold,75), prctile(T.threshold,90), medianOfMedians ]);

fprintf('Candidates to test: %s\n\n', mat2str(round(candidates,4)));

% For each acquisition: load audio ONCE, compute env_trial ONCE, then
% cheaply re-run findpeaks for every candidate threshold.
valRows = {};   % subject, phase, acquisition, candidate, n_original, n_candidate, diff

for r = 1:height(T)

    acq_folder = T.acq_folder{r};
    audio_file  = fullfile(acq_folder, 'audio.mat');
    events_file = fullfile(acq_folder, 'events.mat');

    if ~isfile(audio_file) || ~isfile(events_file)
        continue;   % can't validate this one — skip
    end

    try
        U = load(audio_file);  AUDIO  = U.AUDIO;
        E = load(events_file); EVENTS = E.EVENTS;

        t_aud    = AUDIO.time_rel;
        fs_audio = AUDIO.fs_estimated;
        ch_names = AUDIO.channel_names;

        known_new = {'ch11','ch12','ch13','ch14','ch16','ch17'};
        known_old = {'ch12','ch13','ch14','ch16','ch17','ch18'};
        idx_new   = find(ismember(ch_names, known_new));
        idx_old   = find(ismember(ch_names, known_old));
        if numel(idx_new) >= numel(idx_old)
            audio_ch_idx = idx_new;
        else
            audio_ch_idx = idx_old;
        end
        if isempty(audio_ch_idx)
            audio_ch_idx = 1:size(AUDIO.data, 2);
        end

        audio_raw = AUDIO.data(:, audio_ch_idx);
        audio_bp  = bandpass_channels(audio_raw, fs_audio, 80, 1000);
        env       = rms_envelope(audio_bp, fs_audio, 0.02);

        t_ws = EVENTS.t_trial_start;
        t_we = EVENTS.t_trial_end;

        in_trial  = (t_aud >= t_ws) & (t_aud <= t_we);
        env_trial = env(in_trial);
        t_trial   = t_aud(in_trial);

        % Ensure monotonic time (same defensive check as detection script)
        keep = true(size(t_trial));
        last_t = -inf;
        for k = 1:numel(t_trial)
            if t_trial(k) > last_t, last_t = t_trial(k); else, keep(k) = false; end
        end
        t_trial   = t_trial(keep);
        env_trial = env_trial(keep);

        if isempty(env_trial) || all(isnan(env_trial)) || numel(t_trial) < 3
            continue;
        end

        t_span = t_trial(end) - t_trial(1);
        eff_min_dist = PEAK_MIN_DIST_SEC;
        if eff_min_dist >= t_span
            eff_min_dist = t_span * 0.5;
        end
        if eff_min_dist <= 0, continue; end

        for c = 1:numel(candidates)
            cand = candidates(c);
            [~, locs] = findpeaks(env_trial, t_trial, ...
                'MinPeakDistance', eff_min_dist, 'MinPeakHeight', cand);
            n_cand = numel(locs);

            valRows(end+1,:) = { T.subject{r}, T.phase{r}, T.acquisition{r}, ...
                cand, T.n_collisions(r), n_cand, n_cand - T.n_collisions(r) }; %#ok<AGROW>
        end

    catch
        continue;
    end
end

V = cell2table(valRows, 'VariableNames', ...
    {'subject','phase','acquisition','candidate','n_original','n_candidate','diff'});

%% SECTION 5 — SUMMARIZE VALIDATION: which candidate best reproduces existing counts?
fprintf('\n%-12s | %-10s | %-10s | %-10s | %-14s\n', 'Candidate', 'MeanAbsDiff', 'MedAbsDiff', 'Corr(r)', '%RepsExactMatch');
fprintf('%s\n', repmat('-',1,65));

candStats = struct('candidate',{},'mean_abs_diff',{},'median_abs_diff',{},'corr',{},'pct_exact',{});

for c = 1:numel(candidates)
    mask = V.candidate == candidates(c);
    absdiff = abs(V.diff(mask));
    corrVal = corr(V.n_original(mask), V.n_candidate(mask));
    pctExact = 100 * mean(V.diff(mask) == 0);

    fprintf('%-12.4f | %-10.2f | %-10.1f | %-10.3f | %-14.1f\n', ...
        candidates(c), mean(absdiff), median(absdiff), corrVal, pctExact);

    candStats(end+1) = struct('candidate',candidates(c), ...
        'mean_abs_diff',mean(absdiff), 'median_abs_diff',median(absdiff), ...
        'corr',corrVal, 'pct_exact',pctExact); %#ok<AGROW>
end

% ---- Pick winner: lowest mean absolute difference ----
[~, winIdx] = min(arrayfun(@(s) s.mean_abs_diff, candStats));
winningThresh = candStats(winIdx).candidate;

fprintf('\n>>> RECOMMENDED FIXED THRESHOLD: %.4f\n', winningThresh);
fprintf('    (lowest mean abs. difference from existing adaptive-based counts: %.2f)\n', ...
    candStats(winIdx).mean_abs_diff);

%% SECTION 6 — PER-SUBJECT BIAS CHECK FOR THE WINNING THRESHOLD
fprintf(' PER-SUBJECT BIAS — winning threshold = %.4f\n', winningThresh);

maskWin = V.candidate == winningThresh;
Vwin = V(maskWin,:);

subjBias = struct('subject',{},'mean_diff',{},'mean_abs_diff',{},'n',{});
for si = 1:numel(subjList)
    m = strcmp(Vwin.subject, subjList{si});
    if ~any(m), continue; end
    subjBias(end+1) = struct('subject',subjList{si}, ...
        'mean_diff', mean(Vwin.diff(m)), ...
        'mean_abs_diff', mean(abs(Vwin.diff(m))), ...
        'n', sum(m)); %#ok<AGROW>
    fprintf('  %-10s : mean_diff=%+.2f  mean_abs_diff=%.2f  (n=%d reps)\n', ...
        subjList{si}, subjBias(end).mean_diff, subjBias(end).mean_abs_diff, subjBias(end).n);
end

biasVals = arrayfun(@(s) s.mean_diff, subjBias);
flaggedSubj = subjList(abs(biasVals) > 2);
if ~isempty(flaggedSubj)
    fprintf('\n  [FLAG] Subjects with |mean bias| > 2 collisions/rep at this threshold:\n');
    fprintf('         %s\n', strjoin(flaggedSubj, ', '));
    fprintf('         Consider reviewing these subjects individually.\n');
else
    fprintf('\n  No subject shows a large systematic bias at this threshold — looks broadly consistent.\n');
end

%% SECTION 7 — VALIDATION PLOTS
fig5 = figure('Name','Candidate threshold performance','Units','normalized','Position',[0.05 0.1 0.5 0.5],'Visible','off');
bar(candidates, arrayfun(@(s) s.mean_abs_diff, candStats), 'FaceColor',[0.85 0.4 0.1]);
hold on;
plot(winningThresh, candStats(winIdx).mean_abs_diff, 'g*', 'MarkerSize',15,'LineWidth',2);
xlabel('Candidate fixed threshold'); ylabel('Mean |Δ collisions| vs adaptive');
title('Candidate threshold validation — lower is better'); grid on;

fig6 = figure('Name','Winning threshold — per-subject bias','Units','normalized','Position',[0.55 0.1 0.4 0.5],'Visible','off');
bar(biasVals);
set(gca, 'XTick', 1:numel(subjList), 'XTickLabel', subjList); xtickangle(45);
ylabel('Mean (candidate - original) collisions/rep');
title(sprintf('Per-subject bias at threshold=%.4f', winningThresh));
yline(0, 'k-'); grid on;

if SAVE_FIGS
    exportgraphics(fig5, fullfile(base, 'candidate_validation.png'), 'Resolution',130);
    exportgraphics(fig6, fullfile(base, 'winning_threshold_bias.png'), 'Resolution',130);
end

%% SECTION 8 — SAVE EVERYTHING TO .mat FOR LATER REFERENCE
save(fullfile(base, 'FixedThresholdAnalysis.mat'), 'T', 'V', 'candStats', 'subjBias', 'winningThresh');

fprintf('\n[SAVE] Harvested table, validation table, and recommendation saved to:\n  %s\n', ...
    fullfile(base, 'FixedThresholdAnalysis.mat'));

diary off;
fprintf('\n[REPORT SAVED] → %s\n\n', report_file);


%  LOCAL FUNCTIONS 

function t = get_threshold_field(paramsStruct)
    % Handles the different field names used across script versions
    t = NaN;
    if isfield(paramsStruct, 'adaptive_thresh')
        t = paramsStruct.adaptive_thresh;
    elseif isfield(paramsStruct, 'fixed_audio_thresh')
        t = paramsStruct.fixed_audio_thresh;
    elseif isfield(paramsStruct, 'peak_height_factor')
        t = NaN;   % factor-based, not an absolute threshold — not comparable, skip
    end
end

function out = bandpass_channels(mat, fs, flo, fhi)
    out = zeros(size(mat,1), 1);
    for k = 1:size(mat,2)
        col = double(mat(:,k));
        col = col - mean(col, 'omitnan');
        if numel(col) > 10*fs
            col = bandpass(col, [flo fhi], fs);
        end
        out = max(out, abs(col));
    end
end

function env = rms_envelope(sig, fs, win_sec)
    win = max(3, round(fs * win_sec));
    env = sqrt(movmean(sig.^2, win));
end