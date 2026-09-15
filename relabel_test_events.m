%% relabel_test_events.m
% Interactive tool to fix Peg Transfer (Test1/Test2) events.mat files.
%
% WHY: convert2mat.m converts events.csv -> events.mat verbatim (see that
% file's PARSE TRIAL WINDOW / SAVE events.mat sections), copying every
% logged event row as-is. During Peg Transfer, the spacebar was pressed
% inconsistently -- sometimes to mark a left/right direction switch mid-
% task, sometimes (when the Shimmer was slow to connect) as an
% improvised task-start marker instead. safe_trial_window.m's ordinary
% TRIAL_START/TRIAL_END/spacebar-before-end logic (unchanged, and correct
% for training/Baseline phases) can therefore lock onto the wrong row as
% the trial start for Test1/Test2. Per your instruction, the fix happens
% here, at the events.csv -> events.mat conversion step, not by adding
% Test-phase special-casing to safe_trial_window.m itself.
%
% Unlike training (rep_01..rep_10) and Baseline (Level1..Level5), Test1
% and Test2 each hold their sensor files DIRECTLY -- there is no
% acquisition subfolder underneath. Each is therefore treated here as one
% single acquisition per subject.
%
% For each subject x {Test1, Test2}:
%   1. Loads that phase's RAW events.csv (same columns convert2mat.m
%      reads: 'recording_time', 'data').
%   2. Prints every row (index, recording_time, label) to the console.
%   3. Prompts you for the row number that is the true start event ("s"
%      skips this file with nothing written). The end event does not need
%      confirmation -- it is located automatically as the last row whose
%      label contains 'END', per your note that it is always correct.
%   4. Rewrites that phase's events.mat using ONLY those two rows, in the
%      exact structure convert2mat.m produces (EVENTS.time_unix,
%      .time_rel, .t_trial_start, .t_trial_end, .t0_unix, .source_file,
%      .data) -- so safe_trial_window.m and every *_extract_features.m
%      need no further change; they already expect this structure.
%   5. Reuses the t0_unix ALREADY used for this phase's other sensor files
%      (read from its global_tvec.mat), rather than recomputing one from
%      just the 2 kept events -- recomputing it would silently shift
%      EVENTS.time_rel out of alignment with gsr.mat/eye.mat/force.mat's
%      own time_rel column, which all share that same t0_unix.
%
% Any subject/phase whose raw events.csv already has exactly 2 rows is
% rewritten with no prompt (already clean, nothing to choose) -- makes
% this script safe to re-run after you've cleaned some files by hand.
%
clear; clc;
cfg = config();

% >>> SET THIS to wherever your raw events.csv files actually live <<<
% If you kept a local copy of the raw CSVs alongside the already-
% converted .mat files, this is the same as cfg.data_root. If they only
% ever existed on the original capture share (convert2mat.m's
% sharks_root), point this there instead.
RAW_EVENTS_ROOT = '/run/user/1001/gvfs/smb-share:server=shark,share=acatalano';   % <-- fill in before running
if isempty(RAW_EVENTS_ROOT)
    error(['relabel_test_events: set RAW_EVENTS_ROOT near the top of this file to the folder ' ...
           'containing the raw Test1/Test2 events.csv files before running.']);
end

phases = {'Test1', 'Test2'};
n_fixed = 0; n_skipped = 0; n_already_clean = 0;

for si = 1:numel(cfg.all_subjects)
    subj = cfg.all_subjects{si};
    for pi = 1:numel(phases)
        phase = phases{pi};
        dir_raw = fullfile(RAW_EVENTS_ROOT, subj, phase);
        dir_mat = fullfile(cfg.data_root, subj, phase);

        csv_path = fullfile(dir_raw, 'events.csv');
        if ~isfile(csv_path)
            continue;   % this subject doesn't have this phase, or no raw CSV -- not every subject has both
        end

        events = readtable(csv_path);
        if ~ismember('data', events.Properties.VariableNames) || ~ismember('recording_time', events.Properties.VariableNames)
            fprintf('  [SKIP] %s -- missing expected columns (data/recording_time)\n', csv_path);
            n_skipped = n_skipped + 1;
            continue;
        end

        n = height(events);
        if n < 2
            fprintf('  [SKIP] %s -- only %d row(s), cannot form a start/end pair\n', csv_path, n);
            n_skipped = n_skipped + 1;
            continue;
        elseif n == 2
            fprintf('  [already clean] %s (2 rows)\n', csv_path);
            start_idx = 1; end_idx = 2;
            n_already_clean = n_already_clean + 1;
        else
            fprintf('\n=== %s | %s (%d rows) ===\n', subj, phase, n);
            for r = 1:n
                fprintf('  [%2d] t=%.4f  %s\n', r, events.recording_time(r), events.data{r});
            end
            end_idx = find(contains(events.data, 'END'), 1, 'last');
            if isempty(end_idx)
                fprintf('  No row containing "END" found -- skipping, fix manually.\n');
                n_skipped = n_skipped + 1;
                continue;
            end
            fprintf('  End event (auto-detected, row %d): %s\n', end_idx, events.data{end_idx});

            answer = input('  Enter the row number that is the START event (or "s" to skip): ', 's');
            if isempty(answer) || strcmpi(answer, 's')
                fprintf('  [skipped by user, nothing written]\n');
                n_skipped = n_skipped + 1;
                continue;
            end
            start_idx = str2double(answer);
            if isnan(start_idx) || start_idx < 1 || start_idx > n || start_idx == end_idx
                fprintf('  Invalid row number -- skipping, nothing written.\n');
                n_skipped = n_skipped + 1;
                continue;
            end
        end

        % --- Reuse this phase's existing t0_unix so the rewritten
        % EVENTS.time_rel stays aligned with gsr.mat/eye.mat/force.mat ---
        gtv_path = fullfile(dir_mat, 'global_tvec.mat');
        if ~isfile(gtv_path)
            fprintf('  [SKIP] %s -- no global_tvec.mat found, cannot recover t0_unix\n', gtv_path);
            n_skipped = n_skipped + 1;
            continue;
        end
        gtv     = load(gtv_path, 'GLOBAL');
        t0_unix = gtv.GLOBAL.t0_unix;

        t_start_unix = events.recording_time(start_idx);
        t_end_unix   = events.recording_time(end_idx);
        start_label  = sprintf('TRIAL_START (manually selected from raw row %d: "%s")', start_idx, events.data{start_idx});
        end_label    = events.data{end_idx};

        [t_unix_sorted, ord] = sort([t_start_unix; t_end_unix]);
        labels_sorted = {start_label, end_label};
        labels_sorted = labels_sorted(ord);

        EVENTS.time_unix     = t_unix_sorted;
        EVENTS.time_rel      = t_unix_sorted - t0_unix;
        EVENTS.t_trial_start = t_unix_sorted(1) - t0_unix;
        EVENTS.t_trial_end   = t_unix_sorted(2) - t0_unix;
        EVENTS.t0_unix       = t0_unix;
        EVENTS.source_file   = csv_path;
        EVENTS.data          = labels_sorted(:);

        save(fullfile(dir_mat, 'events.mat'), 'EVENTS');
        fprintf('  Saved %s (start=row %d, end=row %d)\n', fullfile(dir_mat, 'events.mat'), start_idx, end_idx);
        n_fixed = n_fixed + 1;
    end
end

fprintf('\n=== Done: %d file(s) rewritten, %d already clean, %d skipped ===\n', n_fixed, n_already_clean, n_skipped);
fprintf(['Delete cfg.output_root/eda_features.mat, eye_features.mat, perf_features.mat and rerun\n' ...
    'gsr_extract_features(cfg)/eye_extract_features(cfg)/perf_extract_features(cfg) to pick up the fixed events.\n']);