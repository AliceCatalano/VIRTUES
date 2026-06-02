%% VIRTUES — Post-Phase Sanity Check
% Run after any recording phase to verify data was saved correctly.
% Asks which phase and subject, then prints a structured report.

clear; clc; close all;

BASE_FOLDER = '/home/acatalano/VIRTUES/recordings/';

accel_fs         = 3000;
audio_fs         = 3000;
gsr_expected_fs  = 10;
eye_expected_fs  = 200;
audio_channels   = {'ch12','ch13','ch14','ch16','ch17','ch18'};


fprintf('VIRTUES — SANITY CHECK\n');


subject_id = input('Subject ID (e.g. S001): ', 's');
subject_folder = fullfile(BASE_FOLDER, sprintf('subject_%s', subject_id));

if ~isfolder(subject_folder)
    fprintf('[ERROR] Subject folder not found:\n  %s\n', subject_folder);
    return
end

fprintf('\nPhases available:\n');
fprintf('  1 - Resting state\n');
fprintf('  2 - Baseline\n');
fprintf('  3 - Test\n');
fprintf('  4 - Repetitions (level trials)\n');
phase = input('Select phase (1-4): ', 's');

switch phase

    %  RESTING STATE 
    case '1'
        idx = input('Resting state index (1 or 2): ', 's');
        folder = fullfile(subject_folder, 'resting_state', sprintf('%s_r%s', subject_id, idx));
        fprintf('\n--- RESTING STATE %s ---\n', idx);
        sanity_check_folder(folder, accel_fs, gsr_expected_fs, eye_expected_fs, audio_channels);

    %  BASELINE 
    case '2'
        acq = input('Acquisition number (1 or 2): ', 's');
        baseline_folder = fullfile(subject_folder, sprintf('Baseline%s', acq));

        if ~isfolder(baseline_folder)
            fprintf('[ERROR] Folder not found: %s\n', baseline_folder);
            return
        end

        lv_choice = input('Check specific level (1-5) or all (press Enter): ', 's');

        if isempty(lv_choice)
            levels = 1:5;
        else
            levels = str2double(lv_choice);
        end

        for lv = levels
            folder = fullfile(baseline_folder, sprintf('Level%d', lv));
            fprintf('\n--- BASELINE%s / LEVEL %d ---\n', acq, lv);
            sanity_check_folder(folder, accel_fs, gsr_expected_fs, eye_expected_fs, audio_channels);

            redo_folder = fullfile(baseline_folder, sprintf('Level%d_R', lv));
            if isfolder(redo_folder)
                fprintf('\n  [REDO found] Level%d_R:\n', lv);
                sanity_check_folder(redo_folder, accel_fs, gsr_expected_fs, eye_expected_fs, audio_channels);
            end
        end

    %  TEST 
    case '3'
        acq = input('Acquisition number (1, 2, or 3): ', 's');
        folder = fullfile(subject_folder, sprintf('Test%s', acq));
        fprintf('\n--- TEST%s ---\n', acq);
        sanity_check_folder(folder, accel_fs, gsr_expected_fs, eye_expected_fs, audio_channels);

    %  REPETITIONS 
    case '4'
        level = input('Level (e.g. L1): ', 's');
        level_folder = fullfile(subject_folder, sprintf('level_%s', upper(level)));

        if ~isfolder(level_folder)
            fprintf('[ERROR] Folder not found: %s\n', level_folder);
            return
        end

        rep_choice = input('Check specific rep (1-10) or all (press Enter): ', 's');

        if isempty(rep_choice)
            reps = 1:10;
        else
            reps = str2double(rep_choice);
        end

        for rep = reps
            folder = fullfile(level_folder, sprintf('rep_%02d', rep));
            if ~isfolder(folder)
                fprintf('\n  rep_%02d — NOT FOUND, skipping.\n', rep);
                continue
            end
            fprintf('\n--- %s / rep_%02d ---\n', upper(level), rep);
            sanity_check_folder(folder, accel_fs, gsr_expected_fs, eye_expected_fs, audio_channels);

            redo_folder = fullfile(level_folder, sprintf('rep_%02d_R', rep));
            if isfolder(redo_folder)
                fprintf('\n  [REDO found] rep_%02d_R:\n', rep);
                sanity_check_folder(redo_folder, accel_fs, gsr_expected_fs, eye_expected_fs, audio_channels);
            end
        end

    otherwise
        fprintf('[ERROR] Unknown phase selection.\n');
        return
end

fprintf('\n==========================================================\n');
fprintf('                  CHECK COMPLETE\n');




%% CORE SANITY CHECK FUNCTION


function sanity_check_folder(folder, accel_fs, gsr_expected_fs, eye_expected_fs, audio_channels)

    if ~isfolder(folder)
        fprintf('  [MISSING] Folder does not exist:\n    %s\n', folder);
        return
    end

    fprintf('  Folder : %s\n', folder);

    %  List all files saved 
    files = dir(fullfile(folder, '*.csv'));
    if isempty(files)
        fprintf('  [WARNING] No CSV files found in folder.\n');
    else
        fprintf('  Files saved:\n');
        for f = 1:numel(files)
            fp = fullfile(folder, files(f).name);
            sz = files(f).bytes / 1024;
            fprintf('    %-30s  %.1f KB\n', files(f).name, sz);
            if sz < 1
                fprintf('      [WARNING] File is suspiciously small (< 1 KB)\n');
            end
        end
    end

    %  Load each sensor 
    accel  = load_csv(folder, 'accel');
    gsr    = load_csv(folder, 'gsr');
    eye    = load_csv(folder, 'eye');
    events = load_csv(folder, 'events');
    audio  = load_csv(folder, 'audio');

    %  EVENTS 
    fprintf('\n  EVENTS\n');
    if isempty(events)
        fprintf('    [WARNING] events.csv missing or empty\n');
    else
        fprintf('    Count : %d\n', height(events));
        for i = 1:height(events)
            fprintf('    [%.3f]  %s\n', events.recording_time(i), events.data{i});
        end
    end

    %  ACCEL / FORCE 
    fprintf('\n  ACCEL / FORCE (NI-DAQ)\n');
    if isempty(accel)
        fprintf('    [WARNING] accel.csv missing\n');
    else
        n = height(accel);
        dur = accel.pc_time(end) - accel.pc_time(1);
        fprintf('    Samples  : %d\n', n);
        fprintf('    Duration : %.2f s\n', dur);

        dt = diff(accel.pc_time);
        dt_pos = dt(dt > 0);
        if isempty(dt_pos)
            fprintf('    [WARNING] All timestamps identical — batch mode, check reconstruction\n');
        else
            fs_est = 1 / median(dt_pos);
            fprintf('    fs est.  : %.1f Hz  (expected %d Hz)\n', fs_est, accel_fs);
        end

        n_neg = sum(dt <= 0);
        if n_neg > 0
            fprintf('    [WARNING] %d non-monotonic timestamps\n', n_neg);
        end

        gap_thresh = 5 / accel_fs;
        n_gaps = sum(dt > gap_thresh);
        if n_gaps > 0
            fprintf('    [WARNING] %d timing gaps > 5x nominal (max = %.4f s)\n', n_gaps, max(dt));
        end

        cols_check = intersect({'ai1','ai2','ai3','ai4','ai5','ai6'}, accel.Properties.VariableNames);
        if ~isempty(cols_check)
            vals = accel{:, cols_check};
            fprintf('    Accel range (V) : [%.4f  %.4f]\n', min(vals,[],'all'), max(vals,[],'all'));
            dead = find(std(vals) < 1e-6);
            if ~isempty(dead)
                fprintf('    [WARNING] Near-constant accel channels: %s\n', num2str(dead));
            end
            nan_count = sum(isnan(vals),'all');
            if nan_count > 0
                fprintf('    [WARNING] %d NaNs in accel channels\n', nan_count);
            end
        end
    end

    %  GSR 
    fprintf('\n  GSR\n');
    if isempty(gsr)
        fprintf('    [WARNING] gsr.csv missing\n');
    else
        if height(gsr) > 5, gsr(1:5,:) = []; end
        n = height(gsr);
        dur = gsr.pc_time(end) - gsr.pc_time(1);
        fprintf('    Samples  : %d\n', n);
        fprintf('    Duration : %.2f s\n', dur);

        dt_gsr = diff(gsr.pc_time);
        dt_pos = dt_gsr(dt_gsr > 0);
        if ~isempty(dt_pos)
            fs_gsr = 1 / median(dt_pos);
            fprintf('    fs est.  : %.1f Hz  (expected ~%d Hz)\n', fs_gsr, gsr_expected_fs);
            fprintf('    Jitter   : std = %.4f s\n', std(dt_gsr));
        end

        gsr_col = get_gsr_col_safe(gsr);
        if ~isempty(gsr_col)
            vals = gsr.(gsr_col);
            fprintf('    Range    : [%.2f  %.2f]\n', min(vals), max(vals));
            nan_count = sum(isnan(vals));
            if nan_count > 0
                fprintf('    [WARNING] %d NaNs in GSR\n', nan_count);
            end
            if max(vals) - min(vals) < 1e-3
                fprintf('    [WARNING] Near-constant GSR signal — sensor may not be connected\n');
            end
        else
            fprintf('    [WARNING] No recognised GSR column found\n');
        end
    end

    %  EYE 
    fprintf('\n  EYE TRACKER\n');
    if isempty(eye)
        fprintf('    [WARNING] eye.csv missing\n');
    else
        n = height(eye);
        fprintf('    Samples  : %d\n', n);

        if ismember('timestamp_unix_seconds', eye.Properties.VariableNames)
            dur = eye.timestamp_unix_seconds(end) - eye.timestamp_unix_seconds(1);
            dt_eye = diff(eye.timestamp_unix_seconds);
            fs_eye = 1 / median(dt_eye(dt_eye > 0));
            fprintf('    Duration : %.2f s\n', dur);
            fprintf('    fs est.  : %.1f Hz  (expected ~%d Hz)\n', fs_eye, eye_expected_fs);
        end

        for side = {'left','right'}
            col = sprintf('pupil_diameter_%s', side{1});
            if ismember(col, eye.Properties.VariableNames)
                vals = eye.(col);
                pct_nan = 100 * mean(isnan(vals));
                fprintf('    Pupil %-5s : %d samples  NaN=%.1f%%', side{1}, numel(vals), pct_nan);
                if pct_nan > 30
                    fprintf('  [WARNING] High NaN rate');
                end
                fprintf('\n');
            end
        end
    end

    %  AUDIO 
    fprintf('\n  AUDIO\n');
    if isempty(audio)
        fprintf('    [WARNING] audio.csv missing\n');
    else
        n = height(audio);
        dur = audio.pc_time(end) - audio.pc_time(1);
        fprintf('    Samples  : %d\n', n);
        fprintf('    Duration : %.2f s\n', dur);

        dt_audio = diff(audio.pc_time);
        dt_pos = dt_audio(dt_audio > 0);
        if ~isempty(dt_pos)
            fs_audio = 1 / median(dt_pos);
            fprintf('    fs est.  : %.1f Hz  (expected %d Hz)\n', fs_audio, 3000);
        end

        present_ch  = intersect(audio_channels, audio.Properties.VariableNames);
        missing_ch  = setdiff(audio_channels, audio.Properties.VariableNames);
        fprintf('    Channels present : %s\n', strjoin(present_ch, ', '));
        if ~isempty(missing_ch)
            fprintf('    [WARNING] Missing channels: %s\n', strjoin(missing_ch, ', '));
        end

        for i = 1:numel(present_ch)
            ch = present_ch{i};
            vals = audio.(ch);
            if std(vals) < 1e-6
                fprintf('    [WARNING] Channel %s appears flat (std < 1e-6)\n', ch);
            end
            nan_count = sum(isnan(vals));
            if nan_count > 0
                fprintf('    [WARNING] %d NaNs in channel %s\n', nan_count, ch);
            end
        end
    end

    %  ROSBAG VIDEO 
    fprintf('\n  VIDEO (rosbag)\n');
    bag_folder = fullfile(folder, 'video_bag');
    if ~isfolder(bag_folder)
        fprintf('    [WARNING] video_bag folder missing\n');
    else
        bag_files = dir(fullfile(bag_folder, '*.db3'));
        if isempty(bag_files)
            fprintf('    [WARNING] No .db3 bag file found in video_bag/\n');
        else
            for b = 1:numel(bag_files)
                sz_mb = bag_files(b).bytes / (1024^2);
                fprintf('    %-40s  %.1f MB\n', bag_files(b).name, sz_mb);
                if sz_mb < 0.1
                    fprintf('      [WARNING] Bag file suspiciously small\n');
                end
            end
        end
    end

    fprintf('\n');
end



%% UTILITY FUNCTIONS


function data = load_csv(folder, name)
    fp = fullfile(folder, [name '.csv']);
    if exist(fp, 'file')
        try
            data = readtable(fp);
        catch
            fprintf('    [ERROR] Could not read %s.csv\n', name);
            data = [];
        end
    else
        data = [];
    end
end

function gsr_col = get_gsr_col_safe(gsr)
    if     ismember('GSR_ohm',                 gsr.Properties.VariableNames), gsr_col = 'GSR_ohm';
    elseif ismember('GSR_Skin_Resistance_CAL', gsr.Properties.VariableNames), gsr_col = 'GSR_Skin_Resistance_CAL';
    else,  gsr_col = '';
    end
end