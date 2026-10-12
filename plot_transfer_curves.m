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

    eda_file  = fullfile(cfg.output_root, 'eda_features_v2.mat');
    perf_file = fullfile(cfg.output_root, 'perf_features.mat');
    if ~isfile(eda_file) || ~isfile(perf_file)
        error('plot_transfer_curves: run gsr_extract_features(cfg) and perf_extract_features(cfg) first.');
    end
    Teda  = load(eda_file,  'T'); Teda  = Teda.T;
    Tperf = load(perf_file, 'T'); Tperf = Tperf.T;
    stat_sources = struct('gsr',  local_load_stats(cfg, 'transfer_lmm_results.mat'), ...
        'eye',  local_load_stats(cfg, 'eye_transfer_lmm_results.mat'), 'perf', local_load_stats(cfg, 'performance_transfer_lmm_results.mat'));

    families = { 'baseline', 'Baseline1', 'Baseline2', 'Elastic task (SAP 4.3 / H2)','baseline_transfer_elastic'
        'test',     'Test1',     'Test2',     'Peg Transfer (carry-over control)', 'test_transfer_pegtransfer'};

    outcomes = {'scl_mean',      'Mean SCL (uS)',Teda
        'scr_freq',       'SCR frequency', Teda
        'scr_mean_amp',   'Mean SCR amplitude',  Teda
        'duration_s',     'Completion time (s)', Tperf
        'n_collisions',   'Collisions (count)',  Tperf };

    for f = 1:size(families, 1)
        phase_type  = families{f,1};
        phase_pre   = families{f,2};
        phase_post  = families{f,3};
        fam_title   = families{f,4};
        fam_field   = families{f,5};

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
            ylabel(ylab);
            p_fdr = local_get_pfdr(stat_sources, outcome, fam_field);
            if isnan(p_fdr)
                sig_str = 'stats pending';
            elseif p_fdr < 0.05
                sig_str = sprintf('p_{FDR}=%.4f *', p_fdr);
            else
                sig_str = sprintf('p_{FDR}=%.3f n.s.', p_fdr);
            end
            title(sprintf('%s\n%s', ylab, sig_str), 'FontSize', 9, 'Interpreter', 'tex');
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
function all_results = local_load_stats(cfg, filename)
    path = fullfile(cfg.output_root, filename);
    if ~isfile(path)
        all_results = [];
        return;
    end
    loaded = load(path, 'all_results');
    all_results = loaded.all_results;
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
    end
    if isempty(src_field), return; end
    all_results = stat_sources.(src_field);
    if isempty(all_results) || ~isfield(all_results, fam_field), return; end
    fam = all_results.(fam_field);
    idx = find(strcmp(fam.outcomes, outcome), 1);
    if isempty(idx), return; end
    p_fdr = fam.p_fdr(idx);
end