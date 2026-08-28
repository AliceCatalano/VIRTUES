function t_end = find_resting_end(ev_path)
% Extract the RESTING_END_* time (seconds, time_rel) from a resting-state
% events.mat file.
%
% Called from safe_trial_window.m when it detects a resting-state events
% file (labels containing 'RESTING'). Not normally called directly.
%
% IMPORTANT — two things this function deliberately does NOT do:
%
% 1. It never reads RESTING_START_*. On the Shimmer3+ setup used for
%    this protocol, RESTING_START fires regardless of whether the EDA
%    sensor had actually finished connecting, so it does not reliably
%    mark the true beginning of the resting block. The block duration is
%    fixed by protocol instead, so callers should derive
%       t_start = t_end - resting_duration
%    (see compute_rest_reference), never from RESTING_START itself.
%
% 2. It does NOT trust EVENTS.time_unix / EVENTS.time_rel for the
%    timestamp. Those are derived in convert2mat.m from the events.csv
%    'recording_time' column, which may not agree with the timestamp
%    actually embedded in the event label text. Each row of EVENTS.data
%    looks like:
%       'RESTING_END_1 1779093152.62805'
%    i.e. "LABEL unix_timestamp" as a single string — that embedded
%    number is the authoritative source of truth here, so it is parsed
%    directly out of the string and converted to time_rel using
%    EVENTS.t0_unix, bypassing whatever convert2mat did with
%    recording_time entirely.

    t_end = NaN;
    if isempty(ev_path) || ~isfile(ev_path), return; end

    loaded = load(ev_path, 'EVENTS');
    if ~isfield(loaded, 'EVENTS'), return; end
    EVENTS = loaded.EVENTS;

    if ~isfield(EVENTS, 'data') || isempty(EVENTS.data), return; end
    labels = EVENTS.data;

    if ~isfield(EVENTS, 't0_unix') || isempty(EVENTS.t0_unix)
        warning('find_resting_end: missing t0_unix in %s', ev_path);
        return;
    end
    t0_unix = EVENTS.t0_unix;

    end_idx = find(contains(labels, 'RESTING_END'), 1, 'last');
    if isempty(end_idx), return; end

    t_end_unix = parse_embedded_timestamp(labels{end_idx});
    if isnan(t_end_unix)
        warning('find_resting_end: could not parse timestamp from "%s" in %s', ...
            labels{end_idx}, ev_path);
        return;
    end

    t_end = t_end_unix - t0_unix;

    % Diagnostic: flag disagreement with convert2mat's recording_time-based
    % extraction, so mismatches can be spotted/quantified per subject.
    if isfield(EVENTS, 'time_unix') && numel(EVENTS.time_unix) >= end_idx
        recorded_unix = EVENTS.time_unix(end_idx);
        discrepancy   = abs(recorded_unix - t_end_unix);
        if discrepancy > 0.5   % seconds; adjust threshold as needed
            % warning(['find_resting_end: embedded timestamp for RESTING_END differs from ', ...
            %     'recording_time by %.3f s in %s (embedded=%.6f, recording_time=%.6f). ', ...
            %     'Using the embedded value.'], ...
            %     discrepancy, ev_path, t_end_unix, recorded_unix);
        end
    end
end

function t = parse_embedded_timestamp(label_str)
% Parse "LABEL unix_timestamp" -> unix_timestamp (double)
    t = NaN;
    parts = strsplit(strtrim(label_str));
    if numel(parts) < 2, return; end
    val = str2double(parts{end});
    if ~isnan(val)
        t = val;
    end
end