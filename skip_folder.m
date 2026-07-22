function tf = skip_folder(path_str)
    % Returns true if path contains a _X component (should be skipped)
    parts = strsplit(path_str, filesep);
    tf = any(cellfun(@(p) endsWith_X(p), parts));
    end
    
    function tf = endsWith_X(name)
    tf = ~isempty(regexp(name, '_X$', 'once'));
end