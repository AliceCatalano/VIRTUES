clear;clc;

BASE_FOLDER = '/run/user/1002/gvfs/smb-share:server=shark,share=acatalano';

participants = {'s02N','s05N','s07N','s09N','s11N','s14N','s15H','s16N','s18N','s20N','s22N','s24N','s27N','s28N','s30N','s32N','s34N','s36N','s37N','s39N','s42N','s43N','s44N','s46N','s48N','s03H','s04H','s06H','s08H','s10H','s12H','s13H','s17H','s19H','s21H','s23H','s25H','s26H','s29H','s31H','s33H','s35H','s38H','s40H','s41H','s45H','s47H'};
% 
target_fs = 500;
accel_fs = 3000;

V2G = 1/0.4;
n_baseline_offset = 50;

safe_interp = @(t_src,y_src,t_query) interp1(t_src(:), y_src(:), min(max(t_query,min(t_src)),max(t_src)), 'linear');

DATA_BASELINE = struct();
DATA_TEST = struct();
DATA_REST = struct();
DATA_TRAINING = struct();

for s = 1:length(participants)

    subj_short = participants{s};
    SUBJECT_ID = ['subject_' subj_short];

    
    fprintf('SUBJECT %s\n', SUBJECT_ID);

    subj_mod = subj_short(end);

    DATA_BASELINE.subjects(s).id = subj_short;
    DATA_BASELINE.subjects(s).subj_mod = subj_mod;

    DATA_TEST.subjects(s).id = subj_short;
    DATA_TEST.subjects(s).subj_mod = subj_mod;

    DATA_REST.subjects(s).id = subj_short;
    DATA_REST.subjects(s).subj_mod = subj_mod;

    DATA_TRAINING.subjects(s).id = subj_short;
    DATA_TRAINING.subjects(s).subj_mod = subj_mod;

    rest_folder = fullfile(BASE_FOLDER, SUBJECT_ID, 'resting_state');

    if isfolder(rest_folder)
    
        rest_trials = dir(fullfile(rest_folder, [subj_short '_r*']));
        rest_trials = rest_trials([rest_trials.isdir]);
    
        for r = 1:length(rest_trials)
    
            rest_path = fullfile(rest_trials(r).folder, rest_trials(r).name);
    
            trial = build_trial(rest_path, accel_fs, target_fs, V2G, n_baseline_offset, safe_interp);
    
            if isempty(trial)
                continue
            end
    
            trial.acq = r;
    
            DATA_REST.subjects(s).acq(r) = trial;
    
        end
    end

    baseline_sections = {'Baseline1','Baseline2'};

    for a = 1:length(baseline_sections)

        section_path = fullfile(BASE_FOLDER, SUBJECT_ID, baseline_sections{a});

        if ~isfolder(section_path)
            continue
        end

        lev_folders = dir(fullfile(section_path,'Level*'));
        lev_folders = lev_folders([lev_folders.isdir]);
        valid = false(length(lev_folders),1);

        for k = 1:length(lev_folders)
            valid(k) = ~contains(lev_folders(k).name,'_');
        end

        lev_folders = lev_folders(valid);

        for l = 1:length(lev_folders)

            lev_path = fullfile(lev_folders(l).folder, lev_folders(l).name);

            trial = build_trial(lev_path, accel_fs, target_fs, V2G, n_baseline_offset, safe_interp);

            if isempty(trial)
                continue
            end

            trial.level = l;

            DATA_BASELINE.subjects(s).acq(a).trial(l) = trial;

        end
    end

    test_sections = {'Test1','Test2','Test3'};

    for a = 1:length(test_sections)

        section_path = fullfile(BASE_FOLDER, SUBJECT_ID, test_sections{a});

        if ~isfolder(section_path)
            continue
        end

        trial = build_trial(section_path, accel_fs, target_fs, V2G, n_baseline_offset, safe_interp);

        if isempty(trial)
            continue
        end

        trial.acq = a;

        DATA_TEST.subjects(s).acq(a) = trial;

    end

    training_folder = fullfile(BASE_FOLDER, SUBJECT_ID);

    if isfolder(training_folder)

        lev_folders = dir(fullfile(training_folder, 'level_L*'));
        lev_folders = lev_folders([lev_folders.isdir]);

        for l = 1:length(lev_folders)

            lev_path = fullfile(lev_folders(l).folder, lev_folders(l).name);

            rep_folders = dir(fullfile(lev_path,'rep_*'));
            rep_folders = rep_folders([rep_folders.isdir]);
            rep_folders = rep_folders(~contains({rep_folders.name},'_X'));
            
            DATA_TRAINING.subjects(s).lev(l).lev = l;

            for r = 1:length(rep_folders)

                rep_path = fullfile(rep_folders(r).folder, rep_folders(r).name);

                trial = build_trial(rep_path, accel_fs, target_fs, V2G, n_baseline_offset, safe_interp);

                if isempty(trial)
                    continue
                end

                trial.rep = r;

                DATA_TRAINING.subjects(s).lev(l).rep(r) = trial;

            end
        end
    end
end

% save('DATA_BASELINE.mat','DATA_BASELINE','-v7.3');
% save('DATA_TEST.mat','DATA_TEST','-v7.3');
save('DATA_REST.mat','DATA_REST','-v7.3');
save('DATA_TRAINING.mat','DATA_TRAINING','-v7.3');

fprintf('\nDONE\n');

function trial = build_trial(trial_path, accel_fs, target_fs, V2G, n_baseline_offset, safe_interp)

    trial = struct();

    accel_file = fullfile(trial_path, 'accel.csv');
    audio_file = fullfile(trial_path, 'audio.csv');
    gsr_file = fullfile(trial_path, 'gsr.csv');
    eye_file = fullfile(trial_path, 'eye.csv');
    events_file = fullfile(trial_path, 'events.csv');

    if ~isfile(accel_file) || ~isfile(events_file)
        fprintf('No acc or events %s', trial_path)
        return
    end

    try
        nidaq = readtable(accel_file);
        events = readtable(events_file);
    catch
        return
    end

    raw_t = nidaq.recording_time;
    n_samp = height(nidaq);

    anchor_idx = [1; find(diff(raw_t) ~= 0) + 1];
    anchor_t = raw_t(anchor_idx);

    t_recon = zeros(n_samp,1);

    for a = 1:numel(anchor_idx)

        i0 = anchor_idx(a);

        if a < numel(anchor_idx)

            i1 = anchor_idx(a+1)-1;
            npts = i1-i0+1;

            t_recon(i0:i1) = anchor_t(a) + (0:npts-1)' * (anchor_t(a+1)-anchor_t(a)) / npts;

        else

            i1 = n_samp;
            npts = i1-i0+1;

            t_recon(i0:i1) = anchor_t(a) + (0:npts-1)' / accel_fs;

        end
    end

    [t_start_unix, t_end_unix] = parse_trial_window(events);

    if isnan(t_start_unix) || isnan(t_end_unix)
        trial = [];
        return
    end

    mask = t_recon >= t_start_unix & t_recon <= t_end_unix;

    if sum(mask) < 100
        trial = [];
        return
    end

    t_trial = t_recon(mask);
    t_rel = t_trial - t_trial(1);

    ds_factor = round(accel_fs / target_fs);

    idx_ds = 1:ds_factor:length(t_rel);

    master_time = t_rel(idx_ds);

    xL = (nidaq.ai9(mask) - mean(nidaq.ai9(1:n_baseline_offset))) * V2G;
    yL = (nidaq.ai10(mask) - mean(nidaq.ai10(1:n_baseline_offset))) * V2G;
    zL = (nidaq.ai11(mask) - mean(nidaq.ai11(1:n_baseline_offset))) * V2G;

    xR = (nidaq.ai12(mask) - mean(nidaq.ai12(1:n_baseline_offset))) * V2G;
    yR = (nidaq.ai13(mask) - mean(nidaq.ai13(1:n_baseline_offset))) * V2G;
    zR = (nidaq.ai14(mask) - mean(nidaq.ai14(1:n_baseline_offset))) * V2G;

    accL = sqrt(xL.^2 + yL.^2 + zL.^2);
    accR = sqrt(xR.^2 + yR.^2 + zR.^2);

    acc = [accL(idx_ds) accR(idx_ds)];

    audio = [];

    if isfile(audio_file)

        try

            T = readtable(audio_file);
            ch = intersect({'ch11','ch12','ch13','ch14','ch16','ch17','ch18'}, T.Properties.VariableNames, 'stable');

            for c = 1:length(ch)
                sig = double(T.(ch{c}));
                sig_interp = safe_interp(T.recording_time, sig, t_trial);
                audio = [audio sig_interp(idx_ds)];

            end

        catch
        end
    end

    gsr = [];

    if isfile(gsr_file)

        try

            T = readtable(gsr_file);

            gsr = safe_interp(T.recording_time, T.GSR_ohm, t_trial);
            gsr = gsr(idx_ds);

        catch
        end
    end

    eye = [];

    if isfile(eye_file)

        try

            T = readtable(eye_file);

            pr = safe_interp(T.recording_time, T.pupil_diameter_right, t_trial);
            pl = safe_interp(T.recording_time, T.pupil_diameter_left, t_trial);

            eye = [pr(idx_ds) pl(idx_ds)];

        catch
        end
    end

    trial.time = master_time;
    trial.duration = master_time(end);

    trial.acc = acc;
    trial.audio = audio;
    trial.gsr = gsr;
    trial.eye = eye;

    trial.events = events;

end

function [t_start, t_end] = parse_trial_window(events)

    t_start = NaN;
    t_end = NaN;

    if isempty(events)
        return
    end

    if ismember('recording_time', events.Properties.VariableNames)

        t_col = events.recording_time;

    else

        num_cols = varfun(@isnumeric, events, 'OutputFormat','uniform');

        if ~any(num_cols)
            return
        end

        t_col = events{:, find(num_cols,1)};

    end

    if iscell(t_col)
        t_col = str2double(t_col);
    end

    if ~ismember('data', events.Properties.VariableNames)
        return
    end

    end_mask = contains(events.data,'END') & ~contains(events.data,'START');

    start_mask = contains(events.data,'START') & ~contains(events.data,'END');

    kb_mask = contains(events.data,'[Publisher]') & contains(events.data,'event_spacebar');

    if ~any(end_mask)
        return
    end

    t_end = t_col(find(end_mask,1,'last'));

    kb_before_end = kb_mask & (t_col < t_end);

    if any(kb_before_end)

        t_start = t_col(find(kb_before_end,1,'last'));

    elseif any(start_mask)

        t_start = t_col(find(start_mask,1,'first'));

    end
end

