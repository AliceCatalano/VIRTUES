%% FindFixedThreshold.m
%  Finds the best single FIXED audio threshold to use across ALL subjects
%  and phases for collision detection, using the per-side bandpassed-sum
%  signal (audio_side_abs_sum -- matches Accelerometer_visualization.m's
%  validated sumbp exactly, no RMS envelope) rather than the old
%  max(abs(.))-across-6-channels + RMS-envelope signal this script
%  originally validated against.
%
%  WHY THE OLD METHODOLOGY COULDN'T JUST BE REPOINTED AT THE NEW SIGNAL:
%  the previous version harvested the adaptive threshold each existing
%  collision_results.mat was detected with, then picked whichever
%  candidate fixed threshold best REPRODUCED those already-saved counts.
%  Those saved counts came from the old, structurally inflated envelope
%  signal -- validating a new threshold against them would just calibrate
%  it back toward the discredited signal's answer, not the new one's.
%  There is no trustworthy "ground truth" count to compare against here.
%
%  INSTEAD, THIS VERSION VALIDATES BY SELF-CONSISTENCY ON THE NEW SIGNAL:
%  for each candidate fixed threshold, across every subject/phase/
%  acquisition in the dataset, it checks (a) what fraction of
%  acquisitions land inside your own trusted range [REVIEW_LOW_N,
%  REVIEW_HIGH_N], and (b) how consistent the per-subject median count is
%  across subjects (low spread = a fixed threshold that behaves the same
%  way for everyone, not one that only works for some subjects). Neither
%  of those requires assuming any prior run's counts were correct.
%
%  Candidate thresholds are drawn from percentiles of the NEW signal's own
%  pooled sample distribution across the whole dataset (a real collision
%  should be a rare, large excursion relative to typical background,
%  the same data-driven-noise-floor idea already used elsewhere in this
%  pipeline, e.g. cfg.scr_sensitivity).
%
%  OUTPUT:
%    - FixedThresholdAnalysis.txt   (full text report, via diary)
%    - FixedThresholdAnalysis.mat   (all harvested/validation tables + recommendation)
%    - Figures (PNG in BASE_FOLDER if SAVE_FIGS = true)
%
%  WORKFLOW: edit SUBJECTS_TO_RUN (or leave empty to auto-discover), run.
%  No prompts, fully automatic -- this reprocesses raw audio for every
%  acquisition in the dataset, so it will take a while.

clear; clc; close all;

%% SECTION 0 — PARAMETERS
BASE_FOLDER = '/home/acatalano/Desktop/Virtues_Data';

SUBJECTS_TO_RUN = {};   % leave empty -> auto-discover ALL subject_* folders

% Test1/Test2 (Peg Transfer) included -- single continuous acquisition,
% no Level/rep subfolder, handled explicitly in the sweep loop below.
allPhases = {'Baseline1','Baseline2','level_L1','level_L2','level_L3','level_L4','level_L5','Test1','Test2'};

AUDIO_BP_LOW      = 80;    % Hz
AUDIO_BP_HIGH     = 1000;  % Hz
PEAK_MIN_DIST_SEC = 1;     % must match whatever your detection script uses

REVIEW_LOW_N  = 2;    % your own trusted-range bounds (must match the detection scripts)
REVIEW_HIGH_N = 10;

% Candidate thresholds: percentiles of the pooled per-sample signal
% across the WHOLE dataset (computed in Section 1), not percentiles of
% any prior run's adaptive threshold -- there is no adaptive threshold
% concept left once collisions are peaks on a raw bandpassed signal
% rather than a smoothed envelope.
CANDIDATE_PERCENTILES = [90 95 97 98 99 99.5 99.9];

SAVE_FIGS = true;

base = BASE_FOLDER;

if isempty(SUBJECTS_TO_RUN)
    d = dir(fullfile(base, 'subject_*'));
    SUBJECTS_TO_RUN = {d([d.isdir]).name};
end

report_file = fullfile(base, 'FixedThresholdAnalysis.txt');
if strcmp(get(0,'Diary'), 'on'), diary off; end
diary(report_file);
diary on;

fprintf('Subjects found (%d): %s\n\n', numel(SUBJECTS_TO_RUN), strjoin(SUBJECTS_TO_RUN, ', '));

%% SECTION 1 — COMPUTE THE NEW SIGNAL FOR EVERY ACQUISITION (once, cached)
% Loads audio ONCE per acquisition, computes the per-side bandpassed-sum
% signal ONCE, and pools every sample from every acquisition into one big
% vector to derive candidate thresholds from -- then a cheap findpeaks
% sweep per candidate reuses the cached per-acquisition signal.

acqCache = struct('subject', {}, 'phase', {}, 'acquisition', {}, 'acq_folder', {}, ...
    't_trial', {}, 'sig_trial', {});
pooled_samples = [];   % subsampled pool across all acquisitions, for percentile candidates

for subjIdx = 1:numel(SUBJECTS_TO_RUN)
    subjFolderName = SUBJECTS_TO_RUN{subjIdx};
    SUBJECT = erase(subjFolderName, 'subject_');
    subj_folder = fullfile(base, subjFolderName);
    if ~isfolder(subj_folder), continue; end

    for pIdx = 1:numel(allPhases)
        PHASE = allPhases{pIdx};
        phase_folder = fullfile(subj_folder, PHASE);
        if ~isfolder(phase_folder), continue; end

        is_test_phase = startsWith(PHASE, 'Test', 'IgnoreCase', true);
        if startsWith(PHASE, 'Baseline', 'IgnoreCase', true)
            acquisitions = arrayfun(@(k) sprintf('Level%d', k), 1:5, 'UniformOutput', false);
        elseif is_test_phase
            acquisitions = {'main'};
        else
            acquisitions = arrayfun(@(k) sprintf('rep_%02d', k), 1:10, 'UniformOutput', false);
        end

        for aIdx = 1:numel(acquisitions)
            ACQUISITION = acquisitions{aIdx};
            if is_test_phase
                acq_folder = phase_folder;
            else
                acq_folder = fullfile(phase_folder, ACQUISITION);
                if ~isfolder(acq_folder)
                    if isfolder([acq_folder '_R'])
                        acq_folder = [acq_folder '_R'];
                    else
                        continue;
                    end
                end
            end

            audio_file  = fullfile(acq_folder, 'audio.mat');
            events_file = fullfile(acq_folder, 'events.mat');
            if ~isfile(audio_file) || ~isfile(events_file), continue; end

            try
                U = load(audio_file); AUDIO = U.AUDIO;
                t_aud    = AUDIO.time_rel;
                fs_audio = AUDIO.fs_estimated;
                ch_names = AUDIO.channel_names;

                sig = audio_side_abs_sum(AUDIO, ch_names, AUDIO_BP_LOW, AUDIO_BP_HIGH, fs_audio);

                [t_ws, t_we] = safe_trial_window(events_file);
                if isnan(t_ws) || isnan(t_we), continue; end

                in_trial  = (t_aud >= t_ws) & (t_aud <= t_we);
                t_trial   = t_aud(in_trial);
                sig_trial = sig(in_trial);

                keep = true(size(t_trial));
                last_t = -inf;
                for k = 1:numel(t_trial)
                    if t_trial(k) > last_t, last_t = t_trial(k); else, keep(k) = false; end
                end
                t_trial   = t_trial(keep);
                sig_trial = sig_trial(keep);

                if isempty(sig_trial) || all(isnan(sig_trial)) || numel(t_trial) < 3
                    continue;
                end

                acqCache(end+1) = struct('subject', SUBJECT, 'phase', PHASE, ...
                    'acquisition', ACQUISITION, 'acq_folder', acq_folder, ...
                    't_trial', t_trial, 'sig_trial', sig_trial); %#ok<SAGROW>

                % Subsample (every 10th sample) to keep the pooled vector a
                % manageable size across ~thousands of acquisitions.
                pooled_samples = [pooled_samples; sig_trial(1:10:end)]; %#ok<AGROW>

            catch ME
                fprintf('  [skip %s/%s/%s] %s\n', SUBJECT, PHASE, ACQUISITION, ME.message);
                continue;
            end
        end
    end
    fprintf('Processed %s (%d acquisitions cached so far)\n', SUBJECT, numel(acqCache));
end

if isempty(acqCache)
    error('FindFixedThreshold: no usable acquisitions found -- check BASE_FOLDER and that relabel_test_events.m has been run for Test1/Test2.');
end

fprintf('\nCached %d acquisitions across %d subjects.\n\n', numel(acqCache), numel(unique({acqCache.subject})));

%% SECTION 2 — POOLED SIGNAL DISTRIBUTION AND CANDIDATE THRESHOLDS
fprintf(' POOLED SIGNAL STATISTICS (all subjects, all acquisitions, every 10th sample)\n');
fprintf('  n samples = %d\n', numel(pooled_samples));
fprintf('  min/median/mean/max = %.5f / %.5f / %.5f / %.5f\n', ...
    min(pooled_samples), median(pooled_samples), mean(pooled_samples), max(pooled_samples));

candidates = arrayfun(@(p) prctile(pooled_samples, p), CANDIDATE_PERCENTILES);
candidates = unique(round(candidates, 5));

fprintf('\nCandidate thresholds (percentiles %s of pooled signal): %s\n\n', ...
    mat2str(CANDIDATE_PERCENTILES), mat2str(candidates));

fig1 = figure('Name','Pooled signal histogram','Units','normalized','Position',[0.05 0.1 0.5 0.4],'Visible','off');
histogram(pooled_samples, 100, 'FaceColor',[0.2 0.45 0.8]);
hold on;
for c = 1:numel(candidates)
    xline(candidates(c), '--', sprintf('p%g', CANDIDATE_PERCENTILES(c)), 'LabelOrientation','horizontal');
end
xlabel('Signal amplitude (V)'); ylabel('Sample count');
title('Pooled per-sample distribution of the new audio signal, with candidate thresholds');
set(gca, 'YScale', 'log'); grid on;

%% SECTION 3 — SWEEP: for each candidate, detect collisions in every cached acquisition
fprintf(' SWEEP — detecting collisions per candidate threshold\n');

valRows = {};   % subject, phase, acquisition, candidate, n_collisions
for r = 1:numel(acqCache)
    t_trial   = acqCache(r).t_trial;
    sig_trial = acqCache(r).sig_trial;

    t_span = t_trial(end) - t_trial(1);
    eff_min_dist = PEAK_MIN_DIST_SEC;
    if eff_min_dist >= t_span, eff_min_dist = t_span * 0.5; end
    if eff_min_dist <= 0, continue; end

    for c = 1:numel(candidates)
        [~, locs] = findpeaks(sig_trial, t_trial, 'MinPeakDistance', eff_min_dist, 'MinPeakHeight', candidates(c));
        valRows(end+1,:) = {acqCache(r).subject, acqCache(r).phase, acqCache(r).acquisition, ...
            candidates(c), numel(locs)}; %#ok<AGROW>
    end
end

V = cell2table(valRows, 'VariableNames', {'subject','phase','acquisition','candidate','n_collisions'});

%% SECTION 4 — SCORE EACH CANDIDATE: %-within-trusted-range + per-subject consistency
fprintf('\n%-12s | %-16s | %-18s | %-10s\n', 'Candidate', '%%InTrustedRange', 'PerSubjMedianCV%%', 'MeanCount');
fprintf('%s\n', repmat('-', 1, 65));

subjList = unique(V.subject, 'stable');
candStats = struct('candidate', {}, 'pct_in_range', {}, 'subj_median_cv', {}, 'mean_count', {});

for c = 1:numel(candidates)
    mask = V.candidate == candidates(c);
    counts = V.n_collisions(mask);
    subjs  = V.subject(mask);

    pct_in_range = 100 * mean(counts >= REVIEW_LOW_N & counts <= REVIEW_HIGH_N);
    mean_count   = mean(counts);

    subjMed = nan(numel(subjList), 1);
    for si = 1:numel(subjList)
        subjMed(si) = median(counts(strcmp(subjs, subjList{si})));
    end
    subj_cv = 100 * std(subjMed, 'omitnan') / mean(subjMed, 'omitnan');

    fprintf('%-12.5f | %-16.1f | %-18.1f | %-10.2f\n', candidates(c), pct_in_range, subj_cv, mean_count);

    candStats(end+1) = struct('candidate', candidates(c), 'pct_in_range', pct_in_range, ...
        'subj_median_cv', subj_cv, 'mean_count', mean_count); %#ok<SAGROW>
end

% ---- Pick winner: highest %-in-trusted-range, tie-broken by lowest per-subject CV ----
pct_vals = arrayfun(@(s) s.pct_in_range, candStats);
best_pct = max(pct_vals);
tied = find(pct_vals >= best_pct - 1e-9);   % essentially equal to the max
[~, best_of_tied] = min(arrayfun(@(i) candStats(i).subj_median_cv, tied));
winIdx = tied(best_of_tied);
winningThresh = candStats(winIdx).candidate;

fprintf('\n>>> RECOMMENDED FIXED THRESHOLD: %.5f\n', winningThresh);
fprintf('    %.1f%% of acquisitions land in [%d, %d] collisions; per-subject median CV = %.1f%%\n', ...
    candStats(winIdx).pct_in_range, REVIEW_LOW_N, REVIEW_HIGH_N, candStats(winIdx).subj_median_cv);
fprintf('    This is a recommendation for visual inspection (see figures), not a silent final answer --\n');
fprintf('    "in the trusted range" is a proxy for "plausible," not ground truth on any single acquisition.\n');

%% SECTION 5 — PER-SUBJECT BIAS CHECK FOR THE WINNING THRESHOLD
fprintf('\n PER-SUBJECT MEDIAN COUNT — winning threshold = %.5f\n', winningThresh);

maskWin = V.candidate == winningThresh;
Vwin = V(maskWin, :);

subjBias = struct('subject', {}, 'median_count', {}, 'n', {});
for si = 1:numel(subjList)
    m = strcmp(Vwin.subject, subjList{si});
    if ~any(m), continue; end
    med_c = median(Vwin.n_collisions(m));
    subjBias(end+1) = struct('subject', subjList{si}, 'median_count', med_c, 'n', sum(m)); %#ok<SAGROW>
    flag = '';
    if med_c < REVIEW_LOW_N || med_c > REVIEW_HIGH_N, flag = '  <-- outside trusted range'; end
    fprintf('  %-10s : median n_collisions=%.1f  (n=%d acquisitions)%s\n', subjList{si}, med_c, sum(m), flag);
end

flaggedSubj = {subjBias(arrayfun(@(s) s.median_count < REVIEW_LOW_N || s.median_count > REVIEW_HIGH_N, subjBias)).subject};
if ~isempty(flaggedSubj)
    fprintf('\n  [FLAG] Subjects whose median count falls outside [%d, %d] even at the winning threshold:\n', REVIEW_LOW_N, REVIEW_HIGH_N);
    fprintf('         %s\n', strjoin(flaggedSubj, ', '));
    fprintf('         No single fixed threshold will fit these well -- review individually regardless of the global choice.\n');
else
    fprintf('\n  No subject''s median count falls outside the trusted range at this threshold.\n');
end

%% SECTION 6 — VALIDATION PLOTS
fig2 = figure('Name','Candidate threshold performance','Units','normalized','Position',[0.05 0.1 0.5 0.5],'Visible','off');
yyaxis left;
plot(candidates, pct_vals, '-o', 'LineWidth', 1.5); ylabel('%% acquisitions in trusted range');
yyaxis right;
plot(candidates, arrayfun(@(s) s.subj_median_cv, candStats), '-s', 'LineWidth', 1.5); ylabel('Per-subject median CV (%%)');
hold on;
xline(winningThresh, 'g--', 'LineWidth', 1.5, 'Label', 'recommended');
xlabel('Candidate fixed threshold'); title('Candidate threshold self-consistency'); grid on;

fig3 = figure('Name','Winning threshold -- per-subject median count','Units','normalized','Position',[0.55 0.1 0.4 0.5],'Visible','off');
medVals = arrayfun(@(s) s.median_count, subjBias);
[sortedMed, sortIdx] = sort(medVals);
bar(sortedMed, 'FaceColor',[0.6 0.2 0.6]);
set(gca, 'XTick', 1:numel(subjBias), 'XTickLabel', {subjBias(sortIdx).subject}); xtickangle(45);
ylabel('Median n\_collisions'); title(sprintf('Per-subject median count at threshold=%.5f', winningThresh));
yline(REVIEW_LOW_N, 'r--'); yline(REVIEW_HIGH_N, 'r--'); grid on;

fig4 = figure('Name','Collision count by phase','Units','normalized','Position',[0.05 0.1 0.5 0.4],'Visible','off');
boxplot(Vwin.n_collisions, Vwin.phase);
ylabel('n\_collisions at winning threshold'); title('Collision count distribution per phase');
yline(REVIEW_LOW_N, 'r--'); yline(REVIEW_HIGH_N, 'r--');
xtickangle(45); grid on;

if SAVE_FIGS
    exportgraphics(fig1, fullfile(base, 'newsig_pooled_histogram.png'), 'Resolution',130);
    exportgraphics(fig2, fullfile(base, 'candidate_selfconsistency.png'), 'Resolution',130);
    exportgraphics(fig3, fullfile(base, 'winning_threshold_persubject.png'), 'Resolution',130);
    exportgraphics(fig4, fullfile(base, 'winning_threshold_byphase.png'), 'Resolution',130);
end

%% SECTION 7 — SAVE EVERYTHING
save(fullfile(base, 'FixedThresholdAnalysis.mat'), 'V', 'candStats', 'subjBias', 'winningThresh', 'pooled_samples');
fprintf('\n[SAVE] Validation table and recommendation saved to:\n  %s\n', fullfile(base, 'FixedThresholdAnalysis.mat'));

diary off;
fprintf('\n[REPORT SAVED] -> %s\n\n', report_file);


%  LOCAL FUNCTIONS

function sig = audio_side_abs_sum(AUDIO, ch_names, bp_lo, bp_hi, fs)
% Reproduces Accelerometer_visualization.m's validated sumbp = xbp+ybp+zbp
% exactly, per side (Left: x/y/z summed after individually bandpassing;
% Right: same), then combines the two sides by taking whichever side has
% the larger |sum| at each instant. No rectification before the per-axis
% sum, and no RMS-envelope smoothing.
    scheme_old = {'ch12','ch13','ch14','ch16','ch17','ch18'};   % L: ch12/13/14 | R: ch16/17/18
    scheme_new = {'ch11','ch12','ch13','ch14','ch16','ch17'};   % L: ch11/12/13 | R: ch14/16/17
    if all(ismember(scheme_old, ch_names))
        L_names = scheme_old(1:3); R_names = scheme_old(4:6);
    elseif all(ismember(scheme_new, ch_names))
        L_names = scheme_new(1:3); R_names = scheme_new(4:6);
    else
        error('audio_side_abs_sum: neither known audiomixer channel scheme found in: %s', strjoin(ch_names, ', '));
    end

    get_ch = @(name) double(AUDIO.data(:, find(strcmp(ch_names, name), 1)));
    bp     = @(x) bandpass(x - mean(x, 'omitnan'), [bp_lo bp_hi], fs);

    sum_L = bp(get_ch(L_names{1})) + bp(get_ch(L_names{2})) + bp(get_ch(L_names{3}));
    sum_R = bp(get_ch(R_names{1})) + bp(get_ch(R_names{2})) + bp(get_ch(R_names{3}));

    sig = max(abs(sum_L), abs(sum_R));
end