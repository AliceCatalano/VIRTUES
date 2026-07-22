%% analysis_L3_group_comparisons.m
% Q1: Did haptic vs no-haptic training change baseline arousal? (B1 vs B2)
% Q2: Does difficulty level affect arousal? (L1 vs L5)
% Q3: Does arousal change across 50 training repetitions? (learning curve)

clear; clc; close all;

cfg = config();

plot_dir = fullfile(cfg.output_root, 'L3_plots');
if ~exist(plot_dir, 'dir'), mkdir(plot_dir); end

feature_list = {'scl_mean','scl_slope','scr_n_peaks','scr_mean_amp',...
                'scr_max_amp','scr_rate','scr_auc','gsr_mean','gsr_std','gsr_rms'};
n_feat = numel(feature_list);

training_levels = {'levelL1','levelL2','levelL3','levelL4','levelL5'};
n_levels = numel(training_levels);
n_reps   = cfg.n_training_reps;   % 10

%% =========================================================
%  LOAD ALL SUBJECTS
% =========================================================
all_data       = struct();
valid_subjects = {};

for si = 1:numel(cfg.all_subjects)
    subj     = cfg.all_subjects{si};
    mat_path = fullfile(cfg.output_root, sprintf('%s_L1_features.mat', subj));
    if ~isfile(mat_path), continue; end
    d = load(mat_path);
    all_data.(subj)    = d.results;
    valid_subjects{end+1} = subj;
end
n_subj = numel(valid_subjects);
fprintf('Loaded %d subjects\n', n_subj);

%% =========================================================
%  BUILD FEATURE MATRICES
% =========================================================
% Baseline: [n_subj x 5_levels x n_feat]
B1 = NaN(n_subj, 5, n_feat);
B2 = NaN(n_subj, 5, n_feat);

% Training: [n_subj x n_levels x n_reps x n_feat]
TRAIN = NaN(n_subj, n_levels, n_reps, n_feat);

% Group labels
groups = cell(n_subj, 1);

for si = 1:n_subj
    subj  = valid_subjects{si};
    feats = all_data.(subj).features;
    groups{si} = all_data.(subj).group;

    for li = 1:5
        lv = sprintf('Level%d', li);
        for fi = 1:n_feat
            fn = feature_list{fi};
            if isfield(feats,'Baseline1') && isfield(feats.Baseline1,lv) && isfield(feats.Baseline1.(lv),fn)
                B1(si,li,fi) = feats.Baseline1.(lv).(fn);
            end
            if isfield(feats,'Baseline2') && isfield(feats.Baseline2,lv) && isfield(feats.Baseline2.(lv),fn)
                B2(si,li,fi) = feats.Baseline2.(lv).(fn);
            end
        end
    end

    for ti = 1:n_levels
        lv_key = training_levels{ti};
        for r = 1:n_reps
            rk = sprintf('rep%02d', r);
            for fi = 1:n_feat
                fn = feature_list{fi};
                if isfield(feats,lv_key) && isfield(feats.(lv_key),rk) && isfield(feats.(lv_key).(rk),fn)
                    TRAIN(si,ti,r,fi) = feats.(lv_key).(rk).(fn);
                end
            end
        end
    end
end

is_H   = strcmp(groups,'H');
is_N   = strcmp(groups,'N');
n_H    = sum(is_H);
n_N    = sum(is_N);
col_H  = [0.2 0.4 0.8];
col_N  = [0.8 0.3 0.2];

fprintf('Group H: %d  |  Group N: %d\n', n_H, n_N);

%% =========================================================
%  Q1 — VIOLIN PLOTS: Baseline1 vs Baseline2, per level, H vs N
% =========================================================
fprintf('\nPlotting Q1...\n');
fig_dir_q1 = fullfile(plot_dir,'Q1_Baseline');
if ~exist(fig_dir_q1,'dir'), mkdir(fig_dir_q1); end

for fi = 1:n_feat
    fn = feature_list{fi};

    %% Q1 Plot A: violin per level (5 levels x 4 violins each: B1H B1N B2H B2N)
    figure('Position',[0 0 1600 500],'Visible','on');
    ax1 = axes; hold on;

    x_pos   = [];
    x_labs  = {};
    x_ticks = [];

    for li = 1:5
        b1h = B1(is_H, li, fi);  b1h = b1h(~isnan(b1h));
        b1n = B1(is_N, li, fi);  b1n = b1n(~isnan(b1n));
        b2h = B2(is_H, li, fi);  b2h = b2h(~isnan(b2h));
        b2n = B2(is_N, li, fi);  b2n = b2n(~isnan(b2n));

        % x positions: 4 violins per level, spaced by 1, gap of 2 between levels
        base = (li-1)*6;
        xb1h = base+1; xb1n = base+2; xb2h = base+3; xb2n = base+4;

        plot_violin(xb1h, b1h, col_H, 0.6);
        plot_violin(xb1n, b1n, col_N, 0.6);
        plot_violin(xb2h, b2h, col_H, 0.9);  % lighter = B2
        plot_violin(xb2n, b2n, col_N, 0.9);

        % Level centre label
        x_ticks(end+1) = base + 2.5;
        x_labs{end+1}  = sprintf('L%d', li);
        x_pos = [x_pos xb1h xb1n xb2h xb2n];
    end

    % Legend patches
    % patch(NaN,NaN,col_H,          'DisplayName','H  B1');
    % patch(NaN,NaN,col_H*0.5+0.5,  'DisplayName','H  B2');
    % patch(NaN,NaN,col_N,          'DisplayName','N  B1');
    % patch(NaN,NaN,col_N*0.5+0.5,  'DisplayName','N  B2');
    

    set(gca,'XTick',x_ticks,'XTickLabel',x_labs,'FontSize',9);
    xlabel('Difficulty Level');
    ylabel(strrep(fn,'_',' '));
    title(sprintf('Q1 — Baseline1 vs Baseline2 per level — %s', strrep(fn,'_',' ')));
    grid on; box on;

    % Shade B2 region lightly
    yl = ylim;
    for li = 1:5
        base = (li-1)*6;
        patch([base+2.5 base+4.5 base+4.5 base+2.5], ...
              [yl(1) yl(1) yl(2) yl(2)], [0.9 0.9 0.9], ...
              'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    end
    ylim(yl);

    %saveas(gcf, fullfile(fig_dir_q1, sprintf('Q1A_violin_perLevel_%s.png', fn)));
    %close(gcf);

    %% Q1 Plot B: Mean across all levels — B1 vs B2, H vs N
    figure('Position',[0 0 600 500],'Visible','on');
    hold on;

    % Mean across levels (dim 2) for each subject
    b1h_mean = squeeze(nanmean(B1(is_H,:,fi), 2));
    b1n_mean = squeeze(nanmean(B1(is_N,:,fi), 2));
    b2h_mean = squeeze(nanmean(B2(is_H,:,fi), 2));
    b2n_mean = squeeze(nanmean(B2(is_N,:,fi), 2));

    plot_violin(1, b1h_mean, col_H,       0.6);
    plot_violin(2, b1n_mean, col_N,       0.6);
    plot_violin(4, b2h_mean, col_H*0.5+0.5, 0.9);
    plot_violin(5, b2n_mean, col_N*0.5+0.5, 0.9);

    % Connect paired B1→B2 per subject
    % h_idx = find(is_H); n_idx = find(is_N);
    % for si = 1:n_H
    %     plot([1 4],[b1h_mean(si) b2h_mean(si)],'-','Color',[col_H 0.25],'LineWidth',1);
    % end
    % for si = 1:n_N
    %     plot([2 5],[b1n_mean(si) b2n_mean(si)],'-','Color',[col_N 0.25],'LineWidth',1);
    % end

    set(gca,'XTick',[1.5 4.5],'XTickLabel',{'Baseline1','Baseline2'},'FontSize',10);
    ylabel(strrep(fn,'_',' '));
    title(sprintf('Q1 — Mean baseline (all levels) B1 vs B2\n%s', strrep(fn,'_',' ')));

    % patch(NaN,NaN,col_H,        'DisplayName','H'); 
    % patch(NaN,NaN,col_N,        'DisplayName','N');
    % legend('Location','best');
    % grid on; box on;

    %saveas(gcf, fullfile(fig_dir_q1, sprintf('Q1B_mean_B1vsB2_%s.png', fn)));
    %close(gcf);
end

%% =========================================================
%  Q2 — DIFFICULTY: L1 vs L5 across training reps
%  Violin of all reps pooled, then per-rep comparison
% =========================================================
fprintf('\nPlotting Q2...\n');
fig_dir_q2 = fullfile(plot_dir,'Q2_Difficulty');
if ~exist(fig_dir_q2,'dir'), mkdir(fig_dir_q2); end

for fi = 1:n_feat
    fn = feature_list{fi};

    figure('Position',[0 0 1400 600],'Visible','on');

    %% Q2 subplot 1: violin of ALL reps pooled — L1 vs L5, H vs N
    subplot(1,2,1); hold on;

    % Pool all 10 reps per subject → one value per subject per level
    l1h = squeeze(nanmean(TRAIN(is_H,1,:,fi), 3));  % [n_H x 1]
    l1n = squeeze(nanmean(TRAIN(is_N,1,:,fi), 3));
    l5h = squeeze(nanmean(TRAIN(is_H,5,:,fi), 3));
    l5n = squeeze(nanmean(TRAIN(is_N,5,:,fi), 3));

    plot_violin(1, l1h, col_H, 0.6);
    plot_violin(2, l1n, col_N, 0.6);
    plot_violin(4, l5h, col_H, 0.8);
    plot_violin(5, l5n, col_N, 0.8);

    % Paired lines L1→L5
    % for si = 1:n_H, plot([1 4],[l1h(si) l5h(si)],'-','Color',[col_H 0.2],'LineWidth',0.8); end
    % for si = 1:n_N, plot([2 5],[l1n(si) l5n(si)],'-','Color',[col_N 0.2],'LineWidth',0.8); end

    set(gca,'XTick',[1.5 4.5],'XTickLabel',{'Level 1','Level 5'},'FontSize',10);
    ylabel(strrep(fn,'_',' '));
    title('L1 vs L5 — mean across reps');
    patch(NaN,NaN,col_H,'DisplayName','H'); patch(NaN,NaN,col_N,'DisplayName','N');
    

    %% Q2 subplot 2: per-rep trajectory L1 vs L5, H vs N
    subplot(1,2,2); hold on;

    % Mean ± SEM across subjects for each rep
    m_l1h = nanmean(squeeze(TRAIN(is_H,1,:,fi)),1);
    s_l1h = nanstd( squeeze(TRAIN(is_H,1,:,fi)),0,1) ./ sqrt(n_H);
    m_l1n = nanmean(squeeze(TRAIN(is_N,1,:,fi)),1);
    s_l1n = nanstd( squeeze(TRAIN(is_N,1,:,fi)),0,1) ./ sqrt(n_N);
    m_l5h = nanmean(squeeze(TRAIN(is_H,5,:,fi)),1);
    s_l5h = nanstd( squeeze(TRAIN(is_H,5,:,fi)),0,1) ./ sqrt(n_H);
    m_l5n = nanmean(squeeze(TRAIN(is_N,5,:,fi)),1);
    s_l5n = nanstd( squeeze(TRAIN(is_N,5,:,fi)),0,1) ./ sqrt(n_N);

    x = 1:n_reps;
    plot_mean_sem_line(x, m_l1h, s_l1h, col_H,       '-',  'H L1');
    plot_mean_sem_line(x, m_l1n, s_l1n, col_N,       '-',  'N L1');
    plot_mean_sem_line(x, m_l5h, s_l5h, col_H*0.5,   '--', 'H L5');
    plot_mean_sem_line(x, m_l5n, s_l5n, col_N*0.5,   '--', 'N L5');

    set(gca,'XTick',1:n_reps); xlabel('Repetition');
    ylabel(strrep(fn,'_',' '));
    title('Learning curve: L1 (solid) vs L5 (dashed)');
    % legend('Location','best','FontSize',8); grid on; box on;

    linkaxes(findobj(gcf,'Type','axes'),'y');
    sgtitle(sprintf('Q2 — Difficulty effect — %s', strrep(fn,'_',' ')), 'FontSize',11);
    %saveas(gcf, fullfile(fig_dir_q2, sprintf('Q2_L1vsL5_%s.png', fn)));
    %close(gcf);
end

%% Q3 — LEARNING CURVE: all 50 reps (5 levels x 10 reps)
%  Plot 1: overall mean across subjects, all levels on x-axis
%  Plot 2: same split by group H vs N

fprintf('\nPlotting Q3...\n');
fig_dir_q3 = fullfile(plot_dir,'Q3_LearningCurve');
if ~exist(fig_dir_q3,'dir'), mkdir(fig_dir_q3); end

for fi = 1:n_feat
    fn = feature_list{fi};

    % Y axis limits — slope needs wider range
    if strcmp(fn, 'scl_slope')
        y_lim = [-900 100];
    else
        y_lim = [0 1];
    end

    figure('Position',[0 0 1800 700],'Visible','on');

    for ti = 1:n_levels

        % --- Top row: all subjects ---
        ax_top = subplot(2, n_levels, ti);
        hold on;

        % Individual subject lines (thin, transparent)
        for si = 1:n_subj
            vals = squeeze(TRAIN(si, ti, :, fi));
            valid = isfinite(vals);
            if sum(valid) < 2, continue; end
            if is_H(si), lc = [col_H 0.15];
            else,        lc = [col_N 0.15]; end
            plot(find(valid), vals(valid), '-', 'Color', lc, 'LineWidth', 0.8);
        end

        % Group means
        m_all = nanmean(squeeze(TRAIN(:,ti,:,fi)), 1);   % [1 x n_reps]
        s_all = nanstd( squeeze(TRAIN(:,ti,:,fi)), 0,1) ./ ...
                sqrt(sum(isfinite(squeeze(TRAIN(:,ti,:,fi))),1));
        plot_mean_sem_line(1:n_reps, m_all, s_all, [0.3 0.3 0.3], '-', 'All');

        set(gca,'XTick',1:2:n_reps,'FontSize',7);
        ylim(y_lim);
        if ti == 1, ylabel(strrep(fn,'_',' '),'FontSize',8); end
        title(sprintf('L%d', ti), 'FontSize',9);
        % grid on; box on;
        % if ti == n_levels
        %     legend('Location','best','FontSize',6);
        % end

        % --- Bottom row: H vs N ---
        ax_bot = subplot(2, n_levels, n_levels + ti);
        hold on;

        m_H = nanmean(squeeze(TRAIN(is_H,ti,:,fi)), 1);
        s_H = nanstd( squeeze(TRAIN(is_H,ti,:,fi)), 0,1) ./ sqrt(n_H);
        m_N = nanmean(squeeze(TRAIN(is_N,ti,:,fi)), 1);
        s_N = nanstd( squeeze(TRAIN(is_N,ti,:,fi)), 0,1) ./ sqrt(n_N);

        plot_mean_sem_line(1:n_reps, m_H, s_H, col_H, '-', 'H');
        plot_mean_sem_line(1:n_reps, m_N, s_N, col_N, '-', 'N');

        set(gca,'XTick',1:2:n_reps,'FontSize',7);
        xlabel('Rep','FontSize',7);
        ylim(y_lim);
        if ti == 1, ylabel(strrep(fn,'_',' '),'FontSize',8); end
        grid on; box on;
        % if ti == n_levels
        %     legend('Location','best','FontSize',6);
        % end
    end

    sgtitle(sprintf('Q3 — Learning curve per level — %s', strrep(fn,'_',' ')), ...
            'FontSize',11);
    % saveas(gcf, fullfile(fig_dir_q3, sprintf('Q3_%s.png', fn)));
    % close(gcf);
end

fprintf('\n=== L3 Analysis complete ===\n');
fprintf('Plots saved to: %s\n', plot_dir);


%% HELPER FUNCTIONS

function plot_violin(x_center, data, col, alpha)
% REMOVED: filled/outline toggle (was causing line confusion)
% REMOVED: all connecting lines
    % data = clean(data);
    if numel(data) < 3
        scatter(x_center*ones(size(data)), data, 30, col, 'filled', ...
                'MarkerFaceAlpha', alpha);
        return;
    end

    % KDE violin shape
    [f, xi] = ksdensity(data, 'NumPoints', 100);
    f = f / max(f) * 0.4;
    fill([x_center+f fliplr(x_center-f)], [xi fliplr(xi)], col, 'FaceAlpha', alpha*0.5, 'EdgeColor', col, 'LineWidth', 0.8);

    % IQR box
    q25 = quantile(data, 0.25);
    q75 = quantile(data, 0.75);
    med = median(data);
    rectangle('Position',[x_center-0.08, q25, 0.16, q75-q25],'FaceColor',[col alpha*0.6], 'LineWidth',0.5);
    plot([x_center-0.12 x_center+0.12],[med med],'k-','LineWidth',2);

    % Whiskers
    lo = max(min(data), q25 - 1.5*(q75-q25));
    hi = min(max(data), q75 + 1.5*(q75-q25));
    plot([x_center x_center],[lo q25],'k-','LineWidth',0.8);
    plot([x_center x_center],[q75 hi],'k-','LineWidth',0.8);

    % Scatter — NO connecting lines, just points with jitter
    jitter = (rand(numel(data),1)-0.5) * 0.15;
    scatter(x_center + jitter, data, 20, col, 'filled','MarkerFaceAlpha', 0.6, 'MarkerEdgeColor','none');
end

function plot_mean_sem_line(x, m, s, col, ls, label)
% Plots mean line with SEM shading
% x:     x axis vector
% m, s:  mean and SEM vectors (same size as x)
% col:   [r g b]
% ls:    line style string e.g. '-' or '--'
% label: legend entry

    valid = ~isnan(m) & ~isnan(s);
    xv = x(valid); mv = m(valid); sv = s(valid);
    if isempty(xv), return; end

    fill([xv fliplr(xv)], [mv+sv fliplr(mv-sv)], col, ...
         'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility','off');
    plot(xv, mv, ls, 'Color', col, 'LineWidth', 2, ...
         'MarkerFaceColor', col, 'DisplayName', label);
end