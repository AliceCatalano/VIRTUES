%% repair_t0_unix.m
% One-time repair for sessions where accel/force/gsr/eye/audio/events .mat
% files were generated with DIFFERENT t0_unix — e.g. because convert2mat.m
% was re-run on a subject after a sensor's CSV appeared/changed, or only a
% subset of sensors was reconverted. Operates ONLY on .mat files already on
% disk. For each trial folder:
%   1. Loads whichever of accel/force/gsr/eye/audio/events/global_tvec .mat
%      files are present.
%   2. Computes ONE unified t0_unix = min(time_unix) across ALL of them.
%   3. Recomputes time_rel (and t_trial_start/t_trial_end/events_time_rel)
%      relative to that unified t0_unix, exactly as convert2mat.m would
%      have if all sensors had been present in the same run.
%   4. Overwrites t0_unix in every struct and re-saves the .mat file.

clear; clc;

output_root = '/home/acatalano/Desktop/Virtues_Data/subject_s04H';
TOL         = 1e-6;   % seconds; below this, consider "already aligned"

trial_folders = find_leaf_folders_mat(output_root);
fprintf('Found %d converted trial folders.\n\n', numel(trial_folders));

n_fixed = 0; n_ok = 0; n_skipped = 0;

for fi = 1:numel(trial_folders)
    folder = trial_folders{fi};
    [changed, status] = repair_folder(folder, TOL);
    fprintf('[%d/%d] %-90s %s\n', fi, numel(trial_folders), folder, status);
    if changed,               n_fixed   = n_fixed + 1;
    elseif strcmp(status(1:4),'skip'), n_skipped = n_skipped + 1;
    else,                     n_ok      = n_ok + 1;
    end
end

fprintf('\nDone. Fixed=%d  AlreadyAligned=%d  Skipped=%d\n', n_fixed, n_ok, n_skipped);


function [changed, status] = repair_folder(folder, tol)
    changed = false;

    files = struct( ...
        'accel',  fullfile(folder,'accel.mat'), ...
        'force',  fullfile(folder,'force.mat'), ...
        'gsr',    fullfile(folder,'gsr.mat'), ...
        'eye',    fullfile(folder,'eye.mat'), ...
        'audio',  fullfile(folder,'audio.mat'), ...
        'events', fullfile(folder,'events.mat'), ...
        'global', fullfile(folder,'global_tvec.mat'));

    varnames = struct('accel','ACCEL','force','FORCE','gsr','GSR','eye','EYE', ...
                       'audio','AUDIO','events','EVENTS','global','GLOBAL');

    fn = fieldnames(files);
    present   = struct();
    time_mins = [];

    for k = 1:numel(fn)
        key = fn{k};
        fp  = files.(key);
        if ~isfile(fp), continue; end
        L = load(fp);
        vn = varnames.(key);
        if ~isfield(L, vn), continue; end
        present.(key) = L.(vn);

        s = present.(key);
        if isfield(s,'time_unix') && ~isempty(s.time_unix)
            time_mins(end+1) = min(s.time_unix); %#ok<AGROW>
        elseif strcmp(key,'global') && isfield(s,'events_time_unix') && ~isempty(s.events_time_unix)
            time_mins(end+1) = min(s.events_time_unix); %#ok<AGROW>
        end
    end

    if isempty(time_mins)
        status = 'skip (no time_unix found)';
        return;
    end

    new_t0 = min(time_mins);

    % Check current spread of t0_unix across present structs
    old_t0s = [];
    pf = fieldnames(present);
    for k = 1:numel(pf)
        s = present.(pf{k});
        if isfield(s,'t0_unix') && isscalar(s.t0_unix)
            old_t0s(end+1) = s.t0_unix; %#ok<AGROW>
        end
    end

    if ~isempty(old_t0s) && (max(old_t0s) - min(old_t0s)) <= tol
        status = 'ok (already aligned)';
        return;
    end

    spread = max(old_t0s) - min(old_t0s);

    % --- Apply the fix to each present struct ---
    for k = 1:numel(pf)
        key = pf{k};
        s   = present.(key);

        old_t0 = NaN;
        if isfield(s,'t0_unix') && isscalar(s.t0_unix)
            old_t0 = s.t0_unix;
        end
        delta = old_t0 - new_t0;   % NaN-safe

        % Prefer recomputing directly from time_unix (exact, no drift)
        if isfield(s,'time_unix') && ~isempty(s.time_unix)
            s.time_rel = s.time_unix - new_t0;
        elseif isfield(s,'time_rel') && isfinite(delta)
            s.time_rel = s.time_rel + delta;
        end

        if isfield(s,'t_trial_start') && isfinite(s.t_trial_start) && isfinite(delta)
            s.t_trial_start = s.t_trial_start + delta;
        end
        if isfield(s,'t_trial_end') && isfinite(s.t_trial_end) && isfinite(delta)
            s.t_trial_end = s.t_trial_end + delta;
        end
        if strcmp(key,'global') && isfield(s,'events_time_unix') && ~isempty(s.events_time_unix)
            s.events_time_rel = s.events_time_unix - new_t0;
        end

        s.t0_unix = new_t0;
        present.(key) = s;
    end

    % --- Save back, one struct per file, using its original variable name ---
    if isfield(present,'accel'),  ACCEL  = present.accel;  save(files.accel,  'ACCEL');  end
    if isfield(present,'force'),  FORCE  = present.force;  save(files.force,  'FORCE');  end
    if isfield(present,'gsr'),    GSR    = present.gsr;    save(files.gsr,    'GSR');    end
    if isfield(present,'eye'),    EYE    = present.eye;    save(files.eye,    'EYE');    end
    if isfield(present,'audio'),  AUDIO  = present.audio;  save(files.audio,  'AUDIO');  end
    if isfield(present,'events'), EVENTS = present.events; save(files.events, 'EVENTS'); end
    if isfield(present,'global'), GLOBAL = present.global; save(files.global, 'GLOBAL'); end

    changed = true;
    status  = sprintf('FIXED (spread was %.3f s)', spread);
end


function folders = find_leaf_folders_mat(root)
% Same traversal as convert2mat.m's find_leaf_folders, but looks for
% *.mat files instead of *.csv (no subject filter — scans everything
% already converted under output_root).
    folders = {};
    items = dir(root);
    for i = 1:numel(items)
        if ~items(i).isdir || strcmp(items(i).name,'.') || strcmp(items(i).name,'..')
            continue;
        end
        sub = fullfile(root, items(i).name);
        folders = [folders, recurse_into_mat(sub)]; %#ok<AGROW>
    end
end

function folders = recurse_into_mat(folder)
    folders = {};
    mats = dir(fullfile(folder, '*.mat'));
    if ~isempty(mats)
        folders{end+1} = folder;
    end
    items = dir(folder);
    for i = 1:numel(items)
        if ~items(i).isdir || strcmp(items(i).name,'.') || strcmp(items(i).name,'..')
            continue;
        end
        sub = fullfile(folder, items(i).name);
        folders = [folders, recurse_into_mat(sub)]; %#ok<AGROW>
    end
end
