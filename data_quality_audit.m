%% data_quality_audit.m
% Census of every documented exclusion/missing-data mechanism in the
% pipeline, run against the ACTUAL current data on disk, for the
% "data quality" supervisor slide: which subjects/trials are excluded,
% from which specific tables, under which specific rule, and why.
%
% This is a read-only audit (does not modify any data or re-run
% preprocessing) -- it inspects the already-saved feature tables and
% raw per-acquisition files. Run gsr_extract_features.m / eye_extract_
% features.m / perf_extract_features.m / perf_extract_force_vibration_
% features.m / CollisionAnalysis_Auto.m first if you want fully current
% numbers.
%
% DOCUMENTED EXCLUSION MECHANISMS (verified by reading the source, not
% assumed):
%   1. Canonical subject list: exactly 47 subjects (config.m
%      cfg.all_subjects). Two respondents in the raw demographics export
%      (s00H, s01H) are pilot subjects, never part of the 47 -- they are
%      kept in demographics.csv (prepare_demographics.m) but never match
%      any feature-table row, so they contribute nothing to any result.
%   2. GSR: a trial's entire row is DROPPED (not NaN'd) from
%      eda_features.mat if gsr_preprocess.m errors -- fewer than 20
%      samples in the trial window, OR a dropout gap > cfg.max_gap_s
%      (0.5s), OR cvxEDA decomposition fails. Gaps are never interpolated
%      across; the row is excluded outright.
%   3. Eye-tracking: same pattern, eye_preprocess.m, threshold
%      cfg.eye_max_gap_s (0.2s). Additionally, individual samples flagged
%      by the tracker's own blink flag are excluded (not interpolated)
%      WITHIN an otherwise-surviving trial.
%   4. Force/vibration: tssf_raw/tssv are NaN'd (row kept, not dropped)
%      per acquisition if force.mat/accel.mat is missing for that
%      acquisition. tssf_raw is additionally a construct-validity caveat
%      (relative platform-loading proxy, not calibrated Newtons -- no
%      factory calibration matrix exists for this sensor).
%   5. Collision detection: an acquisition is skipped entirely (no
%      collision_results.mat saved -- "SKIP-BAD-AUDIO") if, after
%      removing non-monotonic audio timestamps, the remaining trial audio
%      span is too short to run peak detection (likely corrupted
%      audio.mat). Acquisitions with n_collisions outside
%      [REVIEW_LOW_N=2, REVIEW_HIGH_N=10] are FLAGGED for manual review,
%      not auto-excluded.
%   6. Random-effects structure: models fall back from maximal
%      (correlated intercept+slope) to reduced (uncorrelated) when the
%      maximal fit is degenerate -- a model-fitting choice, not a data
%      exclusion, but affects which SEs are trustworthy; recorded per
%      result, not silently decided.
%   7. Pipeline-wide policy: missing/unreliable data is excluded and
%      documented, never interpolated or imputed to fill a gap.
%
% This script counts how many rows/acquisitions each mechanism actually
% affects in the CURRENT data, rather than just listing the mechanisms.

clear; clc;
cfg = config();

fprintf('================================================================\n');
fprintf('DATA QUALITY AUDIT -- %s\n', datestr(now));
fprintf('================================================================\n');

%% 1. Subject accounting
fprintf('\n--- 1. Subject accounting ---\n');
fprintf('Canonical subjects (config.m): %d  (N=%d, H=%d)\n', ...
    numel(cfg.all_subjects), numel(cfg.subjects_N), numel(cfg.subjects_H));

demo_path = fullfile(cfg.data_root, 'demographics.csv');
if isfile(demo_path)
    Tdemo = readtable(demo_path);
    fprintf('demographics.csv: %d rows total\n', height(Tdemo));
else
    fprintf('demographics.csv NOT FOUND at %s -- run prepare_demographics.m first.\n', demo_path);
end

%% 2. Per-modality row accounting (how many subject x phase x acquisition
%%    combinations exist vs. how many are actually present)
fprintf('\n--- 2. Feature-table coverage ---\n');
tables_to_check = {
    'eda_features.mat',            'EDA (GSR)'
    'eye_features.mat',            'Eye-tracking'
    'perf_features.mat',           'Performance'
    'force_vibration_features.mat','Force/vibration'
    };
for i = 1:size(tables_to_check, 1)
    path = fullfile(cfg.output_root, tables_to_check{i,1});
    label = tables_to_check{i,2};
    if ~isfile(path)
        fprintf('%-16s : FILE NOT FOUND (%s) -- run the corresponding extract_features script.\n', label, tables_to_check{i,1});
        continue;
    end
    L = load(path, 'T');
    T = L.T;
    n_subj_present = numel(unique(T.subject));
    fprintf('%-16s : %5d rows | %2d/%2d subjects have >=1 row', label, height(T), n_subj_present, numel(cfg.all_subjects));
    missing_subj = setdiff(cfg.all_subjects, unique(T.subject));
    if ~isempty(missing_subj)
        fprintf('  | MISSING ENTIRELY: %s', strjoin(missing_subj, ', '));
    end
    fprintf('\n');
    for pt = {'baseline','training','test'}
        n = sum(strcmp(T.phase_type, pt{1}));
        fprintf('                    %-9s: %5d rows\n', pt{1}, n);
    end
end

%% 3. NaN / missing-value rates per key outcome column
fprintf('\n--- 3. NaN rate per outcome (within its own table) ---\n');
outcome_tables = {
    'eda_features.mat',             {'scl_mean','scr_freq','scr_mean_amp','collision_scr_amp_mean'}
    'eye_features.mat',             {'pupil_mean','pupil_slope_norm','gaze_dispersion','saccade_rate','collision_pupil_response_mean'}
    'perf_features.mat',            {'duration_s','n_collisions'}
    'force_vibration_features.mat', {'tssf_raw','tssv'}
    };
for i = 1:size(outcome_tables, 1)
    path = fullfile(cfg.output_root, outcome_tables{i,1});
    if ~isfile(path), continue; end
    L = load(path, 'T'); T = L.T;
    for oc = outcome_tables{i,2}
        col = oc{1};
        if ~ismember(col, T.Properties.VariableNames), continue; end
        n_nan = sum(~isfinite(T.(col)));
        fprintf('  %-30s : %4d / %4d rows NaN (%.1f%%)\n', col, n_nan, height(T), 100*n_nan/height(T));
        if n_nan > 0
            nan_subj = T.subject(~isfinite(T.(col)));
            [u_subj, ~, ic] = unique(nan_subj);
            counts = accumarray(ic, 1);
            [counts, order] = sort(counts, 'descend');
            u_subj = u_subj(order);
            top_n = min(5, numel(u_subj));
            parts = arrayfun(@(k) sprintf('%s(%d)', u_subj{k}, counts(k)), 1:top_n, 'UniformOutput', false);
            fprintf('      NaN concentrated in %d/%d subjects; top: %s%s\n', numel(u_subj), numel(unique(T.subject)), ...
                strjoin(parts, ', '), local_ternary(numel(u_subj) > top_n, ', ...', ''));
        end
    end
end

%% 4. Collision-detection coverage: audio.mat present vs. collision_results.mat present
fprintf('\n--- 4. Collision detection coverage (SKIP-BAD-AUDIO census) ---\n');
REVIEW_LOW_N = 2; REVIEW_HIGH_N = 10;
n_audio_present = 0; n_coll_present = 0; n_flagged = 0;
n_flagged_low = 0; n_flagged_high = 0;
skip_list = {};
flag_list = {};
all_phases = [cfg.baseline_phases, cfg.training_levels, cfg.test_phases];
for si = 1:numel(cfg.all_subjects)
    subj = cfg.all_subjects{si};
    for ph_idx = 1:numel(all_phases)
        phase = all_phases{ph_idx};
        phase_dir = fullfile(cfg.data_root, subj, phase);
        if ~isfolder(phase_dir), continue; end
        if ismember(phase, cfg.training_levels)
            acqs = arrayfun(@(k) sprintf('rep_%02d', k), 1:cfg.n_training_reps, 'UniformOutput', false);
        elseif ismember(phase, cfg.baseline_phases)
            acqs = arrayfun(@(k) sprintf('Level%d', k), 1:numel(cfg.level_names), 'UniformOutput', false);
        else
            acqs = {'main'};
        end
        is_test = ismember(phase, cfg.test_phases);
        for ai = 1:numel(acqs)
            acq = acqs{ai};
            if is_test
                acq_dir = phase_dir;
            else
                acq_dir = fullfile(phase_dir, acq);
                if ~isfolder(acq_dir)
                    if isfolder([acq_dir '_R']), acq_dir = [acq_dir '_R']; else, continue; end
                end
            end
            audio_path = fullfile(acq_dir, 'audio.mat');
            coll_path  = fullfile(acq_dir, 'collision_results.mat');
            if ~isfile(audio_path), continue; end
            n_audio_present = n_audio_present + 1;
            if isfile(coll_path)
                n_coll_present = n_coll_present + 1;
                C = load(coll_path, 'results');
                n_coll = C.results.n_collisions;
                if n_coll < REVIEW_LOW_N
                    n_flagged = n_flagged + 1;
                    n_flagged_low = n_flagged_low + 1;
                    flag_list{end+1} = sprintf('%s/%s/%s (n=%d, LOW)', subj, phase, acq, n_coll); %#ok<AGROW>
                elseif n_coll > REVIEW_HIGH_N
                    n_flagged = n_flagged + 1;
                    n_flagged_high = n_flagged_high + 1;
                    flag_list{end+1} = sprintf('%s/%s/%s (n=%d, HIGH)', subj, phase, acq, n_coll); %#ok<AGROW>
                end
            else
                skip_list{end+1} = sprintf('%s/%s/%s', subj, phase, acq); %#ok<AGROW>
            end
        end
    end
end
fprintf('Acquisitions with audio.mat:             %d\n', n_audio_present);
fprintf('Acquisitions with collision_results.mat: %d (%.1f%%)\n', n_coll_present, 100*n_coll_present/max(n_audio_present,1));
fprintf('SKIP-BAD-AUDIO (audio present, no collision_results.mat): %d\n', numel(skip_list));
if ~isempty(skip_list)
    fprintf('  %s\n', strjoin(skip_list, '\n  '));
end
fprintf('FLAGGED for manual review (n_collisions outside [%d,%d]): %d / %d (%.1f%%)\n', ...
    REVIEW_LOW_N, REVIEW_HIGH_N, n_flagged, n_coll_present, 100*n_flagged/max(n_coll_present,1));
fprintf(['  -> LOW (n_collisions < %d, usually just a clean/easy trial, not a defect): %d / %d (%.1f%%)\n' ...
         '  -> HIGH (n_collisions > %d, worth a second look): %d / %d (%.1f%%)\n'], ...
    REVIEW_LOW_N, n_flagged_low,  n_coll_present, 100*n_flagged_low/max(n_coll_present,1), ...
    REVIEW_HIGH_N, n_flagged_high, n_coll_present, 100*n_flagged_high/max(n_coll_present,1));
if n_flagged_high > 0
    fprintf('  HIGH-flagged acquisitions (these are the ones worth reviewing):\n');
    high_only = flag_list(contains(flag_list, 'HIGH'));
    fprintf('    %s\n', strjoin(high_only, '\n    '));
end

%% 5. Gap-exclusion thresholds currently in effect (from config.m)
fprintf('\n--- 5. Active dropout-gap exclusion thresholds ---\n');
fprintf('GSR:  cfg.max_gap_s     = %.2fs  (trial dropped if any gap exceeds this)\n', cfg.max_gap_s);
fprintf('Eye:  cfg.eye_max_gap_s = %.2fs  (trial dropped if any gap exceeds this)\n', cfg.eye_max_gap_s);

fprintf('\n================================================================\n');
fprintf('Audit complete. See the header comment of this script for the\n');
fprintf('documented mechanism behind each number above.\n');
fprintf('================================================================\n');

function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
