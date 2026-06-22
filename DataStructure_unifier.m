clc;clear;

%% Folder containing the separated .mat files
DATA_FOLDER = pwd;   % change if needed, e.g. '/path/to/mat/files'

% What to merge
data_types = {'BASELINE'}%;, 'TEST', 'REST', 'TRAINING'};

% What to do if the same subject appears in more than one file:
% 'error'      -> stop and show duplicate subject IDs
% 'keep_first' -> keep first occurrence
% 'keep_last'  -> keep last occurrence
duplicate_policy = 'error';

%% Merge each data type
for d = 1:numel(data_types)

    dtype = data_types{d};
    varname = ['DATA_' dtype];

    fprintf('\nMerging %s...\n', varname);

    % Find files like DATA_BASELINE_*.mat, DATA_TEST_*.mat, etc.
    files = dir(fullfile(DATA_FOLDER, [varname '*.mat']));

    % Exclude previously merged files if present
    file_names = {files.name};
    exclude = contains(file_names, '_UNIFIED') | ...
              contains(file_names, '_MERGED')  | ...
              contains(file_names, '_ALL');

    files = files(~exclude);

    if isempty(files)
        warning('No files found for %s', varname);
        eval([varname ' = struct();']);
        continue
    end

    % Sort files by numeric suffix if possible
    files = sort_files_by_suffix(files, varname);

    all_subjects = [];

    for f = 1:numel(files)

        file_path = fullfile(files(f).folder, files(f).name);
        fprintf('  Loading %s\n', files(f).name);

        S = load(file_path);

        if ~isfield(S, varname)
            warning('File %s does not contain variable %s. Skipping.', files(f).name, varname);
            continue
        end

        D = S.(varname);

        if ~isfield(D, 'subjects')
            warning('%s in file %s has no field "subjects". Skipping.', varname, files(f).name);
            continue
        end

        subjects_to_add = D.subjects;

        if isempty(subjects_to_add)
            continue
        end

        all_subjects = concatenate_subjects(all_subjects, subjects_to_add);

    end

    % Check duplicates
    all_subjects = handle_duplicate_subjects(all_subjects, duplicate_policy);

    % Sort by subject number: s02N, s05N, ..., s47H
    all_subjects = sort_subjects_by_id(all_subjects);

    % Create final struct
    FINAL = struct();
    FINAL.subjects = all_subjects;

    % Put final struct in workspace with correct name
    eval([varname ' = FINAL;']);

    fprintf('  Final number of subjects in %s: %d\n', varname, numel(FINAL.subjects));

end

%% Save final unified structs
save(fullfile(DATA_FOLDER, 'DATA_BASELINE_UNIFIED.mat'), 'DATA_BASELINE', '-v7.3');
% save(fullfile(DATA_FOLDER, 'DATA_TEST_UNIFIED.mat'),     'DATA_TEST',     '-v7.3');
% save(fullfile(DATA_FOLDER, 'DATA_REST_UNIFIED.mat'),     'DATA_REST',     '-v7.3');
% save(fullfile(DATA_FOLDER, 'DATA_TRAINING_UNIFIED.mat'), 'DATA_TRAINING', '-v7.3');
% 
% % Optional: save all 4 structs together in one file
% save(fullfile(DATA_FOLDER, 'DATA_ALL_4_STRUCTS_UNIFIED.mat'), ...
%     'DATA_BASELINE', 'DATA_TEST', 'DATA_REST', 'DATA_TRAINING', '-v7.3');
% 
% fprintf('\nDONE. Unified structs saved.\n');


%% Local functions

function out = concatenate_subjects(a, b)

    if isempty(a)
        out = b;
        return
    end

    if isempty(b)
        out = a;
        return
    end

    % Make sure both struct arrays have the same top-level fields
    fields_a = fieldnames(a);
    fields_b = fieldnames(b);

    all_fields = unique([fields_a; fields_b], 'stable');

    a = add_missing_fields(a, all_fields);
    b = add_missing_fields(b, all_fields);

    a = orderfields(a, all_fields);
    b = orderfields(b, all_fields);

    % Concatenate as row vector
    out = [a(:); b(:)].';

end


function S = add_missing_fields(S, all_fields)

    current_fields = fieldnames(S);

    for i = 1:numel(all_fields)

        fname = all_fields{i};

        if ~ismember(fname, current_fields)
            [S.(fname)] = deal([]);
        end

    end

end


function S = handle_duplicate_subjects(S, duplicate_policy)

    if isempty(S) || ~isfield(S, 'id')
        return
    end

    ids = {S.id};

    [unique_ids, ~, idx] = unique(ids, 'stable');
    counts = accumarray(idx(:), 1);

    duplicate_ids = unique_ids(counts > 1);

    if isempty(duplicate_ids)
        return
    end

    fprintf('\nDuplicate subject IDs found:\n');
    disp(duplicate_ids(:));

    switch duplicate_policy

        case 'error'

            error(['Duplicate subjects found. ', ...
                   'Check your input files or set duplicate_policy to ', ...
                   '''keep_first'' or ''keep_last''.']);

        case 'keep_first'

            [~, keep_idx] = unique(ids, 'stable');
            keep_idx = sort(keep_idx);
            S = S(keep_idx);

        case 'keep_last'

            [~, reversed_idx] = unique(fliplr(ids), 'stable');
            keep_idx = numel(ids) - reversed_idx + 1;
            keep_idx = sort(keep_idx);
            S = S(keep_idx);

        otherwise

            error('Unknown duplicate_policy: %s', duplicate_policy);

    end

end


function S = sort_subjects_by_id(S)

    if isempty(S) || ~isfield(S, 'id')
        return
    end

    ids = {S.id};
    subj_nums = nan(numel(ids), 1);

    for i = 1:numel(ids)

        token = regexp(ids{i}, '^s(\d+)', 'tokens', 'once');

        if ~isempty(token)
            subj_nums(i) = str2double(token{1});
        else
            subj_nums(i) = inf;
        end

    end

    [~, order] = sort(subj_nums);
    S = S(order);

end


function files_sorted = sort_files_by_suffix(files, varname)

    nums = nan(numel(files), 1);

    for i = 1:numel(files)

        % Example: DATA_BASELINE_47.mat -> 47
        expr = ['^' regexptranslate('escape', varname) '_(\d+)\.mat$'];
        token = regexp(files(i).name, expr, 'tokens', 'once');

        if ~isempty(token)
            nums(i) = str2double(token{1});
        else
            nums(i) = inf;
        end

    end

    [~, order] = sort(nums);
    files_sorted = files(order);

end