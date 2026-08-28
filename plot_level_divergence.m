function plot_level_divergence(cfg)
% PLOT_LEVEL_DIVERGENCE  The dissociation figure for Results 3.2: for each
% outcome, the within-group simple effect of Level (vs. Level 1) for NHF
% and HF plotted side by side with 95% CIs -- reads directly off
% results{i}.simple_effects (the exact contrast-derived values from
% gsr_training_lmm.m / perf_training_lmm.m, not an approximation). Physio
% panels (top row) show the group divergence that grows with difficulty;
% performance panels (bottom row) show no such divergence -- the point of
% this figure is the visual contrast between the two rows.
%
% Requires cfg.output_root/training_lmm_results.mat and
% performance_lmm_results.mat (run run_training_lmms.m / gsr_lmm.m and
% run_performance_lmms.m first if not present).

    COLOR_N = [55  138 221] / 255;
    COLOR_H = [212  83 126] / 255;

    fig_dir = fullfile(cfg.output_root, 'figures');
    if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

    eda_res_file  = fullfile(cfg.output_root, 'training_lmm_results.mat');
    perf_res_file = fullfile(cfg.output_root, 'performance_lmm_results.mat');
    if ~isfile(eda_res_file) || ~isfile(perf_res_file)
        error('plot_level_divergence: run gsr_lmm.m (training_lmm_results.mat) and run_performance_lmms.m first.');
    end
    Reda  = load(eda_res_file,  'results', 'outcomes');
    Rperf = load(perf_res_file, 'results', 'outcomes');

    panels = {
        Reda.results,  Reda.outcomes,  {'scl_mean','scr_freq','scr_mean_amp','collision_scr_amp_mean'}, ...
        {'Mean SCL','SCR frequency','Mean SCR amp.','Event-locked SCR amp.'}
        Rperf.results, Rperf.outcomes, {'duration_s','n_collisions'}, {'Completion time','Collisions (log-rate)'}
        };

    fig = figure('Name', 'Group x Level divergence', 'Position', [50 50 1500 700]);
    sgtitle('Level effect (vs. Level 1), NHF vs HF -- physiology (top) vs performance (bottom)', 'FontWeight', 'bold');

    plot_idx = 0;
    for row = 1:2
        results_all = panels{row, 1};
        outcome_names_all = panels{row, 2};
        outcome_keys  = panels{row, 3};
        outcome_labels = panels{row, 4};

        for k = 1:numel(outcome_keys)
            oi = find(strcmp(outcome_names_all, outcome_keys{k}), 1);
            plot_idx = plot_idx + 1;
            subplot(2, 4, plot_idx); hold on;
            if isempty(oi)
                title(sprintf('%s (not found)', outcome_labels{k}));
                continue;
            end

            se = results_all{oi}.simple_effects;
            is_level = ~cellfun('isempty', regexp(se.effect, '^level \d+ vs level 1$', 'once'));
            se = se(is_level, :);
            lvl_num = cellfun(@(s) sscanf(s, 'level %d vs level 1'), se.effect);

            for grp = {'N','H'}
                g    = grp{1};
                mask = strcmp(se.group, g);
                x    = lvl_num(mask);
                [x, ord] = sort(x);
                y    = se.beta(mask); y = y(ord);
                lo   = se.lower(mask); lo = lo(ord);
                hi   = se.upper(mask); hi = hi(ord);
                col  = local_ternary(strcmp(g,'H'), COLOR_H, COLOR_N);
                lbl  = local_ternary(strcmp(g,'H'), 'HF', 'NHF');
                errorbar(x, y, y-lo, hi-y, '-o', 'Color', col, 'LineWidth', 1.6, ...
                    'MarkerFaceColor', col, 'DisplayName', lbl);
            end
            yline(0, ':k', 'HandleVisibility', 'off');
            xlabel('Level (vs. 1)'); ylabel('\beta (within-group)');
            xlim([1.5 5.5]); xticks(2:5);
            title(outcome_labels{k}, 'FontSize', 10);
            if plot_idx == 1 || plot_idx == 5
                legend('Location', 'best', 'FontSize', 8);
            end
            grid on;
        end
    end

    saveas(fig, fullfile(fig_dir, 'level_divergence.png'));
    fprintf('Saved %s\n', fullfile(fig_dir, 'level_divergence.png'));
end

function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
