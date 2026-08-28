%% eye_check_sampling_jitter.m
% Diagnostic only -- run this BEFORE trusting eye_preprocess.m's defaults.
% Mirrors gsr_check_sampling_jitter.m's role for the GSR pipeline, but
% checks two things specific to the eye-tracking data that a single
% sample file (subject_s02N/level_L3/rep_08) already showed are NOT
% edge cases in that file:
%
%   1. TIMESTAMP ORDERING. In the sample file, 4533 / 17938 intervals
%      (25.3%) had NEGATIVE dt -- time_rel was not monotonically
%      increasing, in a repeating pattern of exactly -0.000647s jumps
%      (consistent with two async streams -- e.g. gaze vs
%      pupil/blink/fixation/saccade -- interleaved by simple row
%      concatenation rather than a time-sorted merge, upstream in
%      convert2mat.m/the eye.csv export). Sorting by time_rel removed all
%      duplicate timestamps in that file (0 exact ties after sort), so a
%      stable sort looks like a sufficient fix -- eye_preprocess.m does
%      this -- but this script checks whether that holds across the
%      whole dataset, and how bad the ordering violation is per
%      acquisition, before you rely on it silently fixing everything.
%   2. FIXATION/SACCADE FLAG PLAUSIBILITY. In the sample file, the
%      pre-computed 'fixation' channel was 1 for exactly 1 of 17939
%      samples, and 'saccade' for 4 -- i.e. ~4 saccades detected in a
%      59-second trial, versus a typical 2-4 saccades/SECOND during
%      active visual behavior. That's not a usable saccade-rate signal
%      as-is. Most likely explanation: this task involves continuous
%      smooth-pursuit tracking of moving robotic tools rather than
%      static-scene viewing, and Neon's onboard fixation/saccade
%      classifier (tuned for the latter) rarely fires here -- most
%      samples are probably unclassified pursuit, not fixation. This
%      script counts fixation/saccade events per acquisition across the
%      dataset so you can confirm this is systemic (in which case
%      eye_preprocess.m's own velocity-based saccade detector, not the
%      'saccade' channel, should be the one actually used) rather than a
%      fluke of the one file already inspected.

clear; clc;
cfg = config();

n_check = 800;
rows = {};
count = 0;

for si = 1:numel(cfg.all_subjects)
    if count >= n_check, break; end
    subj     = cfg.all_subjects{si};
    subj_dir = fullfile(cfg.data_root, subj);

    all_phases = [cfg.baseline_phases, cfg.training_levels, cfg.test_phases];
    for ph_idx = 1:numel(all_phases)
        if count >= n_check, break; end
        phase     = all_phases{ph_idx};
        phase_dir = fullfile(subj_dir, phase);
        if ~isfolder(phase_dir), continue; end

        if ismember(phase, cfg.training_levels)
            acquisitions = arrayfun(@(k) sprintf('rep_%02d', k), 1:cfg.n_training_reps, 'UniformOutput', false);
        else
            acquisitions = arrayfun(@(k) sprintf('Level%d', k), 1:numel(cfg.level_names), 'UniformOutput', false);
        end

        for ai = 1:numel(acquisitions)
            if count >= n_check, break; end
            acq     = acquisitions{ai};
            acq_dir = fullfile(phase_dir, acq);
            if ~isfolder(acq_dir)
                if isfolder([acq_dir '_R']), acq_dir = [acq_dir '_R'];
                else, continue; end
            end
            eye_path = fullfile(acq_dir, 'eye.mat');
            ev_path  = fullfile(acq_dir, 'events.mat');
            if ~isfile(eye_path) || ~isfile(ev_path), continue; end

            [t_start, t_end] = safe_trial_window(ev_path);
            if isnan(t_start) || isnan(t_end), continue; end

            try
                loaded = load(eye_path, 'EYE');
                EYE = loaded.EYE;
                t   = EYE.time_rel;
                mask = t >= t_start & t <= t_end;
                t    = t(mask);
                D    = EYE.data(mask, :);
                ch   = EYE.channel_names;
            catch
                continue;
            end
            if numel(t) < 10, continue; end

            duration_s = t_end - t_start;

            % --- Ordering check (on load order, i.e. BEFORE any sort) ---
            dt_raw     = diff(t);
            frac_neg   = mean(dt_raw < 0);
            max_neg    = min([dt_raw(dt_raw<0); 0]);

            % --- Post-sort stats (what eye_preprocess.m will actually see) ---
            t_sorted   = sort(t);
            dt_sorted  = diff(t_sorted);
            n_dup      = sum(dt_sorted == 0);
            fs_est     = 1 / median(dt_sorted(dt_sorted>0));

            % --- Fixation/saccade/blink event counts ---
            idx_fix = find(strcmp(ch, 'fixation'), 1);
            idx_sac = find(strcmp(ch, 'saccade'),  1);
            idx_bli = find(strcmp(ch, 'blink'),    1);
            n_fix = local_count_onsets(D(:, idx_fix));
            n_sac = local_count_onsets(D(:, idx_sac));
            n_bli = local_count_onsets(D(:, idx_bli));

            rows(end+1, :) = {subj, phase, acq, numel(t), duration_s, fs_est, ...
                100*frac_neg, max_neg, n_dup, n_fix, n_sac, n_bli}; %#ok<AGROW>
            count = count + 1;
        end
    end
end

T = cell2table(rows, 'VariableNames', ...
    {'subject','phase','acquisition','n_samples','duration_s','fs_est', ...
     'pct_negative_dt','max_negative_dt_s','n_dup_after_sort', ...
     'n_fixation_events','n_saccade_events','n_blink_events'});
disp(T);

fprintf('\n=== Summary across %d acquisitions ===\n', height(T));
fprintf('Native fs: %.1f +/- %.1f Hz (median %.1f)\n', mean(T.fs_est), std(T.fs_est), median(T.fs_est));

fprintf('\n--- Timestamp ordering ---\n');
fprintf('Acquisitions with ANY out-of-order timestamp: %d / %d (%.1f%%)\n', ...
    sum(T.pct_negative_dt > 0), height(T), 100*mean(T.pct_negative_dt > 0));
fprintf('pct_negative_dt across acquisitions: mean %.1f%%, median %.1f%%, max %.1f%%\n', ...
    mean(T.pct_negative_dt), median(T.pct_negative_dt), max(T.pct_negative_dt));
fprintf('Duplicate timestamps remaining AFTER sort: %d total across all acquisitions (0 expected if sort alone is a sufficient fix)\n', ...
    sum(T.n_dup_after_sort));

fprintf('\n--- Saccade/fixation rate plausibility (per-minute, from the raw channels) ---\n');
sac_per_min = T.n_saccade_events ./ (T.duration_s/60);
fix_per_min = T.n_fixation_events ./ (T.duration_s/60);
fprintf('Saccade events/min: mean %.2f, median %.2f (typical active-viewing saccade rate is ~120-240/min)\n', ...
    mean(sac_per_min), median(sac_per_min));
fprintf('Fixation events/min: mean %.2f, median %.2f\n', mean(fix_per_min), median(fix_per_min));
fprintf(['\nIf saccade events/min is far below typical active-viewing rates across most\n' ...
    'acquisitions (as in the single file already inspected), the ''saccade'' channel is\n' ...
    'not usable as SAP''s saccade-rate outcome directly -- eye_preprocess.m''s own\n' ...
    'velocity-threshold detector should be used instead, and its threshold tuned\n' ...
    'against this dataset''s actual velocity distribution, not assumed.\n']);


function n = local_count_onsets(col)
% Counts rising edges (0->1 transitions) in a binary state/event column.
    col = col(:) == 1;
    d = diff([0; double(col)]);
    n = sum(d == 1);
end
