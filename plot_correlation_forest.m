function plot_correlation_forest(cfg)
% PLOT_CORRELATION_FOREST  Forest plot of the within-subject and
% between-subject associations from run_correlation_analyses.m (Results
% 3.6/3.7): one row per predictor-outcome pair, point = beta, whiskers =
% beta +/- 1.96*SE (Wald CI, matching the p-values fitlme itself reports),
% filled marker where p_FDR < .05 within that family, hollow otherwise.
% Within-subject and between-subject estimates are plotted side by side
% (not pooled) since person-mean centering deliberately keeps them as two
% separate questions (Curran & Bauer, 2011) -- see
% multilevel_correlation_lmm.m's header.
%
% One panel per family exactly as defined in run_correlation_analyses.m
% (each family's own FDR correction is what determines the fill/hollow
% marker in that panel -- do not compare fill status across panels).
%
% Requires cfg.output_root/correlation_results.mat (run
% run_correlation_analyses.m first).

    COLOR_WITHIN  = [55  138 221] / 255;
    COLOR_BETWEEN = [212  83 126] / 255;

    fig_dir = fullfile(cfg.output_root, 'figures');
    if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

    res_file = fullfile(cfg.output_root, 'correlation_results.mat');
    if ~isfile(res_file)
        error('plot_correlation_forest: run run_correlation_analyses.m first.');
    end
    loaded = load(res_file, 'all_results');
    all_results = loaded.all_results;

    fam_names = fieldnames(all_results);
    fig = figure('Name', 'Within/between-subject correlations', 'Position', [50 50 1700 950]);
    sgtitle('Within-subject vs. between-subject associations with performance (standardized t = \beta/SE \pm 1.96)', 'FontWeight', 'bold');
    legend_handles = gobjects(1,2);

    for f = 1:numel(fam_names)
        fam = all_results.(fam_names{f});
        n_pairs = numel(fam.results);

        labels = cell(n_pairs, 1);
        w_t = nan(n_pairs,1); w_sig = false(n_pairs,1);
        b_t = nan(n_pairs,1); b_sig = false(n_pairs,1);

        for i = 1:n_pairs
            r = fam.results{i};
            labels{i} = sprintf('%s -> %s', strrep(r.predictor,'_',' '), strrep(r.outcome,'_',' '));
            w_t(i)   = r.within_beta  / r.within_se;
            b_t(i)   = r.between_beta / r.between_se;
            w_sig(i) = fam.within_p_fdr(i)  < 0.05;
            b_sig(i) = fam.between_p_fdr(i) < 0.05;
        end

        subplot(1, numel(fam_names), f); hold on;
        y_within  = (1:n_pairs) + 0.15;
        y_between = (1:n_pairs) - 0.15;

        for i = 1:n_pairs
            plot([w_t(i)-1.96 w_t(i)+1.96], [y_within(i) y_within(i)], '-','Color', COLOR_WITHIN, 'LineWidth', 1.3, 'HandleVisibility', 'off');
            plot([b_t(i)-1.96 b_t(i)+1.96], [y_between(i) y_between(i)], '-','Color', COLOR_BETWEEN, 'LineWidth', 1.3, 'HandleVisibility', 'off');
        end
        local_scatter_sig(w_t, y_within,  COLOR_WITHIN,  w_sig);
        local_scatter_sig(b_t, y_between, COLOR_BETWEEN, b_sig);

        xline(0, ':k', 'HandleVisibility', 'off');
        xline(1.96, '--', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off');
        xline(-1.96, '--', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off');
        yticks(1:n_pairs); yticklabels(labels); set(gca, 'TickLabelInterpreter', 'none', 'FontSize', 8);
        ylim([0.5, n_pairs+0.5]); set(gca, 'YDir', 'reverse');
        xlabel('t = \beta / SE (dashed lines: uncorrected p=.05)');
        title(strrep(fam_names{f}, '_', ' '), 'FontSize', 10, 'Interpreter', 'none');
        grid on;

        if f == 1
            legend_handles(1) = plot(nan, nan, 'o', 'Color', COLOR_WITHIN,  'MarkerFaceColor', COLOR_WITHIN);
            legend_handles(2) = plot(nan, nan, 'o', 'Color', COLOR_BETWEEN, 'MarkerFaceColor', COLOR_BETWEEN);
        end
    end
    subplot(1, numel(fam_names), 1);
    legend(legend_handles, {'Within-subject (filled = FDR<.05)', 'Between-subject (filled = FDR<.05)'},'Location', 'southoutside', 'FontSize', 7);
    saveas(fig, fullfile(fig_dir, 'correlation_forest.png'));
    fprintf('Saved %s\n', fullfile(fig_dir, 'correlation_forest.png'));
end

function local_scatter_sig(t, y, col, sig)
    if any(sig)
        scatter(t(sig), y(sig), 45, col, 'filled', 'HandleVisibility', 'off');
    end
    if any(~sig)
        scatter(t(~sig), y(~sig), 45, col, 'HandleVisibility', 'off');
    end
end