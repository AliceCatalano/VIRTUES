function gsr_out = gsr_preprocess(gsr_mat_path, cfg, t_start, t_end)

    loaded = load(gsr_mat_path, 'GSR');
    GSR = loaded.GSR;
    
    t   = GSR.time_rel;
    raw = GSR.GSR_ohm;
    
    valid = isfinite(raw) & raw > 0;
    t     = t(valid);
    raw   = raw(valid);
    
    % NOTE: despite the field name GSR_ohm, values are populated in kOhm
    % (matches Shimmer3+ spec: 22-680 kOhm range <-> ~5-45 uS). Using
    % 1e6 here (as if raw were in Ohm) was inflating every conductance
    % value by exactly 1000x -- confirmed against observed baseline
    % numbers. Verify against your CSV/Consensys export docs if this
    % sensor/firmware config ever changes.
    gsr_us_raw = 1e3 ./ raw;
    
    if ~isempty(t_start) && ~isempty(t_end) && ~isnan(t_start) && ~isnan(t_end)
        mask       = t >= t_start & t <= t_end;
        t          = t(mask);
        gsr_us_raw = gsr_us_raw(mask);
    end
    
    if numel(t) < 20
        error('gsr_preprocess: fewer than 20 samples in window for %s', gsr_mat_path);
    end

    % Reject acquisitions with a dropout gap large enough that
    % interpolation would be reconstructing across real missing data
    % (e.g. dropped Bluetooth packets) rather than smoothing normal
    % timing jitter. See gsr_check_sampling_jitter.m for how to pick
    % this threshold from your data's actual gap distribution.
    if ~isfield(cfg, 'max_gap_s') || isempty(cfg.max_gap_s)
        cfg.max_gap_s = 1.0;
    end
    max_gap = max(diff(t));
    if max_gap > cfg.max_gap_s
        error('gsr_preprocess: dropout gap of %.3fs exceeds cfg.max_gap_s (%.3fs) in %s', ...
            max_gap, cfg.max_gap_s, gsr_mat_path);
    end
    
    fs        = cfg.fs_target;
    t_uniform = (t(1) : 1/fs : t(end))';

    cfg.resample_method = 'nearest';
    
    % 'pchip' (default): smooth interpolated curve; values at grid points
    %   are computed, not necessarily equal to any single recorded sample.
    % 'nearest': every output value equals an actual recorded sample (the
    %   nearest one in time) -- no interpolated/synthetic values, at the
    %   cost of a staircased signal and duplicated samples wherever the
    %   grid spacing is finer than the native sampling interval. Run
    %   gsr_check_sampling_jitter.m first to see how much this matters for
    %   your data.
    gsr_us = interp1(t, gsr_us_raw, t_uniform, cfg.resample_method);
    
    if ~isfield(cfg, 'lowpass_cutoff_hz') || isempty(cfg.lowpass_cutoff_hz)
        % Default per EDA preprocessing literature (Boucsein, 2012;
        % Benedek & Kaernbach, 2010): 2-5 Hz preserves SCR rise-time
        % morphology needed for accurate phasic/tonic decomposition.
        % A 1 Hz cutoff (the previous hardcoded value) is more
        % appropriate for a purely smoothed SCL trace than as input to
        % cvxEDA, and risked blunting SCR amplitude estimates.
        cfg.lowpass_cutoff_hz = 3;
    end
    if cfg.lowpass_cutoff_hz >= fs/2
        error('gsr_preprocess: cfg.lowpass_cutoff_hz (%.2f) must be below the Nyquist frequency (%.2f Hz at fs=%.1fHz)', ...
            cfg.lowpass_cutoff_hz, fs/2, fs);
    end
    [b, a]       = butter(4, cfg.lowpass_cutoff_hz/(fs/2), 'low');
    gsr_us_filt  = filtfilt(b, a, gsr_us);
    gsr_us_filt  = max(gsr_us_filt, 1e-6);
    
    % cvxEDA: y must be a column vector, delta = 1/fs
    % Outputs: r=phasic, p=sparse SMNA driver, tonic, l=offset, d=drift, e=residual, obj
    y     = gsr_us_filt(:);
    delta = 1 / fs;
    
    try
        [r, p, tonic, l, d, e, obj] = cvxEDA(y, delta);
    catch ME
        error('cvxEDA failed on %s: %s', gsr_mat_path, ME.message);
    end
    
    gsr_out.time     = t_uniform;
    gsr_out.gsr_us   = gsr_us_filt;
    gsr_out.tonic    = tonic(:);
    gsr_out.phasic   = r(:);
    gsr_out.smna     = p(:);
    gsr_out.residual = e(:);
    gsr_out.fs       = fs;
    gsr_out.source   = gsr_mat_path;

    out_file = fullfile(fileparts(gsr_mat_path), 'gsr_preprocessed.mat');
    save(out_file, 'gsr_out')
end