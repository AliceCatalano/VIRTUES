
function [t_start,t_end] = parse_trial_events(events,t0_unix)
    t_start=NaN; t_end=NaN;
    if isempty(events), return; end
    try
        for i = 1:height(events)
            if contains(events.data{i},'TRIAL_START'), t_start=events.recording_time(i)-t0_unix;
            elseif contains(events.data{i},'TRIAL_END'), t_end=events.recording_time(i)-t0_unix; end
        end
    catch; end
end