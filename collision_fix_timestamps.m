%% fix_collision_timestamps.m
% Corrects collision timestamps by subtracting the measured audiomixer-NIDAQ lag
% so that peak_accel_g_nidaq and impact_tssv are computed at the correct NIDAQ window

clear; clc; cfg = config();

T_sync=load(fullfile(cfg.output_root,'sync_check_results.mat'),'T'); T_sync=T_sync.T;
CI=load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact'); T=CI.T_impact;

% add corrected collision time column
T.collision_t_nidaq = T.collision_t;   % start with original
T.lag_ms_applied    = zeros(height(T),1);
n_corrected=0; n_skipped=0;

all_phases=[cfg.baseline_phases, cfg.training_levels, cfg.test_phases];

for si=1:numel(cfg.all_subjects)
    subj=cfg.all_subjects{si};
    for ph_idx=1:numel(all_phases)
        phase=all_phases{ph_idx};
        is_training=ismember(phase,cfg.training_levels);
        is_baseline=ismember(phase,cfg.baseline_phases);

        if is_training
            acquisitions=arrayfun(@(k)sprintf('rep_%02d',k),1:cfg.n_training_reps,'UniformOutput',false);
        elseif is_baseline
            acquisitions=arrayfun(@(k)sprintf('Level%d',k),1:numel(cfg.level_names),'UniformOutput',false);
        else
            acquisitions={'main'};
        end

        for ai=1:numel(acquisitions)
            acq=acquisitions{ai};
            % find sync check result for this acquisition
            sync_mask=strcmp(T_sync.subject,subj)&strcmp(T_sync.phase,phase)&strcmp(T_sync.acquisition,acq);
            if ~any(sync_mask), continue; end
            sync_row=T_sync(sync_mask,:);

            % only apply correction if lag is reliable
            % (max_xcorr > 0.3 and |lag| between 50ms and 600ms — the hardware latency range)
            if isnan(sync_row.lag_ms)||isnan(sync_row.max_xcorr), continue; end
            if sync_row.max_xcorr < 0.3, n_skipped=n_skipped+1; continue; end
            if abs(sync_row.lag_ms) < 50 || abs(sync_row.lag_ms) > 600, continue; end

            % apply correction to all collision rows for this acquisition
            row_mask=strcmp(T.subject,subj)&strcmp(T.phase,phase)&strcmp(T.acquisition,acq);
            if ~any(row_mask), continue; end

            lag_s=sync_row.lag_ms/1000;
            T.collision_t_nidaq(row_mask)=T.collision_t(row_mask)-lag_s;
            T.lag_ms_applied(row_mask)=sync_row.lag_ms;
            n_corrected=n_corrected+sum(row_mask);
        end
    end
end

fprintf('Collision timestamps corrected: %d events\n',n_corrected);
fprintf('Acquisitions skipped (low xcorr): %d\n',n_skipped);
fprintf('Remaining uncorrected (no sync data or |lag| out of range): %d\n',...
    sum(T.lag_ms_applied==0&isfinite(T.collision_t)));

% now recompute peak_accel_g_nidaq and impact_tssv using corrected timestamps
fprintf('\nRecomputing peak_accel_g_nidaq and impact_tssv with corrected timestamps...\n');
% [this requires re-running add_peak_accel_nidaq and collision_impact_features
%  with collision_t_nidaq instead of collision_t for the NIDAQ windowing]

T_impact=T;
save(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact');
fprintf('Saved updated collision_impact_features.mat with collision_t_nidaq\n');

% summary of corrections applied
fprintf('\nLag corrections applied:\n');
fprintf('  0ms (no correction): %d events\n',sum(T.lag_ms_applied==0));
fprintf('  ~100ms:              %d events\n',sum(T.lag_ms_applied>50&T.lag_ms_applied<150));
fprintf('  ~200ms:              %d events\n',sum(T.lag_ms_applied>=150&T.lag_ms_applied<250));
fprintf('  ~300ms:              %d events\n',sum(T.lag_ms_applied>=250&T.lag_ms_applied<400));
fprintf('  other:               %d events\n',sum(T.lag_ms_applied>=400));