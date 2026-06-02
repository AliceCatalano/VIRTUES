function audio_events = detect_audio_collisions(audio, channels, fs_audio, ...
        bp_lo, bp_hi, t_start, t_end, cfg)

    % ---- Build summed bandpassed signal ---------------------------
    audio_sum = zeros(height(audio),1);

    for k = 1:numel(channels)
        raw = double(audio.(channels{k}));
        raw = raw - mean(raw,'omitnan');

        if numel(raw) > 10*fs_audio
            raw_bp = bandpass(raw, [bp_lo bp_hi], fs_audio);
        else
            raw_bp = raw;
        end

        audio_sum = audio_sum + raw_bp;
    end

    % ---- RMS envelope (energy) ------------------------------------
    win = max(3, round(fs_audio * 0.02)); % 20 ms window
    audio_rms = sqrt(movmean(audio_sum.^2, win));

    % ---- Restrict to trial window ---------------------------------
    mask = (audio.t >= t_start) & (audio.t <= t_end);
    t_w   = audio.t(mask);
    rms_w = audio_rms(mask);

    % ---- Derivative (spike detection) -----------------------------
    drv = [0; abs(diff(rms_w))];

    % ---- Threshold (robust) ---------------------------------------
    thresh = max( ...
        median(drv) + 6 * mad(drv,1), ...
        prctile(drv, 99.5) ...
    );

    % ---- Detect peaks ---------------------------------------------
    min_dist = round(cfg.min_distance_sec * fs_audio);
    audio_events = detect_peaks(drv, t_w, thresh, min_dist);
end