function plot_layer1_levels(cfg)
% PLOT_LAYER1_LEVELS  Visualizes layer1_levels_comparisons.m's results
% (run that function first -- requires cfg.output_root/layer1_levels_results.mat).
%
% One figure, one panel per outcome: every subject's own trajectory
% across the 5 training levels (thin lines, individual data), colored by
% group, group mean +/- 95% CI overlaid in bold. At each level, the
% group-mean marker is FILLED if that level's between-group comparison
% is FDR-significant (layer1_levels_comparisons.m's
% between_group_per_level table) and hollow otherwise -- same filled/
% hollow convention as plot_level_divergence.m. Panel title reports the
% two within-group omnibus (Friedman) p-values -- "does level matter at
% all, within this group" -- which is the direct answer to "within
% levels" from the requested structure.
%
% Saved to cfg.output_root/figures/layer1_levels.png.

    COLOR_N = [55  138 221] / 255;
    COLOR_H = [212  83 126] / 255;

    fig_dir = fullfile(cfg.output_root, 'figures');
    if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

    res_path = fullfile(cfg.output_root, 'layer1_levels_results.mat');
    if ~isfile(res_path)
        error('plot_layer1_levels: run layer1_levels_comparisons(cfg) first.');
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
    n_levels = 5;
    ncols = 4; nrows = ceil(n_out / ncols);

    fig = figure('Name', 'Layer1 levels comparisons', 'Position', [50 50 1750 380*nrows]);
    sgtitle('Training phase -- value by difficulty level (individual subjects + mean \pm 95% CI); filled marker = FDR-significant N vs H at that level', ...
        'FontWeight', 'bold');

    for oi = 1:n_out
        outcome = outcome_list{oi,1};
        Tsrc    = outcome_list{oi,2};
        subplot(nrows, ncols, oi);

        Ttr = Tsrc(strcmp(Tsrc.phase_type, 'training') & isfinite(Tsrc.(outcome)), :);
        subj_list = unique(Ttr.subject);
        subj_by_level = nan(numel(subj_list), n_levels);
        is_h = false(numel(subj_list), 1);
        for si = 1:numel(subj_list)
            s = subj_list{si};
            Ts = Ttr(strcmp(Ttr.subject, s), :);
            is_h(si) = any(Ts.haptic);
            for lv = 1:n_levels
                subj_by_level(si, lv) = mean(Ts.(outcome)(Ts.level == lv), 'omitnan');
            end
        end

        hold on;
        for grp = [false true]
            sel = (is_h == grp);
            X = subj_by_level(sel, :);
            col = local_ternary(grp, COLOR_H, COLOR_N);
            for si = 1:size(X,1)
                plot(1:n_levels, X(si,:), '-', 'Color', [col, 0.15], 'LineWidth', 0.6, 'HandleVisibility', 'off');
            end
            mu  = mean(X, 1, 'omitnan');
            sem = std(X, 0, 1, 'omitnan') ./ sqrt(sum(isfinite(X), 1));
            ci95 = sem * 1.96;

            sig_at_level = false(1, n_levels);
            bg = local_get_between_group(results.between_group_per_level, outcome);
            for lv = 1:n_levels
                if ~isempty(bg)
                    row = bg(bg.level == lv, :);
                    if ~isempty(row) && isfinite(row.p_fdr(1)) && row.p_fdr(1) < 0.05
                        sig_at_level(lv) = true;
                    end
                end
            end

            lbl = local_ternary(grp, 'HF', 'NHF');
            errorbar(1:n_levels, mu, ci95, '-', 'Color', col, 'LineWidth', 1.8, 'DisplayName', lbl, 'HandleVisibility', 'on');
            for lv = 1:n_levels
                if sig_at_level(lv)
                    plot(lv, mu(lv), 'o', 'Color', col, 'MarkerFaceColor', col, 'MarkerSize', 7, 'HandleVisibility', 'off');
                else
                    plot(lv, mu(lv), 'o', 'Color', col, 'MarkerFaceColor', 'w', 'MarkerSize', 7, 'HandleVisibility', 'off');
                end
            end
        end

        omni_N = local_get_omnibus(results.omnibus_within_N, outcome);
        omni_H = local_get_omnibus(results.omnibus_within_H, outcome);
        ttl = sprintf('%s\nomnibus(Friedman) N p=%s | H p=%s', strrep(outcome,'_',' '), ...
            local_fmt_p(omni_N), local_fmt_p(omni_H));
        title(ttl, 'FontSize', 8, 'Interpreter', 'none');
        xlim([0.5 5.5]); xticks(1:5); xlabel('Level', 'FontSize', 7.5);
        if oi == 1, legend('Location','best','FontSize',7); end
        grid on; set(gca, 'FontSize', 8);
    end

    saveas(fig, fullfile(fig_dir, 'layer1_levels.png'));
    fprintf('Saved %s\n', fullfile(fig_dir, 'layer1_levels.png'));
end

function bg = local_get_between_group(tbl, outcome)
    idx = strcmp(string(tbl.outcome), outcome);
    if ~any(idx), bg = []; return; end
    bg = tbl(idx, :);
end

function row = local_get_omnibus(tbl, outcome)
    idx = strcmp(string(tbl.outcome), outcome);
    if ~any(idx), row = []; return; end
    row = tbl(idx, :);
end

function s = local_fmt_p(row)
    if isempty(row) || ~isfinite(row.p(1))
        s = 'n/a';
    else
        s = sprintf('%.3f', row.p(1));
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
