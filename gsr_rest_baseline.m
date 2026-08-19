function rest_ref = gsr_rest_baseline(subj, cfg)
% Load and preprocess resting state R1, return mean tonic and mean GSR.
% This becomes the subject-level baseline for all subsequent sessions.
%
% Window logic (per experiment protocol):
%   1. safe_trial_window routes resting-state events files to
%      find_resting_end internally and returns the RESTING_END time
%      (t_start comes back NaN and is intentionally unused — see below).
%   2. t_start = t_end - cfg.resting_duration  (default 180 s)
%   3. The actual baseline statistics are computed over a short
%      sub-window [t_start + cfg.baseline_offset_start,
%                   t_start + cfg.baseline_offset_end]
%      rather than the full 3 minutes.
%
% cfg fields used (with defaults if absent):
%   cfg.resting_duration      (180)  total resting block length, s
%   cfg.baseline_offset_start (5)    sub-window start, s after t_start
%   cfg.baseline_offset_end   (15)   sub-window end,   s after t_start

    if ~isfield(cfg, 'resting_duration'),      cfg.resting_duration = 180; end
    if ~isfield(cfg, 'baseline_offset_start'),  cfg.baseline_offset_start = 5;  end
    if ~isfield(cfg, 'baseline_offset_end'),    cfg.baseline_offset_end   = 15; end

    snum_full = strrep(subj, 'subject_', '');   % e.g. 's02N'
    rest_dir  = fullfile(cfg.data_root, subj, 'resting_state', ...
                         sprintf('%s_r1', snum_full));
    gsr_path  = fullfile(rest_dir, 'gsr.mat');
    ev_path   = fullfile(rest_dir, 'events.mat');

    if ~isfile(gsr_path) || ~isfile(ev_path)
        warning('compute_rest_reference: R1 not found for %s — using empty reference', subj);
        rest_ref = [];
        return;
    end

    % safe_trial_window detects this is a resting-state events file
    % (labels contain 'RESTING') and internally delegates to
    % find_resting_end, which never reads RESTING_START (unreliable on
    % this Shimmer3+ setup) and parses the authoritative embedded
    % timestamp for RESTING_END. The returned t_start is NaN by design —
    % the true start is always derived from resting_duration below.
    [~, t_end] = safe_trial_window(ev_path);
    if isnan(t_end)
        warning('compute_rest_reference: no RESTING_END event found for %s — using empty reference', subj);
        rest_ref = [];
        return;
    end
    block_start = t_end - cfg.resting_duration;

    % Sub-window actually used for baseline statistics
    t_start   = block_start + cfg.baseline_offset_start;
    t_win_end = block_start + cfg.baseline_offset_end;

    % Preprocess just that sub-window
    proc = gsr_preprocess(gsr_path, cfg, t_start, t_win_end);

    % Store mean and std of each signal component
    rest_ref.tonic_mean  = mean(proc.tonic);
    rest_ref.tonic_std   = std(proc.tonic);
    rest_ref.phasic_mean = mean(proc.phasic);
    rest_ref.phasic_std  = std(proc.phasic);
    rest_ref.gsr_mean    = mean(proc.gsr_us);
    rest_ref.gsr_std     = std(proc.gsr_us);
    rest_ref.source      = gsr_path;
    rest_ref.window      = [t_start, t_win_end];   % for auditing

    fprintf('  R1 reference [%.1f-%.1fs]: tonic_mean=%.4f  gsr_mean=%.4f uS\n', ...
        t_start, t_win_end, rest_ref.tonic_mean, rest_ref.gsr_mean);
end