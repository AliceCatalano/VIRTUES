%% gsr_check_sampling_jitter.m
% Diagnostic only. Quantifies how irregular the raw GSR.time_rel
% timestamps actually are within each acquisition's TRIAL_START/TRIAL_END
% window (via safe_trial_window.m) -- matching exactly what
% gsr_extract_features.m now feeds into gsr_preprocess.m, not the full
% unwindowed recording (which may include pre/post-trial dead time you
% don't care about).
%
% If raw sampling turns out to be extremely regular (jitter << 1/fs_target),
% interpolation is barely doing anything beyond enforcing an exact grid --
% the "synthetic values" it produces will be numerically almost identical
% to the real recorded values. If jitter is substantial, some form of
% resampling is unavoidable for cvxEDA/filtfilt (both require constant
% sample spacing), but you can choose 'nearest' instead of 'pchip' (see
% gsr_preprocess.m) to use only real recorded values, at the cost of
% duplicated/staircased samples instead of smooth interpolation.

clear; clc;
cfg = config();

n_check = 600;
rows = {};
count = 0;

for si = 1:numel(cfg.all_subjects)
    if count >= n_check, break; end
    subj     = cfg.all_subjects{si};
    subj_dir = fullfile(cfg.data_root, subj);

    all_phases = [cfg.baseline_phases, cfg.training_levels, cfg.test_phases];
    for ph_idx = 1:numel(all_phases)
        if count >= n_check, break; end
        phase     = all_phases{ph_idx};
        phase_dir = fullfile(subj_dir, phase);
        if ~isfolder(phase_dir), continue; end

        if ismember(phase, cfg.training_levels)
            acquisitions = arrayfun(@(k) sprintf('rep_%02d', k), 1:cfg.n_training_reps, 'UniformOutput', false);
        else
            acquisitions = arrayfun(@(k) sprintf('Level%d', k), 1:numel(cfg.level_names), 'UniformOutput', false);
        end

        for ai = 1:numel(acquisitions)
            if count >= n_check, break; end
            acq     = acquisitions{ai};
            acq_dir = fullfile(phase_dir, acq);
            if ~isfolder(acq_dir)
                if isfolder([acq_dir '_R']), acq_dir = [acq_dir '_R'];
                else, continue; end
            end
            gsr_path = fullfile(acq_dir, 'gsr.mat');
            ev_path  = fullfile(acq_dir, 'events.mat');
            if ~isfile(gsr_path) || ~isfile(ev_path), continue; end

            [t_start, t_end] = safe_trial_window(ev_path);
            if isnan(t_start) || isnan(t_end), continue; end

            try
                loaded = load(gsr_path, 'GSR');
                t = loaded.GSR.time_rel;
                t = t(isfinite(t));
                t = sort(t);
                t = t(t >= t_start & t <= t_end);   % trial window only
            catch
                continue;
            end
            if numel(t) < 10, continue; end

            dt = diff(t);
            native_fs_est = 1 / median(dt);

            rows(end+1, :) = {subj, phase, acq, numel(t), native_fs_est, ...
                mean(dt), median(dt), std(dt), min(dt), max(dt)}; %#ok<AGROW>
            count = count + 1;
        end
    end
end

T = cell2table(rows, 'VariableNames', ...
    {'subject','phase','acquisition','n_samples','native_fs_est', ...
     'mean_dt','median_dt','std_dt','min_dt','max_dt'});
disp(T);

fprintf('\n=== Summary across %d sampled acquisitions ===\n', height(T));
fprintf('Estimated native sampling rate: %.3f +/- %.3f Hz (median: %.3f)\n', ...
    mean(T.native_fs_est), std(T.native_fs_est), median(T.native_fs_est));
fprintf('dt jitter (std_dt / median_dt), avg across acquisitions: %.2f%%\n', ...
    100 * mean(T.std_dt ./ T.median_dt));
fprintf('Max single-gap dt observed: %.4f s (vs median dt %.4f s)\n', ...
    max(T.max_dt), median(T.median_dt));

fprintf(['\nInterpretation: if jitter %% is small (a few %% or less) and the max\n' ...
    'gap is close to the median dt, raw sampling is close enough to regular\n' ...
    'that resampling mostly just snaps to an exact grid rather than inventing\n' ...
    'meaningfully different values. If jitter is large or there are big gaps\n' ...
    '(e.g. from dropped Bluetooth packets), some correction is unavoidable --\n' ...
    'consider the nearest-neighbor option in gsr_preprocess.m instead of pchip.\n']);

fprintf('\n=== Gap threshold check (candidate cfg.max_gap_s cutoffs) ===\n');
for thresh = [0.3, 0.5, 1.0, 2.0]
    n_over = sum(T.max_dt > thresh);
    fprintf('  acquisitions with a gap > %.1fs: %d / %d (%.1f%%)\n', ...
        thresh, n_over, height(T), 100*n_over/height(T));
end
fprintf(['\nThese acquisitions have at least one dropout gap large enough that\n' ...
    'interpolation (pchip OR nearest) is reconstructing across real missing\n' ...
    'data, not just smoothing timing noise. Pick a cfg.max_gap_s threshold\n' ...
    'above and gsr_preprocess.m will now exclude (error on) acquisitions that\n' ...
    'exceed it, rather than silently interpolating over the gap.\n']);