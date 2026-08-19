function [T, T_coll] = gsr_extract_features(cfg)
% GSR_EXTRACT_FEATURES  Build long-format EDA outcome tables (SAP Section 3.3)
% ready for the mixed-effects models in Section 4.
%
% Returns:
%   T      - block-level table, one row per subject x phase x acquisition
%            (i.e. per Level for Baseline/Test phases, per Repetition for
%            training level_L* phases). Columns match cfg.amplitude_features
%            plus scr_freq, collision-derived summaries, and grouping vars.
%   T_coll - collision-level table, one row per individual collision, for
%            the time-resolved / growth-curve analyses mentioned in 3.3.
%
% Both tables are also saved to cfg.output_root as .mat and .csv.
%
% - Subject ID suffix 'H' = Haptic Feedback (HF) group, 'N' = No Haptic Feedback (NHF).
%   - Each acquisition is bounded to its own TRIAL_START/TRIAL_END window
%     via safe_trial_window.m (reading that acquisition's events.mat)
%     before any signal processing -- acquisitions without a resolvable
%     trial window (missing events.mat, or no TRIAL_START/END found) are
%     skipped rather than processed over their full unwindowed recording.
%   - cfg.scr_min_dist is in SAMPLES at cfg.fs_target, not seconds.
%     (Not confirmed -- using samples as the stated default. If your SCR
%     counts look implausibly high/low, check this first: at fs_target=10Hz,
%     10 samples = 1s minimum peak spacing.)
%   - SCR detection uses only the fixed criteria cfg.scr_min_amp /
%     cfg.scr_min_dist -- no adaptive/data-driven noise floor.
%   - "Event-locked SCR amplitude" (block-level) = mean of per-collision
%     peak phasic amplitude within a 5s post-collision window, matching
%     the search window already used in gsr_collision_overview.m.
%   - scl_mean_bc / scl_mean_pctchg / gsr_mean_bc / gsr_mean_pctchg are
%     baseline-corrected against the subject's resting-state reference
%     (gsr_rest_baseline.m), computed once per subject. NaN if no valid
%     R1 resting recording was found for that subject. SCR
%     amplitude/frequency columns are NOT baseline-corrected (resting
%     phasic activity is near-zero/undefined, so this isn't standard
%     practice for those measures).
%   - Demographic covariates (age, gender, handedness, gaming/robotic experience -- SAP Section 6) are NOT included: no demographics file
%     has been supplied. Join one onto T by 'subject' before fitting your final confirmatory models if you want those covariates included.
%   - Baseline/Test acquisitions ('Level1'..'Level5') are each single, unrepeated trials, so 'repetition' is NaN for those rows.

    all_phases = [cfg.baseline_phases, cfg.training_levels, cfg.test_phases];

    rows      = {};
    coll_rows = {};

    for si = 1:numel(cfg.all_subjects)
        subj     = cfg.all_subjects{si};
        group    = subj(end);           % 'H' or 'N'
        haptic   = strcmp(group, 'H');  % see ASSUMPTIONS
        subj_dir = fullfile(cfg.data_root, subj);

        % Resting-state baseline: computed once per subject (not once per
        % acquisition -- previously gsr_preprocess recomputed this from
        % scratch, including a full cvxEDA re-optimization, on every single
        % acquisition, which was both wasted work and never actually used).
        rest_ref = gsr_rest_baseline(subj, cfg);
        has_rest_ref = ~isempty(rest_ref);
        if ~has_rest_ref
            fprintf('  [no rest baseline] %s -- baseline-corrected columns will be NaN\n', subj);
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

                gsr_path  = fullfile(acq_dir, 'gsr.mat');
                ev_path   = fullfile(acq_dir, 'events.mat');
                coll_path = fullfile(acq_dir, 'collision_results.mat');
                if ~isfile(gsr_path), continue; end

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
                    proc = gsr_preprocess(gsr_path, cfg, t_start, t_end);
                catch ME
                    fprintf('  [skip GSR] %s/%s/%s: %s\n', subj, phase, acq, ME.message);
                    continue;
                end

                t_gsr  = proc.time;
                gsr_us = proc.gsr_us;
                tonic  = proc.tonic;
                phasic = proc.phasic;

                if numel(t_gsr) < 2, continue; end
                duration_s = t_gsr(end) - t_gsr(1);

                % --- SCR peak detection ---
                % Fixed detection criteria only (cfg.scr_min_amp,
                % cfg.scr_min_dist) -- no adaptive/computed noise floor.
                [pk_vals, ~] = findpeaks(phasic, ...
                    'MinPeakHeight',     cfg.scr_min_amp, ...
                    'MinPeakProminence', cfg.scr_min_amp, ...
                    'MinPeakDistance',   cfg.scr_min_dist);

                n_scr = numel(pk_vals);
                if duration_s > 0
                    scr_freq = n_scr / (duration_s / 60);   % SCRs per minute
                else
                    scr_freq = NaN;
                end

                if n_scr > 0
                    scr_mean_amp = mean(pk_vals);
                    scr_max_amp  = max(pk_vals);
                else
                    scr_mean_amp = 0;
                    scr_max_amp  = 0;
                end
                scr_auc = trapz(t_gsr, max(phasic, 0));

                scl_mean  = mean(tonic);
                scl_range = max(tonic) - min(tonic);
                gsr_mean_ = mean(gsr_us);
                gsr_std_  = std(gsr_us);
                gsr_rms_  = sqrt(mean(gsr_us.^2));

                % --- Baseline-corrected SCL/GSR (delta and % change from
                % resting reference). Only tonic-level measures are
                % baseline-corrected here: SCR amplitude/frequency during
                % quiet rest is near-zero/undefined, so subtracting a
                % resting phasic value is not standard practice (Boucsein,
                % 2012) and is intentionally not done for those columns.
                if has_rest_ref
                    scl_mean_bc     = scl_mean - rest_ref.tonic_mean;
                    scl_mean_pctchg = 100 * scl_mean_bc / rest_ref.tonic_mean;
                    gsr_mean_bc     = gsr_mean_ - rest_ref.gsr_mean;
                    gsr_mean_pctchg = 100 * gsr_mean_bc / rest_ref.gsr_mean;
                else
                    scl_mean_bc     = NaN;
                    scl_mean_pctchg = NaN;
                    gsr_mean_bc     = NaN;
                    gsr_mean_pctchg = NaN;
                end

                % --- Collision-locked SCR amplitude ---
                coll_scr_amp_mean  = NaN;
                coll_response_rate = NaN;
                n_coll = 0;
                rep_this = rep_nums(ai);
                if is_training
                    level_this = level_num;
                else
                    level_this = ai;   % Baseline/Test: acquisition index IS the level
                end

                if isfile(coll_path)
                    try
                        C = load(coll_path);
                        coll_t = C.results.collision_rel;
                        n_coll = numel(coll_t);
                        if n_coll > 0
                            coll_amps = nan(n_coll, 1);
                            coll_resp = false(n_coll, 1);
                            for ci = 1:n_coll
                                t0       = coll_t(ci);
                                scr_mask = (t_gsr >= t0) & (t_gsr < t0 + 5.0);  % matches overview script's scr_win
                                if any(scr_mask)
                                    pk = max(phasic(scr_mask));
                                    coll_amps(ci) = pk;
                                    coll_resp(ci) = pk > cfg.scr_min_amp;
                                end
                                coll_rows(end+1, :) = {subj, group, haptic, phase_type, phase, acq, ...
                                    level_this, rep_this, ci, t0, coll_amps(ci), coll_resp(ci)}; %#ok<AGROW>
                            end
                            coll_scr_amp_mean  = mean(coll_amps, 'omitnan');
                            coll_response_rate = mean(coll_resp);
                        end
                    catch ME
                        fprintf('  [skip collisions] %s/%s/%s: %s\n', subj, phase, acq, ME.message);
                    end
                end

                rows(end+1, :) = {subj, group, haptic, phase_type, phase, acq, ...
                    level_this, rep_this, duration_s, ...
                    scl_mean, scl_range, scr_freq, scr_mean_amp, scr_max_amp, scr_auc, ...
                    gsr_mean_, gsr_std_, gsr_rms_, ...
                    scl_mean_bc, scl_mean_pctchg, gsr_mean_bc, gsr_mean_pctchg, ...
                    n_coll, coll_scr_amp_mean, coll_response_rate}; %#ok<AGROW>
            end
        end
        fprintf('Processed %s\n', subj);
    end

    varnames = {'subject','group','haptic','phase_type','phase','acquisition', ...
        'level','repetition','duration_s', ...
        'scl_mean','scl_range','scr_freq','scr_mean_amp','scr_max_amp','scr_auc', ...
        'gsr_mean','gsr_std','gsr_rms', ...
        'scl_mean_bc','scl_mean_pctchg','gsr_mean_bc','gsr_mean_pctchg', ...
        'n_collisions','collision_scr_amp_mean','collision_response_rate'};
    T = cell2table(rows, 'VariableNames', varnames);
    if height(T) > 0, T.haptic = logical(T.haptic); end

    coll_varnames = {'subject','group','haptic','phase_type','phase','acquisition', ...
        'level','repetition','collision_idx','collision_t','scr_amp','scr_response'};
    T_coll = cell2table(coll_rows, 'VariableNames', coll_varnames);
    if height(T_coll) > 0, T_coll.haptic = logical(T_coll.haptic); end

    if ~exist(cfg.output_root, 'dir'), mkdir(cfg.output_root); end
    save(fullfile(cfg.output_root, 'eda_features.mat'), 'T', 'T_coll');
    writetable(T,      fullfile(cfg.output_root, 'eda_features_blocklevel.csv'));
    writetable(T_coll, fullfile(cfg.output_root, 'eda_features_collisionlevel.csv'));

    fprintf('\nSaved block-level table (%d rows) and collision-level table (%d rows) to %s\n', ...
        height(T), height(T_coll), cfg.output_root);
end

function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end