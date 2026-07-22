function num_str = extract_subject_num(subject_id)
    % 'subject_s40H' → '40'
    tokens = regexp(subject_id, 's(\d+)[HN]', 'tokens');
    if ~isempty(tokens)
        num_str = tokens{1}{1};
    else
        num_str = '';
    end
end