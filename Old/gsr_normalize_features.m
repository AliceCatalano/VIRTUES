function feat_norm = gsr_normalize_features(feat, subj_max, cfg)
    % Divide each amplitude feature by subject max. Non-amplitude features (slopes, times, counts) are kept as-is.
    
    feat_norm = feat;
    amp_feats = cfg.amplitude_features;
    
    for k = 1:numel(amp_feats)
        fn = amp_feats{k};
        if isfield(feat_norm, fn) && subj_max.(fn) > 0
            feat_norm.(fn) = feat_norm.(fn) / subj_max.(fn);
        end
    end
end