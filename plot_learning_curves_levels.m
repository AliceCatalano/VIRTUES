function plot_learning_curves_levels(cfg)
% PLOT_LEARNING_CURVES  Raw (model-free) group-mean trajectories across the
% 10 within-level training repetitions, for the 4 physiological (GSR), 4
% eye-tracking, and 2 performance outcomes -- supports Results 3.1 ("both
% groups improve, no differential rate") and its eye-tracking extension.
%
% NOTE ON THE X-AXIS: the training phase has 50 trials per subject (5
% difficulty Levels x 10 repetitions each), not 10. "Repetition" here is
% the WITHIN-LEVEL trial index (1-10), which recurs once per Level.
% Earlier versions of this figure pooled all 5 levels' r-th repetition
% together into a single curve (averaging e.g. Level 1's repetition 1 with
% Level 5's repetition 1) to match the *additive* Table 1 model, where
% Level is a separate covariate and the Repetition slope is assumed equal
% across levels. That assumption does NOT hold for every outcome (see
% run_training_lmms_3way.m / Table 2b: the group difference in repetition
% slope is level-dependent for scr_mean_amp and collision_scr_amp_mean in
% particular) -- so pooling across levels here would hide exactly the
% pattern that matters and can visually misrepresent outcomes where it
% doesn't hold. This version therefore plots one curve PER LEVEL, never
% averaging repetition r across levels: each panel is one outcome x one
% level, x-axis is repetition 1-10 within that level only.
%
% One figure per modality (GSR, Eye, Performance), laid out as
% outcome (rows) x level (columns), so nothing is pooled across levels.
%
% NOTE: these are descriptive raw means, NOT the model-adjusted marginal
% effects the LMM/GLMM in gsr_training_lmm.m / perf_training_lmm.m /
% run_training_lmms_3way.m actually test (those use REML/Laplace
% estimates with the full random-effects structure, not simple
% averaging). Use these figures for visual context, not as a substitute
% for the reported beta/p values.
%
% Requires cfg.output_root/eda_features.mat, eye_features.mat, and
% perf_features.mat to already exist (run gsr_extract_features(cfg) /
% eye_extract_features(cfg) / perf_extract_features(cfg) first if not).
%
% SIGNIFICANCE ANNOTATION: each row's outcome label carries two FDR
% p-values: the additive Haptic x Repetition test (Table 1, pooled across
% levels) and the 3-way Haptic x Level x Repetition omnibus test (Table
% 2b, run_training_lmms_3way.m) -- the latter is the one that actually
% tests whether the per-level curves shown here differ from each other
% across levels between groups. Falls back to "pending" if the
% corresponding *_lmm_results.mat file isn't there yet.

    COLOR_N = [55  138 221] / 255;
    COLOR_H = [212  83 126] / 255;

    fig_dir = fullfile(cfg.output_root, 'figures');
    if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

    eda_file  = fullfile(cfg.output_root, 'eda_features_v2.mat');
    eye_file  = fullfile(cfg.output_root, 'eye_features_v2.mat');
    perf_file = fullfile(cfg.output_root, 'perf_features.mat');
    if ~isfile(eda_file) || ~isfile(eye_file) || ~isfile(perf_file)
        error('plot_learning_curves: run gsr_extract_features(cfg), eye_extract_features(cfg), and perf_extract_features(cfg) first.');
    end
    Teda  = load(eda_file,  'T'); Teda  = Teda.T;
    Teye  = load(eye_file,  'T'); Teye  = Teye.T;
    Tperf = load(perf_file, 'T'); Tperf = Tperf.T;

    p_fdr_lookup      = local_load_pfdr_lookup(cfg);
    p_fdr_3way_lookup = local_load_pfdr_3way_lookup(cfg);

    modalities = {
        'GSR',         { 'scl_mean',              'Mean SCL (uS)'
                          'scr_freq',              'SCR frequency (per min)'
                          'scr_mean_amp',          'Mean SCR amplitude (uS)'
                          'collision_scr_amp_mean','Event-locked SCR amp. (uS)' }, Teda
        'Eye',         { 'pupil_mean',             'Mean pupil diam. (a.u.)'
                          'pupil_slope',            'Within-trial pupil slope'
                          'gaze_dispersion',        'Gaze dispersion (a.u.)'
                          'saccade_rate',           'Saccade rate (per s)' },       Teye
        'Performance', { 'duration_s',             'Completion time (s)'
                          'n_collisions',           'Collisions (count)' },         Tperf
        };

    for mi = 1:size(modalities, 1)
        mod_name = modalities{mi, 1};
        outcomes = modalities{mi, 2};
        Tsrc     = modalities{mi, 3};
        n_out    = size(outcomes, 1);

        fig = figure('Name', sprintf('Training-phase learning curves -- %s', mod_name), ...
            'Position', [50 50 1900 max(350, 320 * n_out)]);
        sgtitle(sprintf('%s: training-phase trajectories by level and repetition (raw group means \\pm SEM)', mod_name), ...
            'FontWeight', 'bold');

        for oi = 1:n_out
            outcome = outcomes{oi, 1};
            ylab    = outcomes{oi, 2};

            Ttr = Tsrc(strcmp(Tsrc.phase_type, 'training') & isfinite(Tsrc.(outcome)), :);

            if isKey(p_fdr_lookup, outcome), p_add = p_fdr_lookup(outcome); else, p_add = NaN; end
            if isKey(p_fdr_3way_lookup, outcome), p_3way = p_fdr_3way_lookup(outcome); else, p_3way = NaN; end
            row_label = sprintf('%s  (Haptic\\times Rep p_{FDR}=%s, 3-way p_{FDR}=%s)', ...
                strrep(outcome, '_', ' '), local_fmt_p(p_add), local_fmt_p(p_3way));

            for lv = 1:5
                subplot(n_out, 5, (oi - 1) * 5 + lv); hold on;
                Tlv = Ttr(Ttr.level == lv, :);

                for grp = [false true]
                    Tg = Tlv(Tlv.haptic == grp, :);
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
                    errorbar(1:10, mu, sem, '-o', 'Color', col, 'LineWidth', 1.3, ...
                        'MarkerFaceColor', col, 'MarkerSize', 3.5, 'DisplayName', lbl);
                end

                xlim([0.5 10.5]); xticks(1:10);
                if lv == 1
                    ylabel(ylab, 'FontSize', 8);
                end
                if oi == n_out
                    xlabel('Repetition (within level)', 'FontSize', 7.5);
                end
                if oi == 1
                    title(sprintf('Level %d', lv), 'FontSize', 9, 'FontWeight', 'bold');
                end
                if lv == 1 && oi == 1
                    legend('Location', 'best', 'FontSize', 7);
                end
                grid on; set(gca, 'FontSize', 7);
            end

            % Row label as a shared annotation to the left of the row's panels
            ax1 = subplot(n_out, 5, (oi - 1) * 5 + 1);
            pos = get(ax1, 'Position');
            annotation('textbox', [0.005, pos(2) + pos(4) - 0.02, 0.30, 0.05], ...
                'String', row_label, 'EdgeColor', 'none', 'FontSize', 8, ...
                'FontWeight', 'bold', 'Interpreter', 'tex', 'HorizontalAlignment', 'left');
        end

        fname = sprintf('learning_curves_training_%s.png', lower(mod_name));
        saveas(fig, fullfile(fig_dir, fname));
        fprintf('Saved %s\n', fullfile(fig_dir, fname));
    end
end

function out = local_ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end

function s = local_fmt_p(p)
    if isnan(p), s = 'pending'; else, s = sprintf('%.3f', p); end
end

function lookup = local_load_pfdr_lookup(cfg)
% Maps outcome name -> Table 1's (additive) Haptic x Repetition p_FDR,
% pooled across the three *_lmm_results.mat files that each cover a
% subset of outcomes. Missing files just leave their outcomes unmapped
% (isKey false), handled by the caller as "pending" rather than an error.
    lookup = containers.Map('KeyType', 'char', 'ValueType', 'double');
    files = {'training_lmm_results.mat', 'eye_lmm_results.mat', 'performance_lmm_results.mat'};
    for f = 1:numel(files)
        path = fullfile(cfg.output_root, files{f});
        if ~isfile(path), continue; end
        loaded = load(path, 'outcomes', 'p_fdr');
        for i = 1:numel(loaded.outcomes)
            lookup(loaded.outcomes{i}) = loaded.p_fdr(i);
        end
    end
end

function lookup = local_load_pfdr_3way_lookup(cfg)
% Maps outcome name -> Table 2b's Haptic x Level x Repetition omnibus
% p_FDR (run_training_lmms_3way.m). This is the test that actually speaks
% to whether the level-specific curves plotted here differ across levels
% between groups; the additive Table 1 p_FDR (above) assumes they don't.
    lookup = containers.Map('KeyType', 'char', 'ValueType', 'double');
    path = fullfile(cfg.output_root, 'training_lmm_3way_results.mat');
    if ~isfile(path), return; end
    loaded = load(path, 'outcomes', 'p_fdr');
    for i = 1:numel(loaded.outcomes)
        lookup(loaded.outcomes{i}) = loaded.p_fdr(i);
    end
end