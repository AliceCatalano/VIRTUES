function T_impact = collision_impact_features(cfg)
% COLLISION_IMPACT_FEATURES  Per-collision-event impact characterization,
% one row per individual detected collision (joinable to
% eda_features.mat's T_coll and eye_features.mat's T_coll on
% subject/phase/acquisition/collision_idx, which all iterate the same
% collision_results.mat's collision_rel in the same order).
%
% THREE PHYSICALLY DISTINCT impact measures are kept separate, never
% collapsed into one composite "impact score" (same principle as the
% terminology note on arousal measures elsewhere in this pipeline --
% distinct sensors are distinct constructs and can disagree):
%
%   impact_audio_peak  - peak of the per-side bandpass-summed audiomixer
%                         signal in a +-INTENSITY_WIN_SEC window around
%                         the collision (the SAME signal collision
%                         detection itself runs on). Reused directly from
%                         collision_results.mat's peak_audio, not
%                         recomputed.
%   impact_tssv        - windowed TSSV: sum-of-squares of the combined
%                         left/right tool accelerometer magnitude in the
%                         same +-INTENSITY_WIN_SEC window, using the exact
%                         same formula/units/thresholding as
%                         perf_extract_force_vibration_features.m's
%                         trial-level tssv, just windowed to the collision
%                         instead of the whole trial.
%   impact_tssf        - windowed tssf_raw: sum-of-squares of the 6-gauge
%                         force-sensor magnitude in the same window, same
%                         formula as perf_extract_force_vibration_features.m's
%                         trial-level tssf_raw.
%
% IMPORTANT PHYSICAL NOTE (confirmed by the researcher): impact_audio_peak
% and impact_tssv are NOT independent measurements. Both the audiomixer
% channels and the NIDAQ accel.mat channels digitize the SAME physical
% tool accelerometers, just via two different streaming/recording paths.
% Expect impact_audio_peak and impact_tssv to correlate strongly by
% construction; impact_tssf (a separate force sensor under the task
% platform) is the only truly independent third measure.
%
% TIERING: each of the three impact measures gets its own pooled tertile
% split (33rd/66th percentile across ALL detected collisions in the
% dataset, not per-subject), producing impact_tier_audio,
% impact_tier_tssv, impact_tier_tssf (categorical: Low/Mid/High). Kept as
% three separate tiers rather than one combined tier, since the three
% measures can and do disagree (see note above) and collapsing them would
% hide that.
%
% Requires collision_results.mat (CollisionAnalysis_Auto.m) plus
% force.mat/accel.mat to already exist per acquisition. Rows are skipped
% (not NaN-padded) for acquisitions missing force.mat or accel.mat --
% impact_tssf/impact_tssv are NaN for that row but impact_audio_peak is
% still populated if collision_results.mat has it.
%
% Saved to cfg.output_root/collision_impact_features.mat (T_impact) and
% .csv.

    if isnan(cfg.accel_sensitivity_ms2_per_V)
        error(['collision_impact_features: cfg.accel_sensitivity_ms2_per_V must be ' ...
               'set before impact_tssv can be computed -- see perf_extract_force_vibration_features.m header.']);
    end

    INTENSITY_WIN_SEC = 0.10;   % matches CollisionAnalysis_Auto.m's window exactly

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

                coll_path = fullfile(acq_dir, 'collision_results.mat');
                if ~isfile(coll_path), continue; end
                C = load(coll_path, 'results');
                coll_t   = C.results.collision_rel;
                n_coll   = numel(coll_t);
                if n_coll == 0, continue; end
                peak_audio_all = C.results.peak_audio;

                rep_this = rep_nums(ai);
                if is_training
                    level_this = level_num;
                elseif is_baseline
                    level_this = ai;
                else
                    level_this = NaN;
                end

                % ---- Load force/accel once per acquisition, window per collision ----
                have_force = false;
                force_path = fullfile(acq_dir, 'force.mat');
                if isfile(force_path)
                    LF = load(force_path, 'FORCE');
                    have_force = true;
                end
                have_accel = false;
                accel_path = fullfile(acq_dir, 'accel.mat');
                if isfile(accel_path)
                    LA = load(accel_path, 'ACCEL');
                    have_accel = true;
                end

                for ci = 1:n_coll
                    t0 = coll_t(ci);
                    win_lo = t0 - INTENSITY_WIN_SEC;
                    win_hi = t0 + INTENSITY_WIN_SEC;

                    impact_tssf = NaN;
                    if have_force
                        mask = LF.FORCE.time_rel >= win_lo & LF.FORCE.time_rel <= win_hi;
                        if any(mask)
                            g_V = LF.FORCE.data(mask, :);
                            Gmag = sqrt(sum(g_V.^2, 2));
                            noise_floor = median(Gmag) + cfg.force_noise_k_mad * mad(Gmag, 1);
                            Gmag(Gmag < noise_floor) = 0;
                            impact_tssf = sum(Gmag.^2);
                        end
                    end

                    impact_tssv = NaN;
                    if have_accel
                        mask = LA.ACCEL.time_rel >= win_lo & LA.ACCEL.time_rel <= win_hi;
                        if any(mask)
                            accel_V     = LA.ACCEL.data(mask, :) * cfg.accel_sensitivity_ms2_per_V;
                            a_left_ms2  = sqrt(sum(accel_V(:,1:3).^2, 2));
                            a_right_ms2 = sqrt(sum(accel_V(:,4:6).^2, 2));
                            Amag = sqrt(a_right_ms2.^2 + a_left_ms2.^2);
                            Amag(Amag < cfg.tssv_noise_threshold_ms2) = 0;
                            impact_tssv = sum(Amag.^2);
                        end
                    end

                    impact_audio_peak = NaN;
                    if ci <= numel(peak_audio_all)
                        impact_audio_peak = peak_audio_all(ci);
                    end

                    rows(end+1, :) = {subj, group, haptic, phase_type, phase, acq, ...
                        level_this, rep_this, ci, t0, ...
                        impact_audio_peak, impact_tssv, impact_tssf}; %#ok<AGROW>
                end
            end
        end
        fprintf('Processed %s\n', subj);
    end

    varnames = {'subject','group','haptic','phase_type','phase','acquisition', ...
        'level','repetition','collision_idx','collision_t', ...
        'impact_audio_peak','impact_tssv','impact_tssf'};
    T_impact = cell2table(rows, 'VariableNames', varnames);
    if height(T_impact) > 0, T_impact.haptic = logical(T_impact.haptic); end

    % ---- Pooled tertile tiers, one per impact measure (never combined) ----
    T_impact.impact_tier_audio = local_tertile_tier(T_impact.impact_audio_peak);
    T_impact.impact_tier_tssv  = local_tertile_tier(T_impact.impact_tssv);
    T_impact.impact_tier_tssf  = local_tertile_tier(T_impact.impact_tssf);

    if ~exist(cfg.output_root, 'dir'), mkdir(cfg.output_root); end
    save(fullfile(cfg.output_root, 'collision_impact_features.mat'), 'T_impact');
    writetable(T_impact, fullfile(cfg.output_root, 'collision_impact_features.csv'));
    fprintf('\nSaved collision-impact table (%d collision events) to %s\n', ...
        height(T_impact), cfg.output_root);

    % ---- Quick sanity report: audio/tssv correlation (expected high, same sensor) ----
    valid = isfinite(T_impact.impact_audio_peak) & isfinite(T_impact.impact_tssv);
    if sum(valid) > 2
        r = corr(T_impact.impact_audio_peak(valid), T_impact.impact_tssv(valid));
        fprintf(['\n[sanity check] impact_audio_peak vs impact_tssv correlation: r=%.3f ' ...
                 '(n=%d) -- expected high, since both trace the same tool accelerometers ' ...
                 'via two different streaming paths.\n'], r, sum(valid));
    end
end

function tier = local_tertile_tier(x)
% Pooled tertile split (33rd/66th percentile across all non-NaN values),
% returned as a categorical with categories in order Low < Mid < High.
    tier = repmat(categorical({'NaN'}), numel(x), 1);
    valid = isfinite(x);
    if sum(valid) < 3
        tier = categorical(cellstr(repmat('NaN', numel(x), 1)));
        return
    end
    cuts = quantile(x(valid), [1/3, 2/3]);
    labels = strings(numel(x), 1);
    labels(:) = "NaN";
    labels(valid & x <= cuts(1))                 = "Low";
    labels(valid & x > cuts(1) & x <= cuts(2))    = "Mid";
    labels(valid & x > cuts(2))                   = "High";
    tier = categorical(labels, {'Low','Mid','High','NaN'}, 'Ordinal', true);
end
