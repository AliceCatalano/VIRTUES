%% debug_tssf_frozen_subjects.m
% Chases down WHY s10H, s11N, s23H produce a bit-identical tssf_raw
% value across all 50 training trials, given that you've visually
% confirmed the raw force signal looks normal (not dead/garbage).
%
% A trace can look perfectly normal in isolation and STILL be the same
% recording duplicated across trials -- you'd only catch that by
% comparing trial N to trial N+1 byte-for-byte, which isn't something
% you'd normally think to check. This script does exactly that: for
% each flagged subject, across every training/baseline/test acquisition,
% it loads the raw (pre-windowing, pre-noise-floor) force.mat content
% and prints a cheap fingerprint (sample count, sum, sum-of-squares,
% first/last 3 raw values, file size, file mtime) plus the computed
% [t_start,t_end] window. If two trials share an identical fingerprint,
% that's near-certain proof they're reading the same underlying data --
% and the file size/mtime columns tell you whether it's literally the
% same file (same mtime/size for multiple acq folders) or separate files
% with duplicated content (different mtime, same fingerprint).
%
% This mirrors the phase/acquisition iteration logic in
% perf_extract_force_vibration_features.m exactly, so the acq_dir
% resolution (including the '_R' redo-folder fallback) matches what
% that script actually reads.

clear; clc; cfg = config();
flagged_subjects = {'subject_s10H','subject_s11N','subject_s23H'};

all_phases = [cfg.baseline_phases, cfg.training_levels, cfg.test_phases];

for si = 1:numel(flagged_subjects)
    subj = flagged_subjects{si};
    subj_dir = fullfile(cfg.data_root, subj);
    
    fprintf('SUBJECT: %s\n', subj);
    fprintf('%-14s %-10s %10s %14s %14s %10s %22s %10s %10s\n', 'phase','acq','n_samp','sum','sumsq','filesize','mtime','t_start','t_end');

    for ph_idx = 1:numel(all_phases)
        phase = all_phases{ph_idx};
        phase_dir = fullfile(subj_dir, phase);
        if ~isfolder(phase_dir), continue; end

        is_training = ismember(phase, cfg.training_levels);
        is_baseline = ismember(phase, cfg.baseline_phases);
        is_test     = ismember(phase, cfg.test_phases);

        if is_training
            acquisitions = arrayfun(@(k) sprintf('rep_%02d', k), 1:cfg.n_training_reps, 'UniformOutput', false);
        elseif is_baseline
            acquisitions = arrayfun(@(k) sprintf('Level%d', k), 1:numel(cfg.level_names), 'UniformOutput', false);
        else
            acquisitions = {'main'};
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

            force_path = fullfile(acq_dir, 'force.mat');
            if ~isfile(force_path)
                fprintf('%-14s %-10s   [no force.mat]\n', phase, acq);
                continue;
            end

            finfo = dir(force_path);
            L = load(force_path, 'FORCE');
            raw = L.FORCE.data;
            n_samp = size(raw,1);
            s = sum(raw(:));
            ss = sum(raw(:).^2);

            fprintf('%-14s %-10s %10d %14.4f %14.4f %10d %22s %10.4f %10.4f\n', ...
                phase, acq, n_samp, s, ss, finfo.bytes, datestr(finfo.datenum,'yyyy-mm-dd HH:MM:SS'), t_start, t_end);
        end
    end
end

fprintf('\n--- How to read this ---\n');
fprintf('If multiple rows for the SAME subject share identical n_samp/sum/sumsq,\n');
fprintf('those trials are reading the same underlying raw data.\n');
fprintf('  - Same mtime + same filesize across those rows -> likely the literal\n');
fprintf('    same file (hardlink/copy during data collection or folder setup).\n');
fprintf('  - Different mtime but identical fingerprint -> separate files with\n');
fprintf('    duplicated content (recording software re-saved the same buffer).\n');
fprintf('  - Identical t_start/t_end across many trials for one subject is also\n');
fprintf('    worth a second look -- same window position repeatedly is unusual\n');
fprintf('    across genuinely different trials.\n');
