%% list_flagged_tssv.m
% After re-running the updated perf_extract_force_vibration_features(cfg),
% this lists every row flagged by gate 1 (missing samples) and/or gate 2
% (noise detection) -- the tssv value is still there, just flagged, so
% you can review and decide per-row rather than it being auto-discarded.

cfg = config();
S = load(fullfile(cfg.output_root,'force_vibration_features.mat'),'T');
T = S.T;

flagged = T(T.tssv_flag_missing | T.tssv_flag_noise, ...
    {'subject','phase','acquisition','level','repetition','tssv','tssv_pct_missing','tssv_flag_missing','tssv_flag_noise'});

fprintf('%d rows flagged (%d missing, %d noise, overlap counted once)\n', ...
    height(flagged), sum(flagged.tssv_flag_missing), sum(flagged.tssv_flag_noise));
disp(flagged)
