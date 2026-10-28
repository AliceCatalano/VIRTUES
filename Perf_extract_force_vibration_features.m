%% perf_extract_force_vibration_features.m
% Stand-alone script version — workspace is preserved on error.
% Set cfg before running, or edit the cfg block below.


cfg = config();
if isnan(cfg.accel_sensitivity_ms2_per_V)
    error('cfg.accel_sensitivity_ms2_per_V must be set.');
end

BP_LOW  = 80;
BP_HIGH = 1000;

C_force    = load_ati_cal(cfg.force_cal_path);
all_phases = [cfg.baseline_phases, cfg.training_levels, cfg.test_phases];
rows       = cell(0, 16);

%% --- main loop ---
for si = 1:numel(cfg.all_subjects)
    subj     = cfg.all_subjects{si};
    group    = subj(end);
    haptic   = strcmp(group,'H');
    subj_dir = fullfile(cfg.data_root, subj);

    for ph_idx = 1:numel(all_phases)
        phase     = all_phases{ph_idx};
        phase_dir = fullfile(subj_dir, phase);
        if ~isfolder(phase_dir), continue; end

        is_training = ismember(phase, cfg.training_levels);
        is_baseline = ismember(phase, cfg.baseline_phases);
        is_test     = ismember(phase, cfg.test_phases);

        if is_training
            phase_type   = 'training';
            level_num    = str2double(regexp(phase,'\d+','match','once'));
            acquisitions = arrayfun(@(k) sprintf('rep_%02d',k), 1:cfg.n_training_reps, 'UniformOutput', false);
            rep_nums     = 1:cfg.n_training_reps;
        elseif is_baseline
            phase_type   = 'baseline';
            level_num    = NaN;
            acquisitions = arrayfun(@(k) sprintf('Level%d',k), 1:numel(cfg.level_names), 'UniformOutput', false);
            rep_nums     = nan(1, numel(acquisitions));
        else
            phase_type   = 'test';
            level_num    = NaN;
            acquisitions = {'main'};
            rep_nums     = NaN;
        end

        for ai = 1:numel(acquisitions)
            acq = acquisitions{ai};
            if is_test
                acq_dir = phase_dir;
            else
                acq_dir = fullfile(phase_dir, acq);
                if ~isfolder(acq_dir)
                    if isfolder([acq_dir '_R'])
                        acq_dir = [acq_dir '_R'];
                    else
                        continue;
                    end
                end
            end

            ev_path = fullfile(acq_dir, 'events.mat');
            if ~isfile(ev_path), continue; end
            [t_start, t_end] = safe_trial_window(ev_path);
            if isnan(t_start) || isnan(t_end), continue; end

            rep_this = rep_nums(ai);
            if is_training
                level_this = level_num;
            elseif is_baseline
                level_this = ai;
            else
                level_this = NaN;
            end

            % ----------------------------------------------------------------
            % TSSF
            % ----------------------------------------------------------------
            tssf              = NaN;
            tssf_flag_noise   = false;
            tssf_flag_missing = false;
            tssf_pct_missing  = NaN;

            force_path = fullfile(acq_dir, 'force.mat');
            if isfile(force_path)
                LF      = load(force_path, 'FORCE');
                t_force = LF.FORCE.time_rel(:);
                raw_V_f = LF.FORCE.data;

                % gate 1: missing samples
                dt_nominal       = median(diff(t_force));
                fs_f_nominal     = 1 / dt_nominal;
                trial_mask_check = t_force >= t_start & t_force <= t_end;
                expected_samp    = round((t_end - t_start) * fs_f_nominal);
                pct_missing      = max(0, (expected_samp - sum(trial_mask_check)) / expected_samp * 100);
                tssf_pct_missing = pct_missing;
                if pct_missing > cfg.force_max_pct_missing
                    warning('perf_extract: force %.1f%% missing — FLAGGED for %s/%s/%s', ...
                            pct_missing, subj, phase, acq);
                    tssf_flag_missing = true;
                end

                % gate 2: noise detection
                if pf_force_is_noise(LF, t_start, t_end, cfg, C_force)
                    warning('perf_extract: force noise detected — FLAGGED for %s/%s/%s', ...
                            subj, phase, acq);
                    tssf_flag_noise = true;
                end

                % bias window
                bias_mask_f = t_force >= (t_start - 1.0) & t_force < t_start;
                if sum(bias_mask_f) < 3
                    bias_mask_f = t_force < (t_force(1) + 1.0);
                end
                bias_f    = mean(raw_V_f(bias_mask_f,:), 1, 'omitnan');
                F_base    = (C_force * (raw_V_f(bias_mask_f,:) - bias_f)')';
                Fmag_base = sqrt(sum(F_base(:,1:3).^2, 2));
                nf        = median(Fmag_base) + cfg.force_noise_k_mad * mad(Fmag_base, 1);

                % trial
                trial_mask_f = t_force >= t_start & t_force <= t_end;
                if any(trial_mask_f)
                    dt_f  = median(diff(t_force(trial_mask_f)));
                    fs_f  = 1 / dt_f;
                    F_cal = (C_force * (raw_V_f(trial_mask_f,:) - bias_f)')';
                    Fmag  = sqrt(sum(F_cal(:,1:3).^2, 2));
                    Fmag(Fmag < nf) = 0;
                    tssf  = sum(Fmag.^2) / fs_f;   % N²·s
                end
            end

            % ----------------------------------------------------------------
            % TSSV
            % ----------------------------------------------------------------
            tssv              = NaN;
            tssv_pct_missing  = NaN;
            tssv_flag_missing = false;
            tssv_flag_noise   = false;

            accel_path = fullfile(acq_dir, 'accel.mat');
            if isfile(accel_path)
                LA      = load(accel_path, 'ACCEL');
                t_accel = LA.ACCEL.time_rel(:);
                fs      = LA.ACCEL.fs_nominal;
                dt      = 1 / fs;

                % gate 1: missing samples
                trial_mask_check = t_accel >= t_start & t_accel <= t_end;
                expected_samp    = round((t_end - t_start) * fs);
                pct_missing      = max(0, (expected_samp - sum(trial_mask_check)) / expected_samp * 100);
                tssv_pct_missing = pct_missing;
                if pct_missing > cfg.accel_max_pct_missing
                    warning('perf_extract: accel %.1f%% missing — FLAGGED for %s/%s/%s', ...
                            pct_missing, subj, phase, acq);
                    tssv_flag_missing = true;
                end

                % gate 2: noise detection
                if pf_accel_is_noise(LA, t_start, t_end, cfg, BP_LOW, BP_HIGH)
                    warning('perf_extract: accel noise detected — FLAGGED for %s/%s/%s', ...
                            subj, phase, acq);
                    tssv_flag_noise = true;
                end

                % bias
                bias_mask_a = t_accel >= (t_start - 1.0) & t_accel < t_start;
                if sum(bias_mask_a) < 3
                    bias_mask_a = t_accel < (t_accel(1) + 1.0);
                end
                bias_a  = mean(LA.ACCEL.data(bias_mask_a,:), 1, 'omitnan');
                raw_V   = LA.ACCEL.data - bias_a;
                raw_ms2 = raw_V * cfg.accel_sensitivity_ms2_per_V;

                % baseline noise threshold
                raw_ms2_base = raw_ms2(bias_mask_a,:);
                Amag_base_L  = sqrt(sum(raw_ms2_base(:,1:3).^2, 2));
                Amag_base_R  = sqrt(sum(raw_ms2_base(:,4:6).^2, 2));
                thr_L = cfg.tssv_noise_threshold_ms2;
                thr_R = cfg.tssv_noise_threshold_ms2;

                % trial
                trial_mask_a = t_accel >= t_start & t_accel <= t_end;
                if sum(trial_mask_a) > 2
                    seg_ms2 = raw_ms2(trial_mask_a,:);
                    if fs/2 > BP_HIGH
                        seg_ms2 = pf_bandpass(seg_ms2, BP_LOW, BP_HIGH, fs);
                    else
                        warning('perf_extract: Nyquist<=BP_HIGH, bandpass skipped: %s/%s/%s', ...
                                subj, phase, acq);
                    end
                    Amag_left  = sqrt(sum(seg_ms2(:,1:3).^2, 2));
                    Amag_right = sqrt(sum(seg_ms2(:,4:6).^2, 2));
                    Amag_left( Amag_left  < thr_L) = 0;
                    Amag_right(Amag_right < thr_R) = 0;
                    tssv = (sum(Amag_left.^2) + sum(Amag_right.^2)) * dt;  % m²/s³
                end
            end

            % ----------------------------------------------------------------
            % append row
            % ----------------------------------------------------------------
            rows(end+1, :) = {subj, group, haptic, phase_type, phase, acq, ...
                              level_this, rep_this, ...
                              tssf, tssf_flag_missing, tssf_flag_noise, tssf_pct_missing, ...
                              tssv, tssv_flag_missing, tssv_flag_noise, tssv_pct_missing}; %#ok<SAGROW>
        end
    end
    fprintf('Processed %s\n', subj);
end

%% --- build table ---
varnames = {'subject','group','haptic','phase_type','phase','acquisition','level','repetition', ...
            'tssf','tssf_flag_missing','tssf_flag_noise','tssf_pct_missing', ...
            'tssv','tssv_flag_missing','tssv_flag_noise','tssv_pct_missing'};

% diagnostic
fprintf('\nvarnames : %d\n', numel(varnames));
fprintf('row width: %d\n', size(rows, 2));
fprintf('n rows   : %d\n', size(rows, 1));

T = cell2table(rows, 'VariableNames', varnames);

if height(T) > 0
    T.haptic            = logical(T.haptic);
    T.tssf_flag_missing = logical(T.tssf_flag_missing);
    T.tssf_flag_noise   = logical(T.tssf_flag_noise);
    T.tssv_flag_missing = logical(T.tssv_flag_missing);
    T.tssv_flag_noise   = logical(T.tssv_flag_noise);
end

if ~exist(cfg.output_root,'dir'), mkdir(cfg.output_root); end
save(fullfile(cfg.output_root, 'force_vibration_features.mat'), 'T');

fprintf(['\nSaved force/vibration table (%d rows)\n', ...
         '  TSSF: %d NaN | %d flagged missing | %d flagged noisy\n', ...
         '  TSSV: %d NaN | %d flagged missing | %d flagged noisy\n'], ...
    height(T), ...
    sum(~isfinite(T.tssf)), sum(T.tssf_flag_missing), sum(T.tssf_flag_noise), ...
    sum(~isfinite(T.tssv)), sum(T.tssv_flag_missing), sum(T.tssv_flag_noise));

%% =========================================================================
%  LOCAL FUNCTIONS  (must be at end of script file)
% ==========================================================================

function out = pf_bandpass(data, lo, hi, fs)
    [b,a] = butter(4, [lo hi]/(fs/2), 'bandpass');
    out   = zeros(size(data));
    for c = 1:size(data,2)
        out(:,c) = filtfilt(b, a, double(data(:,c)));
    end
end

function is_bad = pf_accel_is_noise(LA, t_start, t_end, cfg, BP_LOW, BP_HIGH)
    % 1. n_unique_raw < 50  : toggling noise → very few ADC codes
    % 2. rms_bp < 0.01 m/s² : near-zero energy after bandpass
    is_bad = false;
    t_a    = LA.ACCEL.time_rel(:);
    fs     = LA.ACCEL.fs_nominal;
    rv     = LA.ACCEL.data;
    tm     = t_a >= t_start & t_a <= t_end;
    if sum(tm) < 10, is_bad = true; return; end

    n_unique = mean(arrayfun(@(c) numel(unique(rv(tm,c))), 1:6));
    if n_unique < 50, is_bad = true; return; end

    seg    = (rv(tm,:) - mean(rv(tm,:),1,'omitnan')) * cfg.accel_sensitivity_ms2_per_V;
    seg_bp = seg;
    if fs/2 > BP_HIGH
        [b,a_f] = butter(4, [BP_LOW BP_HIGH]/(fs/2), 'bandpass');
        for c = 1:6
            seg_bp(:,c) = filtfilt(b, a_f, double(seg(:,c)));
        end
    end
    if mean(sqrt(mean(seg_bp.^2, 1))) < 0.01, is_bad = true; return; end
end

function is_bad = pf_force_is_noise(LF, t_start, t_end, cfg, C_force)
    % 1. n_unique_raw < 50  : very few ADC codes → floating input
    % 2. mean Fmag < threshold → dead/unpowered sensor
    is_bad = false;
    t_f    = LF.FORCE.time_rel(:);
    rv     = LF.FORCE.data;
    tm     = t_f >= t_start & t_f <= t_end;
    if sum(tm) < 10, is_bad = true; return; end

    n_chan   = size(rv, 2);
    n_unique = mean(arrayfun(@(c) numel(unique(rv(tm,c))), 1:n_chan));
    if n_unique < 50, is_bad = true; return; end

    seg   = rv(tm,:) - mean(rv(tm,:), 1, 'omitnan');
    F_cal = (C_force * seg')';
    Fmag  = sqrt(sum(F_cal(:,1:3).^2, 2));
    if mean(Fmag) < cfg.force_noise_rms_threshold_N, is_bad = true; return; end
end