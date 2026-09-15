function plot_sessiontiming_paired_estimation(cfg, first_n, last_n)
% PLOT_SESSIONTIMING_PAIRED_ESTIMATION  Same paired individual-subject +
% mean-95%CI estimation-plot style as plot_transfer_paired_estimation.m
% (see that file's header for the Weissgerber et al. 2015 / Ho et al.
% 2019 rationale), applied to the training-block "start vs end" (first_n
% vs last_n repetitions, pooled across Levels) comparison used by
% perf_sessiontiming_lmm.m -- completion time, TSSF, TSSV, all log scale.
%
% Every panel is drawn regardless of significance, annotated from
% sessiontiming_lmm_results.mat's Haptic:Timing interaction row when
% available, "stats pending" otherwise.

    if nargin < 2 || isempty(first_n), first_n = 3; end
    if nargin < 3 || isempty(last_n),  last_n  = 3; end

    COLOR_N = [55  138 221] / 255;
    COLOR_H = [212  83 126] / 255;

    fig_dir = fullfile(cfg.output_root, 'figures');
    if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

    perf_file = fullfile(cfg.output_root, 'perf_features.mat');
    fv_file   = fullfile(cfg.output_root, 'force_vibration_features.mat');
    if ~isfile(perf_file) || ~isfile(fv_file)
        error('plot_sessiontiming_paired_estimation: run perf_extract_features(cfg) and perf_extract_force_vibration_features(cfg) first.');
    end
    Tperf = load(perf_file, 'T'); Tperf = Tperf.T;
    Tfv   = load(fv_file,   'T'); Tfv   = Tfv.T;
    join_keys = {'subject','phase_type','phase','acquisition','level','repetition','group','haptic'};
    T = innerjoin(Tperf, Tfv, 'Keys', join_keys);

    st_file = fullfile(cfg.output_root, 'sessiontiming_lmm_results.mat');
    st_results = [];
    if isfile(st_file)
        loaded = load(st_file, 'results', 'outcomes');
        st_results = loaded;
    end

    outcomes = {'duration_s', 'tssf_raw', 'tssv'};
    fig = figure('Name', 'Training start-vs-end (log scale) paired estimation', 'Position', [50 50 1300 380]);
    sgtitle(sprintf('Training: first %d vs last %d repetitions (pooled across Levels), log scale -- individual subjects (thin) + group mean \\pm 95%% CI (bold)', first_n, last_n), ...
        'FontWeight', 'bold');

    for oi = 1:numel(outcomes)
        outcome = outcomes{oi};
        subplot(1, numel(outcomes), oi);
        p_int = local_get_interaction_p(st_results, outcome);
        local_plot_panel(T, outcome, first_n, last_n, COLOR_N, COLOR_H, p_int, oi == 1);
    end

    fname = fullfile(fig_dir, 'sessiontiming_paired_estimation.png');
    saveas(fig, fname);
    fprintf('Saved %s\n', fname);
end

function local_plot_panel(T, outcome, first_n, last_n, COLOR_N, COLOR_H, p_int, is_first_panel)
    Ttr = T(strcmp(T.phase_type, 'training') & isfinite(T.(outcome)) & T.(outcome) > 0, :);
    is_start = Ttr.repetition <= first_n;
    is_end   = Ttr.repetition >= (11 - last_n);
    Ttr = Ttr(is_start | is_end, :);
    timing = repmat({'end'}, height(Ttr), 1);
    timing(Ttr.repetition <= first_n) = {'start'};
    log_val = log(Ttr.(outcome));

    subj_list = unique(Ttr.subject);
    start_vals = nan(numel(subj_list), 1);
    end_vals   = nan(numel(subj_list), 1);
    is_h       = false(numel(subj_list), 1);
    for si = 1:numel(subj_list)
        s = subj_list{si};
        mask_s = strcmp(Ttr.subject, s);
        start_vals(si) = mean(log_val(mask_s & strcmp(timing, 'start')), 'omitnan');
        end_vals(si)   = mean(log_val(mask_s & strcmp(timing, 'end')),   'omitnan');
        is_h(si) = any(Ttr.haptic(mask_s));
    end
    keep = isfinite(start_vals) & isfinite(end_vals);
    start_vals = start_vals(keep); end_vals = end_vals(keep); is_h = is_h(keep);

    hold on;
    jitter_x = @(base, n) base + (rand(n,1) - 0.5) * 0.12;
    for grp = [false true]
        idx = find(is_h == grp);
        if isempty(idx), continue; end
        col = local_ternary(grp, COLOR_H, COLOR_N);
        x1 = jitter_x(1, numel(idx)); x2 = x1 + 1;
        for k = 1:numel(idx)
            plot([x1(k) x2(k)], [start_vals(idx(k)), end_vals(idx(k))], ...
                '-', 'Color', [col, 0.25], 'LineWidth', 0.7, 'HandleVisibility', 'off');
        end
        scatter(x1, start_vals(idx), 14, col, 'filled', 'MarkerFaceAlpha', 0.35, 'HandleVisibility', 'off');
        scatter(x2, end_vals(idx),   14, col, 'filled', 'MarkerFaceAlpha', 0.35, 'HandleVisibility', 'off');

        mu   = [mean(start_vals(idx)), mean(end_vals(idx))];
        sem  = [std(start_vals(idx)), std(end_vals(idx))] / sqrt(numel(idx));
        ci95 = sem * 1.96;
        lbl = local_ternary(grp, 'HF', 'NHF');
        errorbar([1 2] + local_ternary(grp, 0.08, -0.08), mu, ci95, '-o', 'Color', col, ...
            'LineWidth', 2.2, 'MarkerFaceColor', col, 'MarkerSize', 6, 'DisplayName', lbl);
    end

    xlim([0.5 2.5]); xticks([1 2]); xticklabels({sprintf('first %d reps',first_n), sprintf('last %d reps',last_n)});
    ylabel(sprintf('log(%s)', strrep(outcome,'_',' ')), 'Interpreter', 'none');
    if isnan(p_int)
        sig_str = 'stats pending';
    elseif p_int < 0.05
        sig_str = sprintf('Haptic\\times Timing p=%.4f *', p_int);
    else
        sig_str = sprintf('Haptic\\times Timing p=%.3f n.s.', p_int);
    end
    title(sprintf('%s (%s)', strrep(outcome,'_',' '), sig_str), 'FontSize', 9, 'Interpreter', 'tex');
    if is_first_panel, legend('Location','best','FontSize',7); end
    grid on;
end

function p_int = local_get_interaction_p(st_results, outcome)
    p_int = NaN;
    if isempty(st_results), return; end
    idx = find(strcmp(st_results.outcomes, outcome), 1);
    if isempty(idx), return; end
    atbl = st_results.results{idx}.anova_table;
    row = cellfun(@(t) isequal(sort(strsplit(t, ':')), sort({'haptic_num','timing_num'})), atbl.Term);
    if any(row), p_int = atbl.pValue(row); end
end

function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
