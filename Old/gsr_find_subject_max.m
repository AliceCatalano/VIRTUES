function subj_max = gsr_find_subject_max(subject_id, cfg)
    
    subj_dir  = fullfile(cfg.data_root, subject_id);
    amp_feats = cfg.amplitude_features;
    n_feat    = numel(amp_feats);
    all_vals  = NaN(0, n_feat);
    
    % --- Baseline phases ---
    for ph = cfg.baseline_phases
        for li = 1:numel(cfg.level_names)
            lv_dir   = fullfile(subj_dir, ph{1}, cfg.level_names{li});
            gsr_path = fullfile(lv_dir, 'gsr.mat');
            all_vals = append_feat(all_vals, gsr_path, cfg, amp_feats, n_feat, [], []);
        end
    end
    
    % --- Test phases ---
    for ph = cfg.test_phases
        ph_dir   = fullfile(subj_dir, ph{1});
        gsr_path = fullfile(ph_dir, 'gsr.mat');
        ev_path  = fullfile(ph_dir, 'events.mat');
        [t_start, t_end] = safe_trial_window(ev_path);
        all_vals = append_feat(all_vals, gsr_path, cfg, amp_feats, n_feat, t_start, t_end);
    end
    
    % --- Training levels ---
    for li = 1:numel(cfg.training_levels)
        lv_dir = fullfile(subj_dir, cfg.training_levels{li});
        if ~isfolder(lv_dir) || skip_folder(lv_dir), continue; end
        for r = 1:cfg.n_training_reps
            rep_dir  = fullfile(lv_dir, sprintf('rep_%02d', r));
            gsr_path = fullfile(rep_dir, 'gsr.mat');
            all_vals = append_feat(all_vals, gsr_path, cfg, amp_feats, n_feat, [], []);
        end
    end
    
    % --- Resting state ---
    snum = extract_subject_num(subject_id);
    for r = 1:2
        rest_dir = fullfile(subj_dir, 'resting_state', sprintf('s%s_r%d', snum, r));
        gsr_path = fullfile(rest_dir, 'gsr.mat');
        ev_path  = fullfile(rest_dir, 'events.mat');
        if ~isfile(ev_path), continue; end
        [~, t_end] = safe_trial_window(ev_path);
        t_start    = t_end - cfg.resting_duration;
        all_vals   = append_feat(all_vals, gsr_path, cfg, amp_feats, n_feat, t_start, t_end);
    end
    
    if isempty(all_vals) || all(isnan(all_vals(:)))
        error('gsr_find_subject_max: no valid data found for %s', subject_id);
    end
    
    subj_max = struct();
    for k = 1:n_feat
        col = all_vals(:, k);
        col = col(isfinite(col));
        if isempty(col)
            subj_max.(amp_feats{k}) = 1;
        else
            subj_max.(amp_feats{k}) = max(col);
        end
    end
    end
    
    function all_vals = append_feat(all_vals, gsr_path, cfg, amp_feats, n_feat, t_start, t_end)
    if ~isfile(gsr_path) || skip_folder(gsr_path), return; end
    try
        proc = gsr_preprocess(gsr_path, cfg, t_start, t_end);
        f    = gsr_extract_features(proc, cfg);
        row  = NaN(1, n_feat);
        for k = 1:n_feat
            v = f.(amp_feats{k});
            if isscalar(v) && isfinite(v)
                row(k) = v;
            end
        end
        all_vals = [all_vals; row];
    catch ME
        fprintf('    append_feat skipped %s: %s\n', gsr_path, ME.message);
    end
end
    
function [t_start, t_end] = safe_trial_window(ev_path)
        t_start = [];
        t_end   = [];
        if ~isfile(ev_path), return; end
        try
            [t_start, t_end] = get_trial_window(ev_path);
        catch
        end
end