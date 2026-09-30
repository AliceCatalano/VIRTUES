%% h1_scl_detailed_plots.m
clear; clc; close all; cfg = config();
CN = [64 96 179]/255; CH = [139 82 168]/255;
fig_dir = fullfile(cfg.output_root,'figures');
EDA = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); T = EDA.T;

%% Figure 1: Summary across all phases — CORRECTED ORDER
% Protocol order: BL1, T1, L1, L2, L3, L4, L5, BL2, T2
phases_ord = {'Baseline1','Test1','Training_L1','Training_L2','Training_L3','Training_L4','Training_L5','Baseline2','Test2'};
xlabels    = {'BL1','T1','L1','L2','L3','L4','L5','BL2','T2'};
% [existing summary figure code with corrected order — already in summary_plots.m, just reorder]

%% Figure 2: Tonic SCL across the 5 difficulty levels within Baseline1 and Baseline2
fig2 = figure('Position',[50 50 900 420]);
tl = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
title(tl,'Tonic SCL across difficulty levels — Baseline1 and Baseline2 (subject means ± SE)', ...
    'FontWeight','bold','FontSize',11);
for bi = 1:2
    bl_phase = sprintf('Baseline%d',bi);
    Tbl = T(strcmp(T.phase,bl_phase) & isfinite(T.scl_mean_bc),:);
    nexttile; hold on;
    for grp = [false true]
        col = local_ternary(grp,CH,CN); lbl = local_ternary(grp,'HF','NHF');
        Tg = Tbl(Tbl.haptic==grp,:); subj_g = unique(Tg.subject);
        mu_lv = nan(1,5); se_lv = nan(1,5);
        for lv = 1:5
            xs = nan(numel(subj_g),1);
            for si = 1:numel(subj_g)
                v = Tg.scl_mean_bc(strcmp(Tg.subject,subj_g{si}) & Tg.level==lv);
                if ~isempty(v), xs(si) = mean(v,'omitnan'); end
            end
            xs = xs(isfinite(xs));
            jx = lv + local_ternary(grp,0.12,-0.12) + (rand(numel(xs),1)-0.5)*0.08;
            scatter(jx,xs,18,col,'filled','MarkerFaceAlpha',0.35,'HandleVisibility','off');
            mu_lv(lv) = mean(xs); se_lv(lv) = std(xs)/sqrt(numel(xs));
        end
        errorbar(1:5,mu_lv,se_lv,'o-','Color',col,'LineWidth',2,'MarkerFaceColor',col,'MarkerSize',7,'DisplayName',lbl);
    end
    set(gca,'XTick',1:5,'XTickLabel',{'L1','L2','L3','L4','L5'},'FontSize',9);
    xlabel('Difficulty level','FontSize',10); ylabel('Tonic SCL above resting (\muS)','FontSize',9);
    title(sprintf('%s — note: levels reflect task difficulty, not training order',bl_phase),'FontSize',9);
    if bi==1, legend('Location','best','FontSize',9); end
    grid on; box on;
end
exportgraphics(fig2,fullfile(fig_dir,'h1_scl_baseline_levels.png'),'Resolution',180);

%% Figure 3: Training SCL across all 50 reps (already in generate_all_report_figures.m)
% Use the existing rep-by-rep and full_sequence figures — these already exist

%% Figure 4: Test phase SCL — need to handle variable trial durations
% Since test trials have variable durations, we use the aggregate per-trial mean
% (not a time-series) and show it as a snapshot comparison
fig4 = figure('Position',[50 50 700 420]);
tl = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
title(tl,'Tonic SCL — Test phases (per-trial mean ± SE, individual dots)', ...
    'FontWeight','bold','FontSize',11);
for ti = 1:2
    tph = sprintf('Test%d',ti);
    Ttest = T(strcmp(T.phase,tph) & isfinite(T.scl_mean_bc),:);
    subj_t = unique(Ttest.subject);
    xN = nan(numel(subj_t),1); xH = nan(numel(subj_t),1); ihs = false(numel(subj_t),1);
    for si = 1:numel(subj_t)
        s = subj_t{si};
        v = Ttest.scl_mean_bc(strcmp(Ttest.subject,s));
        ihs(si) = any(Ttest.haptic(strcmp(Ttest.subject,s)));
        if ihs(si), xH(si) = mean(v,'omitnan'); else, xN(si) = mean(v,'omitnan'); end
    end
    xN = xN(~ihs & isfinite(xN)); xH = xH(ihs & isfinite(xH));
    nexttile; hold on;
    scatter(0.9+(rand(numel(xN),1)-0.5)*0.15,xN,22,CN,'filled','MarkerFaceAlpha',0.4,'HandleVisibility','off');
    scatter(1.9+(rand(numel(xH),1)-0.5)*0.15,xH,22,CH,'filled','MarkerFaceAlpha',0.4,'HandleVisibility','off');
    errorbar(1,mean(xN,'omitnan'),std(xN,'omitnan')/sqrt(numel(xN)),'o','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',9,'DisplayName','NHF');
    errorbar(2,mean(xH,'omitnan'),std(xH,'omitnan')/sqrt(numel(xH)),'o','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',9,'DisplayName','HF');
    xticks([1 2]); xticklabels({'NHF','HF'}); xlim([0.5 2.5]);
    ylabel('Tonic SCL above resting (\muS)','FontSize',9);
    title(sprintf('%s (per-trial mean, variable durations)',tph),'FontSize',9);
    if ti==1, legend('Location','best','FontSize',9); end
    grid on; box on;
    % note on variable durations
    text(1.5,min([xN;xH])-0.3*range([xN;xH]), ...
        'Note: trial durations vary across subjects (see Table X)', ...
        'HorizontalAlignment','center','FontSize',7,'Color',[0.5 0.5 0.5]);
end
exportgraphics(fig4,fullfile(fig_dir,'h1_scl_test_phases.png'),'Resolution',180);

fig4 = figure('Position',[50 50 700 420]);
tl = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
title(tl,'Tonic SCL — Test phases (per-trial mean ± SE, individual dots; red × = outlier)', ...
    'FontWeight','bold','FontSize',11);

for ti = 1:2
    tph = sprintf('Test%d',ti);
    Ttest = T(strcmp(T.phase,tph) & isfinite(T.scl_mean_bc),:);
    subj_t = unique(Ttest.subject);
    xN = nan(numel(subj_t),1); xH = nan(numel(subj_t),1); ihs = false(numel(subj_t),1);
    for si = 1:numel(subj_t)
        s = subj_t{si};
        v = Ttest.scl_mean_bc(strcmp(Ttest.subject,s));
        ihs(si) = any(Ttest.haptic(strcmp(Ttest.subject,s)));
        if ihs(si), xH(si) = mean(v,'omitnan'); else, xN(si) = mean(v,'omitnan'); end
    end
    xN_all = xN(~ihs & isfinite(xN));
    xH_all = xH( ihs & isfinite(xH));

    % detect outliers: >3 MAD from group median
    is_out_N = abs(xN_all - median(xN_all)) > 3*mad(xN_all,1);
    is_out_H = abs(xH_all - median(xH_all)) > 3*mad(xH_all,1);

    nexttile; hold on;
    % NHF: normal points
    scatter(0.9+(rand(sum(~is_out_N),1)-0.5)*0.15, xN_all(~is_out_N), 22, CN,'filled','MarkerFaceAlpha',0.4,'HandleVisibility','off');
    % NHF: outliers as red crosses
    if any(is_out_N)
        scatter(0.9+(rand(sum(is_out_N),1)-0.5)*0.15, xN_all(is_out_N), 50,'rx','LineWidth',2,'HandleVisibility','off');
    end
    % HF: normal points
    scatter(1.9+(rand(sum(~is_out_H),1)-0.5)*0.15, xH_all(~is_out_H), 22, CH,'filled','MarkerFaceAlpha',0.4,'HandleVisibility','off');
    % HF: outliers as red crosses
    if any(is_out_H)
        scatter(1.9+(rand(sum(is_out_H),1)-0.5)*0.15, xH_all(is_out_H), 50,'rx','LineWidth',2,'HandleVisibility','off');
    end

    % group means computed WITHOUT outliers
    xN_clean = xN_all(~is_out_N); xH_clean = xH_all(~is_out_H);
    errorbar(1,mean(xN_clean,'omitnan'),std(xN_clean,'omitnan')/sqrt(numel(xN_clean)),'o', ...
        'Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',9,'DisplayName','NHF');
    errorbar(2,mean(xH_clean,'omitnan'),std(xH_clean,'omitnan')/sqrt(numel(xH_clean)),'o', ...
        'Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',9,'DisplayName','HF');

    % annotate outlier count
    n_out = sum(is_out_N)+sum(is_out_H);
    if n_out>0
        text(1.5,max([xN_all;xH_all])+0.3,sprintf('%d outlier(s) marked (×), excluded from mean',n_out), ...
            'HorizontalAlignment','center','FontSize',7,'Color',[0.7 0.1 0.1]);
    end

    xticks([1 2]); xticklabels({'NHF','HF'}); xlim([0.5 2.5]);
    ylabel('Tonic SCL above resting (\muS)','FontSize',9);
    title(sprintf('%s (per-trial mean; variable trial durations)',tph),'FontSize',9);
    if ti==1, legend('Location','best','FontSize',9); end
    grid on; box on;
end
exportgraphics(fig4,fullfile(fig_dir,'h1_scl_test_phases.png'),'Resolution',180);
function out = local_ternary(c,a,b), if c, out=a; else, out=b; end, end