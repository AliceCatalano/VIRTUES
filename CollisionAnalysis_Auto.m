%% CollisionDetection_Local.m
%  Fully automatic collision detection across ALL phases of one SUBJECT,
%  using a FIXED, validated detection threshold. No plots, no prompts —
%  every acquisition is auto-detected and auto-saved.
%
%  At the end of each phase, a DATA QUALITY REPORT is printed summarizing:
%    - collision counts per repetition (min/max/mean/std, which rep)
%    - which repetitions fall outside the "trusted" count range (FYI only)
%    - collision intensity (accel-g and audio) statistics
%    - the single strongest / weakest collision in the whole phase
%
%  A final report across all phases is printed at the very end.
%
%  WORKFLOW:
%    1. Enter SUBJECT.  skippink subj 44N
%    2. Script loops through every known phase automatically.
%    3. For each phase, loops through every acquisition automatically.
%    4. Nothing is shown/asked — everything is saved directly.
%    5. Quality report printed after each phase + one grand summary at the end.

clear; clc; close all;

% SECTION 1 — FIXED PARAMETERS
BASE_FOLDER   = '~/Desktop/Virtues_Data';

TARGET_FS            = 500;        % Hz — accelerometer processing rate (not used for plotting anymore)
AUDIO_BP_LOW         = 80;         % Hz
AUDIO_BP_HIGH        = 1000;       % Hz
AUDIO_RMS_WIN_SEC    = 0.02;       % RMS envelope window (s)
PEAK_MIN_DIST_SEC    = 0.5;          % minimum gap between detections (s)

% Validated fixed threshold (kept for reference/report; adaptive one used below)
FIXED_AUDIO_THRESHOLD = 0.2;

% Range used ONLY for flagging in the report — does not stop processing
REVIEW_LOW_N  = 2;
REVIEW_HIGH_N = 10;

INTENSITY_WIN_SEC    = 0.10;       % ± half-window around each collision (s)

% SECTION 2 — ASK USER FOR SUBJECT ONLY
base = expanduser(BASE_FOLDER);
SUBJECTS_TO_RUN = {};
if isempty(SUBJECTS_TO_RUN)
    d = dir(fullfile(base, 'subject_*'));
    SUBJECTS_TO_RUN = {d([d.isdir]).name};
end
sprintf('Subjects found (%d): %s\n\n', numel(SUBJECTS_TO_RUN), strjoin(SUBJECTS_TO_RUN, ', '));

for subjIdx = 1:numel(SUBJECTS_TO_RUN)

    subjFolderName = SUBJECTS_TO_RUN{subjIdx};      % e.g. 'subject_s32N'
    SUBJECT = erase(subjFolderName, 'subject_');     % e.g. 's32N'  (used for filenames/labels)

    subj_folder = fullfile(base, subjFolderName);
    report_file = fullfile(subj_folder, sprintf('CollisionReport_%s.txt', SUBJECT));
    assert(isfolder(subj_folder), 'Subject folder not found:\n  %s', subj_folder);
    if strcmp(get(0,'Diary'), 'on')
        diary off;   % just in case a previous run left it open
    end
    if isfile(report_file)
        delete(report_file);   % diary() appends, so clear any stale report first
    end
    diary(report_file);
    diary on;
    
    % SECTION 3 — LOOP THROUGH ALL PHASES AUTOMATICALLY
    allPhases = {'Baseline1','Baseline2','level_L1','level_L2','level_L3','level_L4','level_L5'};
    
    fprintf('\n=== CollisionDetection_Local — FULL AUTO MODE ===\n');
    fprintf('Subject : %s\n', SUBJECT);
    fprintf('Phases  : %s\n\n', strjoin(allPhases, ', '));
    
    grandLog = struct([]);   % accumulates every acquisition across every phase, for the final report
    
    for pIdx = 1:numel(allPhases)
    
        PHASE = allPhases{pIdx};
        phase_folder = fullfile(subj_folder, PHASE);
    
        if ~isfolder(phase_folder)
            fprintf('--- Skipping phase "%s" (folder not found) ---\n\n', PHASE);
            continue;
        end
          
        fprintf(' PHASE: %s\n', PHASE);
        
    
        if startsWith(PHASE, 'Baseline', 'IgnoreCase', true)
            acquisitions = arrayfun(@(k) sprintf('Level%d', k), 1:5, 'UniformOutput', false);
        else
            acquisitions = arrayfun(@(k) sprintf('rep_%02d', k), 1:10, 'UniformOutput', false);
        end
    
        phaseLog = struct([]);   % accumulates every acquisition within this phase
    
        for aIdx = 1:numel(acquisitions)
    
            ACQUISITION = acquisitions{aIdx};
            acq_folder  = fullfile(phase_folder, ACQUISITION);
    
            if ~isfolder(acq_folder)
                if isfolder([acq_folder '_R'])
                    acq_folder = [acq_folder '_R'];
                else
                    fprintf('  [skip] %s — folder not found\n', ACQUISITION);
                    continue;
                end
            end
    
            accel_file  = fullfile(acq_folder, 'accel.mat');
            audio_file  = fullfile(acq_folder, 'audio.mat');
            events_file = fullfile(acq_folder, 'events.mat');
    
            if ~isfile(accel_file) || ~isfile(audio_file) || ~isfile(events_file)
                fprintf('  [skip] %s — missing accel/audio/events.mat\n', ACQUISITION);
                continue;
            end
    
            % ---- LOAD ----
            A = load(accel_file);   ACCEL  = A.ACCEL;
            U = load(audio_file);   AUDIO  = U.AUDIO;
            E = load(events_file);  EVENTS = E.EVENTS;
    
            % ---- ACCELEROMETER ----
            t_niq      = ACCEL.time_rel;
            t0_unix    = ACCEL.t0_unix;
            ACCEL_FS   = ACCEL.fs_nominal;
    
            N_BASELINE = 50;
            V2G        = 1 / 0.4;
            accel_raw  = ACCEL.data;
    
            xL = baseline_and_scale(accel_raw(:,1), N_BASELINE, V2G);
            yL = baseline_and_scale(accel_raw(:,2), N_BASELINE, V2G);
            zL = baseline_and_scale(accel_raw(:,3), N_BASELINE, V2G);
            xR = baseline_and_scale(accel_raw(:,4), N_BASELINE, V2G);
            yR = baseline_and_scale(accel_raw(:,5), N_BASELINE, V2G);
            zR = baseline_and_scale(accel_raw(:,6), N_BASELINE, V2G);
    
            mag_nat = max(sqrt(xL.^2+yL.^2+zL.^2), sqrt(xR.^2+yR.^2+zR.^2));
    
            ds = max(1, round(ACCEL_FS / TARGET_FS));
            [mag_ds, t_ds] = aa_downsample(mag_nat, t_niq, ACCEL_FS, TARGET_FS, 4, ds);
    
            % ---- AUDIO ----
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
            audio_bp  = bandpass_channels(audio_raw, fs_audio, AUDIO_BP_LOW, AUDIO_BP_HIGH);
            env       = rms_envelope(audio_bp, fs_audio, AUDIO_RMS_WIN_SEC);
    
            % ---- TRIAL WINDOW ----
            t_ws = EVENTS.t_trial_start;
            t_we = EVENTS.t_trial_end;
    
            in_trial    = (t_aud >= t_ws) & (t_aud <= t_we);
            audio_trial = audio_bp(in_trial);
            t_trial     = t_aud(in_trial);
            env_trial   = env(in_trial);
            keep = true(size(t_trial));
            last_t = -inf;
            for k = 1:numel(t_trial)
                if t_trial(k) > last_t
                    last_t = t_trial(k);
                else
                    keep(k) = false;
                end
            end
            
            n_dropped = sum(~keep);
            if n_dropped > 0
                fprintf('  [warn] %s — %d non-monotonic audio timestamps removed\n',ACQUISITION, n_dropped);
                t_trial     = t_trial(keep);
                audio_trial = audio_trial(keep);
                env_trial   = env_trial(keep);
            end
            
            if isempty(env_trial) || all(isnan(env_trial))
                fprintf('  [skip] %s — empty/invalid trial window\n', ACQUISITION);
                continue;
            end
            
            % ---- AUTO-DETECT (adaptive threshold, no plot, no prompt) ----
            thresh = 0.0039;
            trial_span = t_trial(end) - t_trial(1);
            if trial_span <= PEAK_MIN_DIST_SEC
                fprintf(['  [SKIP-BAD-AUDIO] %s — trial audio span too short (%.4fs) after removing ' ...
                    'non-monotonic timestamps (dropped %d). Likely corrupted audio.mat for this ' ...
                    'acquisition — flagging, not detecting collisions.\n'], ...
                    ACQUISITION, trial_span, n_dropped);
                continue;
            end
            [~, locs] = findpeaks(env_trial, t_trial, 'MinPeakDistance', PEAK_MIN_DIST_SEC, 'MinPeakHeight', thresh);
    
            coll_t = locs(:);
            n_coll = numel(coll_t);
    
            % ---- INTENSITY ----
            [intens_g, intens_audio] = compute_intensity(coll_t, mag_ds, t_ds, audio_bp, t_aud, ...
                INTENSITY_WIN_SEC, TARGET_FS, fs_audio);
    
            flagged = (n_coll < REVIEW_LOW_N) || (n_coll > REVIEW_HIGH_N);
    
            % ---- SAVE ----
            results = build_results(SUBJECT, PHASE, ACQUISITION, acq_folder, t0_unix, ...
                t_ws, t_we, coll_t, intens_g, intens_audio, ...
                AUDIO_BP_LOW, AUDIO_BP_HIGH, AUDIO_RMS_WIN_SEC, thresh, INTENSITY_WIN_SEC);
    
            out_file = fullfile(acq_folder, 'collision_results.mat');
            save(out_file, 'results');
    
            tag = 'ok';
            if flagged, tag = 'CHECK'; end
            fprintf('  %-10s : n=%2d  |  g[min/max]=%.2f/%.2f  |  audio[min/max]=%.4f/%.4f  |  thresh=%.4f  [%s]\n', ...
                ACQUISITION, n_coll,safe_min(intens_g), safe_max(intens_g),safe_min(intens_audio), safe_max(intens_audio), ...
                thresh, tag);
    
            % ---- LOG FOR REPORT ----
            rec.acquisition = ACQUISITION;
            rec.phase       = PHASE;
            rec.n_coll      = n_coll;
            rec.coll_t      = coll_t;
            rec.intens_g    = intens_g;
            rec.intens_audio= intens_audio;
            rec.thresh      = thresh;
            rec.flagged     = flagged;
            rec.duration    = t_we - t_ws;
    
            phaseLog = [phaseLog, rec]; %#ok<AGROW>
            grandLog = [grandLog, rec]; %#ok<AGROW>
    
        end % acquisition loop
    
        % ---- PHASE QUALITY REPORT ----
        print_phase_report(PHASE, phaseLog, REVIEW_LOW_N, REVIEW_HIGH_N);
    
    end % phase loop

    % SECTION 4 — GRAND SUMMARY ACROSS ALL PHASES
    print_grand_report(SUBJECT, grandLog, REVIEW_LOW_N, REVIEW_HIGH_N);
    
    diary off;
    fprintf('\n[REPORT SAVED] → %s\n\n', report_file);
end
%%
clear; clc; close all;

% ── CONFIG 
BASE_FOLDER   = '~/Desktop/Virtues_Data';
REVIEW_LOW_N  = 2;
REVIEW_HIGH_N = 10;

base = expanduser(BASE_FOLDER);

d = dir(fullfile(base, 'subject_*'));
SUBJECTS = {d([d.isdir]).name};
fprintf('Found %d subjects.\n', numel(SUBJECTS));

allPhases = {'Baseline1','Baseline2','level_L1','level_L2','level_L3','level_L4','level_L5'};

% ── BUILD SESSION LABEL LIST (fixed column order for heatmap) ────────────
session_labels = {};
session_phase  = {};
for pIdx = 1:numel(allPhases)
    PHASE = allPhases{pIdx};
    if startsWith(PHASE, 'Baseline', 'IgnoreCase', true)
        for lv = 1:5
            session_labels{end+1} = sprintf('%s_L%d', PHASE, lv); %#ok<AGROW>
            session_phase{end+1}  = PHASE; %#ok<AGROW>
        end
    else
        for rep = 1:10
            session_labels{end+1} = sprintf('%s_r%02d', PHASE, rep); %#ok<AGROW>
            session_phase{end+1}  = PHASE; %#ok<AGROW>
        end
    end
end
nSess = numel(session_labels);
nSubj = numel(SUBJECTS);

% ── SCAN DISK FOR collision_results.mat ──────────────────────────────────
heat_n       = nan(nSubj, nSess);     % n_collisions, NaN = missing
heat_flagged = false(nSubj, nSess);
row_subject  = {}; row_phase = {}; row_acq = {}; row_n = []; row_flag = [];
row_accel_g  = {}; row_audio = {};

for si = 1:nSubj
    subjFolderName = SUBJECTS{si};
    SUBJECT = erase(subjFolderName, 'subject_');
    subj_folder = fullfile(base, subjFolderName);

    for pIdx = 1:numel(allPhases)
        PHASE = allPhases{pIdx};
        phase_folder = fullfile(subj_folder, PHASE);
        if ~isfolder(phase_folder), continue; end

        if startsWith(PHASE, 'Baseline', 'IgnoreCase', true)
            acquisitions = arrayfun(@(k) sprintf('Level%d', k), 1:5, 'UniformOutput', false);
            col_offset   = find(strcmp(session_phase, PHASE), 1, 'first') - 1;
        else
            acquisitions = arrayfun(@(k) sprintf('rep_%02d', k), 1:10, 'UniformOutput', false);
            col_offset   = find(strcmp(session_phase, PHASE), 1, 'first') - 1;
        end

        for aIdx = 1:numel(acquisitions)
            ACQUISITION = acquisitions{aIdx};
            acq_folder  = fullfile(phase_folder, ACQUISITION);
            if ~isfolder(acq_folder)
                if isfolder([acq_folder '_R']), acq_folder = [acq_folder '_R']; end
            end

            col = col_offset + aIdx;
            res_file = fullfile(acq_folder, 'collision_results.mat');

            if ~isfile(res_file)
                continue;   % stays NaN in heat_n -> "missing"
            end

            R = load(res_file); results = R.results;

            heat_n(si, col)       = results.n_collisions;
            heat_flagged(si, col) = (results.n_collisions < REVIEW_LOW_N) || (results.n_collisions > REVIEW_HIGH_N);

            row_subject{end+1} = SUBJECT;      %#ok<AGROW>
            row_phase{end+1}   = PHASE;        %#ok<AGROW>
            row_acq{end+1}     = ACQUISITION;  %#ok<AGROW>
            row_n(end+1)       = results.n_collisions; %#ok<AGROW>
            row_flag(end+1)    = heat_flagged(si, col); %#ok<AGROW>
            row_accel_g{end+1} = results.peak_accel_g(:); %#ok<AGROW>
            row_audio{end+1}   = results.peak_audio(:);   %#ok<AGROW>
        end
    end
end

fprintf('Loaded collision_results.mat for %d/%d possible acquisitions.\n', ...
    sum(~isnan(heat_n(:))), numel(heat_n));


%  PLOT 1 — HEATMAP: subjects x acquisitions, collision count

figure('Name','Collision Count Heatmap','Position',[50 50 min(22*nSess,1800) max(18*nSubj,500)]);
h_plot = heat_n;
imagesc(h_plot, 'AlphaData', ~isnan(h_plot));
set(gca, 'Color', [0.75 0.75 0.75]);   % grey background shows through NaN (missing)
colormap(parula);
cb = colorbar; cb.Label.String = 'n collisions';
caxis([0, max(REVIEW_HIGH_N+2, max(h_plot(:),[],'omitnan'))]);

set(gca, 'XTick', 1:nSess, 'XTickLabel', session_labels, 'XTickLabelRotation', 90, 'FontSize', 6);
set(gca, 'YTick', 1:nSubj, 'YTickLabel', strrep(SUBJECTS,'subject_',''), 'FontSize', 7);
xlabel('Acquisition'); ylabel('Subject');
title('Collision count per acquisition (grey = missing / no collision\_results.mat)');

% Overlay flagged cells with a red box outline
hold on;
[fr, fc] = find(heat_flagged);
for k = 1:numel(fr)
    rectangle('Position',[fc(k)-0.5, fr(k)-0.5, 1, 1], 'EdgeColor','r', 'LineWidth',1.2);
end


%  PLOT 2 — BOXPLOT: collision count distribution per phase

figure('Name','Collision Count per Phase','Position',[80 80 900 500]);
phase_of_row = row_phase;
uphases = allPhases(ismember(allPhases, unique(phase_of_row)));

grp_data = {}; grp_labels = {};
for pIdx = 1:numel(uphases)
    mask = strcmp(phase_of_row, uphases{pIdx});
    grp_data{end+1} = row_n(mask); %#ok<AGROW>
    grp_labels{end+1} = uphases{pIdx}; %#ok<AGROW>
end

% Build vectors for boxplot (grouped)
all_vals = []; all_grp = [];
for pIdx = 1:numel(grp_data)
    all_vals = [all_vals, grp_data{pIdx}]; %#ok<AGROW>
    all_grp  = [all_grp, repmat(pIdx, 1, numel(grp_data{pIdx}))]; %#ok<AGROW>
end
boxplot(all_vals, all_grp, 'Labels', grp_labels);
hold on;
yline(REVIEW_LOW_N, 'r--', sprintf('review low = %d', REVIEW_LOW_N));
yline(REVIEW_HIGH_N, 'r--', sprintf('review high = %d', REVIEW_HIGH_N));
ylabel('Collisions detected'); title('Collision count distribution per phase');
grid on;


%  PLOT 3 — BAR: % flagged (outside trusted range) per phase

figure('Name','Flagged Fraction per Phase','Position',[100 100 800 450]);
pct_flagged = zeros(numel(uphases),1);
pct_missing = zeros(numel(uphases),1);
n_total_expected = zeros(numel(uphases),1);

for pIdx = 1:numel(uphases)
    PHASE = uphases{pIdx};
    cols = find(strcmp(session_phase, PHASE));
    sub_mat = heat_n(:, cols);
    n_total_expected(pIdx) = numel(sub_mat);
    pct_missing(pIdx) = 100 * sum(isnan(sub_mat(:))) / numel(sub_mat);

    present_mask = ~isnan(sub_mat(:));
    present_vals = sub_mat(present_mask);
    flagged_mask = (present_vals < REVIEW_LOW_N) | (present_vals > REVIEW_HIGH_N);
    if isempty(present_vals)
        pct_flagged(pIdx) = 0;
    else
        pct_flagged(pIdx) = 100 * sum(flagged_mask) / numel(present_vals);
    end
end

bar([pct_flagged, pct_missing], 'grouped');
set(gca, 'XTickLabel', uphases, 'XTickLabelRotation', 20);
legend({'% flagged (of processed)','% missing (no file)'}, 'Location','northoutside','Orientation','horizontal');
ylabel('%'); title('Data quality per phase'); grid on;


%  PLOT 4 — HISTOGRAMS: intensity of detected collisions

allG     = vertcat(row_accel_g{:});
allAudio = vertcat(row_audio{:});
allG     = allG(~isnan(allG));
allAudio = allAudio(~isnan(allAudio));

figure('Name','Collision Intensity Distributions','Position',[120 120 1000 450]);
subplot(1,2,1);
histogram(allG, 40, 'FaceColor',[0.2 0.4 0.8]);
xlabel('Peak accel (g)'); ylabel('Count'); title('Accel intensity of detected collisions'); grid on;

subplot(1,2,2);
histogram(allAudio, 40, 'FaceColor',[0.8 0.3 0.2]);
xlabel('Peak audio amplitude'); ylabel('Count'); title('Audio intensity of detected collisions'); grid on;
xline(0.0039, 'k--', 'fixed thresh (env)', 'LabelVerticalAlignment','bottom');

%  PLOT 5 — SCATTER: accel-g vs audio intensity per collision, by phase

figure('Name','Accel-g vs Audio Intensity per Collision','Position',[140 140 800 650]);
hold on;
colors = lines(numel(uphases));
for pIdx = 1:numel(uphases)
    PHASE = uphases{pIdx};
    mask = strcmp(phase_of_row, PHASE);
    g_vals = vertcat(row_accel_g{mask});
    a_vals = vertcat(row_audio{mask});
    n = min(numel(g_vals), numel(a_vals));
    scatter(a_vals(1:n), g_vals(1:n), 18, colors(pIdx,:), 'filled', 'MarkerFaceAlpha',0.5, 'DisplayName', PHASE);
end
xlabel('Peak audio amplitude'); ylabel('Peak accel (g)');
title('Per-collision intensity — audio vs accel (color = phase)');
legend('Location','best'); grid on;

%
%  PLOT 6 — BAR: total collisions per subject (sorted) + missing overlay

subj_total_coll = sum(heat_n, 2, 'omitnan');
subj_missing    = sum(isnan(heat_n), 2);
subj_names_clean = strrep(SUBJECTS, 'subject_', '');

[sorted_total, order] = sort(subj_total_coll, 'descend');

figure('Name','Total Collisions per Subject','Position',[160 160 1400 500]);
yyaxis left;
bar(sorted_total, 'FaceColor',[0.2 0.5 0.3]);
ylabel('Total collisions (sum across all acquisitions)');

yyaxis right;
plot(subj_missing(order), 'ro-', 'LineWidth',1.2, 'MarkerFaceColor','r');
ylabel('Missing acquisitions (count)');

set(gca, 'XTick', 1:nSubj, 'XTickLabel', subj_names_clean(order), 'XTickLabelRotation', 90, 'FontSize', 7);
title('Total detected collisions vs missing acquisitions, per subject (sorted by total collisions)');
grid on;

fprintf('\nDone. %d subjects, %d total (subject x acquisition) cells, %d with data, %d missing.\n', ...
    nSubj, numel(heat_n), sum(~isnan(heat_n(:))), sum(isnan(heat_n(:))));


% LOCAL FUNCTIONS 

function v = safe_min(x)
    if isempty(x), v = NaN; else, v = min(x); end
end
function v = safe_max(x)
    if isempty(x), v = NaN; else, v = max(x); end
end

function results = build_results(SUBJECT, PHASE, ACQUISITION, acq_folder, t0_unix, ...
        t_ws, t_we, coll_t, intens_g, intens_audio, ...
        AUDIO_BP_LOW, AUDIO_BP_HIGH, AUDIO_RMS_WIN_SEC, thresh_used, INTENSITY_WIN_SEC)

    results.subject        = SUBJECT;
    results.phase          = PHASE;
    results.acquisition    = ACQUISITION;
    results.acq_folder     = acq_folder;
    results.t0_unix        = t0_unix;
    results.t_win_start    = t_ws;
    results.t_win_end      = t_we;
    results.n_collisions   = numel(coll_t);
    results.collision_rel  = coll_t;
    results.collision_unix = t0_unix + coll_t;
    results.peak_accel_g   = intens_g;
    results.peak_audio     = intens_audio;
    results.save_time      = datetime('now');
    results.params         = struct( ...
        'audio_bp_low',       AUDIO_BP_LOW, ...
        'audio_bp_high',      AUDIO_BP_HIGH, ...
        'audio_rms_win_sec',  AUDIO_RMS_WIN_SEC, ...
        'adaptive_thresh',    thresh_used, ...
        'intensity_win_sec',  INTENSITY_WIN_SEC);
end
function p = expanduser(p)
    if startsWith(p,'~')
        home = char(java.lang.System.getProperty('user.home'));
        p    = [home, p(2:end)];
    end
end

function ch = baseline_and_scale(raw, n_base, V2G)
    n_bl = min(n_base, numel(raw));
    ch   = (raw - mean(raw(1:n_bl))) * V2G;
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

function [sd, td] = aa_downsample(sig, t, fi, ~, ord, ds)
    Wn = min(0.99, (fi/ds/2*0.9) / (fi/2));
    [b,a] = butter(ord, Wn, 'low');
    sf = filtfilt(b, a, double(sig));
    nd = floor(numel(sf)/ds);
    sd = zeros(nd,1);  td = zeros(nd,1);
    for k = 1:nd
        idx    = (k-1)*ds+1 : k*ds;
        sd(k)  = mean(sf(idx));
        td(k)  = t(idx(1));
    end
end

function [ig, ia] = compute_intensity(ct, mag_ds, t_ds, audio_bp, t_aud,win_sec, tgt_fs, fs_aud)
    n   = numel(ct);
    ig  = nan(n,1);
    ia  = nan(n,1);
    hwa = round(win_sec * tgt_fs);
    hwu = round(win_sec * fs_aud);
    for ci = 1:n
        [~,ic] = min(abs(t_ds  - ct(ci)));
        [~,iu] = min(abs(t_aud - ct(ci)));
        ig(ci) = max(mag_ds(  max(1,ic-hwa):min(numel(mag_ds),  ic+hwa)));
        ia(ci) = max(audio_bp(max(1,iu-hwu):min(numel(audio_bp),iu+hwu)));
    end
end

%  REPORTING 
function print_phase_report(PHASE, phaseLog, lowN, highN)

    fprintf(' DATA QUALITY REPORT — Phase: %s\n', PHASE);
    
    if isempty(phaseLog)
        fprintf('  No acquisitions processed for this phase.\n\n');
        return;
    end

    nAcq   = numel(phaseLog);
    counts = arrayfun(@(r) r.n_coll, phaseLog);

    fprintf('  Acquisitions processed : %d\n', nAcq);
    fprintf('  Total collisions found : %d\n', sum(counts));
    fprintf('  Collisions per rep     : min=%d  max=%d  mean=%.1f  median=%.1f  std=%.2f\n', ...
        min(counts), max(counts), mean(counts), median(counts), std(counts));

    [~, iMin] = min(counts);
    [~, iMax] = max(counts);
    fprintf('    → fewest  collisions : %-10s (n=%d)\n', phaseLog(iMin).acquisition, counts(iMin));
    fprintf('    → most    collisions : %-10s (n=%d)\n', phaseLog(iMax).acquisition, counts(iMax));

    flaggedIdx = find(arrayfun(@(r) r.flagged, phaseLog));
    if isempty(flaggedIdx)
        fprintf('  Flagged reps (n<%d or n>%d) : none\n', lowN, highN);
    else
        flaggedNames = arrayfun(@(i) sprintf('%s(n=%d)', phaseLog(i).acquisition, phaseLog(i).n_coll), ...
            flaggedIdx, 'UniformOutput', false);
        fprintf('  Flagged reps (n<%d or n>%d) : %s\n', lowN, highN, strjoin(flaggedNames, ', '));
    end

    % ---- Intensity stats across all collisions in this phase ----
    allG     = vertcat(phaseLog.intens_g);
    allAudio = vertcat(phaseLog.intens_audio);
    allG     = allG(~isnan(allG));
    allAudio = allAudio(~isnan(allAudio));

    if ~isempty(allG)
        fprintf('\n  Accel intensity (peak g) across all collisions:\n');
        fprintf('    min=%.2f  max=%.2f  mean=%.2f  median=%.2f  std=%.2f\n', ...
            min(allG), max(allG), mean(allG), median(allG), std(allG));
    else
        fprintf('\n  Accel intensity: no collisions detected in this phase.\n');
    end

    if ~isempty(allAudio)
        fprintf('  Audio intensity (peak amplitude) across all collisions:\n');
        fprintf('    min=%.4f  max=%.4f  mean=%.4f  median=%.4f  std=%.4f\n', ...
            min(allAudio), max(allAudio), mean(allAudio), median(allAudio), std(allAudio));
    end

    % ---- Strongest / weakest single collision (by accel-g) ----
    [strongVal, strongLoc] = find_extreme_collision(phaseLog, 'max');
    [weakVal,   weakLoc]   = find_extreme_collision(phaseLog, 'min');

    if ~isnan(strongVal)
        fprintf('\n  STRONGEST single collision : %-10s  t=%.3fs  peak-g=%.2f\n', ...
            strongLoc.acquisition, strongLoc.t, strongVal);
    end
    if ~isnan(weakVal)
        fprintf('  WEAKEST   single collision : %-10s  t=%.3fs  peak-g=%.2f\n', ...
            weakLoc.acquisition, weakLoc.t, weakVal);
    end

    % ---- Adaptive threshold spread (sanity check across reps) ----
    threshVals = arrayfun(@(r) r.thresh, phaseLog);
    fprintf('\n  Adaptive threshold used : min=%.4f  max=%.4f  mean=%.4f\n', ...
        min(threshVals), max(threshVals), mean(threshVals));

   
end

function [val, loc] = find_extreme_collision(phaseLog, mode)
    val = NaN; loc = struct('acquisition','', 't', NaN);
    for k = 1:numel(phaseLog)
        g = phaseLog(k).intens_g;
        t = phaseLog(k).coll_t;
        if isempty(g), continue; end
        switch mode
            case 'max'
                [v, i] = max(g);
                better = isnan(val) || v > val;
            case 'min'
                [v, i] = min(g);
                better = isnan(val) || v < val;
        end
        if better
            val = v;
            loc.acquisition = phaseLog(k).acquisition;
            loc.t = t(i);
        end
    end
end

function print_grand_report(SUBJECT, grandLog, lowN, highN)

    
    fprintf(' GRAND SUMMARY — Subject: %s  (all phases combined)\n', SUBJECT);
    

    if isempty(grandLog)
        fprintf('  No data processed.\n\n');
        return;
    end

    phases = unique({grandLog.phase}, 'stable');
    fprintf('  Phases processed : %s\n', strjoin(phases, ', '));
    fprintf('  Total acquisitions : %d\n', numel(grandLog));

    counts = arrayfun(@(r) r.n_coll, grandLog);
    fprintf('  Total collisions across all phases : %d\n', sum(counts));
    fprintf('  Collisions per rep (global) : min=%d  max=%d  mean=%.1f  std=%.2f\n', ...
        min(counts), max(counts), mean(counts), std(counts));

    flaggedCount = sum(arrayfun(@(r) r.flagged, grandLog));
    fprintf('  Flagged reps (n<%d or n>%d) : %d / %d (%.1f%%)\n', ...
        lowN, highN, flaggedCount, numel(grandLog), 100*flaggedCount/numel(grandLog));

    allG     = vertcat(grandLog.intens_g);
    allAudio = vertcat(grandLog.intens_audio);
    allG     = allG(~isnan(allG));
    allAudio = allAudio(~isnan(allAudio));

    if ~isempty(allG)
        fprintf('\n  Accel intensity (peak g) — ALL phases:\n');
        fprintf('    min=%.2f  max=%.2f  mean=%.2f  median=%.2f  std=%.2f\n', ...
            min(allG), max(allG), mean(allG), median(allG), std(allG));
    end
    if ~isempty(allAudio)
        fprintf('  Audio intensity — ALL phases:\n');
        fprintf('    min=%.4f  max=%.4f  mean=%.4f  median=%.4f  std=%.4f\n', ...
            min(allAudio), max(allAudio), mean(allAudio), median(allAudio), std(allAudio));
    end

    [strongVal, strongLoc] = find_extreme_collision(grandLog, 'max');
    [weakVal,   weakLoc]   = find_extreme_collision(grandLog, 'min');

    if ~isnan(strongVal)
        fprintf('\n  STRONGEST collision overall : %s | %-10s  t=%.3fs  peak-g=%.2f\n', ...
            find_phase_of(grandLog, strongLoc.acquisition), strongLoc.acquisition, strongLoc.t, strongVal);
    end
    if ~isnan(weakVal)
        fprintf('  WEAKEST   collision overall : %s | %-10s  t=%.3fs  peak-g=%.2f\n', ...
            find_phase_of(grandLog, weakLoc.acquisition), weakLoc.acquisition, weakLoc.t, weakVal);
    end
end

function phaseName = find_phase_of(grandLog, acqName)
    idx = find(strcmp({grandLog.acquisition}, acqName), 1);
    if isempty(idx)
        phaseName = '?';
    else
        phaseName = grandLog(idx).phase;
    end
end