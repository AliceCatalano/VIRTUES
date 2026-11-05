function T = perf_extract_force_vibration_features(cfg)
% PERF_EXTRACT_FORCE_VIBRATION_FEATURES  Per-trial force-loading proxy
% (`tssf_raw`) and TSSV (total sum of squared combined-tool vibration),
% from the NIDAQ force/accelerometer channels saved by convert2mat.m
% (force.mat / accel.mat).
%WHY tssf_raw IS NOT "TSSF" AS ORIGINALLY SPECIFIED (read before using
% this column): the originally specified method defines TSSF on the
% translational force magnitude sqrt(fx^2+fy^2+fz^2), in Newtons. That
% requires knowing which raw channels correspond to Fx/Fy/Fz. For a
% strain-gauge-bridge F/T sensor (the Mini40), the six raw analog
% channels are NOT per-axis outputs the way a 3-axis accelerometer's are
% -- each raw channel is a linear mixture of all six load components
% (Fx,Fy,Fz,Tx,Ty,Tz), by the physical construction of the gauge bridge.
% Recovering actual Fx/Fy/Fz values requires multiplying by the sensor's
% 6x6 FACTORY calibration matrix (unique per serial-numbered sensor,
% supplied by ATI/Novanta at manufacture, typically a .cal file) -- this
% is a different, more fundamental requirement than the per-task/
% coordinate-frame calibration that was deliberately skipped (see 2.2).
% Confirmed for this dataset: no factory calibration matrix exists, only
% the 6 raw uncalibrated gauge voltages.
%
% Consequently, `tssf_raw` here is NOT a translational-force magnitude in
% Newtons -- it is a total-mechanical-loading PROXY computed from the sum
% of squares of ALL SIX raw gauge channels together (no per-axis
% decomposition is possible without the missing matrix):
%
%   G[i]   = sqrt(sum_c g_c[i]^2),  c = 1..6 raw gauge channels (RAW VOLTS)
%   G[i]   = 0 if G[i] < noise floor (DATA-DRIVEN: median + cfg.force_noise_k_mad*MAD
%            of G across the trial -- NOT the physical-unit 0.21 N threshold from the
%            original method, which cannot be applied to voltage that was never
%            converted to Newtons and never can be without the missing matrix)
%   tssf_raw = sum_i G[i]^2
%
% Treat tssf_raw as valid ONLY for relative/within-study comparison
% (same sensor, same raw-to-mixed-signal transfer function throughout),
% never as an absolute force value, and never compared numerically to any
% Newton-denominated threshold or to another study's TSSF. This is
% reported explicitly in the paper (Section 2.5b) as a deviation from the
% specified method, not a silent substitution.
%
% TSSV (vibration) is NOT affected by this problem: accelerometers do not
% have the strain-gauge cross-axis-mixing issue -- each axis output is
% directly proportional to acceleration along that axis by construction
% -- so a simple scalar per-axis sensitivity conversion (Volts per m/s^2,
% from the accelerometer's own datasheet) is valid and still required
% here:
%
%   a_side[i] = sqrt(ax_side[i]^2 + ay_side[i]^2 + az_side[i]^2)   (side = left/right tool)
%   A[i]      = sqrt(a_right[i]^2 + a_left[i]^2)
%   A[i]      = 0 if A[i] < cfg.tssv_noise_threshold_ms2
%   TSSV      = sum_i A[i]^2
%
% (The source method's "each was calculated as the sum of the
% acceleration components in x/y/z" is read here as vector MAGNITUDE
% [sqrt of sum of squares], matching the analogous, unambiguous
% definition originally given for translational force -- not a literal
% linear sum, which would not be rotation-invariant and would not match
% the A[i]=sqrt(a_right^2+a_left^2) combination step, which itself only
% makes sense if a_right/a_left are already non-negative magnitudes.)
% ACCELEROMETER CHANNEL MAPPING (confirmed, not assumed): convert2mat.m's
% own header comment documents ai9:ai11 = left-tool x/y/z, ai12:ai14 =
% right-tool x/y/z, which is ACCEL.data columns 1:3 and 4:6 respectively.
%
% Returns T: one row per subject x phase x acquisition, same
% subject/group/haptic/phase_type/phase/acquisition/level/repetition
% convention as gsr_extract_features.m/perf_extract_features.m. Saved to
% cfg.output_root/force_vibration_features.mat and .csv.

    if isnan(cfg.accel_sensitivity_ms2_per_V)
        error(['perf_extract_force_vibration_features: cfg.accel_sensitivity_ms2_per_V must be ' ...
               'set from the accelerometer datasheet before TSSV can be thresholded in m/s^2 -- ' ...
               'see this file''s header.']);
    end

    all_phases = [cfg.baseline_phases, cfg.training_levels, cfg.test_phases];
    rows = {};

    for si = 1:numel(cfg.all_subjects)
        subj     = cfg.all_subjects{si};
        group    = subj(end);
        haptic   = strcmp(group, 'H');
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
                level_num    = str2double(regexp(phase, '\d+', 'match', 'once'));
                acquisitions = arrayfun(@(k) sprintf('rep_%02d', k), 1:cfg.n_training_reps, 'UniformOutput', false);
                rep_nums     = 1:cfg.n_training_reps;
            elseif is_baseline
                phase_type   = 'baseline';
                acquisitions = arrayfun(@(k) sprintf('Level%d', k), 1:numel(cfg.level_names), 'UniformOutput', false);
                rep_nums     = nan(1, numel(acquisitions));
            else
                phase_type   = 'test';
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
                        if isfolder([acq_dir '_R']), acq_dir = [acq_dir '_R'];
                        else, continue; end
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

                tssf_raw = NaN;
                force_path = fullfile(acq_dir, 'force.mat');
                if isfile(force_path)
                    L = load(force_path, 'FORCE');
                    mask = L.FORCE.time_rel >= t_start & L.FORCE.time_rel <= t_end;
                    if any(mask)
                        g_V = L.FORCE.data(mask, :);
                        Gmag = sqrt(sum(g_V.^2, 2));
                        noise_floor = median(Gmag) + cfg.force_noise_k_mad * mad(Gmag, 1);
                        Gmag(Gmag < noise_floor) = 0;
                        tssf_raw = sum(Gmag.^2);
                    end
                end

                tssv = NaN;
                accel_path = fullfile(acq_dir, 'accel.mat');
                if isfile(accel_path)
                    L = load(accel_path, 'ACCEL');
                    mask = L.ACCEL.time_rel >= t_start & L.ACCEL.time_rel <= t_end;
                    if any(mask)
                        raw_V       = L.ACCEL.data(mask, :);
                        raw_V_c     = raw_V - mean(raw_V, 1, 'omitnan');
                        accel_V     = raw_V_c * cfg.accel_sensitivity_ms2_per_V;
                        
                        a_left_ms2  = sqrt(sum(accel_V(:,1:3).^2, 2));
                        a_right_ms2 = sqrt(sum(accel_V(:,4:6).^2, 2));
                        Amag = sqrt(a_right_ms2.^2 + a_left_ms2.^2);
                        Amag(Amag < cfg.tssv_noise_threshold_ms2) = 0;
                        tssv = sum(Amag.^2);
                    end
                end

                rows(end+1, :) = {subj, group, haptic, phase_type, phase, acq,level_this, rep_this, tssf_raw, tssv}; %#ok<AGROW>
            end
        end
        fprintf('Processed %s\n', subj);
    end

    varnames = {'subject','group','haptic','phase_type','phase','acquisition', ...
        'level','repetition','tssf_raw','tssv'};
    T = cell2table(rows, 'VariableNames', varnames);
    if height(T) > 0, T.haptic = logical(T.haptic); end

    if ~exist(cfg.output_root, 'dir'), mkdir(cfg.output_root); end
    save(fullfile(cfg.output_root, 'force_vibration_features.mat'), 'T');
    writetable(T, fullfile(cfg.output_root, 'force_vibration_features.csv'));
    fprintf('\nSaved force/vibration table (%d rows) to %s\n', height(T), cfg.output_root);
end
