%% run_cross_modal_correlations.m
clear; clc;
cfg = config();

EDA  = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); T_eda = EDA.T;
EYE  = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T'); T_eye = EYE.T;
PERF = load(fullfile(cfg.output_root,'perf_features.mat'),'T');   T_perf = PERF.T;
FV   = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); T_fv = FV.T;

T_perf_tr = T_perf(strcmp(T_perf.phase_type,'training'),:);
T_perf_tr.Properties.VariableNames{'duration_s'}   = 'duration_s_perf';
T_perf_tr.Properties.VariableNames{'n_collisions'} = 'n_collisions_perf';

T_eda_tr = T_eda(strcmp(T_eda.phase_type,'training'),:);
T_eye_tr = T_eye(strcmp(T_eye.phase_type,'training'),:);
T_fv_tr  = T_fv(strcmp(T_fv.phase_type,'training'),:);

T_ep = innerjoin(T_eda_tr, T_perf_tr, ...
                 'Keys', {'subject','level','repetition'}, ...
                 'RightVariables', {'duration_s_perf','n_collisions_perf'});

T_eyep = innerjoin(T_eye_tr, T_perf_tr, ...
                   'Keys', {'subject','level','repetition'}, ...
                   'RightVariables', {'duration_s_perf','n_collisions_perf'});

T_fv_eda = innerjoin(T_fv_tr, T_eda_tr, ...
                     'Keys', {'subject','level','repetition'}, ...
                     'RightVariables', {'scl_mean_bc','scr_mean_amp_bc', ...
                                        'collision_scr_amp_mean_bc','haptic'});
if ismember('haptic_T_eda_tr', T_fv_eda.Properties.VariableNames)
    T_fv_eda.haptic = T_fv_eda.haptic_T_eda_tr;
elseif ~ismember('haptic_T_fv_tr', T_fv_eda.Properties.VariableNames)
    T_fv_eda.haptic = T_fv_eda.haptic_T_fv_tr;
end
fprintf('T_ep rows: %d | T_eyep rows: %d | T_fv_eda rows: %d\n', ...
    height(T_ep), height(T_eyep), height(T_fv_eda));

pairs_ep = {
    'scl_mean_bc',              'duration_s_perf',   'EDA tonic SCL -> completion time'
    'scr_mean_amp_bc',          'duration_s_perf',   'EDA phasic amplitude -> completion time'
    'collision_scr_amp_mean_bc','n_collisions_perf', 'ER-SCR amplitude -> collision count'
    'scl_mean_bc',              'n_collisions_perf', 'EDA tonic SCL -> collision count'
};

pairs_eyep = {
    'pupil_mean_norm',   'duration_s_perf',   'Pupil dilation -> completion time'
    'gaze_entropy',      'duration_s_perf',   'Gaze entropy -> completion time'
    'saccade_rate',      'duration_s_perf',   'Saccade rate -> completion time'
    'gaze_entropy',      'n_collisions_perf', 'Gaze entropy -> collision count'
};

pairs_fv_eda = {
    'tssv', 'scl_mean_bc', 'TSSV -> tonic SCL'
    'tssf', 'scl_mean_bc', 'TSSF -> tonic SCL'
};

all_results = struct();

fprintf('\n=== EDA <-> Performance correlations ===\n');
for i = 1:size(pairs_ep,1)
    pred = pairs_ep{i,1}; out = pairs_ep{i,2};
    r = multilevel_correlation_lmm(T_ep, pred, out, 'training');
    fprintf('\n%s\n  Within: beta=%.4f SE=%.4f p=%.4f\n  Between: beta=%.4f SE=%.4f p=%.4f\n', ...
        pairs_ep{i,3}, r.within_beta, r.within_se, r.within_p, ...
        r.between_beta, r.between_se, r.between_p);
    fprintf('  Within x Haptic: beta=%.4f p=%.4f | Between x Haptic: beta=%.4f p=%.4f\n', ...
        r.within_haptic_beta, r.within_haptic_p, r.between_haptic_beta, r.between_haptic_p);
    all_results.eda_perf(i).result = r;
    all_results.eda_perf(i).label  = pairs_ep{i,3};
end

fprintf('\n=== Eye <-> Performance correlations ===\n');
for i = 1:size(pairs_eyep,1)
    pred = pairs_eyep{i,1}; out = pairs_eyep{i,2};
    r = multilevel_correlation_lmm(T_eyep, pred, out, 'training');
    fprintf('\n%s\n  Within: beta=%.4f SE=%.4f p=%.4f\n  Between: beta=%.4f SE=%.4f p=%.4f\n', ...
        pairs_eyep{i,3}, r.within_beta, r.within_se, r.within_p, ...
        r.between_beta, r.between_se, r.between_p);
    fprintf('  Within x Haptic: beta=%.4f p=%.4f | Between x Haptic: beta=%.4f p=%.4f\n', ...
        r.within_haptic_beta, r.within_haptic_p, r.between_haptic_beta, r.between_haptic_p);
    all_results.eye_perf(i).result = r;
    all_results.eye_perf(i).label  = pairs_eyep{i,3};
end

fprintf('\n=== Mechanical <-> EDA correlations ===\n');
for i = 1:size(pairs_fv_eda,1)
    pred = pairs_fv_eda{i,1}; out = pairs_fv_eda{i,2};
    T_fv_eda.(pred)(T_fv_eda.(pred) <= 0) = NaN;
    T_fv_eda.([pred '_log']) = log(T_fv_eda.(pred));
    r = multilevel_correlation_lmm(T_fv_eda, [pred '_log'], out, 'training');
    fprintf('\n%s\n  Within: beta=%.4f SE=%.4f p=%.4f\n  Between: beta=%.4f SE=%.4f p=%.4f\n', ...
        pairs_fv_eda{i,3}, r.within_beta, r.within_se, r.within_p, ...
        r.between_beta, r.between_se, r.between_p);
    fprintf('  Within x Haptic: beta=%.4f p=%.4f | Between x Haptic: beta=%.4f p=%.4f\n', ...
        r.within_haptic_beta, r.within_haptic_p, r.between_haptic_beta, r.between_haptic_p);
    all_results.mech_eda(i).result = r;
    all_results.mech_eda(i).label  = pairs_fv_eda{i,3};
end

save(fullfile(cfg.output_root,'cross_modal_correlation_results.mat'),'all_results');
fprintf('\nSaved cross_modal_correlation_results.mat\n');