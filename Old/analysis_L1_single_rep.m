clear;
cfg = config();
if ~exist(cfg.output_root, 'dir'), mkdir(cfg.output_root); end

plot_dir = fullfile(cfg.output_root, 'L1_plots');
if ~exist(plot_dir, 'dir'), mkdir(plot_dir); end

feature_list = {'scl_mean','scl_slope','scr_n_peaks','scr_mean_amp','scr_max_amp','scr_rate','scr_auc','gsr_mean','gsr_std','gsr_rms'};

for si = 1:numel(cfg.all_subjects)
    subj     = cfg.all_subjects{si};
    subj_dir = fullfile(cfg.data_root, subj);
    fprintf('\n=== %s ===\n', subj);

    try
        subj_max = gsr_find_subject_max(subj, cfg); %should output also the Trial start and end.
    catch ME
        fprintf('  SKIP (no valid data): %s\n', ME.message);
        continue;
    end

    results = struct();
    results.subject  = subj;
    results.group    = subj(end);
    results.features = struct();

    % --- Baseline phases ---
    for ph = cfg.baseline_phases
        ph_key = ph{1};
        results.features.(ph_key) = struct();
        for li = 1:numel(cfg.level_names)
            lv_key   = sprintf('Level%d', li);
            lv_dir   = fullfile(subj_dir, ph_key, cfg.level_names{li});
            gsr_path = fullfile(lv_dir, 'gsr.mat');
            ev_path  = fullfile(lv_dir, 'events.mat');
            if ~isfile(gsr_path) || skip_folder(lv_dir), continue; end
            try
                [t_start, t_end] = safe_trial_window(ev_path);
                proc = gsr_preprocess(gsr_path, cfg, t_start, t_end); 
                feat = gsr_extract_features(proc, cfg);
                feat = gsr_normalize_features(feat, subj_max, cfg);
                results.features.(ph_key).(lv_key) = feat;
                fprintf('  %s / %s done\n', ph_key, lv_key);
            catch ME
                fprintf('  SKIP %s/%s: %s\n', ph_key, lv_key, ME.message);
            end
        end
    end

    % --- Test phases ---
    for ph = cfg.test_phases
        ph_key   = ph{1};
        ph_dir   = fullfile(subj_dir, ph_key);
        gsr_path = fullfile(ph_dir, 'gsr.mat');
        ev_path  = fullfile(ph_dir, 'events.mat');
        if ~isfile(gsr_path) || skip_folder(ph_dir), continue; end
        try
            [t_start, t_end] = safe_trial_window(ev_path);
            proc = gsr_preprocess(gsr_path, cfg, t_start, t_end);
            feat = gsr_extract_features(proc, cfg);
            feat = gsr_normalize_features(feat, subj_max, cfg);
            results.features.(ph_key).full_session = feat;
            fprintf('  %s done\n', ph_key);
        catch ME
            fprintf('  SKIP %s: %s\n', ph_key, ME.message);
        end
    end

    % --- Training levels ---
    for li = 1:numel(cfg.training_levels)
        lv_key = strrep(cfg.training_levels{li}, '_', '');
        lv_dir = fullfile(subj_dir, cfg.training_levels{li});
        if ~isfolder(lv_dir) || skip_folder(lv_dir), continue; end
        results.features.(lv_key) = struct();
        for r = 1:cfg.n_training_reps
            rep_key  = sprintf('rep%02d', r);
            rep_dir  = fullfile(lv_dir, sprintf('rep_%02d', r));
            gsr_path = fullfile(rep_dir, 'gsr.mat');
            if ~isfile(gsr_path) || skip_folder(rep_dir), continue; end
            try
                proc = gsr_preprocess(gsr_path, cfg, [], []);
                feat = gsr_extract_features(proc, cfg);
                feat = gsr_normalize_features(feat, subj_max, cfg);
                results.features.(lv_key).(rep_key) = feat;
            catch ME
                fprintf('  SKIP %s/%s: %s\n', lv_key, rep_key, ME.message);
            end
        end
        fprintf('  %s done\n', lv_key);
    end

    %% --- Resting state ---
    snum = extract_subject_num(subj);
    results.features.resting = struct();
    for r = 1:2
        rest_key = sprintf('r%d', r);
        rest_dir = fullfile(subj_dir, 'resting_state', sprintf('%s_r%d', strrep(subj, 'subject_', ''), r));
        gsr_path = fullfile(rest_dir, 'gsr.mat');
        ev_path  = fullfile(rest_dir, 'events.mat');
        if ~isfile(gsr_path) || ~isfile(ev_path) || skip_folder(rest_dir), continue; end
        try
            [~, t_end] = safe_trial_window(ev_path);
            t_start    = t_end - cfg.resting_duration;
            proc = gsr_preprocess(gsr_path, cfg, t_start, t_end);
            feat = gsr_extract_features(proc, cfg);
            feat = gsr_normalize_features(feat, subj_max, cfg);
            results.features.resting.(rest_key) = feat;
            fprintf('  resting %s done\n', rest_key);
        catch ME
            fprintf('  SKIP resting %s: %s\n', rest_key, ME.message);
        end
    end
%
    results.subj_max = subj_max;

    out_path = fullfile(cfg.output_root, sprintf('%s_L1_features.mat', subj));
    %save(out_path, 'results');
    fprintf('  Saved → %s\n', out_path);
%%
    plot_subject_overview(results, feature_list, plot_dir, cfg);
end

function plot_subject_overview(results, feature_list, plot_dir, cfg)

subj  = results.subject;
feats = results.features;
n_feat = numel(feature_list);

% --- Plot 1: Baseline1 vs Baseline2 across levels ---
b1_ok = isfield(feats, 'Baseline1');
b2_ok = isfield(feats, 'Baseline2');
if b1_ok || b2_ok
    figure('Visible','on','Position',[0 0 1400 900]);
    for f = 1:n_feat
        fn = feature_list{f};
        b1_vals = NaN(1, numel(cfg.level_names));
        b2_vals = NaN(1, numel(cfg.level_names));
        for li = 1:numel(cfg.level_names)
            lv_key = sprintf('Level%d', li);
            if b1_ok && isfield(feats.Baseline1, lv_key) && isfield(feats.Baseline1.(lv_key), fn)
                b1_vals(li) = feats.Baseline1.(lv_key).(fn);
            end
            if b2_ok && isfield(feats.Baseline2, lv_key) && isfield(feats.Baseline2.(lv_key), fn)
                b2_vals(li) = feats.Baseline2.(lv_key).(fn);
            end
        end
        subplot(2, 5, f);
        hold on;
        plot(1:5, b1_vals, 'o-', 'Color', [0.2 0.5 0.8], 'LineWidth', 1.5,  'MarkerFaceColor', [0.2 0.5 0.8], 'DisplayName', 'Baseline1');
        plot(1:5, b2_vals, 's-', 'Color', [0.9 0.4 0.2], 'LineWidth', 1.5,  'MarkerFaceColor', [0.9 0.4 0.2], 'DisplayName', 'Baseline2');
        set(gca, 'XTick', 1:5, 'XTickLabel', {'L1','L2','L3','L4','L5'});
        xlabel('Level'); ylabel(strrep(fn,'_',' '));
        title(strrep(fn,'_',' '), 'FontSize', 8);
        legend('Location','best','FontSize',6);
        grid on; hold off;
    end
    sgtitle(sprintf('%s — Baseline1 vs Baseline2', subj), 'Interpreter','none');
    % saveas(fig, fullfile(plot_dir, sprintf('%s_baselines.png', subj)));
    % close(fig);
end

% --- Plot 2: Training learning curves per level ---
for li = 1:numel(cfg.training_levels)
    lv_key = strrep(cfg.training_levels{li}, '_', '');
    if ~isfield(feats, lv_key), continue; end
    figure('Visible','on','Position',[0 0 1400 900]);
    for f = 1:n_feat
        fn = feature_list{f};
        rep_vals = NaN(1, cfg.n_training_reps);
        for r = 1:cfg.n_training_reps
            rep_key = sprintf('rep%02d', r);
            if isfield(feats.(lv_key), rep_key) && isfield(feats.(lv_key).(rep_key), fn)
                rep_vals(r) = feats.(lv_key).(rep_key).(fn);
            end
        end
        subplot(2, 5, f);
        hold on;
        valid = ~isnan(rep_vals);
        plot(find(valid), rep_vals(valid), 'o-', 'Color', [0.2 0.6 0.3], ...
             'LineWidth', 1.5, 'MarkerFaceColor', [0.2 0.6 0.3]);
        if sum(valid) >= 2
            p_fit = polyfit(find(valid), rep_vals(valid), 1);
            plot(find(valid), polyval(p_fit, find(valid)), '--k', 'LineWidth', 1);
        end
        set(gca, 'XTick', 1:cfg.n_training_reps);
        xlabel('Rep'); ylabel(strrep(fn,'_',' '));
        title(strrep(fn,'_',' '), 'FontSize', 8);
        grid on; hold off;
    end
    sgtitle(sprintf('%s — Training %s (reps 1→10)', subj, cfg.training_levels{li}), ...
            'Interpreter','none');
    % saveas(fig, fullfile(plot_dir, sprintf('%s_%s_training.png', subj, lv_key)));
    % close(fig);
end

% --- Plot 3: Resting state pre vs post ---
if isfield(feats, 'resting')
    has_r1 = isfield(feats.resting, 'r1');
    has_r2 = isfield(feats.resting, 'r2');
    if has_r1 || has_r2
        figure('Visible','on','Position',[0 0 1400 500]);
        for f = 1:n_feat
            fn = feature_list{f};
            vals = NaN(1,2);
            if has_r1 && isfield(feats.resting.r1, fn), vals(1) = feats.resting.r1.(fn); end
            if has_r2 && isfield(feats.resting.r2, fn), vals(2) = feats.resting.r2.(fn); end
            subplot(2, 5, f);
            bar(vals, 'FaceColor', [0.5 0.3 0.7]);
            set(gca, 'XTick', [1 2], 'XTickLabel', {'Pre','Post'});
            ylabel(strrep(fn,'_',' '));
            title(strrep(fn,'_',' '), 'FontSize', 8);
            grid on;
        end
        sgtitle(sprintf('%s — Resting state pre vs post', subj), 'Interpreter','none');
        % saveas(fig, fullfile(plot_dir, sprintf('%s_resting.png', subj)));
        % close(fig);
    end
end

% --- Plot 4: Raw + tonic + phasic signal for one representative segment ---
% Re-process one file for visualization (Baseline1/Level1 if available)
b1_l1_path = fullfile(cfg.data_root, subj, 'Baseline1', 'Level1', 'gsr.mat');
if isfile(b1_l1_path)
    try
        proc = gsr_preprocess(b1_l1_path, cfg, [], []);
        figure('Visible','on','Position',[0 0 1200 700]);
        t    = proc.time - proc.time(1);
        subplot(3,1,1);
        plot(t, proc.gsr_us, 'Color', [0.3 0.3 0.3], 'LineWidth', 1);
        ylabel('GSR (µS)'); title(sprintf('%s — B1/L1 raw signal', subj), 'Interpreter','none');
        grid on;
        subplot(3,1,2);
        plot(t, proc.tonic, 'Color', [0.2 0.5 0.8], 'LineWidth', 1.5);
        ylabel('Tonic SCL (µS)'); title('Tonic component (cvxEDA)');
        grid on;
        subplot(3,1,3);
        plot(t, proc.phasic, 'Color', [0.9 0.4 0.2], 'LineWidth', 1);
        ylabel('Phasic SCR (µS)'); xlabel('Time (s)');
        title('Phasic component (cvxEDA)');
        grid on;
        sgtitle(sprintf('%s — cvxEDA decomposition', subj), 'Interpreter','none');
        % saveas(fig, fullfile(plot_dir, sprintf('%s_cvxEDA_example.png', subj)));
        % close(fig);
    catch
    end
end
end