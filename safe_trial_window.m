function [t_start, t_end] = safe_trial_window(ev_path)
% Extract [t_start, t_end] (seconds, time_rel) bounding a trial/resting
% block from an events.mat file.
%
% NOTE: convert2mat.m saves EVENTS as a plain struct (dot-assignment),
% NOT a table. load(ev_path,'EVENTS') therefore returns a wrapper struct
% with a single field .EVENTS holding the real data — treating that
% wrapper as a table (events.Properties.VariableNames) throws an error.
%
% ROUTING: if the events file is a resting-state block (labels contain
% 'RESTING'), this delegates entirely to find_resting_end.m, which:
%   - never reads RESTING_START (unreliable — fires regardless of EDA
%     connection status on the Shimmer3+ setup used here)
%   - parses the authoritative timestamp embedded in the event label
%     text rather than trusting EVENTS.time_unix/time_rel
% In that case t_start is returned as NaN; callers needing the resting
% block start (e.g. compute_rest_reference) must derive it from the
% fixed block duration, not from this function.
%
% For all other (non-resting) events files, the original TRIAL_START /
% TRIAL_END / spacebar-keypress logic is used unchanged.

    t_start = NaN; t_end = NaN;
    if isempty(ev_path) || ~isfile(ev_path), return; end

    loaded = load(ev_path, 'EVENTS');
    if ~isfield(loaded, 'EVENTS'), return; end
    EVENTS = loaded.EVENTS;

    if ~isfield(EVENTS, 'data') || isempty(EVENTS.data), return; end
    labels = EVENTS.data;

    % --- Resting-state block: delegate to the dedicated helper ---
    if any(contains(labels, 'RESTING'))
        t_end   = find_resting_end(ev_path);
        t_start = NaN;
        return;
    end

    % --- Regular trial block: TRIAL_START/TRIAL_END + spacebar ---
    if isfield(EVENTS, 'time_rel') && ~isempty(EVENTS.time_rel)
        t_col = EVENTS.time_rel;
    elseif isfield(EVENTS, 'time_unix') && ~isempty(EVENTS.time_unix)
        t_col = EVENTS.time_unix;
    else
        return;
    end

    if iscell(t_col), t_col = str2double(t_col); end
    if numel(t_col) ~= numel(labels)
        warning('safe_trial_window: time vector / label count mismatch for %s', ev_path);
        return;
    end

    end_mask   = contains(labels,'END')   & ~contains(labels,'START');
    start_mask = contains(labels,'START') & ~contains(labels,'END');
    kb_mask    = contains(labels,'[Publisher]') & contains(labels,'event_spacebar');

    if ~any(end_mask), return; end
    t_end = t_col(find(end_mask,1,'last'));

    kb_before_end = kb_mask & (t_col < t_end);
    if any(kb_before_end)
        t_start = t_col(find(kb_before_end,1,'last'));
    elseif any(start_mask)
        t_start = t_col(find(start_mask,1,'first'));
    end

end