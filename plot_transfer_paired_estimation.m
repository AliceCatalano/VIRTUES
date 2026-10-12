function plot_transfer_paired_estimation(cfg)
% PLOT_TRANSFER_PAIRED_ESTIMATION  Per your instruction to show every
% metric's Baseline1-vs-Baseline2 (and Test1-vs-Test2) comparison in a
% plot regardless of statistical significance: for each outcome, plots
% every subject's own paired pre/post value as a thin connecting line
% (individual data, not hidden behind a summary statistic), colored by
% group, with the group mean +/- 95% CI overlaid as a bold marker/error
% bar at each timepoint. This is the paired/"before-after" form of an
% estimation plot (Ho, Tumkaya, Aryal, Choe, & Claridge-Chang, 2019,
% "Moving beyond P values: data analysis with estimation graphics",
% Nature Methods) and follows Weissgerber, Milic, Winham, & Garovic's
% (2015, PLoS Biology, "Beyond bar and line graphs: time for a new data
% presentation paradigm") core recommendation against summarizing
% repeated-measures data with only a bar/line-and-error-bar plot, which
% can look identical for datasets with very different underlying
% distributions (e.g. uniform small shifts vs. a few large individual
% changes) -- showing every subject's own line makes that distinction
% visible.
%
% Every panel is drawn whether or not the corresponding transfer model
% found a significant effect -- annotated with the FDR-corrected p-value
% when available, "stats pending" when the corresponding *_transfer_lmm_
% results.mat file doesn't exist yet, so absence of significance is never
% mistaken for absence of a result.
%
% Covers all four feature tables (EDA, eye-tracking, performance,
% force/vibration) x both transfer families (Baseline1/2, Test1/2).
%
% Requires the four *_features.mat tables; annotates from
% transfer_lmm_results.mat / eye_transfer_lmm_results.mat /
% performance_transfer_lmm_results.mat / force_vibration_transfer_lmm_
% results.mat where present (each optional -- a missing one just means
% "stats pending" for those outcomes, not an error).

    COLOR_N = [55  138 221] / 255;
    COLOR_H = [212  83 126] / 255;

    fig_dir = fullfile(cfg.output_root, 'figures');
    if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

    sources = local_load_if_exists(cfg.output_root, { ...
        'eda_features_v2.mat', 'eye_features_v2.mat', 'perf_features.mat', 'force_vibration_features_clean.mat'});

    outcome_list = {
        'scl_mean',      sources.eda
        'scr_freq',       sources.eda
        'scr_mean_amp',   sources.eda
        'pupil_mean',     sources.eye
        'pupil_slope',    sources.eye
        'gaze_dispersion',sources.eye
        'saccade_rate',   sources.eye
        'duration_s',     sources.perf
        'n_collisions',   sources.perf
        'tssf_raw',           sources.force_vibration
        'tssv',           sources.force_vibration
        };
    outcome_list = outcome_list(~cellfun(@isempty, outcome_list(:,2)), :);

    stat_sources = struct( ...
        'gsr',              local_load_stats(cfg, 'transfer_lmm_results.mat'), ...
        'eye',              local_load_stats(cfg, 'eye_transfer_lmm_results.mat'), ...
        'perf',             local_load_stats(cfg, 'performance_transfer_lmm_results.mat'), ...
        'force_vibration',  local_load_stats(cfg, 'force_vibration_transfer_lmm_results.mat'));

    families = {
        'baseline', 'Baseline1', 'Baseline2', 'baseline_transfer_elastic', 'Elastic task (Baseline1 vs Baseline2)'
        'test',     'Test1',     'Test2',     'test_transfer_pegtransfer', 'Peg Transfer (Test1 vs Test2)'
        };

    for f = 1:size(families, 1)
        phase_type = families{f,1};
        phase_pre  = families{f,2};
        phase_post = families{f,3};
        fam_field  = families{f,4};
        fam_title  = families{f,5};

        n_out = size(outcome_list, 1);
        ncols = 4; nrows = ceil(n_out / ncols);
        fig = figure('Name', sprintf('Paired estimation: %s', fam_title), 'Position', [50 50 1700 380*nrows]);
        sgtitle(sprintf('%s -- every subject''s own pre/post value (thin lines) + group mean \\pm 95%% CI (bold)', fam_title), ...
            'FontWeight', 'bold');

        for oi = 1:n_out
            outcome = outcome_list{oi,1};
            Tsrc    = outcome_list{oi,2};
            subplot(nrows, ncols, oi);
            p_fdr = local_get_pfdr(stat_sources, outcome, fam_field);
            local_plot_paired_panel(Tsrc, outcome, phase_type, phase_pre, phase_post, COLOR_N, COLOR_H, p_fdr, oi == 1);
        end

        fname = fullfile(fig_dir, sprintf('transfer_paired_estimation_%s.png', phase_type));
        saveas(fig, fname);
        fprintf('Saved %s\n', fname);
    end
end

function local_plot_paired_panel(Tsrc, outcome, phase_type, phase_pre, phase_post, COLOR_N, COLOR_H, p_fdr, is_first_panel)
    Tph = Tsrc(strcmp(Tsrc.phase_type, phase_type) & isfinite(Tsrc.(outcome)), :);
    Tph = Tph(ismember(Tph.phase, {phase_pre, phase_post}), :);

    hold on;
    if isempty(Tph)
        title(sprintf('%s\n(no data yet)', strrep(outcome,'_',' ')), 'FontSize', 9, 'Interpreter', 'none');
        xlim([0.5 2.5]); xticks([1 2]); xticklabels({phase_pre, phase_post});
        return;
    end

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

        mu  = [mean(pre_vals(idx)), mean(post_vals(idx))];
        sem = [std(pre_vals(idx)), std(post_vals(idx))] / sqrt(numel(idx));
        ci95 = sem * 1.96;
        lbl = local_ternary(grp, 'HF', 'NHF');
        errorbar([1 2] + local_ternary(grp, 0.08, -0.08), mu, ci95, '-o', 'Color', col, ...
            'LineWidth', 2.2, 'MarkerFaceColor', col, 'MarkerSize', 6, 'DisplayName', lbl);
    end

    xlim([0.5 2.5]); xticks([1 2]); xticklabels({phase_pre, phase_post});
    ylabel(strrep(outcome, '_', ' '), 'Interpreter', 'none');
    if isnan(p_fdr)
        sig_str = 'stats pending';
    elseif p_fdr < 0.05
        sig_str = sprintf('p_{FDR}=%.4f *', p_fdr);
    else
        sig_str = sprintf('p_{FDR}=%.3f n.s.', p_fdr);
    end
    title(sprintf('%s (%s)', strrep(outcome,'_',' '), sig_str), 'FontSize', 9, 'Interpreter', 'tex');
    if is_first_panel, legend('Location','best','FontSize',7); end
    grid on;
end

function p_fdr = local_get_pfdr(stat_sources, outcome, fam_field)
    p_fdr = NaN;
    src_field = '';
    if ismember(outcome, {'scl_mean','scr_freq','scr_mean_amp','collision_scr_amp_mean'})
        src_field = 'gsr';
    elseif ismember(outcome, {'pupil_mean','pupil_slope','gaze_dispersion','saccade_rate','collision_pupil_response_mean'})
        src_field = 'eye';
    elseif ismember(outcome, {'duration_s','n_collisions'})
        src_field = 'perf';
    elseif ismember(outcome, {'tssf_raw','tssv'})
        src_field = 'force_vibration';
    end
    if isempty(src_field), return; end
    all_results = stat_sources.(src_field);
    if isempty(all_results) || ~isfield(all_results, fam_field), return; end
    fam = all_results.(fam_field);
    idx = find(strcmp(fam.outcomes, outcome), 1);
    if isempty(idx), return; end
    p_fdr = fam.p_fdr(idx);
end

function all_results = local_load_stats(cfg, filename)
    path = fullfile(cfg.output_root, filename);
    if ~isfile(path)
        all_results = [];
        return;
    end
    loaded = load(path, 'all_results');
    all_results = loaded.all_results;
end

function sources = local_load_if_exists(output_root, filenames)
    keys = {'eda','eye','perf','force_vibration'};
    for i = 1:numel(filenames)
        path = fullfile(output_root, filenames{i});
        if isfile(path)
            loaded = load(path, 'T');
            sources.(keys{i}) = loaded.T;
        else
            sources.(keys{i}) = [];
        end
    end
end

function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
