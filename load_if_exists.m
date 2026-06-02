function data = load_if_exists(filepath)
    if exist(filepath,'file'), data = readtable(filepath); else, data = []; end
end