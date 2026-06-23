clc; clear;

DATA_FOLDER = pwd;
varname     = 'DATA_TRAINING';

% Pick the SMALLEST source file to inspect
files   = dir(fullfile(DATA_FOLDER, [varname '*.mat']));
exclude = contains({files.name}, '_UNIFIED')   | ...
          contains({files.name}, '_MERGED')    | ...
          contains({files.name}, '_ALL')        | ...
          contains({files.name}, '_CHECKPOINT');
files   = files(~exclude);

% Sort by file size, pick smallest
[~, order] = sort([files.bytes]);
files      = files(order);

file_path  = fullfile(files(1).folder, files(1).name);
fprintf('Inspecting smallest file: %s (%.2f GB)\n\n', ...
        files(1).name, files(1).bytes/1e9);

S        = load(file_path, varname);
D        = S.(varname);
subjects = D.subjects;
clear S D

fprintf('Number of subjects in this file: %d\n\n', numel(subjects));

% Inspect first subject only
subj = subjects(1);
clear subjects

fprintf('Fields in subjects(1):\n');
fields = fieldnames(subj);

for i = 1:numel(fields)
    fname = fields{i};
    val   = subj.(fname);
    s     = whos('val');
    fprintf('  %-30s  size: %-20s  type: %-15s  RAM: %.4f MB\n', ...
            fname, mat2str(size(val)), class(val), s.bytes/1e6);
end

fprintf('\nEstimated RAM for ONE subject: %.2f MB\n', ...
        sum(cellfun(@(f) getfield(whos('x'), 'bytes'), fields, ...
        'UniformOutput', false), 'all') / 1e6);

% Simpler total estimate
info = whos('subj');
fprintf('Actual RAM used by subjects(1): %.4f MB\n', info.bytes/1e6);