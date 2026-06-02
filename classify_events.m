function [t_start, t_end, kb_times, start_times, end_times] = classify_events(events, t0_unix)
% Split events into three categories and return the relative times of each.
%   kb_times    – keyboard / game events (everything that is NOT a trial marker)
%   start_times – TRIAL_START events
%   end_times   – TRIAL_END events
%   t_start     – scalar time of first TRIAL_START (NaN if absent)
%   t_end       – scalar time of first TRIAL_END   (NaN if absent)

    t_start = NaN;  t_end = NaN;
    kb_times = [];  start_times = [];  end_times = [];

    if isempty(events), return; end
    try
        for i = 1:height(events)
            t_rel = events.recording_time(i) - t0_unix;
            d     = events.data{i};
            if contains(d,'TRIAL_START')
                start_times(end+1) = t_rel; %#ok<AGROW>
                if isnan(t_start), t_start = t_rel; end
            elseif contains(d,'TRIAL_END')
                end_times(end+1) = t_rel; %#ok<AGROW>
                if isnan(t_end),   t_end   = t_rel; end
            else
                kb_times(end+1) = t_rel; %#ok<AGROW>
            end
        end
    catch
    end
end