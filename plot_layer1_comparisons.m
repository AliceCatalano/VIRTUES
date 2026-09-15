function plot_layer1_comparisons(cfg, family_label, phase_type, phase_pre, phase_post)
% PLOT_LAYER1_COMPARISONS  Visualizes the results of
% layer1_simple_comparisons.m (run this AFTER that function has saved
% cfg.output_root/layer1_<family_label>_results.mat).
%
% Two figures per family:
%
%   Figure A "paired" -- one panel per outcome, every subject's own
%   phase_pre -> phase_post value as a thin connecting line (individual
%   data, not hidden behind a summary), colored by group, group mean +/-
%   95% CI overlaid in bold. Same visual convention as
%   plot_transfer_paired_estimation.m, but the title now reports the
%   Layer1 SIMPLE within-group paired test (t-test + Wilcoxon
%   signed-rank) for each group directly, instead of an LMM coefficient
%   -- this is the plot behind comparisons #1/#2 (within_N, within_H).
%
%   Figure B "change score" -- one panel per outcome, the per-subject
%   phase_post-phase_pre change plotted as a jittered strip, split by
%   group, group mean +/- 95% CI overlaid, titled with the between_on_delta
%   test (t-test + Wilcoxon rank-sum) -- this is the plot behind
%   comparison #5 (does the SIZE of the change differ by group), the
%   simple-statistics analogue of the LMM's Haptic x Phase interaction.
%
% Saved to cfg.output_root/figures/layer1_<family_label>_paired.png and
% layer1_<family_label>_delta.png.

    COLOR_N = [55  138 221] / 255;
    COLOR_H = [212  83 126] / 255;

    fig_dir = fullfile(cfg.output_root, 'figures');
    if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

    res_path = fullfile(cfg.output_root, sprintf('layer1_%s_results.mat', family_label));
    if ~isfile(res_path)
        error('plot_layer1_comparisons: run layer1_simple_comparisons(cfg, ...) for family "%s" first.', family_label);
    end
    L = load(res_path, 'results'); results = L.results;

    sources = local_load_sources(cfg);
    outcome_list = {
        'scl_mean',          sources.eda
        'scr_freq',          sources.eda
        'scr_mean_amp',      sources.eda
        'pupil_mean',        sources.eye
        'pupil_slope_norm',  sources.eye
        'gaze_dispersion',   sources.eye
        'saccade_rate',      sources.eye
        'tssf_raw',          sources.force_vibration
        'tssv',              sources.force_vibration
        'duration_s',        sources.perf
        'n_collisions',      sources.perf
        };
    outcome_list = outcome_list(~cellfun(@isempty, outcome_list(:,2)), :);
    n_out = size(outcome_list, 1);
    ncols = 4; nrows = ceil(n_out / ncols);

    % ================= Figure A: paired pre/post lines =================
    figA = figure('Name', sprintf('Layer1 paired: %s', family_label), 'Position', [50 50 1750 380*nrows]);
    sgtitle(sprintf('%s (%s vs %s) -- within-group paired comparison (individual subjects + mean \\pm 95%% CI)', ...
        strrep(family_label,'_',' '), phase_pre, phase_post), 'FontWeight', 'bold');

    for oi = 1:n_out
        outcome = outcome_list{oi,1};
        Tsrc    = outcome_list{oi,2};
        subplot(nrows, ncols, oi);
        p_N = local_get_row(results.within_N, outcome);
        p_H = local_get_row(results.within_H, outcome);
        local_plot_paired_panel(Tsrc, outcome, phase_type, phase_pre, phase_post, COLOR_N, COLOR_H, p_N, p_H);
    end
    saveas(figA, fullfile(fig_dir, sprintf('layer1_%s_paired.png', family_label)));
    fprintf('Saved %s\n', fullfile(fig_dir, sprintf('layer1_%s_paired.png', family_label)));

    % ================= Figure B: change-score group comparison =========
    figB = figure('Name', sprintf('Layer1 delta: %s', family_label), 'Position', [50 50 1750 380*nrows]);
    sgtitle(sprintf('%s (%s vs %s) -- does the SIZE of the change differ by group? (%s minus %s)', ...
        strrep(family_label,'_',' '), phase_pre, phase_post, phase_post, phase_pre), 'FontWeight', 'bold');

    for oi = 1:n_out
        outcome = outcome_list{oi,1};
        Tsrc    = outcome_list{oi,2};
        subplot(nrows, ncols, oi);
        p_delta = local_get_row(results.between_on_delta, outcome);
        local_plot_delta_panel(Tsrc, outcome, phase_type, phase_pre, phase_post, COLOR_N, COLOR_H, p_delta);
    end
    saveas(figB, fullfile(fig_dir, sprintf('layer1_%s_delta.png', family_label)));
    fprintf('Saved %s\n', fullfile(fig_dir, sprintf('layer1_%s_delta.png', family_label)));
end

function row = local_get_row(tbl, outcome)
    idx = strcmp(string(tbl.outcome), outcome);
    if ~any(idx), row = []; return; end
    row = tbl(idx, :);
end

function [pre_vals, post_vals, is_h] = local_subject_pre_post(Tsrc, outcome, phase_type, phase_pre, phase_post)
    Tph = Tsrc(strcmp(Tsrc.phase_type, phase_type) & isfinite(Tsrc.(outcome)), :);
    Tph = Tph(ismember(Tph.phase, {phase_pre, phase_post}), :);
    subj_list = unique(Tph.subject);
    pre_vals  = nan(numel(subj_list), 1);
    post_vals = nan(numel(subj_list), 1);
    is_h      = false(numel(subj_list), 1);
    for si = 1:numel(subj_list)
        s = subj_list{si};
        pre_vals(si)  = mean(Tph.(outcome)(strcmp(Tph.subject, s) & strcmp(Tph.phase, phase_pre)),  'omitnan');
        post_vals(si) = mean(Tph.(outcome)(strcmp(Tph.subject, s) & strcmp(Tph.phase, phase_post)), 'omitnan');
        is_h(si) = any(Tph.haptic(strcmp(Tph.subject, s)));
    end
    keep = isfinite(pre_vals) & isfinite(post_vals);
    pre_vals = pre_vals(keep); post_vals = post_vals(keep); is_h = is_h(keep);
end

function local_plot_paired_panel(Tsrc, outcome, phase_type, phase_pre, phase_post, COLOR_N, COLOR_H, row_N, row_H)
    [pre_vals, post_vals, is_h] = local_subject_pre_post(Tsrc, outcome, phase_type, phase_pre, phase_post);
    hold on;
    if isempty(pre_vals)
        title(sprintf('%s\n(no data)', strrep(outcome,'_',' ')), 'FontSize', 9, 'Interpreter', 'none');
        return;
    end
    jitter_x = @(base, n) base + (rand(n,1) - 0.5) * 0.12;
    for grp = [false true]
        idx = find(is_h == grp);
        if isempty(idx), continue; end
        col = local_ternary(grp, COLOR_H, COLOR_N);
        x1 = jitter_x(1, numel(idx)); x2 = x1 + 1;
        for k = 1:numel(idx)
            plot([x1(k) x2(k)], [pre_vals(idx(k)), post_vals(idx(k))], ...
                '-', 'Color', [col, 0.25], 'LineWidth', 0.7, 'HandleVisibility', 'off');
        end
        scatter(x1, pre_vals(idx),  14, col, 'filled', 'MarkerFaceAlpha', 0.35, 'HandleVisibility', 'off');
        scatter(x2, post_vals(idx), 14, col, 'filled', 'MarkerFaceAlpha', 0.35, 'HandleVisibility', 'off');
        mu   = [mean(pre_vals(idx)), mean(post_vals(idx))];
        sem  = [std(pre_vals(idx)), std(post_vals(idx))] / sqrt(numel(idx));
        ci95 = sem * 1.96;
        lbl  = local_ternary(grp, 'HF', 'NHF');
        errorbar([1 2] + local_ternary(grp, 0.10, -0.10), mu, ci95, '-o', ...
            'Color', col, 'LineWidth', 2.2, 'MarkerFaceColor', col, 'MarkerSize', 6, 'DisplayName', lbl);
    end
    xlim([0.5 2.5]); xticks([1 2]); xticklabels({phase_pre, phase_post});
    ttl = sprintf('%s\nN: paired p=%s (Wilc.=%s)  |  H: paired p=%s (Wilc.=%s)', ...
        strrep(outcome,'_',' '), local_fmt_p2(row_N,'p'), local_fmt_p2(row_N,'p_wilcoxon'), ...
        local_fmt_p2(row_H,'p'), local_fmt_p2(row_H,'p_wilcoxon'));
    title(ttl, 'FontSize', 7.5, 'Interpreter', 'none');
    grid on; set(gca, 'FontSize', 8);
end

function local_plot_delta_panel(Tsrc, outcome, phase_type, phase_pre, phase_post, COLOR_N, COLOR_H, row_delta)
    [pre_vals, post_vals, is_h] = local_subject_pre_post(Tsrc, outcome, phase_type, phase_pre, phase_post);
    hold on;
    if isempty(pre_vals)
        title(sprintf('%s\n(no data)', strrep(outcome,'_',' ')), 'FontSize', 9, 'Interpreter', 'none');
        return;
    end
    delta = post_vals - pre_vals;
    jitter_x = @(base, n) base + (rand(n,1) - 0.5) * 0.25;
    for grp = [false true]
        idx = find(is_h == grp);
        if isempty(idx), continue; end
        col = local_ternary(grp, COLOR_H, COLOR_N);
        xpos = local_ternary(grp, 2, 1);
        xj = jitter_x(xpos, numel(idx));
        scatter(xj, delta(idx), 18, col, 'filled', 'MarkerFaceAlpha', 0.45, 'HandleVisibility', 'off');
        mu   = mean(delta(idx));
        sem  = std(delta(idx)) / sqrt(numel(idx));
        ci95 = sem * 1.96;
        lbl  = local_ternary(grp, 'HF', 'NHF');
        errorbar(xpos, mu, ci95, 'o', 'Color', col, 'LineWidth', 2.2, ...
            'MarkerFaceColor', col, 'MarkerSize', 8, 'DisplayName', lbl);
    end
    yline(0, '--', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off');
    xlim([0.5 2.5]); xticks([1 2]); xticklabels({'NHF','HF'});
    ttl = sprintf('%s\n\\Delta between-group p=%s (Wilc.=%s)', ...
        strrep(outcome,'_',' '), local_fmt_p2(row_delta,'p'), local_fmt_p2(row_delta,'p_wilcoxon'));
    title(ttl, 'FontSize', 8, 'Interpreter', 'tex');
    ylabel(sprintf('%s -- %s', phase_post, phase_pre), 'FontSize', 7.5);
    grid on; set(gca, 'FontSize', 8);
end

function s = local_fmt_p2(row, field)
    if isempty(row) || ~isfinite(row.(field)(1))
        s = 'n/a';
    else
        s = sprintf('%.3f', row.(field)(1));
    end
end

function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end

function sources = local_load_sources(cfg)
    sources = struct('eda', [], 'eye', [], 'perf', [], 'force_vibration', []);
    files = {'eda', 'eda_features.mat'; 'eye', 'eye_features.mat'; ...
        'perf', 'perf_features.mat'; 'force_vibration', 'force_vibration_features.mat'};
    for i = 1:size(files, 1)
        path = fullfile(cfg.output_root, files{i, 2});
        if isfile(path)
            L = load(path, 'T');
            sources.(files{i, 1}) = L.T;
        end
    end
end
