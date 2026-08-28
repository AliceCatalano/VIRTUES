function T = merge_modality_tables(cfg)
% MERGE_MODALITY_TABLES  Join the three per-modality feature tables
% (gsr_extract_features.m, eye_extract_features.m, perf_extract_features.m)
% into one wide table, one row per subject x phase x acquisition, for the
% cross-modality correlation analyses in run_correlation_analyses.m.
%
% Join key is {subject, phase, acquisition} only -- NOT repetition, even
% though it's a useful column to carry along: repetition is NaN for every
% Baseline/Test row, and NaN ~= NaN under MATLAB's join semantics, which
% would silently drop every non-training row from the merge. {subject,
% phase, acquisition} already uniquely identifies a row in every source
% table (each subject visits a given phase+acquisition combination
% exactly once), so it's a sufficient and NaN-safe key on its own.
%
% n_collisions is computed independently in both gsr_extract_features.m
% and perf_extract_features.m (same collision_results.mat, same counting
% logic) -- this function keeps perf_extract_features.m's copy as
% authoritative (it's the actual SAP "collision count" performance
% outcome) and drops the EDA table's duplicate before joining, after
% checking the two agree (a mismatch would indicate the two extraction
% scripts have drifted out of sync with each other).

    eda_file  = fullfile(cfg.output_root, 'eda_features.mat');
    eye_file  = fullfile(cfg.output_root, 'eye_features.mat');
    perf_file = fullfile(cfg.output_root, 'perf_features.mat');
    for f = {eda_file, eye_file, perf_file}
        if ~isfile(f{1})
            error('merge_modality_tables: missing %s -- run the corresponding *_extract_features.m first.', f{1});
        end
    end

    Teda  = load(eda_file,  'T'); Teda  = Teda.T;
    Teye  = load(eye_file,  'T'); Teye  = Teye.T;
    Tperf = load(perf_file, 'T'); Tperf = Tperf.T;

    keys = {'subject', 'phase', 'acquisition'};

    % --- Sanity check: n_collisions should agree between EDA and perf tables ---
    % (renamed explicitly before the join -- relying on innerjoin's
    % automatic name-conflict suffixing is fragile when both inputs are
    % indexing expressions rather than plain variables)
    Ta = renamevars(Teda(:,  [keys, {'n_collisions'}]), 'n_collisions', 'n_collisions_eda');
    Tb = renamevars(Tperf(:, [keys, {'n_collisions'}]), 'n_collisions', 'n_collisions_perf');
    Tchk = innerjoin(Ta, Tb, 'Keys', keys);
    mismatch = abs(Tchk.n_collisions_eda - Tchk.n_collisions_perf) > 0;
    if any(mismatch)
        warning('merge_modality_tables: n_collisions disagrees between EDA and performance tables for %d/%d rows -- the two extraction scripts may be out of sync.', ...
            sum(mismatch), height(Tchk));
    end

    eda_cols  = {'scl_mean','scl_range','scl_slope','scr_freq','scr_mean_amp','scr_max_amp','scr_auc', ...
                 'gsr_mean','gsr_std','gsr_rms','collision_scr_amp_mean','collision_response_rate'};
    eye_cols  = {'pupil_mean','pupil_mean_bc','pupil_mean_pctchg','pupil_slope','gaze_dispersion', ...
                 'saccade_rate','collision_pupil_response_mean','collision_saccade_response_rate'};
    perf_cols = {'duration_s','n_collisions'};

    base_cols = [keys, {'group','haptic','phase_type','level','repetition'}];

    Teda_sub  = Teda(:,  [base_cols, eda_cols]);
    Teye_sub  = Teye(:,  [keys, eye_cols]);
    Tperf_sub = Tperf(:, [keys, perf_cols]);

    T = innerjoin(Teda_sub, Teye_sub, 'Keys', keys);
    T = innerjoin(T, Tperf_sub, 'Keys', keys);

    fprintf('Merged table: %d rows (subject x phase x acquisition present in all three modalities)\n', height(T));
    fprintf('EDA-only rows dropped: %d, eye-only rows dropped: %d, perf-only rows dropped: %d (rows missing from >=1 modality)\n', ...
        height(Teda_sub) - height(T), height(Teye_sub) - height(T), height(Tperf_sub) - height(T));

    save(fullfile(cfg.output_root, 'merged_features.mat'), 'T');
    writetable(T, fullfile(cfg.output_root, 'merged_features.csv'));
end
