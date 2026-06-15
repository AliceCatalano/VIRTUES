%% VIRTUES -- Duration Violin Plots (H vs N)
%
% Generates two sets of plots from DurationLevels (nSubjects x nLevels x nReps):
%
%   PLOT SET 1 -- Per-level average duration
%       One figure per level. Two violins per figure: N group and H group.
%       Each data point = mean duration across all 10 reps for that subject.
%
%   PLOT SET 2 -- First 3 vs last 3 repetitions
%       One figure per level. X-axis: "First 3 reps" | "Last 3 reps".
%       At each x-position: two violins, one for N and one for H.
%
% HOW TO USE
% ----------
%   Either run after DurationMatrices.m (matrices already in workspace),
%   or run standalone (it will load the .mat files from SAVE_PATH).
clear; close all

SAVE_PATH    = '/home/acatalano/Desktop/Virtues';
load('DurationLevels.mat');
load('DurationDone.mat');
load( 'DurationBaseline.mat');   % DurationBaseline
load('DurationDone.mat');        % participants_done

% Colours (consistent across all plots)
COLOR_N = [55  138 221] / 255;   % blue  -- Non-haptic
COLOR_H = [212  83 126] / 255;   % pink  -- Haptic
nLevels  = 5;
YLIM_DUR = [0, 180];
participants = {'s02N','s05N','s07N','s09N','s11N','s14N','s15H', 's16N','s18N', 's20N','s22N','s24N','s27N','s28N','s30N','s32N','s34N','s36N','s37N','s39N','s42N','s43N','s44N','s46N','s48N'...
                's03H','s04H','s06H','s08H','s10H','s12H','s13H', 's17H','s19H', 's21H','s23H','s25H','s26H','s29H','s31H','s33H','s35H','s38H','s40H','s41H','s45H','s47H'};

%% LOAD DATA
nSubj      = numel(participants);
%nLevels    = size(DurationLevels, 2);
nReps      = size(DurationLevels, 3);

% Split participant indices into N and H groups based on ID suffix
idx_N = find(cellfun(@(s) s(end) == 'N', participants));
idx_H = find(cellfun(@(s) s(end) == 'H', participants));

fprintf('N group: %d subjects\n', numel(idx_N));
fprintf('H group: %d subjects\n', numel(idx_H));

%% Plots Baseline
for lv = 1:nLevels

    col_bl1 = lv;              % Baseline 1, level lv
    col_bl2 = lv + nLevels;   % Baseline 2, level lv

    % Each subject's single duration for this level at each baseline
    bl1_N = DurationBaseline(idx_N, col_bl1);
    bl1_H = DurationBaseline(idx_H, col_bl1);
    bl2_N = DurationBaseline(idx_N, col_bl2);
    bl2_H = DurationBaseline(idx_H, col_bl2);

    % Group cell array: {N_bl1, H_bl1, N_bl2, H_bl2}
    groups = {bl1_N, bl1_H, bl2_N, bl2_H};

    fig = figure('Name', sprintf('Baseline Duration -- Level %d', lv), ...
                 'Position', [100 + (lv-1)*30, 150 + (lv-1)*30, 550, 500]);
    ax = axes(fig);
    hold(ax, 'on');

    groups = {bl1_N, bl1_H, bl2_N, bl2_H};          % 4 cells --> grouped layout
    violin_plot(ax, groups, {'Bl1', 'Bl2'}, {COLOR_N, COLOR_H});

    ylabel(ax, 'Duration (s)');
    title(ax, sprintf('Level %d — baseline completion time', lv));
    ylim(ax, YLIM_DUR);
    grid(ax, 'on');
    ax.GridColor     = [0.85 0.85 0.85];
    ax.GridAlpha     = 1;
    ax.GridLineStyle = '--';
    ax.Box           = 'off';

    add_legend(ax, COLOR_N, COLOR_H);
end

fprintf('\nAll baseline plots generated.\n');
%% PLOT SET 1 -- Average completion time per level (one figure per level)

for lv = 1:nLevels

    % Each subject's mean duration across all reps for this level
    lv_data = squeeze(DurationLevels(:, lv, :));   % nSubj x nReps
    subj_mean = mean(lv_data, 2, 'omitnan');        % nSubj x 1

    data_N = subj_mean(idx_N);
    data_H = subj_mean(idx_H);
    
    fig = figure('Name', sprintf('Avg Duration -- Level %d', lv), ...
                 'Position', [100 + (lv-1)*30, 150 + (lv-1)*30, 500, 500]);
    ax = axes(fig);
    hold(ax, 'on');

    violin_pair(ax, {data_N, data_H}, {'Non-haptic (N)', 'Haptic (H)'}, {COLOR_N, COLOR_H});
    hold on; 

    ylabel(ax, 'Mean duration (s)');
    title(ax, sprintf('Level %d — average completion time', lv));
    ylim(ax, YLIM_DUR);
    grid(ax, 'on');
    ax.GridColor       = [0.85 0.85 0.85];
    ax.GridAlpha       = 1;
    ax.GridLineStyle   = '--';
    ax.Box             = 'off';

    add_legend(ax, COLOR_N, COLOR_H);
end

%% PLOT SET 2 -- First 3 vs last 3 reps, H vs N (one figure per level)

for lv = 1:nLevels

    lv_data = squeeze(DurationLevels(:, lv, :));   % nSubj x nReps

    first3_mean = mean(lv_data(:, 1:3),      2, 'omitnan');
    last3_mean  = mean(lv_data(:, end-2:end), 2, 'omitnan');

    groups = {
        first3_mean(idx_N), first3_mean(idx_H), ...
        last3_mean(idx_N),  last3_mean(idx_H)
    };
    labels = {'First 3 reps', 'Last 3 reps'};

    fig = figure('Name', sprintf('First3 vs Last3 -- Level %d', lv), ...
                 'Position', [200 + (lv-1)*30, 100 + (lv-1)*30, 600, 500]);
    ax = axes(fig);
    hold(ax, 'on');

    violin_pair_grouped(ax, groups, labels, {COLOR_N, COLOR_H});

    ylabel(ax, 'Mean duration (s)');
    title(ax, sprintf('Level %d — first 3 vs last 3 repetitions', lv));
    ylim(ax, YLIM_DUR);
    grid(ax, 'on');
    ax.GridColor       = [0.85 0.85 0.85];
    ax.GridAlpha       = 1;
    ax.GridLineStyle   = '--';
    ax.Box             = 'off';

    add_legend(ax, COLOR_N, COLOR_H);
end

fprintf('\nAll plots generated.\n');

%% LOCAL HELPER FUNCTIONS

function violin_plot(ax, groups, outer_labels, colors)
% Universal dispatcher.
%
% CASE A -- Baseline or First3/Last3  (grouped: 2 outer ticks, 2 violins each)
%   groups      : {N_pos1, H_pos1, N_pos2, H_pos2}
%   outer_labels: {'Bl1','Bl2'}  OR  {'First 3 reps','Last 3 reps'}
%   colors      : {COLOR_N, COLOR_H}
%
% CASE B -- Per-level average  (one violin per tick)
%   groups      : {data_N, data_H}
%   outer_labels: {'Non-haptic (N)', 'Haptic (H)'}
%   colors      : {COLOR_N, COLOR_H}
%
% Detection rule:
%   numel(groups) == 4  --> grouped layout (Case A)
%   numel(groups) == 2  --> simple layout  (Case B)

    if numel(groups) == 4
        % ---- Case A: grouped (Bl1/Bl2 or First3/Last3) ------------------
        offsets = [-0.22, 0.22];   % N left of tick, H right of tick
        x_outer = [1, 2];

        for g = 1:2                % outer positions
            for h = 1:2            % N=1, H=2
                idx  = (g-1)*2 + h;
                xpos = x_outer(g) + offsets(h);
                draw_violin(ax, groups{idx}, xpos, colors{h}, 0.35);
            end
        end

        ax.XTick      = x_outer;
        ax.XTickLabel = outer_labels;
        ax.XLim       = [0.5, 2.5];

    elseif numel(groups) == 2
        % ---- Case B: one violin per group --------------------------------
        for k = 1:2
            draw_violin(ax, groups{k}, k, colors{k}, 0.35);
        end

        ax.XTick      = [1, 2];
        ax.XTickLabel = outer_labels;
        ax.XLim       = [0.5, 2.5];

    else
        error('violin_plot: groups must have 2 or 4 cells.');
    end

    ax.FontSize = 11;
end

function draw_violin(ax, data, x_center, color, half_width)
% Single violin + IQR box + median marker at x_center.

    if nargin < 5, half_width = 0.35; end

    data = data(~isnan(data));

    if numel(data) < 2
        if numel(data) == 1
            scatter(ax, x_center, data, 60, ...
                    'MarkerFaceColor', color, 'MarkerEdgeColor', color, ...
                    'MarkerFaceAlpha', 0.7);
        end
        return
    end

    if numel(data) < 3
        med = median(data);
        plot(ax, [x_center x_center], [min(data) max(data)], ...
             '-', 'Color', color, 'LineWidth', 1.5);
        plot(ax, x_center, med, 's', ...
             'Color', color, 'MarkerFaceColor', color, 'MarkerSize', 6);
        return
    end

    % ---- Dynamic support: add 5% padding around the data range ----------
    d_min = min(data);
    d_max = max(data);
    pad   = max((d_max - d_min) * 0.05, 1);   % at least 1 s padding
    sup_lo = max(0, d_min - pad);              % never go below 0
    sup_hi = d_max + pad;

    % ---- KDE ------------------------------------------------------------
    [f, xi] = ksdensity(data, 'NumPoints', 200, ...
                         'Support', [sup_lo, sup_hi], ...
                         'BoundaryCorrection', 'reflection');

    f_norm = f / max(f) * half_width;

    x_poly = [x_center + f_norm,  fliplr(x_center - f_norm)];
    y_poly = [xi,                  fliplr(xi)];

    fill(ax, x_poly, y_poly, color, ...
         'FaceAlpha', 0.30, 'EdgeColor', color, 'LineWidth', 1.5);

    % ---- Statistics -----------------------------------------------------
    q1      = quantile(data, 0.25);
    med     = median(data);
    q3      = quantile(data, 0.75);
    iqr_val = q3 - q1;
    lo      = max(min(data), q1 - 1.5 * iqr_val);
    hi      = min(max(data), q3 + 1.5 * iqr_val);

    % Whisker
    plot(ax, [x_center x_center], [lo hi], '-', ...
         'Color', color, 'LineWidth', 1.5);

    % IQR box
    box_w = half_width * 0.28;
    rectangle(ax, 'Position', [x_center - box_w, q1, ...
                                2 * box_w, max(q3 - q1, 0.1)], ...
              'FaceColor', color, 'EdgeColor', color, ...
              'LineWidth', 1, 'Curvature', [0.2, 0.2]);

    % Median line
    plot(ax, [x_center - box_w, x_center + box_w], [med, med], ...
         'w-', 'LineWidth', 2.0);

    % Median label
    text(ax, x_center, med + 3, sprintf('%.1f', med), ...
         'HorizontalAlignment', 'center', 'FontSize', 9, ...
         'Color', color, 'FontWeight', 'bold');
end

function add_legend(ax, COLOR_N, COLOR_H)
    h_N = patch(ax, NaN, NaN, COLOR_N, ...
                'FaceAlpha', 0.30, 'EdgeColor', COLOR_N, 'LineWidth', 1.5);
    h_H = patch(ax, NaN, NaN, COLOR_H, ...
                'FaceAlpha', 0.30, 'EdgeColor', COLOR_H, 'LineWidth', 1.5);
    legend(ax, [h_N, h_H], {'Non-haptic (N)', 'Haptic (H)'}, ...
           'Location', 'northeast', 'FontSize', 10, 'Box', 'off');
end
