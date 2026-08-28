function rest_ref = eye_rest_baseline(subj, cfg)
% Load and preprocess resting state R1, return mean pupil diameter as the
% subject-level baseline for pupil-diameter comparisons -- mirrors
% gsr_rest_baseline.m exactly (same R1 folder, same sub-window logic),
% applied to eye.mat instead of gsr.mat.
%
% Only pupil diameter is baselined here, not every eye-tracking outcome:
%   - Absolute pupil diameter varies enormously across individuals (iris
%     pigmentation, age, recent light exposure), so raw cross-subject
%     comparison isn't meaningful without a resting reference -- this is
%     standard practice in pupillometry, and the direct analogue of why
%     scl_mean gets baseline-corrected in gsr_extract_features.m.
%   - gaze_dispersion is NOT baselined against rest: during a quiet
%     resting block there is no comparable visual scene/task for gaze to
%     disperse across, so a resting spatial-spread value isn't a
%     meaningful "zero" for an active visual-search/tracking measure.
%   - saccade_rate is NOT baselined against rest for the same reason --
%     saccade behavior during unengaged rest isn't a meaningful reference
%     point for saccade behavior during an active manipulation task.
%   - collision_pupil_response_mean is already baselined locally (against
%     each collision's own 1s pre-event window), so it doesn't need a
%     session-level resting reference either -- same logic already
%     applied to SCR amplitude/frequency in gsr_extract_features.m.
%   - pupil_slope (a rate, mm/s) is also left uncorrected: an additive
%     resting-level offset doesn't transfer to a slope the way it does to
%     a mean level.

    if ~isfield(cfg, 'resting_duration'),      cfg.resting_duration = 180; end
    if ~isfield(cfg, 'baseline_offset_start'),  cfg.baseline_offset_start = 5;  end
    if ~isfield(cfg, 'baseline_offset_end'),    cfg.baseline_offset_end   = 15; end

    snum_full = strrep(subj, 'subject_', '');
    rest_dir  = fullfile(cfg.data_root, subj, 'resting_state', ...
                         sprintf('%s_r1', snum_full));
    eye_path  = fullfile(rest_dir, 'eye.mat');
    ev_path   = fullfile(rest_dir, 'events.mat');

    if ~isfile(eye_path) || ~isfile(ev_path)
        warning('eye_rest_baseline: R1 not found for %s — using empty reference', subj);
        rest_ref = [];
        return;
    end

    [~, t_end] = safe_trial_window(ev_path);
    if isnan(t_end)
        warning('eye_rest_baseline: no RESTING_END event found for %s — using empty reference', subj);
        rest_ref = [];
        return;
    end
    block_start = t_end - cfg.resting_duration;
    t_start     = block_start + cfg.baseline_offset_start;
    t_win_end   = block_start + cfg.baseline_offset_end;

    try
        proc = eye_preprocess(eye_path, cfg, t_start, t_win_end);
    catch ME
        warning('eye_rest_baseline: preprocessing failed for %s: %s — using empty reference', subj, ME.message);
        rest_ref = [];
        return;
    end

    valid_pupil = isfinite(proc.pupil);
    if sum(valid_pupil) < 2
        warning('eye_rest_baseline: no valid (non-blink) pupil samples in R1 window for %s — using empty reference', subj);
        rest_ref = [];
        return;
    end

    rest_ref.pupil_mean = mean(proc.pupil(valid_pupil));
    rest_ref.pupil_std  = std(proc.pupil(valid_pupil));
    rest_ref.source     = eye_path;
    rest_ref.window     = [t_start, t_win_end];

    fprintf('  R1 eye reference [%.1f-%.1fs]: pupil_mean=%.4f mm\n', ...
        t_start, t_win_end, rest_ref.pupil_mean);
end
