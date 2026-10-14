%% plot_edge_subjects_by_phase.m
% Which subject sits at the extreme high/low in each phase, now that
% force_vibration_features_clean.mat already has the known-bad subjects
% removed -- no need to re-apply any exclusion list here.
%
% Training: every individual trial (level x repetition) is plotted, and
% the extreme high/low TRIAL is found and labeled per level -- this is
% finer-grained than a per-subject mean, so a single bad repetition is
% visible even if that subject's overall mean looks fine.
% Baseline/Test: Baseline1, Baseline2, Test1, Test2 are each their own
% panel -- NOT merged into one "baseline"/"test" bucket, since they are
% different points in the study timeline and mixing them together would
% hide a subject who is only extreme at one of the two.

clear; clc; cfg = config();
S = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T');
T = S.T;

metrics = {'tssv','tssf'};

for m = 1:numel(metrics)
    oc = metrics{m};

    % ---- TRAINING: all levels, all repetitions, every trial point ----
    Ttr = T(strcmp(T.phase_type,'training') & isfinite(T.level) & isfinite(T.(oc)) & T.(oc)>0, :);
    figure('Position',[100 100 1000 500]); hold on;
    jitter = (rand(height(Ttr),1)-0.5)*0.5;
    scatter(Ttr.level + jitter, log(Ttr.(oc)), 12, [0.75 0.75 0.75], 'filled', 'MarkerFaceAlpha',0.5);
    for lv = 1:5
        Tl = Ttr(Ttr.level==lv, :);
        if isempty(Tl), continue; end
        [vmax,imax] = max(log(Tl.(oc)));
        [vmin,imin] = min(log(Tl.(oc)));
        scatter(lv, vmax, 70, [0.85 0.1 0.1], 'filled');
        scatter(lv, vmin, 70, [0.1 0.3 0.85], 'filled');
        text(lv+0.1, vmax, sprintf('%s/%s', erase(Tl.subject{imax},'subject_'), Tl.acquisition{imax}), ...
            'Color',[0.85 0.1 0.1], 'FontSize',8, 'FontWeight','bold');
        text(lv+0.1, vmin, sprintf('%s/%s', erase(Tl.subject{imin},'subject_'), Tl.acquisition{imin}), ...
            'Color',[0.1 0.3 0.85], 'FontSize',8, 'FontWeight','bold');
        fprintf('%s / training L%d: HIGH=%s/%s (%.3f)  LOW=%s/%s (%.3f)\n', ...
            upper(oc), lv, Tl.subject{imax}, Tl.acquisition{imax}, vmax, Tl.subject{imin}, Tl.acquisition{imin}, vmin);
    end
    xlabel('Training Level'); ylabel(sprintf('log(%s)', upper(oc)));
    title(sprintf('%s -- training, every trial, extreme per level highlighted', upper(oc)));
    xlim([0.5 5.5]); xticks(1:5); grid on; box on;
    saveas(gcf, fullfile(cfg.output_root,'figures', sprintf('%s_edge_training.png', oc)));

    % ---- BASELINE1 / BASELINE2 / TEST1 / TEST2 -- kept separate -------
    phase_names = {'Baseline1','Baseline2','Test1','Test2'};
    figure('Position',[100 100 1300 450]);
    tl = tiledlayout(1, numel(phase_names), 'TileSpacing','compact','Padding','compact');
    title(tl, sprintf('%s -- extreme subjects, Baseline1/2 and Test1/2 kept separate', upper(oc)), 'FontWeight','bold');

    for p = 1:numel(phase_names)
        pname = phase_names{p};
        Tp = T(strcmp(T.phase, pname) & isfinite(T.(oc)) & T.(oc)>0, :);
        is_baseline = startsWith(pname,'Baseline');

        nexttile; hold on;
        if is_baseline && any(isfinite(Tp.level))
            % baseline: one acquisition per level -- x = level
            jitter2 = (rand(height(Tp),1)-0.5)*0.3;
            scatter(Tp.level + jitter2, log(Tp.(oc)), 20, [0.75 0.75 0.75], 'filled');
            for lv = 1:5
                Tl = Tp(Tp.level==lv, :);
                if isempty(Tl), continue; end
                [vmax,imax] = max(log(Tl.(oc))); [vmin,imin] = min(log(Tl.(oc)));
                scatter(lv, vmax, 60, [0.85 0.1 0.1], 'filled');
                scatter(lv, vmin, 60, [0.1 0.3 0.85], 'filled');
                text(lv+0.08, vmax, erase(Tl.subject{imax},'subject_'), 'Color',[0.85 0.1 0.1], 'FontSize',7, 'FontWeight','bold');
                text(lv+0.08, vmin, erase(Tl.subject{imin},'subject_'), 'Color',[0.1 0.3 0.85], 'FontSize',7, 'FontWeight','bold');
                fprintf('%s / %s L%d: HIGH=%s (%.3f)  LOW=%s (%.3f)\n', ...
                    upper(oc), pname, lv, Tl.subject{imax}, vmax, Tl.subject{imin}, vmin);
            end
            xlim([0.5 5.5]); xticks(1:5); xlabel('Level');
        else
            % test: single acquisition per subject -- one strip
            v = log(Tp.(oc));
            scatter(ones(height(Tp),1), v, 20, [0.75 0.75 0.75], 'filled');
            [vmax,imax] = max(v); [vmin,imin] = min(v);
            scatter(1, vmax, 60, [0.85 0.1 0.1], 'filled');
            scatter(1, vmin, 60, [0.1 0.3 0.85], 'filled');
            text(1.08, vmax, erase(Tp.subject{imax},'subject_'), 'Color',[0.85 0.1 0.1], 'FontSize',8, 'FontWeight','bold');
            text(1.08, vmin, erase(Tp.subject{imin},'subject_'), 'Color',[0.1 0.3 0.85], 'FontSize',8, 'FontWeight','bold');
            fprintf('%s / %s: HIGH=%s (%.3f)  LOW=%s (%.3f)\n', upper(oc), pname, Tp.subject{imax}, vmax, Tp.subject{imin}, vmin);
            xlim([0.7 1.5]); xticks([]);
        end
        title(pname, 'FontSize',10); ylabel(sprintf('log(%s)', upper(oc))); grid on; box on;
    end
    %saveas(gcf, fullfile(cfg.output_root,'figures', sprintf('%s_edge_baseline_test.png', oc)));
end