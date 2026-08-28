function T = perf_extract_features(cfg)
% PERF_EXTRACT_FEATURES  Build a long-format performance-outcome table
% (SAP Section 3.1) in the same row/column convention as
% gsr_extract_features.m's T (subject, group, haptic, phase_type, phase,
% acquisition, level, repetition, ...), so the same modeling code
% (perf_training_lmm.m / perf_transfer_lmm.m) can be reused for both
% physiological and performance outcomes with the same rigor.
%
% IMPLEMENTED (real, computed from data):
%   duration_s    - task completion time (SAP 3.1 "Task completion time").
%                   Computed via safe_trial_window.m on each acquisition's
%                   events.mat, the SAME trial-window logic already used by
%                   gsr_extract_features.m -- i.e. performance and
%                   physiological outcomes share identical trial
%                   boundaries per acquisition, not two independently
%                   re-derived windows. (DurationMatrices.m re-derives its
%                   own window from events.csv instead; that duplicate
%                   logic is not used here on purpose, to keep one
%                   authoritative trial-window definition across the whole
%                   pipeline.)
%   n_collisions  - collision count (SAP 3.1 "Collision count"). Identical
%                   extraction to the n_coll computed inside
%                   gsr_extract_features.m (same collision_results.mat,
%                   same field), just also saved into its own standalone
%                   performance table so it doesn't require rerunning the
%                   (much slower) GSR preprocessing to analyze on its own.
%
% NOT YET IMPLEMENTED (SAP 3.1 outcomes with no existing extraction code
% anywhere in this repo -- left as NaN, not fabricated):
%   error_count   - elastic losses/breaks. Needs an agreed event label in
%                   events.mat (e.g. an 'ELASTIC_BREAK' marker) to count;
%                   none currently exists in the event schema used by
%                   convert2mat.m/safe_trial_window.m.
%   task_success  - binary success/failure. Needs a per-trial outcome
%                   marker (event label, or a rule applied to error_count)
%                   that isn't logged yet.
%   mean_force / peak_force - needs force.mat (saved by convert2mat.m,
%                   FORCE.data / FORCE.channel_names) read and reduced
%                   per-trial the same way gsr_preprocess.m windows GSR --
%                   not yet written. If you want this added, the pattern
%                   is identical to duration_s below: load force.mat for
%                   the acquisition, mask to [t_start, t_end] via
%                   safe_trial_window, then mean()/max() the relevant
%                   channel(s).
%
% Saved to cfg.output_root as perf_features.mat and perf_features.csv.

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

                ev_path   = fullfile(acq_dir, 'events.mat');
                coll_path = fullfile(acq_dir, 'collision_results.mat');
                if ~isfile(ev_path)
                    fprintf('  [skip: no events.mat] %s/%s/%s\n', subj, phase, acq);
                    continue;
                end

                [t_start, t_end] = safe_trial_window(ev_path);
                if isnan(t_start) || isnan(t_end)
                    fprintf('  [skip: no TRIAL_START/END found] %s/%s/%s\n', subj, phase, acq);
                    continue;
                end
                duration_s = t_end - t_start;
                if duration_s <= 0
                    fprintf('  [skip: non-positive duration] %s/%s/%s\n', subj, phase, acq);
                    continue;
                end

                n_coll = 0;
                if isfile(coll_path)
                    try
                        C = load(coll_path);
                        n_coll = numel(C.results.collision_rel);
                    catch ME
                        fprintf('  [skip collisions] %s/%s/%s: %s\n', subj, phase, acq, ME.message);
                    end
                end

                rep_this = rep_nums(ai);
                if is_training
                    level_this = level_num;
                else
                    level_this = ai;
                end

                % Placeholders for not-yet-implemented SAP 3.1 outcomes --
                % NaN, not a guess. See header for what each needs.
                error_count = NaN;
                task_success = NaN;
                mean_force  = NaN;
                peak_force  = NaN;

                rows(end+1, :) = {subj, group, haptic, phase_type, phase, acq, ...
                    level_this, rep_this, duration_s, n_coll, ...
                    error_count, task_success, mean_force, peak_force}; %#ok<AGROW>
            end
        end
        fprintf('Processed %s\n', subj);
    end

    varnames = {'subject','group','haptic','phase_type','phase','acquisition', ...
        'level','repetition','duration_s','n_collisions', ...
        'error_count','task_success','mean_force','peak_force'};
    T = cell2table(rows, 'VariableNames', varnames);
    if height(T) > 0, T.haptic = logical(T.haptic); end

    if ~exist(cfg.output_root, 'dir'), mkdir(cfg.output_root); end
    save(fullfile(cfg.output_root, 'perf_features.mat'), 'T');
    writetable(T, fullfile(cfg.output_root, 'perf_features.csv'));
    fprintf('\nSaved performance table (%d rows) to %s\n', height(T), cfg.output_root);
end

function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
