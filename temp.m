%% DIAGNOSTIC — run this once to inspect .mat structure, then remove
fprintf('\n=== ACCEL.MAT contents ===\n');
inspect_mat(accel_s);
fprintf('\n=== AUDIO.MAT contents ===\n');
inspect_mat(audio_s);
fprintf('\n=== EVENTS.MAT contents ===\n');
inspect_mat(events_s);

% Also inspect global_tvec directly
tvec_file = fullfile(acq_folder, 'global_tvec.mat');
if isfile(tvec_file)
    fprintf('\n=== GLOBAL_TVEC.MAT contents ===\n');
    tv_raw = load(tvec_file);
    inspect_struct(tv_raw, '  ');
end

function inspect_mat(s)
    inspect_struct(s.raw_vars, '  ');
end

function inspect_struct(raw, indent)
    fnames = fieldnames(raw);
    for k = 1:numel(fnames)
        v = raw.(fnames{k});
        if isstruct(v)
            fprintf('%s[struct] %s\n', indent, fnames{k});
            inspect_struct(v, [indent '  ']);
        elseif istable(v)
            fprintf('%s[table]  %s  —  %d rows x %d cols  |  columns: %s\n', ...
                indent, fnames{k}, height(v), width(v), ...
                strjoin(v.Properties.VariableNames, ', '));
        elseif isnumeric(v)
            fprintf('%s[numeric] %s  —  size: %s  |  range: [%.4g, %.4g]\n', ...
                indent, fnames{k}, mat2str(size(v)), min(v(:)), max(v(:)));
        elseif iscell(v)
            fprintf('%s[cell]   %s  —  size: %s\n', indent, fnames{k}, mat2str(size(v)));
        elseif ischar(v) || isstring(v)
            fprintf('%s[string] %s  =  "%s"\n', indent, fnames{k}, char(v));
        else
            fprintf('%s[%s] %s\n', indent, class(v), fnames{k});
        end
    end
end