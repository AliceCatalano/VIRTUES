function gsr_out = gsr_preprocess(gsr_mat_path, cfg, t_start, t_end)

    loaded = load(gsr_mat_path, 'GSR');
    GSR = loaded.GSR;
    
    t   = GSR.time_rel;
    raw = GSR.GSR_ohm;
    
    valid = isfinite(raw) & raw > 0;
    t     = t(valid);
    raw   = raw(valid);
    
    gsr_us_raw = 1e6 ./ raw;
    
    if ~isempty(t_start) && ~isempty(t_end) && ~isnan(t_start) && ~isnan(t_end)
        mask       = t >= t_start & t <= t_end;
        t          = t(mask);
        gsr_us_raw = gsr_us_raw(mask);
    end
    
    if numel(t) < 20
        error('gsr_preprocess: fewer than 20 samples in window for %s', gsr_mat_path);
    end
    
    fs        = cfg.fs_target;
    t_uniform = (t(1) : 1/fs : t(end))';
    gsr_us    = interp1(t, gsr_us_raw, t_uniform, 'pchip');
    
    [b, a]       = butter(4, 1/(fs/2), 'low');
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
end