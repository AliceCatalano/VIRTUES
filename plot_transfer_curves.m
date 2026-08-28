function plot_transfer_curves(cfg)
% PLOT_TRANSFER_CURVES  Pre/post interaction-style plot for Results 3.3:
% raw group means at Baseline1 (pre-training) vs Baseline2 (post-training)
% for the elastic task, connected by lines -- a visibly steeper HF line
% than NHF is the Phase x Group interaction reported in Table 4. Also
% attempts Test1/Test2 (Peg Transfer carry-over) and simply skips any
% outcome/phase pair with no data yet, rather than erroring, since that
% phase's data collection may still be in progress (see Results 3.4).
%
% Requires cfg.output_root/eda_features.mat and perf_features.mat.

    COLOR_N = [55  138 221] / 255;
    COLOR_H = [212  83 126] / 255;

    fig_dir = fullfile(cfg.output_root, 'figures');
    if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

    eda_file  = fullfile(cfg.output_root, 'eda_features.mat');
    perf_file = fullfile(cfg.output_root, 'perf_features.mat');
    if ~isfile(eda_file) || ~isfile(perf_file)
        error('plot_transfer_curves: run gsr_extract_features(cfg) and perf_extract_features(cfg) first.');
    end
    Teda  = load(eda_file,  'T'); Teda  = Teda.T;
    Tperf = load(perf_file, 'T'); Tperf = Tperf.T;

    families = {
        'baseline', 'Baseline1', 'Baseline2', 'Elastic task (SAP 4.3 / H2)'
        'test',     'Test1',     'Test2',     'Peg Transfer (carry-over control)'
        };

    outcomes = {
        'scl_mean',      'Mean SCL (uS)',       Teda
        'scr_freq',       'SCR frequency',       Teda
        'scr_mean_amp',   'Mean SCR amplitude',  Teda
        'duration_s',     'Completion time (s)', Tperf
        'n_collisions',   'Collisions (count)',  Tperf
        };

    for f = 1:size(families, 1)
        phase_type  = families{f,1};
        phase_pre   = families{f,2};
        phase_post  = families{f,3};
        fam_title   = families{f,4};

        fig = figure('Name', sprintf('Transfer: %s', fam_title), 'Position', [50 50 1500 350]);
        sgtitle(sprintf('%s -- %s vs %s (raw group means \\pm SEM)', fam_title, phase_pre, phase_post), ...
            'FontWeight', 'bold');

        any_plotted = false;
        for oi = 1:size(outcomes, 1)
            outcome = outcomes{oi,1};
            ylab    = outcomes{oi,2};
            Tsrc    = outcomes{oi,3};

            Tph = Tsrc(strcmp(Tsrc.phase_type, phase_type) & isfinite(Tsrc.(outcome)), :);
            Tph = Tph(ismember(Tph.phase, {phase_pre, phase_post}), :);

            subplot(1, size(outcomes,1), oi); hold on;
            if isempty(Tph)
                title(sprintf('%s\n(no data yet)', ylab), 'FontSize', 9);
                xlim([0.5 2.5]); xticks([1 2]); xticklabels({phase_pre, phase_post});
                continue;
            end
            any_plotted = true;

            for grp = [false true]
                Tg = Tph(Tph.haptic == grp, :);
                mu  = nan(1,2); sem = nan(1,2);
                for pj = 1:2
                    ph = local_ternary(pj==1, phase_pre, phase_post);
                    subj_list = unique(Tg.subject(strcmp(Tg.phase, ph)));
                    subj_vals = nan(numel(subj_list), 1);
                    for si = 1:numel(subj_list)
                        vals = Tg.(outcome)(strcmp(Tg.subject, subj_list{si}) & strcmp(Tg.phase, ph));
                        subj_vals(si) = mean(vals, 'omitnan');
                    end
                    mu(pj)  = mean(subj_vals, 'omitnan');
                    sem(pj) = std(subj_vals, 'omitnan') / sqrt(sum(isfinite(subj_vals)));
                end
                col = local_ternary(grp, COLOR_H, COLOR_N);
                lbl = local_ternary(grp, 'HF', 'NHF');
                errorbar([1 2], mu, sem, '-o', 'Color', col, 'LineWidth', 1.8, ...
                    'MarkerFaceColor', col, 'MarkerSize', 7, 'DisplayName', lbl);
            end
            xlim([0.5 2.5]); xticks([1 2]); xticklabels({phase_pre, phase_post});
            ylabel(ylab); title(ylab, 'FontSize', 10);
            if oi == 1, legend('Location', 'best', 'FontSize', 8); end
            grid on;
        end

        if any_plotted
            fname = fullfile(fig_dir, sprintf('transfer_%s.png', phase_type));
            saveas(fig, fname);
            fprintf('Saved %s\n', fname);
        else
            fprintf('No data yet for %s vs %s -- figure not saved.\n', phase_pre, phase_post);
            close(fig);
        end
    end
end

function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
