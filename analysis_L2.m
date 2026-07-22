%% analysis_L2_within_subject.m
% For each subject, compares:
%   - Baseline1 vs Baseline2 (per level)
%   - Test1 vs Test2
%   - Rest1 vs Rest2
%   - Training learning curves (per level)
%   - Baseline vs Test (did training change arousal?)

clear; clc; close all;

cfg = config();

plot_dir = fullfile(cfg.output_root, 'L2_plots');
if ~exist(plot_dir, 'dir'), mkdir(plot_dir); end

feature_list = {'scl_mean','scl_slope','scr_n_peaks','scr_mean_amp',...
                'scr_max_amp','scr_rate','scr_auc','gsr_mean','gsr_std','gsr_rms'};
n_feat = numel(feature_list);

training_levels = {'levelL1','levelL2','levelL3','levelL4','levelL5'};
n_levels = numel(training_levels);
n_reps   = cfg.n_training_reps;

%% LOAD ALL SUBJECTS INTO ONE BIG STRUCT

all_data = struct();
valid_subjects = {};

for si = 1:numel(cfg.all_subjects)
    subj     = cfg.all_subjects{si};
    mat_path = fullfile(cfg.output_root, sprintf('%s_L1_features.mat', subj));
    if ~isfile(mat_path)
        fprintf('SKIP %s — no mat file\n', subj);
        continue;
    end
    d = load(mat_path);
    all_data.(subj) = d.results;
    valid_subjects{end+1} = subj;
    fprintf('Loaded %s (group %s)\n', subj, d.results.group);
end

n_subj = numel(valid_subjects);
fprintf('\nLoaded %d subjects\n', n_subj);

%% =========================================================
%  BUILD FEATURE MATRICES
%  These are the core data arrays used for all plots/stats
% =========================================================

% --- Baseline: [n_subj x n_levels x n_feat] for B1 and B2 ---
B1 = NaN(n_subj, 5, n_feat);
B2 = NaN(n_subj, 5, n_feat);

% --- Test: [n_subj x n_feat] for T1 and T2 ---
T1 = NaN(n_subj, n_feat);
T2 = NaN(n_subj, n_feat);

% --- Rest: [n_subj x n_feat] for R1 and R2 ---
R1 = NaN(n_subj, n_feat);
R2 = NaN(n_subj, n_feat);

% --- Training: [n_subj x n_levels x n_reps x n_feat] ---
TRAIN = NaN(n_subj, n_levels, n_reps, n_feat);

% --- Group labels ---
groups = cell(n_subj, 1);

for si = 1:n_subj
    subj  = valid_subjects{si};
    feats = all_data.(subj).features;
    groups{si} = all_data.(subj).group;

    % Baselines
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

    % Tests
    for fi = 1:n_feat
        fn = feature_list{fi};
        if isfield(feats,'Test1') && isfield(feats.Test1,'full_session') && isfield(feats.Test1.full_session,fn)
            T1(si,fi) = feats.Test1.full_session.(fn);
        end
        if isfield(feats,'Test2') && isfield(feats.Test2,'full_session') && isfield(feats.Test2.full_session,fn)
            T2(si,fi) = feats.Test2.full_session.(fn);
        end
    end

    % Resting
    for fi = 1:n_feat
        fn = feature_list{fi};
        if isfield(feats,'resting') && isfield(feats.resting,'r1') && isfield(feats.resting.r1,fn)
            R1(si,fi) = feats.resting.r1.(fn);
        end
        if isfield(feats,'resting') && isfield(feats.resting,'r2') && isfield(feats.resting.r2,fn)
            R2(si,fi) = feats.resting.r2.(fn);
        end
    end

    % Training
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

% Group masks
is_H = strcmp(groups, 'H');
is_N = strcmp(groups, 'N');
fprintf('Group H: %d subjects\n', sum(is_H));
fprintf('Group N: %d subjects\n', sum(is_N));

%% =========================================================
%  PLOT 1: Baseline1 vs Baseline2 — all subjects overlaid
%  One figure per feature, subjects as thin lines,
%  group mean as thick line
% =========================================================
fig_dir_b = fullfile(plot_dir, 'Baseline_B1vsB2');
if ~exist(fig_dir_b,'dir'), mkdir(fig_dir_b); end

for fi = 1:n_feat
    fn = feature_list{fi};
    figure('Position',[0 0 1000 500],'Visible','on');

    % Left panel: all subjects
    subplot(1,2,1); hold on;
    for si = 1:n_subj
        b1v = squeeze(B1(si,:,fi));
        b2v = squeeze(B2(si,:,fi));
        if strcmp(groups{si},'H'), col_b1=[0.4 0.7 1]; col_b2=[0.1 0.3 0.8];
        else,                      col_b1=[1 0.7 0.4]; col_b2=[0.8 0.3 0.1]; end
        plot(1:5, b1v, '-', 'Color',[col_b1 0.3], 'LineWidth',0.8);
        plot(1:5, b2v, '--','Color',[col_b2 0.3], 'LineWidth',0.8);
    end
    % Group means
    plot(1:5, nanmean(B1(is_H,:,fi),1), 'b-',  'LineWidth',2.5, 'DisplayName','H B1');
    plot(1:5, nanmean(B2(is_H,:,fi),1), 'b--', 'LineWidth',2.5, 'DisplayName','H B2');
    plot(1:5, nanmean(B1(is_N,:,fi),1), 'r-',  'LineWidth',2.5, 'DisplayName','N B1');
    plot(1:5, nanmean(B2(is_N,:,fi),1), 'r--', 'LineWidth',2.5, 'DisplayName','N B2');
    set(gca,'XTick',1:5,'XTickLabel',{'L1','L2','L3','L4','L5'});
    xlabel('Difficulty Level'); ylabel(strrep(fn,'_',' '));
    title('B1 (solid) vs B2 (dashed)'); legend('Location','best','FontSize',7); grid on;

    % Right panel: B2 - B1 difference (training effect on baseline)
    subplot(1,2,2); hold on;
    diff_H = squeeze(B2(is_H,:,fi) - B1(is_H,:,fi));
    diff_N = squeeze(B2(is_N,:,fi) - B1(is_N,:,fi));
    % Individual subjects
    for si = 1:sum(is_H)
        plot(1:5, diff_H(si,:), '-', 'Color',[0.4 0.4 1 0.2], 'LineWidth',0.8);
    end
    for si = 1:sum(is_N)
        plot(1:5, diff_N(si,:), '-', 'Color',[1 0.4 0.4 0.2], 'LineWidth',0.8);
    end
    % Mean + SEM shading
    plot_mean_sem(1:5, diff_H, [0.2 0.2 0.9], 'H');
    plot_mean_sem(1:5, diff_N, [0.9 0.2 0.2], 'N');
    yline(0, 'k--', 'LineWidth', 1);
    set(gca,'XTick',1:5,'XTickLabel',{'L1','L2','L3','L4','L5'});
    xlabel('Difficulty Level'); ylabel('B2 - B1 (change)');
    title('Training effect on baseline (B2-B1)'); legend('Location','best'); grid on;

    sgtitle(sprintf('Baseline comparison — %s', strrep(fn,'_',' ')), 'FontSize',11);
    %saveas(gcf, fullfile(fig_dir_b, sprintf('B1vsB2_%s.png', fn)));
    %close(gcf);
end

%% =========================================================
%  PLOT 2: Test1 vs Test2 — bar chart with individual points
% =========================================================
fig_dir_t = fullfile(plot_dir, 'Test_T1vsT2');
if ~exist(fig_dir_t,'dir'), mkdir(fig_dir_t); end

figure('Position',[0 0 1400 900],'Visible','on');
for fi = 1:n_feat
    fn = feature_list{fi};
    subplot(2,5,fi); hold on;

    % Group means
    groups_labels = {'H T1','H T2','N T1','N T2'};
    vals = [nanmean(T1(is_H,fi)), nanmean(T2(is_H,fi)), ...
            nanmean(T1(is_N,fi)), nanmean(T2(is_N,fi))];
    errs = [nanstd(T1(is_H,fi))/sqrt(sum(is_H)), nanstd(T2(is_H,fi))/sqrt(sum(is_H)), ...
            nanstd(T1(is_N,fi))/sqrt(sum(is_N)), nanstd(T2(is_N,fi))/sqrt(sum(is_N))];

    b = bar([1 2 4 5], vals, 'FaceColor','flat');
    b.CData = [0.3 0.5 0.9; 0.1 0.2 0.7; 0.9 0.5 0.3; 0.7 0.2 0.1];
    errorbar([1 2 4 5], vals, errs, 'k.', 'LineWidth', 1.2);

    % Individual points
    jitter = 0.15;
    scatter(ones(sum(is_H),1)  + randn(sum(is_H),1)*jitter, T1(is_H,fi), 20, [0.3 0.5 0.9], 'filled', 'MarkerFaceAlpha', 0.5);
    scatter(2*ones(sum(is_H),1)+ randn(sum(is_H),1)*jitter, T2(is_H,fi), 20, [0.1 0.2 0.7], 'filled', 'MarkerFaceAlpha', 0.5);
    scatter(4*ones(sum(is_N),1)+ randn(sum(is_N),1)*jitter, T1(is_N,fi), 20, [0.9 0.5 0.3], 'filled', 'MarkerFaceAlpha', 0.5);
    scatter(5*ones(sum(is_N),1)+ randn(sum(is_N),1)*jitter, T2(is_N,fi), 20, [0.7 0.2 0.1], 'filled', 'MarkerFaceAlpha', 0.5);

    % Connect paired T1-T2 for each subject
    for si = 1:sum(is_H), plot([1 2],[T1(is_H,fi),T2(is_H,fi)],'-','Color',[0.2 0.3 0.8 0.3],'LineWidth',0.8); end
    for si = 1:sum(is_N), plot([4 5],[T1(is_N,fi),T2(is_N,fi)],'-','Color',[0.8 0.3 0.2 0.3],'LineWidth',0.8); end

    set(gca,'XTick',[1.5 4.5],'XTickLabel',{'H','N'});
    ylabel(strrep(fn,'_',' ')); title(strrep(fn,'_',' '),'FontSize',8); grid on;
end
sgtitle('Test1 vs Test2 — H (blue) vs N (red)  |  light=T1  dark=T2', 'FontSize',11);
%saveas(gcf, fullfile(fig_dir_t, 'Test1vsTest2_all_features.png'));
%close(gcf);

%% =========================================================
%  PLOT 3: Rest1 vs Rest2
% =========================================================
fig_dir_r = fullfile(plot_dir, 'Rest_R1vsR2');
if ~exist(fig_dir_r,'dir'), mkdir(fig_dir_r); end

figure('Position',[0 0 1400 900],'Visible','on');
for fi = 1:n_feat
    fn = feature_list{fi};
    subplot(2,5,fi); hold on;

    vals = [nanmean(R1(is_H,fi)), nanmean(R2(is_H,fi)), ...
            nanmean(R1(is_N,fi)), nanmean(R2(is_N,fi))];
    errs = [nanstd(R1(is_H,fi))/sqrt(sum(is_H)), nanstd(R2(is_H,fi))/sqrt(sum(is_H)), ...
            nanstd(R1(is_N,fi))/sqrt(sum(is_N)), nanstd(R2(is_N,fi))/sqrt(sum(is_N))];

    b = bar([1 2 4 5], vals, 'FaceColor','flat');
    b.CData = [0.3 0.5 0.9; 0.1 0.2 0.7; 0.9 0.5 0.3; 0.7 0.2 0.1];
    errorbar([1 2 4 5], vals, errs, 'k.', 'LineWidth', 1.2);

    % Individual points + lines
    scatter(ones(sum(is_H),1),  R1(is_H,fi), 25, [0.3 0.5 0.9],'filled','MarkerFaceAlpha',0.6);
    scatter(2*ones(sum(is_H),1),R2(is_H,fi), 25, [0.1 0.2 0.7],'filled','MarkerFaceAlpha',0.6);
    scatter(4*ones(sum(is_N),1),R1(is_N,fi), 25, [0.9 0.5 0.3],'filled','MarkerFaceAlpha',0.6);
    scatter(5*ones(sum(is_N),1),R2(is_N,fi), 25, [0.7 0.2 0.1],'filled','MarkerFaceAlpha',0.6);

    h_idx = find(is_H); n_idx = find(is_N);
    for si = 1:numel(h_idx), plot([1 2],[R1(h_idx(si),fi) R2(h_idx(si),fi)],'-','Color',[0.2 0.3 0.8 0.3],'LineWidth',0.8); end
    for si = 1:numel(n_idx), plot([4 5],[R1(n_idx(si),fi) R2(n_idx(si),fi)],'-','Color',[0.8 0.3 0.2 0.3],'LineWidth',0.8); end

    set(gca,'XTick',[1.5 4.5],'XTickLabel',{'H','N'});
    ylabel(strrep(fn,'_',' ')); title(strrep(fn,'_',' '),'FontSize',8); grid on;
end
sgtitle('Rest1 (pre) vs Rest2 (post) — H (blue) vs N (red)', 'FontSize',11);
%saveas(gcf, fullfile(fig_dir_r, 'Rest1vsRest2_all_features.png'));
%close(gcf);

%% =========================================================
%  PLOT 4: Training learning curves — group mean per level
%  One figure per feature showing all 5 levels x 2 groups
% =========================================================
fig_dir_lc = fullfile(plot_dir, 'Training_LearningCurves');
if ~exist(fig_dir_lc,'dir'), mkdir(fig_dir_lc); end

level_colors = lines(n_levels);

for fi = 1:n_feat
    fn = feature_list{fi};
    figure('Position',[0 0 1400 500],'Visible','on');

    for gi = 1:2
        if gi==1, gmask=is_H; gtitle='Group H (Haptic)';
        else,     gmask=is_N; gtitle='Group N (No haptic)'; end

        subplot(1,2,gi); hold on;
        for ti = 1:n_levels
            % [n_subj_in_group x n_reps]
            lc = squeeze(TRAIN(gmask, ti, :, fi));
            if size(lc,1)==1, lc=lc'; end  % handle single subject

            m  = nanmean(lc, 1);
            s  = nanstd(lc,  0, 1) ./ sqrt(sum(~isnan(lc),1));

            % Shade SEM
            valid = ~isnan(m);
            x_v   = find(valid);
            fill([x_v fliplr(x_v)], ...
                 [m(valid)+s(valid) fliplr(m(valid)-s(valid))], ...
                 level_colors(ti,:), 'FaceAlpha',0.15, 'EdgeColor','none');
            plot(x_v, m(valid), 'o-', 'Color', level_colors(ti,:), ...
                 'LineWidth', 2, 'MarkerFaceColor', level_colors(ti,:), ...
                 'DisplayName', sprintf('L%d',ti));
        end
        set(gca,'XTick',1:n_reps);
        xlabel('Repetition'); ylabel(strrep(fn,'_',' '));
        title(gtitle); legend('Location','best','FontSize',7); grid on;
    end
    sgtitle(sprintf('Training learning curves — %s', strrep(fn,'_',' ')), 'FontSize',11);
    %saveas(gcf, fullfile(fig_dir_lc, sprintf('LearningCurve_%s.png', fn)));
    %close(gcf);
end

%% =========================================================
%  PLOT 5: Full experiment timeline per subject
%  Shows: Rest1 → B1 → Training → B2 → Test → Rest2
%  as a single feature value timeline to see the arc
% =========================================================
fig_dir_tl = fullfile(plot_dir, 'Timeline');
if ~exist(fig_dir_tl,'dir'), mkdir(fig_dir_tl); end

for fi = 1:n_feat
    fn = feature_list{fi};
    figure('Position',[0 0 1600 600],'Visible','on');

    for gi = 1:2
        if gi==1, gmask=is_H; gtitle='Group H'; col=[0.2 0.4 0.8];
        else,     gmask=is_N; gtitle='Group N'; col=[0.8 0.3 0.2]; end

        subplot(1,2,gi); hold on;
        gidx = find(gmask);

        % Build timeline points:
        % Rest1, B1_mean(L1-L5), Train_L1_mean, ..., Train_L5_mean, B2_mean, Test1, Test2, Rest2
        tl_labels = {'Rest1','B1_L1','B1_L2','B1_L3','B1_L4','B1_L5',...
                     'Tr_L1','Tr_L2','Tr_L3','Tr_L4','Tr_L5',...
                     'B2_L1','B2_L2','B2_L3','B2_L4','B2_L5',...
                     'Test1','Test2','Rest2'};
        n_tl = numel(tl_labels);
        tl_mat = NaN(numel(gidx), n_tl);

        for si = 1:numel(gidx)
            sii = gidx(si);
            tl_mat(si,1)    = R1(sii,fi);
            tl_mat(si,2:6)  = B1(sii,:,fi);
            for ti = 1:n_levels
                tl_mat(si,6+ti) = nanmean(squeeze(TRAIN(sii,ti,:,fi)));
            end
            tl_mat(si,12:16) = B2(sii,:,fi);
            tl_mat(si,17)    = T1(sii,fi);
            tl_mat(si,18)    = T2(sii,fi);
            tl_mat(si,19)    = R2(sii,fi);
        end

        % Individual subjects (thin)
        for si = 1:numel(gidx)
            plot(1:n_tl, tl_mat(si,:), '-', 'Color',[col 0.2], 'LineWidth',0.8);
        end

        % Group mean + SEM
        m = nanmean(tl_mat,1);
        s = nanstd(tl_mat,0,1) ./ sqrt(sum(~isnan(tl_mat),1));
        valid = ~isnan(m);
        x_v = find(valid);
        fill([x_v fliplr(x_v)],[m(valid)+s(valid) fliplr(m(valid)-s(valid))], ...
             col,'FaceAlpha',0.2,'EdgeColor','none');
        plot(x_v, m(valid), 'o-','Color',col,'LineWidth',2.5,'MarkerFaceColor',col);

        % Add divider lines between phases
        xline(1.5,'k:','LineWidth',1);   % after Rest1
        xline(6.5,'k:','LineWidth',1);   % after B1
        xline(11.5,'k:','LineWidth',1);  % after Training
        xline(16.5,'k:','LineWidth',1);  % after B2
        xline(18.5,'k:','LineWidth',1);  % after Tests

        % Phase labels
        text(1,   max(m(valid))*1.05,'Rest1',  'FontSize',7,'HorizontalAlignment','center');
        text(4,   max(m(valid))*1.05,'Baseline1','FontSize',7,'HorizontalAlignment','center');
        text(9,   max(m(valid))*1.05,'Training','FontSize',7,'HorizontalAlignment','center');
        text(14,  max(m(valid))*1.05,'Baseline2','FontSize',7,'HorizontalAlignment','center');
        text(17.5,max(m(valid))*1.05,'Tests',   'FontSize',7,'HorizontalAlignment','center');
        text(19,  max(m(valid))*1.05,'Rest2',   'FontSize',7,'HorizontalAlignment','center');

        set(gca,'XTick',1:n_tl,'XTickLabel',tl_labels,'XTickLabelRotation',45,'FontSize',7);
        ylabel(strrep(fn,'_',' ')); title(gtitle); grid on;
    end
    sgtitle(sprintf('Experiment timeline — %s', strrep(fn,'_',' ')), 'FontSize',11);
    %saveas(gcf, fullfile(fig_dir_tl, sprintf('Timeline_%s.png', fn)));
    %%close(gcf);
end

fprintf('\n=== L2 Analysis complete ===\n');
fprintf('Plots saved to: %s\n', plot_dir);

%% =========================================================
%  HELPER FUNCTION
% =========================================================
function plot_mean_sem(x, data, col, label)
% data: [n_subjects x n_points], NaN = missing
    if size(data,1) == 1, data = data'; end
    m = nanmean(data, 1);
    s = nanstd(data,  0, 1) ./ sqrt(sum(~isnan(data), 1));
    valid = ~isnan(m);
    x_v = x(valid);
    fill([x_v fliplr(x_v)], ...
         [m(valid)+s(valid) fliplr(m(valid)-s(valid))], ...
         col, 'FaceAlpha', 0.2, 'EdgeColor', 'none');
    plot(x_v, m(valid), 'o-', 'Color', col, 'LineWidth', 2.5, ...
         'MarkerFaceColor', col, 'DisplayName', label);
end