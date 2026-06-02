%% VIRTUES -- Cross-Participant Duration Comparison
% Builds duration matrices across participants for:
%   - Baseline trials      (nSubjects x 10)
%   - Test trials          (nSubjects x 2)
%   - Level repetitions    (nSubjects x 5 x 10)
%
% HOW TO USE
% ----------
%   FULL RUN    Run the whole script. On first run it loads your existing
%               .mat files and processes only the subjects not yet in them.
%               On every subsequent run it does the same -- existing rows
%               are never touched.
%
%   ADD SUBJECTS  Append new IDs anywhere in 'participants', re-run.
%               The new subjects are detected automatically and appended.
%
%   PLOTS ONLY  Run Section 3 alone (Ctrl+Enter inside the section).
%               It loads the .mat files and plots without recomputing.
%
%   FORCE REDO  Set FORCE_RECOMPUTE = true to ignore existing data.

%% ========================================================================
%  SECTION 1 -- CONFIGURATION
% =========================================================================

BASE_FOLDER = '/run/user/1003/gvfs/smb-share:server=shark,share=acatalano';
SAVE_PATH   = '/home/acatalano/Desktop/Virtues';

% Paths to the three matrix files (created on first run if missing)
FILE_BASELINE = fullfile(SAVE_PATH, 'DurationBaseline.mat');
FILE_TEST     = fullfile(SAVE_PATH, 'DurationTest.mat');
FILE_LEVEL    = fullfile(SAVE_PATH, 'DurationLevels.mat');
% Companion file that records which participants are stored in those matrices
FILE_DONE     = fullfile(SAVE_PATH, 'DurationDone.mat');

% Full ordered list of ALL participants (done + new).
% Just keep appending new IDs here; the script handles the rest.
participants = {'s02N','s05N','s07N','s09N','s11N','s14N','s15H', 's16N','s18N', 's20N','s22N','s24N','s27N','s28N','s30N','s32N','s34N','s36N','s37N','s39N','s42N','s43N','s44N','s46N','s48N'...
                's03H','s04H','s06H','s08H','s10H','s12H','s13H', 's17H','s19H', 's21H','s23H','s25H','s26H','s29H','s31H','s33H','s35H','s38H','s40H','s41H','s45H','s47H'};

nLevels    = 5;
nRepsLevel = 10;
nBaseline  = 10;   % 2 acquisitions x 5 levels
nTest      = 2;

YLIM_DUR        = [0, 180];
FORCE_RECOMPUTE = false;

%% ========================================================================
%  SECTION 2 -- COMPUTE  (incremental: skips subjects already stored)
% =========================================================================

% ------------------------------------------------------------------
% Load existing matrices. Priority: files on disk > fresh start.
% If FORCE_RECOMPUTE, treat everything as new.
% ------------------------------------------------------------------
if FORCE_RECOMPUTE
    fprintf('FORCE_RECOMPUTE=true -- all subjects will be reprocessed.\n');
    participants_done = {};
    DurationBaseline  = nan(0, nBaseline);
    DurationTest      = nan(0, nTest);
    DurationLevels    = nan(0, nLevels, nRepsLevel);

else
    if isfile(FILE_BASELINE)
        S = load(FILE_BASELINE, 'DurationBaseline');
        DurationBaseline = S.DurationBaseline;
    else
        DurationBaseline = nan(0, nBaseline);
    end

    if isfile(FILE_TEST)
        S = load(FILE_TEST, 'DurationTest');
        DurationTest = S.DurationTest;
    else
        DurationTest = nan(0, nTest);
    end

    if isfile(FILE_LEVEL)
        S = load(FILE_LEVEL, 'DurationLevels');
        DurationLevels = S.DurationLevels;
    else
        DurationLevels = nan(0, nLevels, nRepsLevel);
    end

    % Load the participant index. On the very first run FILE_DONE won't
    % exist yet -- infer from the number of existing rows instead.
    if isfile(FILE_DONE)
        D = load(FILE_DONE, 'participants_done');
        participants_done = D.participants_done;
    else
        nRows = size(DurationBaseline, 1);
        if nRows > 0 && nRows <= numel(participants)
            participants_done = participants(1:nRows);
            fprintf(['FILE_DONE not found. Inferring that the first %d entries\n' ...
                     'in ''participants'' match the %d existing rows.\n' ...
                     'If that is wrong, set FORCE_RECOMPUTE=true.\n'], nRows, nRows);
        else
            participants_done = {};
        end
    end
end

% ------------------------------------------------------------------
% Identify which subjects in the requested list are missing
% ------------------------------------------------------------------
is_new   = ~ismember(participants, participants_done);
new_subj = participants(is_new);
nNew     = numel(new_subj);

% Authoritative ordered list: existing order first, new subjects appended
all_participants = [participants_done, new_subj];
nSubj = numel(all_participants);

if nNew > 0
    DurationBaseline = [DurationBaseline; nan(nNew, nBaseline)];
    DurationTest     = [DurationTest;     nan(nNew, nTest)];
    DurationLevels   = cat(1, DurationLevels, nan(nNew, nLevels, nRepsLevel));
    fprintf('Already stored: %d subjects.\nNew to process : %s\n', ...
            numel(participants_done), strjoin(new_subj, ', '));
else
    fprintf('All %d subjects already stored -- nothing to compute.\n', nSubj);
    fprintf('Run Section 3 for plots, or set FORCE_RECOMPUTE=true to redo.\n');
end

participants     = all_participants;
any_new_computed = false;

% ------------------------------------------------------------------
% Main loop -- only runs for new subjects
% ------------------------------------------------------------------
for si = 1:nSubj

    subj = participants{si};

    if ismember(subj, participants_done) && ~FORCE_RECOMPUTE
        fprintf('  [SKIP] %s\n', subj);
        continue
    end

    subj_folder = fullfile(BASE_FOLDER, ['subject_' subj]);
    if ~isfolder(subj_folder)
        fprintf('[WARNING] Folder not found: %s\n', subj_folder);
        continue
    end

    fprintf('\nProcessing %s ...\n', subj);
    any_new_computed = true;

    % BASELINE
    baseline_col = 0;
    for acq = 1:2
        bl_folder = fullfile(subj_folder, sprintf('Baseline%d', acq));
        if ~isfolder(bl_folder)
            fprintf('  Baseline%d folder not found, skipping.\n', acq); continue
        end
        for lv = 1:nLevels
            baseline_col = baseline_col + 1;
            lv_folder = fullfile(bl_folder, sprintf('Level%d', lv));
            dur = get_trial_duration(lv_folder);
            if ~isnan(dur)
                DurationBaseline(si, baseline_col) = dur;
                fprintf('  Baseline%d/Level%d : %.2f s\n', acq, lv, dur);
            else
                fprintf('  Baseline%d/Level%d : NOT FOUND or no events\n', acq, lv);
            end
        end
    end

    % TEST
    for acq = 1:nTest
        test_folder = fullfile(subj_folder, sprintf('Test%d', acq));
        dur = get_trial_duration(test_folder);
        if ~isnan(dur)
            DurationTest(si, acq) = dur;
            fprintf('  Test%d : %.2f s\n', acq, dur);
        else
            fprintf('  Test%d : NOT FOUND or no events\n', acq);
        end
    end

    % LEVEL REPETITIONS
    for lv = 1:nLevels
        level_folder = fullfile(subj_folder, sprintf('level_L%d', lv));
        if ~isfolder(level_folder)
            fprintf('  level_L%d folder not found, skipping.\n', lv); continue
        end
        for rep = 1:nRepsLevel
            rep_folder = resolve_rep_folder(level_folder, rep);
            dur = get_trial_duration(rep_folder);
            if ~isnan(dur)
                DurationLevels(si, lv, rep) = dur;
                [~, used] = fileparts(rep_folder);
                fprintf('  L%d rep%02d [%s] : %.2f s\n', lv, rep, used, dur);
            else
                fprintf('  L%d rep%02d : NOT FOUND or no events\n', lv, rep);
            end
        end
    end

end

% ------------------------------------------------------------------
% Save back to the three .mat files + update FILE_DONE
% ------------------------------------------------------------------
if any_new_computed || FORCE_RECOMPUTE
    participants_done = participants;
    save(FILE_BASELINE, 'DurationBaseline');
    save(FILE_TEST,     'DurationTest');
    save(FILE_LEVEL,    'DurationLevels');
    save(FILE_DONE,     'participants_done');
    fprintf('\nMatrices saved to:\n  %s\n  %s\n  %s\n', ...
            FILE_BASELINE, FILE_TEST, FILE_LEVEL);
    fprintf('Participant index saved to:\n  %s\n', FILE_DONE);
end

fprintf('\n========== Matrix summary ==========\n');
fprintf('Subjects         : %d\n',           numel(participants));
fprintf('DurationBaseline : %d x %d\n',      size(DurationBaseline));
fprintf('DurationTest     : %d x %d\n',      size(DurationTest));
fprintf('DurationLevels   : %d x %d x %d\n', size(DurationLevels));

%% ========================================================================
%  SECTION 3 -- PLOTS  (run this section alone to regenerate figures)
% =========================================================================

% Load from files if matrices are not already in the workspace
if ~exist('DurationBaseline','var') || ~exist('participants','var')
    fprintf('Loading matrices for plotting...\n');
    S1 = load(FILE_BASELINE, 'DurationBaseline');
    S2 = load(FILE_TEST,     'DurationTest');
    S3 = load(FILE_LEVEL,    'DurationLevels');
    D  = load(FILE_DONE,     'participants_done');
    DurationBaseline = S1.DurationBaseline;
    DurationTest     = S2.DurationTest;
    DurationLevels   = S3.DurationLevels;
    participants     = D.participants_done;
end

close all;

nSubj_p      = numel(participants);
nBaseline_p  = size(DurationBaseline, 2);
nTest_p      = size(DurationTest,     2);
nLevels_p    = size(DurationLevels,   2);
nRepsLevel_p = size(DurationLevels,   3);
subj_colors  = lines(nSubj_p);

% Baseline
figure('Name','Duration -- Baseline Trials','Position',[50 50 900 500]);
hold on;
for si = 1:nSubj_p
    plot(1:nBaseline_p, DurationBaseline(si,:), 'o', ...
        'Color', subj_colors(si,:), 'MarkerFaceColor', subj_colors(si,:), ...
        'DisplayName', participants{si});
end
plot_mean_line(DurationBaseline, [0 0 0]);
xlabel('Baseline repetition'); ylabel('Duration (s)');
title('Baseline trial durations');
ylim(YLIM_DUR); xlim([0.5, nBaseline_p+0.5]); xticks(1:nBaseline_p);
legend('Location','best','FontSize',8); grid on;

% Test
figure('Name','Duration -- Test Trials','Position',[60 60 500 450]);
hold on;
for si = 1:nSubj_p
    plot(1:nTest_p, DurationTest(si,:), 'o', ...
        'Color', subj_colors(si,:), 'LineWidth', 1.4, ...
        'MarkerFaceColor', subj_colors(si,:), 'DisplayName', participants{si});
end
plot_mean_line(DurationTest, [0 0 0]);
xlabel('Test acquisition'); ylabel('Duration (s)');
title('Test trial durations');
ylim(YLIM_DUR); xlim([0.5, nTest_p+0.5]); xticks(1:nTest_p);
legend('Location','best','FontSize',8); grid on;

% Levels
for lv = 1:nLevels_p
    figure('Name', sprintf('Duration -- Level %d', lv), ...
           'Position', [70+(lv-1)*30, 70+(lv-1)*30, 900, 500]);
    hold on;
    lv_data = squeeze(DurationLevels(:, lv, :));
    for si = 1:nSubj_p
        plot(1:nRepsLevel_p, lv_data(si,:), 'o', ...
            'Color', subj_colors(si,:), 'LineWidth', 1.4, ...
            'MarkerFaceColor', subj_colors(si,:), 'DisplayName', participants{si});
    end
    plot_mean_line(lv_data, [0 0 0]);
    xlabel('Repetition'); ylabel('Duration (s)');
    title(sprintf('Level %d -- trial durations', lv));
    ylim(YLIM_DUR); xlim([0.5, nRepsLevel_p+0.5]); xticks(1:nRepsLevel_p);
    legend('Location','best','FontSize',8); grid on;
end

fprintf('\nAll plots generated.\n');

%% ========================================================================
%  LOCAL HELPER FUNCTIONS
% =========================================================================

function folder = resolve_rep_folder(level_folder, rep)
% Returns the _R (redo) folder if it exists, otherwise the original.
    redo = fullfile(level_folder, sprintf('rep_%02d_R', rep));
    orig = fullfile(level_folder, sprintf('rep_%02d',   rep));
    if isfolder(redo), folder = redo; else, folder = orig; end
end

function dur = get_trial_duration(folder_path)
% Returns duration (s) from real movement start to trial end.
    dur = NaN;
    if ~isfolder(folder_path), return; end
    events_file = fullfile(folder_path, 'events.csv');
    if ~isfile(events_file), return; end
    try, events = readtable(events_file); catch, return; end
    if isempty(events), return; end

    if ismember('recording_time', events.Properties.VariableNames)
        t_col = events.recording_time;
    else
        num_cols = varfun(@isnumeric, events, 'OutputFormat', 'uniform');
        if ~any(num_cols), return; end
        t_col = events{:, find(num_cols, 1)};
    end
    if iscell(t_col) || ischar(t_col), t_col = str2double(t_col); end
    if ~ismember('data', events.Properties.VariableNames), return; end

    [t_start, t_end] = parse_trial_window(events, t_col);
    if isnan(t_start) || isnan(t_end) || t_end <= t_start, return; end
    dur = t_end - t_start;
end

function [t_start, t_end] = parse_trial_window(events, t_col)
% t_end   : system END event (always reliable).
% t_start : last [Publisher] event_spacebar before END = operator keyboard
%           press marking real movement onset.
%           Falls back to system START if no spacebar found.
    t_start = NaN; t_end = NaN;
    end_mask   = contains(events.data, 'END')   & ~contains(events.data, 'START');
    start_mask = contains(events.data, 'START') & ~contains(events.data, 'END');
    kb_mask    = contains(events.data, '[Publisher]') & ...
                 contains(events.data, 'event_spacebar');
    if ~any(end_mask), return; end
    t_end = t_col(find(end_mask, 1, 'last'));
    kb_before_end = kb_mask & (t_col < t_end);
    if any(kb_before_end)
        t_start = t_col(find(kb_before_end, 1, 'last'));
    elseif any(start_mask)
        t_start = t_col(find(start_mask, 1, 'first'));
    end
end

function plot_mean_line(mat, col)
% Overlays the group mean (ignoring NaN) as a thick dashed line.
    mn = mean(mat, 1, 'omitnan');
    valid = ~isnan(mn);
    if any(valid)
        plot(find(valid), mn(valid), '--s', 'Color', col, 'LineWidth', 2.2, ...
            'MarkerSize', 6, 'MarkerFaceColor', col, 'DisplayName', 'Group mean');
    end
end