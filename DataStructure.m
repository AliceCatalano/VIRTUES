clear;clc;

BASE_FOLDER = '/run/user/1001/gvfs/smb-share:server=shark,share=acatalano';

%participants = {'s02N','s05N','s07N','s09N','s11N','s14N','s15H','s16N','s18N','s20N'};%
%participants = {'s22N','s24N','s27N','s28N','s30N','s32N','s34N','s36N','s37N','s39N'};%,
% participants = { 's42N','s43N','s44N','s46N','s48N','s03H','s04H','s06H','s08H','s10H'};%,
participants = {'s12H','s13H','s17H','s19H','s21H','s23H','s25H','s26H','s29H','s31H'};
%participants = {'s33H','s35H','s38H','s40H','s41H','s45H','s47H'};
 
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
    
            trial = build_trial(rest_path);
    
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

            trial = build_trial(lev_path);
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

        trial = build_trial(section_path);

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

                trial = build_trial(rep_path);
                if isempty(trial)
                    continue
                end

                trial.rep = r;

                DATA_TRAINING.subjects(s).lev(l).rep(r) = trial;

            end
        end
    end
end

save('DATA_BASELINE_2131.mat','DATA_BASELINE','-v7.3');
save('DATA_TEST_2131.mat','DATA_TEST','-v7.3');
save('DATA_REST_2131.mat','DATA_REST','-v7.3');
save('DATA_TRAINING_2131.mat','DATA_TRAINING','-v7.3');

fprintf('\nDONE\n');

function trial = build_trial(trial_path)

    trial = [];

    accel_file  = fullfile(trial_path,'accel.csv');
    audio_file  = fullfile(trial_path,'audio.csv');
    gsr_file    = fullfile(trial_path,'gsr.csv');
    eye_file    = fullfile(trial_path,'eye.csv');
    events_file = fullfile(trial_path,'events.csv');

    if ~isfile(accel_file) || ~isfile(events_file)
        fprintf('Missing files: %s\n',trial_path);
        return
    end

    try
        accel = readtable(accel_file);
        events = readtable(events_file);
    catch ME
        fprintf('Failed loading %s\n',trial_path);
        fprintf('%s\n',ME.message);
        return
    end

    trial = struct();

    % Accelerometers / Force
    trial.nidaq.time = accel.recording_time;

    nidaq_vars = accel.Properties.VariableNames;
    nidaq_vars(strcmp(nidaq_vars,'recording_time')) = [];
    
    trial.nidaq.labels = nidaq_vars;
    trial.nidaq.data = accel{:,nidaq_vars};
    
    if all(ismember({'ai9','ai10','ai11','ai12','ai13','ai14'},accel.Properties.VariableNames))
    
        trial.acc.time = accel.recording_time;
    
        trial.acc.labels = {'xL','yL','zL','xR','yR','zR'};
    
        trial.acc.data = [ ...
            accel.ai9 ...
            accel.ai10 ...
            accel.ai11 ...
            accel.ai12 ...
            accel.ai13 ...
            accel.ai14 ];
    
    else
    
        trial.acc = [];
    
    end
    
    force_ch = {'ai7','ai15','ai16','ai24','ai17','ai25', 'ai18','ai26','ai19','ai27','ai20','ai28'};
    
    if all(ismember(force_ch, accel.Properties.VariableNames))
    
        trial.force.time = accel.recording_time;
    
        trial.force.labels = {'F1','F2','F3','F4','F5','F6'};
    
        trial.force.data = [accel.ai7  - accel.ai15 ...
            accel.ai16 - accel.ai24 ...
            accel.ai17 - accel.ai25 ...
            accel.ai18 - accel.ai26 ...
            accel.ai19 - accel.ai27 ...
            accel.ai20 - accel.ai28 ];
    
    else
    
        trial.force = [];
    
    end
    % Audio
    trial.audio = [];

    if isfile(audio_file)

        try

            audio = readtable(audio_file);

            trial.audio.time = audio.recording_time;

            audio_vars = intersect( ...
                {'ch11','ch12','ch13','ch14','ch16','ch17','ch18'}, ...
                audio.Properties.VariableNames, ...
                'stable');

            trial.audio.data = audio{:,audio_vars};

        catch

            trial.audio = [];

        end
    end

    % GSR
    trial.gsr = [];

    if isfile(gsr_file)

        try

            gsr = readtable(gsr_file);

            trial.gsr.time = gsr.recording_time;

            if ismember('GSR_ohm',gsr.Properties.VariableNames)
                trial.gsr.data = gsr.GSR_ohm;
            else
                trial.gsr.data = [];
            end

        catch

            trial.gsr = [];

        end
    end

    % Eye tracking
    trial.eye = [];

    if isfile(eye_file)

        try

            eye = readtable(eye_file);

            trial.eye.time = eye.recording_time;

            eye_vars = intersect( ...
                {'pupil_diameter_right','pupil_diameter_left'}, ...
                eye.Properties.VariableNames, ...
                'stable');

            trial.eye.data = eye{:,eye_vars};

        catch

            trial.eye = [];

        end
    end

    trial.events = events;
% Metadata
    trial.path = trial_path;

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

