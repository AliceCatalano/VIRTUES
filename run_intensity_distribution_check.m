%% h2_intensity_distribution_check.m
clear; clc; cfg = config();
TC = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T_coll'); TC = TC.T_coll;
TC = TC(strcmp(TC.phase_type,'training') & isfinite(TC.peak_accel_g),:);
xN = TC.peak_accel_g(~TC.haptic); xH = TC.peak_accel_g(TC.haptic);
fprintf('N group: n=%d  median=%.3f  mean=%.3f  max=%.3f\n',numel(xN),median(xN),mean(xN),max(xN));
fprintf('H group: n=%d  median=%.3f  mean=%.3f  max=%.3f\n',numel(xH),median(xH),mean(xH),max(xH));
[~,p_ks] = kstest2(xN,xH); fprintf('KS test on intensity distributions: p=%.4g\n',p_ks);
[p_rs] = ranksum(xN,xH); fprintf('Rank-sum test: p=%.4g\n',p_rs);
fig = figure('Position',[50 50 700 400]);
CN=[55 138 221]/255; CH=[212 83 126]/255;
histogram(xN,50,'Normalization','probability','FaceColor',CN,'FaceAlpha',0.5,'DisplayName','NHF'); hold on;
histogram(xH,50,'Normalization','probability','FaceColor',CH,'FaceAlpha',0.5,'DisplayName','HF');
xlabel('peak\_accel\_g (g)'); ylabel('Proportion'); legend('Location','northeast');
title(sprintf('Collision intensity distribution by group (KS p=%.3g)',p_ks));
exportgraphics(fig,fullfile(cfg.output_root,'figures','h2_intensity_distribution.png'),'Resolution',150);
 fprintf('Saved h2_intensity_distribution.png\n');