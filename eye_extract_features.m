function [T, T_coll] = eye_extract_features(cfg)
% EYE_EXTRACT_FEATURES  Build long-format eye-tracking outcome tables, same
% row/column convention and same overall-trial-vs-event-locked split as
% gsr_extract_features.m, so the SAME modeling code (gsr_training_lmm.m /
% gsr_transfer_lmm.m -- both fully generic despite the name; no eye-
% specific LMM/GLMM code needed) fits eye outcomes exactly as rigorously
% as GSR ones. Two return values, exactly mirroring T / T_coll there:
%
%   T      - block-level table, one row per subject x phase x acquisition.
%            Overall-trial outcomes (SAP 3.2's confirmatory list):
%              pupil_mean       - mean pupil diameter (mm), blink-excluded.
%                                 Baseline-corrected against each subject's
%                                 resting-state (R1) reference
%                                 (eye_rest_baseline.m), same delta/%%
%                                 pattern as scl_mean_bc/scl_mean_pctchg --
%                                 see eye_rest_baseline.m for why THIS
%                                 outcome specifically gets baseline-
%                                 corrected and the others below don't.
%              pupil_slope     - "pupil diameter variation rate": within-
%                                 trial linear trend of mean(left,right)
%                                 pupil diameter (mm/s), blink-excluded.
%                                 Same approach as scl_slope. NOT baseline-
%                                 corrected (a rate, not a level).
%              gaze_dispersion  - "gaze dispersion": sqrt(var(x)+var(y))
%                                 in pixels, blink-excluded. NOT the same
%                                 as spatial-binned entropy (SAP lists
%                                 "dispersion/entropy" as one outcome);
%                                 entropy would need a calibrated
%                                 screen/AOI grid this pipeline doesn't
%                                 have -- only the dispersion half is
%                                 implemented.
%              saccade_rate     - velocity-threshold-detected saccades per
%                                 minute of valid gaze time -- NOT the
%                                 tracker's own 'saccade' channel; see
%                                 eye_preprocess.m header for why.
%            Event-locked outcome (analytic extension beyond the SAP's
%            literal eye-tracking list, mirroring "Event-locked SCR
%            amplitude" which IS in the SAP's physiological list -- same
%            idea applied to pupillometry, a standard orienting/arousal
%            response measure):
%              collision_pupil_response_mean - mean, across this trial's
%                                 collisions, of (peak pupil diameter in a
%                                 0-5s post-collision window minus mean
%                                 pupil diameter in the 1s immediately
%                                 before the collision). Same 5s search
%                                 window as collision_scr_amp_mean, for
%                                 direct cross-modality comparability --
%                                 chosen because pupil dilation responses
%                                 (unlike faster SCRs) typically peak
%                                 1-3s post-stimulus, so 5s comfortably
%                                 captures the peak without an unreasonably
%                                 wide window.
%              collision_saccade_response_rate - fraction of this trial's
%                                 collisions followed by a detected saccade
%                                 within 1s (a much shorter window than the
%                                 pupil response -- saccadic orienting
%                                 responses are fast, typically <500ms
%                                 latency). Stored/reported but NOT fit in
%                                 the LMM driver, mirroring
%                                 collision_response_rate's status in
%                                 gsr_extract_features.m's T (present, not
%                                 modeled) -- add a binomial GLMM later if
%                                 you want to test it formally.
%
%   T_coll - collision-level table, one row per individual collision, for
%            the same time-resolved analyses T_coll supports in
%            gsr_extract_features.m.
%
% Level-of-difficulty and repetition-across-training structure match
% gsr_extract_features.m exactly (level = 1-5, repetition = 1-10 for
% training rows, NaN for Baseline/Test rows).

    all_phases = [cfg.baseline_phases, cfg.training_levels, cfg.test_phases];
    rows      = {};
    coll_rows = {};

    for si = 1:numel(cfg.all_subjects)
        subj     = cfg.all_subjects{si};
        group    = subj(end);
        haptic   = strcmp(group, 'H');
        subj_dir = fullfile(cfg.data_root, subj);

        rest_ref = eye_rest_baseline(subj, cfg);
        has_rest_ref = ~isempty(rest_ref);
        if ~has_rest_ref
            fprintf('  [no eye rest baseline] %s -- pupil_mean_bc/pctchg will be NaN\n', subj);
        end

        for ph_idx = 1:numel(all_phases)
            phase     = all_phases{ph_idx};
            phase_dir = fullfile(subj_dir, phase);
            if ~isfolder(phase_dir), continue; end

            is_training = ismember(phase, cfg.training_levels);
            is_baseline = ismember(phase, cfg.baseline_phases);

            if is_training
                phase_type   = 'training';
                level_num    = str2double(regexp(phase, '\d+', 'match', 'once'));
                acquisitions = arrayfun(@(k) sprintf('rep_%02d', k), 1:cfg.n_training_reps, 'UniformOutput', false);
                rep_nums     = 1:cfg.n_training_reps;
            else
                phase_type   = local_ternary(is_baseline, 'baseline', 'test');
                acquisitions = arrayfun(@(k) sprintf('Level%d', k), 1:numel(cfg.level_names), 'UniformOutput', false);
                rep_nums     = nan(1, numel(acquisitions));
            end

            for ai = 1:numel(acquisitions)
                acq     = acquisitions{ai};
                acq_dir = fullfile(phase_dir, acq);
                if ~isfolder(acq_dir)
                    if isfolder([acq_dir '_R']), acq_dir = [acq_dir '_R'];
                    else, continue; end
                end

                eye_path  = fullfile(acq_dir, 'eye.mat');
                ev_path   = fullfile(acq_dir, 'events.mat');
                coll_path = fullfile(acq_dir, 'collision_results.mat');
                if ~isfile(eye_path), continue; end
                if ~isfile(ev_path)
                    fprintf('  [skip: no events.mat] %s/%s/%s\n', subj, phase, acq);
                    continue;
                end
                [t_start, t_end] = safe_trial_window(ev_path);
                if isnan(t_start) || isnan(t_end)
                    fprintf('  [skip: no TRIAL_START/END found] %s/%s/%s\n', subj, phase, acq);
                    continue;
                end

                try
                    proc = eye_preprocess(eye_path, cfg, t_start, t_end);
                catch ME
                    fprintf('  [skip eye] %s/%s/%s: %s\n', subj, phase, acq, ME.message);
                    continue;
                end

                valid_pupil = isfinite(proc.pupil);
                if sum(valid_pupil) >= 2
                    pupil_mean = mean(proc.pupil(valid_pupil));
                    pp = polyfit(proc.time(valid_pupil), proc.pupil(valid_pupil), 1);
                    pupil_slope = pp(1);
                else
                    pupil_mean  = NaN;
                    pupil_slope = NaN;
                end

                if has_rest_ref && isfinite(pupil_mean)
                    pupil_mean_bc     = pupil_mean - rest_ref.pupil_mean;
                    pupil_mean_pctchg = 100 * pupil_mean_bc / rest_ref.pupil_mean;
                else
                    pupil_mean_bc     = NaN;
                    pupil_mean_pctchg = NaN;
                end

                valid_xy = isfinite(proc.x) & isfinite(proc.y);
                if sum(valid_xy) >= 2
                    gaze_dispersion = sqrt(var(proc.x(valid_xy)) + var(proc.y(valid_xy)));
                else
                    gaze_dispersion = NaN;
                end

                n_saccades = numel(proc.saccade_times);
                if proc.valid_duration_s > 0
                    saccade_rate = n_saccades / (proc.valid_duration_s / 60);
                else
                    saccade_rate = NaN;
                end

                blink_frac = mean(proc.blink);

                rep_this = rep_nums(ai);
                if is_training
                    level_this = level_num;
                else
                    level_this = ai;
                end

                % --- Event-locked (collision) outcomes: pupil response +
                % saccade orienting response, mirroring the collision loop
                % in gsr_extract_features.m ---
                coll_pupil_resp_mean = NaN;
                coll_saccade_rate    = NaN;
                n_coll = 0;
                if isfile(coll_path)
                    try
                        C = load(coll_path);
                        coll_t = C.results.collision_rel;
                        n_coll = numel(coll_t);
                        if n_coll > 0
                            resp = nan(n_coll, 1);
                            sacc = false(n_coll, 1);
                            for ci = 1:n_coll
                                t0 = coll_t(ci);
                                base_mask = proc.time >= t0 - 1.0 & proc.time < t0;
                                resp_mask = proc.time > t0 & proc.time <= t0 + 5.0;   % matches SCR's scr_win
                                base_val  = mean(proc.pupil(base_mask), 'omitnan');
                                if any(resp_mask) && isfinite(base_val)
                                    peak = max(proc.pupil(resp_mask), [], 'omitnan');
                                    if isfinite(peak), resp(ci) = peak - base_val; end
                                end
                                sacc(ci) = any(proc.saccade_times > t0 & proc.saccade_times <= t0 + 1.0);

                                coll_rows(end+1, :) = {subj, group, haptic, phase_type, phase, acq, ...
                                    level_this, rep_this, ci, t0, resp(ci), sacc(ci)}; %#ok<AGROW>
                            end
                            coll_pupil_resp_mean = mean(resp, 'omitnan');
                            coll_saccade_rate    = mean(sacc);
                        end
                    catch ME
                        fprintf('  [skip collisions] %s/%s/%s: %s\n', subj, phase, acq, ME.message);
                    end
                end

                rows(end+1, :) = {subj, group, haptic, phase_type, phase, acq, ...
                    level_this, rep_this, pupil_mean, pupil_mean_bc, pupil_mean_pctchg, ...
                    pupil_slope, gaze_dispersion, ...
                    n_saccades, saccade_rate, blink_frac, proc.n_reordered, ...
                    n_coll, coll_pupil_resp_mean, coll_saccade_rate}; %#ok<AGROW>
            end
        end
        fprintf('Processed %s\n', subj);
    end

    varnames = {'subject','group','haptic','phase_type','phase','acquisition', ...
        'level','repetition','pupil_mean','pupil_mean_bc','pupil_mean_pctchg', ...
        'pupil_slope','gaze_dispersion', ...
        'n_saccades','saccade_rate','blink_frac','n_reordered', ...
        'n_collisions','collision_pupil_response_mean','collision_saccade_response_rate'};
    T = cell2table(rows, 'VariableNames', varnames);
    if height(T) > 0, T.haptic = logical(T.haptic); end

    coll_varnames = {'subject','group','haptic','phase_type','phase','acquisition', ...
        'level','repetition','collision_idx','collision_t','pupil_response','saccade_response'};
    T_coll = cell2table(coll_rows, 'VariableNames', coll_varnames);
    if height(T_coll) > 0, T_coll.haptic = logical(T_coll.haptic); end

    if ~exist(cfg.output_root, 'dir'), mkdir(cfg.output_root); end
    save(fullfile(cfg.output_root, 'eye_features.mat'), 'T', 'T_coll');
    writetable(T,      fullfile(cfg.output_root, 'eye_features_blocklevel.csv'));
    writetable(T_coll, fullfile(cfg.output_root, 'eye_features_collisionlevel.csv'));
    fprintf('\nSaved block-level table (%d rows) and collision-level table (%d rows) to %s\n', ...
        height(T), height(T_coll), cfg.output_root);
    fprintf('Total reordered (out-of-order) samples across all acquisitions: %d -- if large, revisit eye_preprocess.m''s sort-based fix.\n', ...
        sum(T.n_reordered));
end

function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
