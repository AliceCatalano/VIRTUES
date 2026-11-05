function eye_out = eye_preprocess(eye_mat_path, cfg, t_start, t_end)
% EYE_PREPROCESS  Load, sort, window, and lightly clean one acquisition's Neon eye-tracking recording, ready for eye_extract_features.m.
%
% Unlike gsr_preprocess.m, this does NOT resample onto a uniform time grid: none of the features computed downstream (pupil-diameter linear
% trend, gaze dispersion, velocity-based saccade detection) require constant sample spacing the way cvxEDA/filtfilt do for GSR -- resampling
% here would only add distortion for no benefit, so all outputs keep the real, sorted, irregularly-spaced timestamps.
%
% TIMESTAMP ORDERING: inspection across the dataset (eye_check_sampling_jitter.m) found time_rel NOT monotonically increasing in 34.6% of
% acquisitions, consistent with two async streams (gaze vs pupil/blink/fixation/saccade) merged by simple concatenation rather than a
% time-sorted join, upstream in the eye.csv export/convert2mat.m. This function windows to [t_start, t_end] FIRST (a value-based mask, so it's
% correct regardless of row order), THEN measures/reports ordering violations (eye_out.n_reordered) and sorts -- so n_reordered reflects
% ordering quality only WITHIN the trial itself, not pre-trial setup or post-trial teardown periods in the raw recording, which are out of
% scope for this analysis. Sorting removed all duplicate timestamps in every acquisition checked dataset-wide, so it's treated as a sufficient
% fix, not just a one-file observation.
%
% BLINK HANDLING: pupil diameter and gaze position (x,y) are set to NaN wherever the tracker's own 'blink' flag is 1, rather than interpolated
% -- gaze position and pupil diameter are not reliable during blinks (partial/full occlusion), and the GSR pipeline's policy in this project
% is to exclude rather than fabricate over invalid physiological samples; the same policy is applied here. In the one file inspected, pupil
% diameter did NOT drop to zero/NaN during tracker-flagged blinks (mean 3.99 vs 4.00 mm blink vs non-blink), so this exclusion is a deliberate
% conservative choice per standard pupillometry practice, not something forced by obviously-corrupted data -- worth knowing if you see fewer
% valid pupil samples than expected.
%
% SACCADE DETECTION: the tracker's own 'saccade' channel is NOT used -- in the sample file it flagged only 4 events in a 59s trial (~4/min,
% versus a typical ~120-240/min during active visual behavior), most likely because this task involves continuous smooth-pursuit tracking of
% moving tools rather than static-scene viewing, which the onboard classifier isn't tuned for. Instead, saccades are detected here with a
% velocity-threshold (I-VT) method computed directly from x,y and time: gaze velocity (px/s) is computed only between temporally-adjacent VALID
% (non-blink) sample pairs whose dt is not itself a dropout gap, then thresholded at median + cfg.eye_saccade_k_mad * MAD (default k=5,
% matching the same MAD-multiplier pattern used for cfg.scr_sensitivity in the GSR pipeline) since no scene-camera pixel-to-degree calibration
% is available to use a literature-standard deg/s threshold. TUNE cfg.eye_saccade_k_mad against a few subjects' velocity traces before
% trusting saccade counts at scale -- exactly the same caveat already documented for cfg.scr_sensitivity.

    loaded = load(eye_mat_path, 'EYE');
    EYE = loaded.EYE;

    t_raw = EYE.time_rel(:);
    D_raw = EYE.data;
    ch    = EYE.channel_names;

    % Window FIRST, on the raw (unsorted) arrays, before computing any
    % quality/ordering diagnostic or sorting -- a value-based mask
    % (t_raw >= t_start & t_raw <= t_end) is order-independent, so this
    % correctly keeps only samples whose OWN timestamp falls inside the
    % trial regardless of where they sit in the recorded row order. Data
    % quality outside [t_start, t_end] (pre-trial setup, calibration,
    % post-trial teardown) is deliberately not reflected in n_reordered or
    % anything else this function reports -- only the trial itself.
    if ~isempty(t_start) && ~isempty(t_end) && ~isnan(t_start) && ~isnan(t_end)
        win_mask = t_raw >= t_start & t_raw <= t_end;
        t_raw = t_raw(win_mask);
        D_raw = D_raw(win_mask, :);
    end

    if numel(t_raw) < 20
        error('eye_preprocess: fewer than 20 samples in window for %s', eye_mat_path);
    end

    n_reordered = sum(diff(t_raw) < 0);   % ordering violations WITHIN the trial window only

    [t, order] = sort(t_raw);
    D = D_raw(order, :);
    

    col = @(name) D(:, strcmp(ch, name));
   
    blink  = col('blink') == 1;
    pdl    = col('pupil_diameter_left');
    pdr    = col('pupil_diameter_right');
    x      = col('x');
    y      = col('y');


    if ~isfield(cfg, 'eye_max_gap_s') || isempty(cfg.eye_max_gap_s)
        cfg.eye_max_gap_s = 0.2;   % ~15-45x the native ~4-15ms sample spacing; see eye_check_sampling_jitter.m
    end
    dt = diff(t);
    max_gap = max(dt);
    if max_gap > cfg.eye_max_gap_s
        error('eye_preprocess: dropout gap of %.3fs exceeds cfg.eye_max_gap_s (%.3fs) in %s', ...
            max_gap, cfg.eye_max_gap_s, eye_mat_path);
    end
    fs_est = 1 / median(dt(dt > 0));

    % --- Pupil diameter: mean of left/right, NaN'd during blinks ---
    pupil = mean([pdl, pdr], 2, 'omitnan');
    pupil(blink) = NaN;

    % --- Gaze position: NaN'd during blinks ---
    xg = x; xg(blink) = NaN;
    yg = y; yg(blink) = NaN;

    % --- Velocity-based saccade detection ---
    if ~isfield(cfg, 'eye_saccade_k_mad') || isempty(cfg.eye_saccade_k_mad)
        cfg.eye_saccade_k_mad = 5;
    end
    valid = ~blink;
    vi = find(valid);
    sac_times = [];
    if numel(vi) > 2
        dt_v   = t(vi(2:end)) - t(vi(1:end-1));
        dist_v = hypot(x(vi(2:end)) - x(vi(1:end-1)), y(vi(2:end)) - y(vi(1:end-1)));
        gate   = dt_v <= 3 * median(dt(dt > 0));   % don't compute velocity across a bridged gap/blink run
        vel    = nan(size(dt_v));
        vel(gate) = dist_v(gate) ./ dt_v(gate);

        vel_valid = vel(isfinite(vel));
        thresh = median(vel_valid, 'omitnan') + cfg.eye_saccade_k_mad * mad(vel_valid, 1);
        above  = isfinite(vel) & vel > thresh;

        d = diff([0; above(:); 0]);
        starts = find(d == 1); ends_ = find(d == -1) - 1;
        sac_times = t(vi(starts + 1));   % velocity sample i corresponds to the sample AFTER vi(i)
    end

    eye_out.time         = t;
    eye_out.pupil        = pupil;
    eye_out.x            = xg;
    eye_out.y            = yg;
    eye_out.blink        = blink;
    eye_out.saccade_times = sac_times;
    %eye_out.valid_duration_s = sum(dt(gate_diff(t, blink)));  %#ok<NASGU> placeholder removed below
    eye_out.fs_est        = fs_est;
    eye_out.n_reordered   = n_reordered;
    eye_out.source        = eye_mat_path;

    % valid_duration_s: total time spanned by non-blink samples (used to
    % normalize saccade rate per minute of USABLE gaze time, not total
    % trial time, since a heavily-blinking trial should not look like it
    % has a lower saccade rate just because more of it was excluded).
    eye_out.valid_duration_s = sum(dt(~blink(1:end-1) & ~blink(2:end)));

    out_file = fullfile(fileparts(eye_mat_path), 'eye_preprocessed.mat');
    save(out_file, 'eye_out');
end
