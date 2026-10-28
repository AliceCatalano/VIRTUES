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

            n_sig = 0;

            for grp = {'N','H'}
                g    = grp{1};
                mask = strcmp(se.group, g);
                x    = lvl_num(mask);
                [x, ord] = sort(x);
                y    = se.beta(mask); y = y(ord);
                lo   = se.lower(mask); lo = lo(ord);
                hi   = se.upper(mask); hi = hi(ord);
                pv   = se.p(mask);     pv = pv(ord);
                col  = local_ternary(strcmp(g,'H'), COLOR_H, COLOR_N);
                lbl  = local_ternary(strcmp(g,'H'), 'HF', 'NHF');
                errorbar(x, y, y-lo, hi-y, '-', 'Color', col, 'LineWidth', 1.6, 'CapSize', 4, 'DisplayName', lbl);
                is_sig = pv < 0.05;
                n_sig = n_sig + sum(is_sig);
                if any(is_sig)
                    scatter(x(is_sig), y(is_sig), 55, col, 'filled', 'HandleVisibility', 'off');
                end
                if any(~is_sig)
                    scatter(x(~is_sig), y(~is_sig), 55, col, 'HandleVisibility', 'off');
                end
            end
            yline(0, ':k', 'HandleVisibility', 'off');
            xlabel('Level (vs. 1)'); ylabel('\beta (within-group)');
            xlim([1.5 5.5]); xticks(2:5);
            title(sprintf('%s\n%d/8 level\\times group contrasts p<.05 (filled)', outcome_labels{k}, n_sig), 'FontSize', 9, 'Interpreter', 'tex');
            if plot_idx == 1 || plot_idx == 5
                legend('Location', 'best', 'FontSize', 8);
            end
            grid on;
        end
    end

    saveas(fig, fullfile(fig_dir, 'level_divergence.png'));
    fprintf('Saved %s\n', fullfile(fig_dir, 'level_divergence.png'));

%% Add to plot_level_divergence_fixed.m — eye tracking version

    eye_res_file = fullfile(cfg.output_root, 'eye_lmm_results.mat');
    if isfile(eye_res_file)
        Reye = load(eye_res_file, 'results', 'outcomes');
        
        fprintf('\nEye outcomes in eye_lmm_results.mat:\n');
        for i = 1:numel(Reye.outcomes)
            fprintf('  %d: %s\n', i, Reye.outcomes{i});
        end
        
        eye_panels = {
            'gaze_entropy',    'Gaze entropy (bits)'
            'fixation_rate',   'Fixation rate (fix/min)'
            'pupil_mean_norm', 'Normalised pupil'
            'collision_pupil_response_mean', 'Collision pupil'
        };
        
        fig2 = figure('Name','Eye Level Divergence','Position',[50 50 1500 400]);
        sgtitle('Eye-tracking: Level effect (vs. Level 1), NHF vs HF',...
            'FontWeight','bold','FontSize',11);
        
        for k = 1:size(eye_panels,1)
            outcome_key   = eye_panels{k,1};
            outcome_label = eye_panels{k,2};
            subplot(1,4,k); hold on;
            
            oi = find(strcmp(Reye.outcomes, outcome_key), 1);
            if isempty(oi)
                title(sprintf('%s\n(not found)',strrep(outcome_key,'_',' ')),'FontSize',9);
                continue;
            end
            
            se = Reye.results{oi}.simple_effects;
            is_level = ~cellfun('isempty', regexp(se.effect,'^level \d+ vs level 1$','once'));
            se = se(is_level,:);
            if isempty(se), continue; end
            
            lvl_num = cellfun(@(s) sscanf(s,'level %d vs level 1'), se.effect);
            n_sig = 0;
            for grp = {'N','H'}
                g = grp{1}; mask = strcmp(se.group,g);
                if ~any(mask), continue; end
                x = lvl_num(mask); [x,ord]=sort(x);
                y = se.beta(mask); y=y(ord);
                lo=se.lower(mask); lo=lo(ord);
                hi=se.upper(mask); hi=hi(ord);
                pv=se.p(mask);     pv=pv(ord);
                col=local_ternary(strcmp(g,'H'),COLOR_H,COLOR_N);
                errorbar(x,y,y-lo,hi-y,'-','Color',col,'LineWidth',1.6,...
                    'CapSize',4,'DisplayName',local_ternary(strcmp(g,'H'),'HF','NHF'));
                is_sig=pv<0.05; n_sig=n_sig+sum(is_sig);
                if any(is_sig),  scatter(x(is_sig), y(is_sig), 55,col,'filled','HandleVisibility','off'); end
                if any(~is_sig), scatter(x(~is_sig),y(~is_sig),55,col,'HandleVisibility','off'); end
            end
            
            yline(0,':k','HandleVisibility','off');
            
            xlabel('Level (vs. 1)','FontSize',9); ylabel('\beta','FontSize',9);
            xlim([1.5 5.5]); xticks(2:5);
            title(sprintf('%s\n%d/8 sig.',outcome_label,n_sig),'FontSize',9,'Interpreter','tex');
            if k==1, legend('Location','best','FontSize',8); end
            grid on;
        end
        
        saveas(fig2, fullfile(fig_dir,'level_divergence_eye_fixed.png'));
        fprintf('Saved level_divergence_eye_fixed.png\n');
    end
    function out = local_ternary(cond, a, b)
        if cond, out = a; else, out = b; end
    end
end