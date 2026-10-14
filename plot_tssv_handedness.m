%% plot_tssv_handedness.m
% Plots left vs right TSSV behavior from the ALREADY-SAVED tssv_handedness.mat Run extract_plot_tssv_handedness.m once beforehand; after that,
% only this script is needed to replot.

clear; clc; cfg = config();
S = load(fullfile(cfg.output_root,'tssv_handedness.mat'),'TH');
TH = S.TH;

Ttr = TH(strcmp(TH.phase_type,'training'),:);
rep_num = str2double(regexp(Ttr.acquisition,'\d+','match','once'));
n_rep = cfg.n_training_reps;

groups = struct('label',{'NHF','HF'}, 'haptic',{false,true});
fig = figure('Position',[100 100 1100 450]);
tl = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
title(tl,'Left vs right tool vibration by repetition, split by group','FontWeight','bold');

for g = 1:2
    Tg = Ttr(Ttr.haptic==groups(g).haptic, :);
    mu_left  = nan(1,n_rep); se_left  = nan(1,n_rep);
    mu_right = nan(1,n_rep); se_right = nan(1,n_rep);
    rep_g = rep_num(Ttr.haptic==groups(g).haptic);
    for r = 1:n_rep
        vl = log(Tg.tssv_left (rep_g==r & Tg.tssv_left >0));
        vr = log(Tg.tssv_right(rep_g==r & Tg.tssv_right>0));
        mu_left(r)  = mean(vl,'omitnan');  se_left(r)  = std(vl,'omitnan') /sqrt(numel(vl));
        mu_right(r) = mean(vr,'omitnan');  se_right(r) = std(vr,'omitnan')/sqrt(numel(vr));
    end

    nexttile; hold on;
    x = 1:n_rep;
    fill([x fliplr(x)], [mu_left+1.96*se_left fliplr(mu_left-1.96*se_left)], ...
        [0.85 0.4 0.1], 'FaceAlpha',0.15, 'EdgeColor','none', 'HandleVisibility','off');
    fill([x fliplr(x)], [mu_right+1.96*se_right fliplr(mu_right-1.96*se_right)], ...
        [0.1 0.5 0.6], 'FaceAlpha',0.15, 'EdgeColor','none', 'HandleVisibility','off');
    plot(x, mu_left,  'o-', 'Color',[0.85 0.4 0.1], 'LineWidth',2, 'MarkerFaceColor',[0.85 0.4 0.1], 'DisplayName','Left tool');
    plot(x, mu_right, 'o-', 'Color',[0.1 0.5 0.6],  'LineWidth',2, 'MarkerFaceColor',[0.1 0.5 0.6],  'DisplayName','Right tool');
    xlabel('Repetition'); ylabel('log(TSSV)'); title(groups(g).label,'FontSize',11);
    xticks(1:n_rep); legend('Location','best'); grid on; box on;
end