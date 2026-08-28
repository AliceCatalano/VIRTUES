function plot_learning_curves(cfg)
% PLOT_LEARNING_CURVES  Raw (model-free) group-mean trajectories across the
% 10 training repetitions, for the 4 physiological and 2 performance
% outcomes -- supports Results 3.1 ("both groups improve, no differential
% rate"). One point per repetition per group: for each subject, the 5
% level-rows at that repetition are averaged first (so one value per
% subject per repetition), then averaged across subjects within each
% group, with SEM error bars.
%
% NOTE: these are descriptive raw means, NOT the model-adjusted marginal
% effects the LMM/GLMM in gsr_training_lmm.m / perf_training_lmm.m
% actually test (those additionally adjust for Level as a covariate and
% use REML/Laplace estimates, not simple averaging). Use this figure for
% visual context alongside Table 1 in the paper, not as a substitute for
% the reported beta/p values.
%
% Requires cfg.output_root/eda_features.mat and perf_features.mat to
% already exist (run gsr_extract_features(cfg) / perf_extract_features(cfg)
% first if not).

    COLOR_N = [55  138 221] / 255;
    COLOR_H = [212  83 126] / 255;

    fig_dir = fullfile(cfg.output_root, 'figures');
    if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

    eda_file  = fullfile(cfg.output_root, 'eda_features.mat');
    perf_file = fullfile(cfg.output_root, 'perf_features.mat');
    if ~isfile(eda_file) || ~isfile(perf_file)
        error('plot_learning_curves: run gsr_extract_features(cfg) and perf_extract_features(cfg) first.');
    end
    Teda  = load(eda_file,  'T'); Teda  = Teda.T;
    Tperf = load(perf_file, 'T'); Tperf = Tperf.T;

    outcomes = {
        'scl_mean',               'Mean SCL (uS)',              Teda
        'scr_freq',                'SCR frequency (per min)',    Teda
        'scr_mean_amp',            'Mean SCR amplitude (uS)',    Teda
        'collision_scr_amp_mean',  'Event-locked SCR amp. (uS)', Teda
        'duration_s',              'Completion time (s)',        Tperf
        'n_collisions',            'Collisions (count)',         Tperf
        };

    fig = figure('Name', 'Training-phase learning curves', 'Position', [50 50 1500 850]);
    sgtitle('Training-phase trajectories by repetition (raw group means \pm SEM)', 'FontWeight', 'bold');

    for oi = 1:size(outcomes, 1)
        outcome = outcomes{oi,1};
        ylab    = outcomes{oi,2};
        Tsrc    = outcomes{oi,3};

        Ttr = Tsrc(strcmp(Tsrc.phase_type, 'training') & isfinite(Tsrc.(outcome)), :);

        subplot(2, 3, oi); hold on;
        for grp = [false true]
            Tg = Ttr(Ttr.haptic == grp, :);
            subj_list = unique(Tg.subject);
            subj_by_rep = nan(numel(subj_list), 10);
            for si = 1:numel(subj_list)
                Ts = Tg(strcmp(Tg.subject, subj_list{si}), :);
                for r = 1:10
                    vals = Ts.(outcome)(Ts.repetition == r);
                    if ~isempty(vals), subj_by_rep(si, r) = mean(vals, 'omitnan'); end
                end
            end
            mu  = mean(subj_by_rep, 1, 'omitnan');
            sem = std(subj_by_rep, 0, 1, 'omitnan') ./ sqrt(sum(isfinite(subj_by_rep), 1));

            col = local_ternary(grp, COLOR_H, COLOR_N);
            lbl = local_ternary(grp, 'HF', 'NHF');
            errorbar(1:10, mu, sem, '-o', 'Color', col, 'LineWidth', 1.6, ...
                'MarkerFaceColor', col, 'DisplayName', lbl);
        end
        xlabel('Repetition'); ylabel(ylab); xlim([0.5 10.5]); xticks(1:10);
        title(strrep(outcome, '_', ' '), 'Interpreter', 'none', 'FontSize', 10);
        legend('Location', 'best', 'FontSize', 8); grid on;
    end

    saveas(fig, fullfile(fig_dir, 'learning_curves_training.png'));
    fprintf('Saved %s\n', fullfile(fig_dir, 'learning_curves_training.png'));
end

function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
