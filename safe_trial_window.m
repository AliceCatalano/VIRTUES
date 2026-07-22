function [t_start, t_end] = safe_trial_window(ev_path)
    t_start = NaN; t_end = NaN;
    if isempty(ev_path), return; end
    events = load(ev_path, 'EVENTS');
    if ismember('recording_time', events.Properties.VariableNames)
        t_col = events.recording_time;
    else
        num_cols = varfun(@isnumeric, events, 'OutputFormat','uniform');
        if ~any(num_cols), return; end
        t_col = events{:, find(num_cols,1)};
    end
    if iscell(t_col), t_col = str2double(t_col); end
    if ~ismember('data', events.Properties.VariableNames), return; end
    end_mask   = contains(events.data,'END')   & ~contains(events.data,'START');
    start_mask = contains(events.data,'START') & ~contains(events.data,'END');
    kb_mask    = contains(events.data,'[Publisher]') & contains(events.data,'event_spacebar');
    if ~any(end_mask), return; end
    t_end = t_col(find(end_mask,1,'last'));
    kb_before_end = kb_mask & (t_col < t_end);
    if any(kb_before_end)
        t_start = t_col(find(kb_before_end,1,'last'));
    elseif any(start_mask)
        t_start = t_col(find(start_mask,1,'first'));
    end
    
end