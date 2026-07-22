function feat = gsr_extract_features(gsr_proc, cfg)
% Extract GSR features from a preprocessed gsr struct. Returns a scalar struct with all features.

    fs      = gsr_proc.fs;
    sig     = gsr_proc.gsr_us;
    tonic   = gsr_proc.tonic;
    phasic  = gsr_proc.phasic;
    n       = numel(sig);
    t_axis  = (0:n-1)' / fs;
    duration_min = n / fs / 60;
    
    % Tonic features
    feat.scl_mean  = mean(tonic);
    feat.scl_slope = polyfit(t_axis, tonic, 1);
    feat.scl_slope = feat.scl_slope(1);   % µS/s
    feat.scl_range = max(tonic) - min(tonic);
    
    %  Global signal features 
    feat.gsr_mean = mean(sig);
    feat.gsr_std  = std(sig);
    feat.gsr_rms  = rms(sig);
    
    %  SCR peak detection on phasic driver 
    min_amp  = cfg.scr_min_amp;
    min_dist = cfg.scr_min_dist;
    
    [peak_vals, peak_locs] = findpeaks(phasic, 'MinPeakHeight',   min_amp, 'MinPeakDistance', min_dist);
    
    feat.scr_n_peaks  = numel(peak_vals);
    feat.scr_rate     = feat.scr_n_peaks / duration_min;
    feat.scr_auc      = trapz(t_axis, max(phasic, 0));
    
    if feat.scr_n_peaks == 0
        feat.scr_mean_amp      = 0;
        feat.scr_max_amp       = 0;
        feat.scr_mean_risetime = NaN;
        feat.scr_mean_halfrec  = NaN;
        return;
    end
    
    feat.scr_mean_amp = mean(peak_vals);
    feat.scr_max_amp  = max(peak_vals);
    
    rise_times = NaN(feat.scr_n_peaks, 1);
    half_rec   = NaN(feat.scr_n_peaks, 1);
    
    for k = 1:feat.scr_n_peaks
        pk_loc = peak_locs(k);
        pk_val = peak_vals(k);
    
        % Rise time: find onset as last sample below 10% of peak before peak
        onset_search = max(1, pk_loc - round(5*fs)) : pk_loc;
        below_thresh = phasic(onset_search) < 0.1 * pk_val;
        if any(below_thresh)
            onset_idx = onset_search(find(below_thresh, 1, 'last'));
            rise_times(k) = (pk_loc - onset_idx) / fs;
        end
    
        % Half-recovery: find first sample after peak where signal <= pk_val/2
        rec_search = pk_loc : min(n, pk_loc + round(10*fs));
        below_half = phasic(rec_search) <= pk_val / 2;
        if any(below_half)
            rec_idx = rec_search(find(below_half, 1, 'first'));
            half_rec(k) = (rec_idx - pk_loc) / fs;
        end
    end
    
    feat.scr_mean_risetime = nanmean(rise_times);
    feat.scr_mean_halfrec  = nanmean(half_rec);
end