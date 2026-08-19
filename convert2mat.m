%  Reads CSVs from sharks/acatalano, saves .mat files to
%  ~/Desktop/Virtues_Data/ mirroring the folder structure.
%
%  Per trial folder the output is:
%    global_tvec.mat   — t0_unix, events time vectors
%    accel.mat
%    force.mat
%    gsr.mat
%    eye.mat           (if present)
%    audio.mat         (if present)
%    events.mat
%
%  Each sensor contains:
%    .time_rel         — seconds since t0_unix
%    .data             — raw values (no unit conversion, no offset removal)
%    .fs_nominal       — nominal sampling rate
%    .source_file      — original CSV path
%  NO .label field
%  NO collision logic code changed from subject 23


clear; clc;

% CONFIGURE PATHS
sharks_root  = '/run/user/1001/gvfs/smb-share:server=shark,share=acatalano';  
output_root  = fullfile(expanduser('~'), 'Desktop', 'Virtues_Data');
% CORRECT — use curly braces for cell array of strings
SUBJECTS_TO_RUN = {'subject_s04H', 'subject_s05N','subject_s06H','subject_s07N','subject_s08H','subject_s09N', ...
    'subject_s10H','subject_s11N','subject_s12H','subject_s13H','subject_s14N','subject_s15H','subject_s16N',...
    'subject_s17H','subject_s18N','subject_s19H','subject_s20N','subject_s21H','subject_s22N','subject_s23H'};
% NOMINAL SAMPLING RATES ----------------------------
FS_NIDAQ = 3000;   % Hz  accelerometer + force
FS_GSR   = 10;     % Hz  Shimmer (approximate, used as fallback)

% DISCOVER ALL LEAF FOLDERS -------------------------
% A leaf folder is one that contains .csv files
all_csv_folders = find_leaf_folders(sharks_root, SUBJECTS_TO_RUN);
fprintf('Found %d trial folders.\n', numel(all_csv_folders));

% PROCESS EACH FOLDER --------------------------------
for fi = 1:numel(all_csv_folders)

    src_folder = all_csv_folders{fi};
    fprintf('\n[%d/%d] %s\n', fi, numel(all_csv_folders), src_folder);

    rel_path   = strrep(src_folder, sharks_root, '');
    dst_folder = fullfile(output_root, rel_path);
    if ~exist(dst_folder, 'dir')
        mkdir(dst_folder);
    end

    try
        process_trial_folder(src_folder, dst_folder, FS_NIDAQ, FS_GSR);
    catch ME
        fprintf('  ERROR: %s\n', ME.message);
    end
end

fprintf('\nDone.\n');

function process_trial_folder(src, dst, FS_NIDAQ, FS_GSR)
% LOAD AVAILABLE CSVs --------------------------------

    % --- NI-DAQ (accel + force) ---------------------------
    nidaq_file = fullfile(src, 'accel.csv');
    has_nidaq  = isfile(nidaq_file);
    if has_nidaq
        nidaq = readtable(nidaq_file);
        fprintf('  Loaded accel.csv  (%d rows)\n', height(nidaq));
    end

    % --- GSR----------
    gsr_file = fullfile(src, 'gsr.csv');
    has_gsr  = isfile(gsr_file);
    if has_gsr
        gsr = readtable(gsr_file);
        % Intentional: remove first 5 rows (Shimmer init artefact)
        if height(gsr) > 5
            gsr(1:5,:) = [];
        end
        fprintf('  Loaded gsr.csv    (%d rows after header drop)\n', height(gsr));
    end

    % --- Eye----------
    eye_file = fullfile(src, 'eye.csv');
    has_eye  = isfile(eye_file);
    if has_eye
        eye = readtable(eye_file);
        fprintf('  Loaded eye.csv    (%d rows)\n', height(eye));
    end

    % --- Audio--------
    audio_file = fullfile(src, 'audio.csv');
    has_audio  = isfile(audio_file);
    if has_audio
        audio = readtable(audio_file);
        fprintf('  Loaded audio.csv  (%d rows)\n', height(audio));
    end

    % --- Events-------
    events_file = fullfile(src, 'events.csv');
    has_events  = isfile(events_file);
    if has_events
        events = readtable(events_file);
        fprintf('  Loaded events.csv (%d rows)\n', height(events));
    end

    % Nothing to do if folder is completely empty
    if ~has_nidaq && ~has_gsr && ~has_eye && ~has_audio && ~has_events
        fprintf('  No recognised CSVs found — skipping.\n');
        return;
    end

% NI-DAQ TIME RECONSTRUCTION -------------------------
    if has_nidaq
        vars = nidaq.Properties.VariableNames;

        has_pc_time  = ismember('pc_time',        vars);
        has_rec_time = ismember('recording_time', vars);

        if has_pc_time
            raw_t = nidaq.pc_time;
            fprintf('  NI-DAQ: using pc_time\n');
        elseif has_rec_time
            raw_t = nidaq.recording_time;
            fprintf('  NI-DAQ: using recording_time\n');
        else
            error('accel.csv has neither pc_time nor recording_time.');
        end

        % --- Single clean reconstruction ------------------
        % Find anchor points: indices where timestamp changes
        % (handles both "repeated per buffer" and "already per-sample" cases)
        n_samp     = height(nidaq);
        diffs      = [1; find(diff(raw_t) ~= 0) + 1];

        if numel(diffs) == n_samp
            % Already one unique timestamp per sample — use directly
            nidaq_t_unix = raw_t;
            fprintf('  NI-DAQ: timestamps already per-sample, using directly\n');
        else
            % Repeated buffer timestamps — interpolate between anchors
            anchor_idx = diffs;
            anchor_t   = raw_t(anchor_idx);
            nidaq_t_unix = zeros(n_samp, 1);

            for a = 1:numel(anchor_idx)
                i0 = anchor_idx(a);
                if a < numel(anchor_idx)
                    i1 = anchor_idx(a+1) - 1;
                    n  = i1 - i0 + 1;
                    t0_a = anchor_t(a);
                    t1_a = anchor_t(a+1);
                    % Linear interpolation preserving real wall-clock gaps
                    nidaq_t_unix(i0:i1) = t0_a + (0:n-1)' * (t1_a - t0_a) / n;
                else
                    % Last segment: extrapolate at nominal rate
                    i1 = n_samp;
                    n  = i1 - i0 + 1;
                    nidaq_t_unix(i0:i1) = anchor_t(a) + (0:n-1)' / FS_NIDAQ;
                end
            end
            fprintf('  NI-DAQ: reconstructed from %d anchors\n', numel(anchor_idx));
        end
    end

% COLLECT ALL ABSOLUTE TIMESTAMPS FOR t0 -------------
    all_unix = [];

    if has_nidaq
        all_unix = [all_unix; nidaq_t_unix];
    end
    if has_gsr
        all_unix = [all_unix; gsr.pc_time];
    end
    if has_eye
        all_unix = [all_unix; eye.timestamp_unix_seconds];
    end
    if has_audio
        all_unix = [all_unix; audio.recording_time];
    end
    if has_events
        all_unix = [all_unix; events.recording_time];
    end

    t0_unix = min(all_unix);
    fprintf('  t0_unix = %.6f\n', t0_unix);

% PARSE TRIAL WINDOW FROM EVENTS ---------------------
    t_trial_start = NaN;
    t_trial_end   = NaN;

    if has_events && ismember('data', events.Properties.VariableNames)
        for i = 1:height(events)
            try
                if contains(events.data{i}, 'TRIAL_START')
                    t_trial_start = events.recording_time(i) - t0_unix;
                elseif contains(events.data{i}, 'TRIAL_END')
                    t_trial_end = events.recording_time(i) - t0_unix;
                end
            catch
            end
        end
    end

% SAVE global_tvec.mat --------------------------------
    GLOBAL.t0_unix        = t0_unix;
    GLOBAL.t_trial_start  = t_trial_start;
    GLOBAL.t_trial_end    = t_trial_end;
    GLOBAL.source_folder  = src;

    if has_events
        GLOBAL.events_time_unix = events.recording_time;
        GLOBAL.events_time_rel  = events.recording_time - t0_unix;
    end

    save(fullfile(dst, 'global_tvec.mat'), 'GLOBAL');
    fprintf('  Saved global_tvec.mat\n');

% SAVE events.mat
    if has_events
        EVENTS.time_unix    = events.recording_time;
        EVENTS.time_rel     = events.recording_time - t0_unix;
        EVENTS.t_trial_start = t_trial_start;
        EVENTS.t_trial_end   = t_trial_end;
        EVENTS.t0_unix      = t0_unix;
        EVENTS.source_file  = events_file;

        % Store event labels if present
        if ismember('data', events.Properties.VariableNames)
            EVENTS.data = events.data;
        end

        save(fullfile(dst, 'events.mat'), 'EVENTS');
        fprintf('  Saved events.mat\n');
    end

% SAVE accel.mat-
    if has_nidaq
        ACCEL.time_rel   = nidaq_t_unix - t0_unix;
        ACCEL.time_unix  = nidaq_t_unix;

        % Raw voltage channels — NO unit conversion, NO offset removal
        % Channel mapping: ai9=xL, ai10=yL, ai11=zL, ai12=xR, ai13=yR, ai14=zR  SOLO per01 {'ai1','ai2','ai3','ai4','ai5','ai6'};
        ch_accel = {'ai9','ai10','ai11','ai12','ai13','ai14'};
        n_ch     = numel(ch_accel);
        n_rows   = height(nidaq);
        ACCEL.data = zeros(n_rows, n_ch);

        for c = 1:n_ch
            col = ch_accel{c};
            if ismember(col, nidaq.Properties.VariableNames)
                ACCEL.data(:,c) = nidaq.(col);
            else
                warning('  accel.csv missing column %s — filling with NaN', col);
                ACCEL.data(:,c) = NaN(n_rows, 1);
            end
        end

        ACCEL.channel_names = ch_accel;   % not .label — just metadata
        ACCEL.fs_nominal    = FS_NIDAQ;
        ACCEL.units         = 'V';
        ACCEL.source_file   = nidaq_file;
        ACCEL.t0_unix       = t0_unix;

        save(fullfile(dst, 'accel.mat'), 'ACCEL');
        fprintf('  Saved accel.mat\n');
    end

% SAVE force.mat-
    if has_nidaq
        % Correct differential pairs (fixed from original bug):
        % F1 = ai7  - ai15
        % F2 = ai16 - ai24
        % F3 = ai17 - ai25
        % F4 = ai18 - ai26
        % F5 = ai19 - ai27
        % F6 = ai20 - ai28
        force_pairs = {
            'ai7',  'ai15';
            'ai16', 'ai24';
            'ai17', 'ai25';
            'ai18', 'ai26';
            'ai19', 'ai27';
            'ai20', 'ai28'
        };

        n_force = size(force_pairs, 1);
        n_rows  = height(nidaq);
        FORCE.data = zeros(n_rows, n_force);

        vars = nidaq.Properties.VariableNames;
        for f = 1:n_force
            col_p = force_pairs{f,1};
            col_n = force_pairs{f,2};
            ok_p  = ismember(col_p, vars);
            ok_n  = ismember(col_n, vars);
            if ok_p && ok_n
                FORCE.data(:,f) = nidaq.(col_p) - nidaq.(col_n);
            else
                warning('  Force pair %s-%s: missing column(s) — NaN', col_p, col_n);
                FORCE.data(:,f) = NaN(n_rows, 1);
            end
        end

        FORCE.time_rel      = nidaq_t_unix - t0_unix;
        FORCE.time_unix     = nidaq_t_unix;
        FORCE.channel_names = {'F1','F2','F3','F4','F5','F6'};
        FORCE.force_pairs   = force_pairs;   % store mapping for reference
        FORCE.fs_nominal    = FS_NIDAQ;
        FORCE.units         = 'V';
        FORCE.source_file   = nidaq_file;
        FORCE.t0_unix       = t0_unix;

        save(fullfile(dst, 'force.mat'), 'FORCE');
        fprintf('  Saved force.mat\n');
    end

% SAVE gsr.mat---
    if has_gsr
        GSR.time_rel    = gsr.pc_time - t0_unix;
        GSR.time_unix   = gsr.pc_time;

        % GSR_ohm — main signal
        GSR.GSR_ohm     = gsr.GSR_ohm;

        % Shimmer on-board accelerometer — stored as 3 columns
        % Original format is string "[x, y, z]" — parse it
        if ismember('accel', gsr.Properties.VariableNames)
            GSR.accel_raw = parse_shimmer_accel(gsr.accel);
        end

        % Extra metadata columns
        if ismember('packettype', gsr.Properties.VariableNames)
            GSR.packettype = gsr.packettype;
        end
        if ismember('timestamp', gsr.Properties.VariableNames)
            GSR.timestamp_shimmer = gsr.timestamp;
        end

        % Estimate actual fs from timestamps
        dt_med       = median(diff(gsr.pc_time));
        GSR.fs_estimated = 1 / dt_med;
        GSR.fs_nominal   = FS_GSR;
        GSR.units        = 'Ohm';
        GSR.source_file  = gsr_file;
        GSR.t0_unix      = t0_unix;

        save(fullfile(dst, 'gsr.mat'), 'GSR');
        fprintf('  Saved gsr.mat  (fs_estimated=%.1f Hz)\n', GSR.fs_estimated);
    end

% SAVE eye.mat---
    if has_eye
        EYE.time_rel   = eye.timestamp_unix_seconds - t0_unix;
        EYE.time_unix  = eye.timestamp_unix_seconds;

        % Store all remaining numeric columns as data
        eye_vars  = eye.Properties.VariableNames;
        skip_cols = {'timestamp_unix_seconds'};
        EYE.data  = [];
        EYE.channel_names = {};

        for c = 1:numel(eye_vars)
            col = eye_vars{c};
            if ismember(col, skip_cols), continue; end
            if isnumeric(eye.(col))
                EYE.data = [EYE.data, eye.(col)];
                EYE.channel_names{end+1} = col;
            end
        end

        EYE.fs_nominal  = NaN;   % set once you know device rate
        EYE.source_file = eye_file;
        EYE.t0_unix     = t0_unix;

        save(fullfile(dst, 'eye.mat'), 'EYE');
        fprintf('  Saved eye.mat\n');
    end

% SAVE audio.mat-
    if has_audio
        %AUDIO.time_rel   = audio.recording_time - t0_unix;
        %AUDIO.time_unix  = audio.recording_time;

        audio_vars  = audio.Properties.VariableNames;
        skip_cols = {'recording_time', 'timestamp', 'sample_index', 'samplerate','pc_time'};
        AUDIO.data  = [];
        AUDIO.channel_names = {};

        for c = 1:numel(audio_vars)
            col = audio_vars{c};
            if ismember(col, skip_cols), continue; end
            if isnumeric(audio.(col))
                AUDIO.data = [AUDIO.data, audio.(col)];
                AUDIO.channel_names{end+1} = col;
            end
        end

         if ismember('pc_time', audio_vars)
            t_hw   = audio.pc_time;
            dt_hw  = diff(t_hw);
            dt_pos = dt_hw(dt_hw > 0 & dt_hw < 1);
            AUDIO.fs_estimated  = 1 / median(dt_pos);
            % pc_time's epoch is wrong (likely CLOCK_MONOTONIC-referenced, not unix).
            % Recover the true offset using recording_time, which is correctly
            % epoch-referenced (if jittery). Use median for robustness to jitter.
            epoch_correction = median(audio.recording_time - t_hw);
            t_hw_corrected   = t_hw + epoch_correction;
        
            AUDIO.time_unix = t_hw_corrected;
            AUDIO.time_rel  = t_hw_corrected - t0_unix;
            fprintf('  Audio: pc_time epoch-corrected by %.3f s (fs=%.1f Hz)\n',epoch_correction, AUDIO.fs_estimated);
        else
            dt_med             = median(diff(audio.recording_time));
            AUDIO.fs_estimated = 1 / dt_med;
            fprintf('  Audio: hardware timestamp not found, using recording_time (fs=%.1f Hz)\n', AUDIO.fs_estimated);
        end
        
        AUDIO.fs_nominal = 3000; 

        save(fullfile(dst, 'audio.mat'), 'AUDIO');
        fprintf('  Saved audio.mat\n');
    end

end   % end process_trial_folder

function accel_mat = parse_shimmer_accel(accel_col)
% Parse Shimmer accel column which contains strings like "[2023, 1427, 2585]"
% Returns Nx3 numeric matrix

    n = numel(accel_col);
    accel_mat = NaN(n, 3);

    for i = 1:n
        try
            s = accel_col{i};
            % Remove brackets and split
            s = strrep(s, '[', '');
            s = strrep(s, ']', '');
            vals = str2double(strsplit(strtrim(s), ','));
            if numel(vals) == 3
                accel_mat(i,:) = vals;
            end
        catch
        end
    end
end

function folders = find_leaf_folders(root, subject_filter)
% Recursively find all folders containing at least one .csv file.
% subject_filter is a cell array of subject folder names.
% Filter is applied only to immediate children of root.

    if nargin < 2
        subject_filter = {};
    end

    folders = {};

    % --- Step 1: list immediate children of root ---
    items = dir(root);

    for i = 1:numel(items)

        if ~items(i).isdir || strcmp(items(i).name,'.') || strcmp(items(i).name,'..')
            continue;
        end

        rel_name = items(i).name;

        % --- Apply subject filter to immediate children only ---
        if ~isempty(subject_filter)
            if ~ismember(rel_name, subject_filter)
                continue;
            end
        end

        % This child passed the filter — now recurse into it
        sub = fullfile(root, rel_name);
        leaf_folders = recurse_into(sub);
        folders = [folders, leaf_folders]; %#ok<AGROW>

    end
end

function folders = recurse_into(folder)
% Descend into folder and collect all subfolders that contain CSVs.
% No filtering here — we are already inside an approved subject folder.

    folders = {};

    % Check if THIS folder contains CSVs
    csvs = dir(fullfile(folder, '*.csv'));
    if ~isempty(csvs)
        folders{end+1} = folder;
    end

    % Recurse into subfolders
    items = dir(folder);
    for i = 1:numel(items)
        if ~items(i).isdir || strcmp(items(i).name,'.') || strcmp(items(i).name,'..')
            continue;
        end
        sub = fullfile(folder, items(i).name);
        sub_folders = recurse_into(sub);
        folders = [folders, sub_folders]; %#ok<AGROW>
    end
end
function p = expanduser(p)
% Expand ~ to home directory
    if strncmp(p,'~',1)
        home = getenv('HOME');
        if isempty(home)
            home = getenv('USERPROFILE');   % Windows fallback
        end
        p = [home, p(2:end)];
    end
end


%% audio_mat_diagnostic.m
% 1 — Sampling rate

fprintf('\nDone.\n');

%% DIAGNOSTIC — runs on the last processed folder's audio
% Uses audio_file and AUDIO already in workspace from the loop above.
% To run on a specific folder, set src_folder before running.
source_file=('/run/user/1001/gvfs/smb-share:server=shark,share=acatalano/subject_s01H/Baseline2/Level1/audio.csv');

    % --- CSV vs MAT row count ---
    fprintf('\n--- CSV vs MAT comparison ---\n');
    csv_table = readtable(source_file);
    fprintf('  CSV rows : %d\n', height(csv_table));
    fprintf('  MAT rows : %d\n', size(AUDIO.data, 1));
    fprintf('  Ratio    : %.1f\n', height(csv_table) / size(AUDIO.data, 1));

    if ismember('timestamp', csv_table.Properties.VariableNames)
        t_csv  = csv_table.timestamp;
        dt_csv = diff(t_csv);
        dt_pos_csv = dt_csv(dt_csv > 0 & dt_csv < 1);
        fprintf('  CSV timestamp fs      : %.1f Hz\n', 1/median(dt_pos_csv));
    end
    if ismember('recording_time', csv_table.Properties.VariableNames)
        t_rec  = csv_table.recording_time;
        dt_rec = diff(t_rec);
        dt_pos_rec = dt_rec(dt_rec > 0 & dt_rec < 1);
        fprintf('  CSV recording_time fs : %.1f Hz\n', 1/median(dt_pos_rec));
    end

    % --- Sampling rate ---
    fprintf('\n--- Sampling rate ---\n');
    fprintf('  fs_nominal   : %.1f Hz\n', AUDIO.fs_nominal);
    fprintf('  fs_estimated : %.1f Hz\n', AUDIO.fs_estimated);
    fprintf('  Nyquist      : %.1f Hz\n', AUDIO.fs_estimated / 2);
    fprintf('  Bandpass 80–1000 Hz fits in Nyquist? %s\n', ...
        diag_yesno(AUDIO.fs_estimated/2 > 1000));

    % --- Time vector ---
    fprintf('\n--- Time vector (time_rel) ---\n');
    t_rel  = AUDIO.time_rel;
    dt_rel = diff(t_rel);
    dt_pos = dt_rel(dt_rel > 0 & dt_rel < 1);
    dt_neg = dt_rel(dt_rel < 0);
    dt_zer = dt_rel(dt_rel == 0);
    fprintf('  Length             : %d samples\n',   numel(t_rel));
    fprintf('  Start              : %.4f s\n',        t_rel(1));
    fprintf('  End                : %.4f s\n',        t_rel(end));
    fprintf('  Duration           : %.3f s\n',        t_rel(end)-t_rel(1));
    fprintf('  dt median          : %.6f s (%.1f Hz)\n', median(dt_pos), 1/median(dt_pos));
    fprintf('  dt min             : %.6f s\n',        min(dt_pos));
    fprintf('  dt max             : %.6f s\n',        max(dt_pos));
    fprintf('  Backward jumps     : %d\n',            numel(dt_neg));
    fprintf('  Zero steps         : %d\n',            numel(dt_zer));
    fprintf('  Monotonic?         : %s\n',            diag_yesno(isempty(dt_neg) && isempty(dt_zer)));

    % --- Data matrix ---
    fprintf('\n--- Data matrix ---\n');
    fprintf('  Size         : %d rows x %d columns\n', size(AUDIO.data,1), size(AUDIO.data,2));
    fprintf('  Channel names: %s\n', strjoin(AUDIO.channel_names, ', '));
    fprintf('\n  Per-channel stats:\n');
    for k = 1:size(AUDIO.data, 2)
        col_k = double(AUDIO.data(:,k));
        fprintf('  [%d] %-6s  min=%10.6f  max=%10.6f  mean=%10.6f  std=%10.6f  allzero=%s\n', ...
            k, AUDIO.channel_names{k}, ...
            min(col_k), max(col_k), mean(col_k), std(col_k), ...
            diag_yesno(all(col_k == 0)));
    end

    % --- Bandpass test ---
    fprintf('\n--- Bandpass test (ch1, 80–1000 Hz) ---\n');
    col_bp = double(AUDIO.data(:,1));
    col_bp = col_bp - median(col_bp);
    fs_use = AUDIO.fs_estimated;
    if fs_use/2 <= 1000
        fprintf('  CANNOT bandpass — Nyquist (%.1f Hz) <= 1000 Hz\n', fs_use/2);
    else
        try
            col_filt = bandpass(col_bp, [80 1000], fs_use);
            fprintf('  Bandpass OK\n');
            fprintf('  Before std : %.6f\n', std(col_bp));
            fprintf('  After  std : %.6f\n', std(col_filt));
            fprintf('  Signal survived? %s\n', diag_yesno(std(col_filt) > 1e-10));
        catch ME
            fprintf('  Bandpass ERROR: %s\n', ME.message);
        end
    end

    % --- Plot ---
    figure('Name','AUDIO diagnostic','Units','normalized','Position',[0.05 0.1 0.9 0.8]);

    subplot(3,1,1);
    plot(t_rel, AUDIO.data(:,1), 'LineWidth',0.5);
    xlabel('Time (s)'); ylabel('V');
    title('Raw channel 1 — no processing'); grid on;

    subplot(3,1,2);
    col_plot = double(AUDIO.data(:,1)) - median(double(AUDIO.data(:,1)));
    if fs_use/2 > 1000
        col_plot = bandpass(col_plot, [80 1000], fs_use);
        title_str = 'Channel 1 — median removed + bandpass 80–1000 Hz';
    else
        title_str = sprintf('Channel 1 — median removed only (Nyquist=%.0f Hz)', fs_use/2);
    end
    plot(t_rel, col_plot, 'r', 'LineWidth',0.5);
    xlabel('Time (s)'); ylabel('V'); title(title_str); grid on;

    subplot(3,1,3);
    plot(dt_rel, 'LineWidth',0.4);
    yline(1/fs_use, 'r--', 'Expected dt');
    xlabel('Sample index'); ylabel('dt (s)');
    title('Time steps — check for gaps or backward jumps'); grid on;

    sgtitle(strrep(audio_file, '_', '\_'), 'FontSize', 8);


% ---- helper (file-scope, not inside process_trial_folder) ----
function s = diag_yesno(x)
    if x, s = 'YES'; else, s = 'NO'; end
end