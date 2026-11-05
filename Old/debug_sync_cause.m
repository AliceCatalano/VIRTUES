%% sync_root_cause_analysis.m
clear; clc; cfg = config();

T=load(fullfile(cfg.output_root,'sync_check_results.mat'),'T'); T=T.T;

% exclude already-known-bad subjects and wrong_fs
excl_subj={'subject_s09N','subject_s10H','subject_s11N','subject_s12H',...
           'subject_s23H','subject_s44N','subject_s48N','subject_s05N',...
           'subject_s02N','subject_s03H','subject_s04H','subject_s27N'};
Tg=T(~ismember(T.subject,excl_subj)&strcmp(T.flag,'large_lag')&isfinite(T.lag_ms),:);

fprintf('=== Root cause analysis: does t0_diff explain the lag? ===\n');
fprintf('n=%d flagged acquisitions from %d subjects\n',height(Tg),numel(unique(Tg.subject)));

% correlation between t0_diff and measured lag
r=corr(Tg.t0_diff_ms,Tg.lag_ms,'Rows','complete');
fprintf('\nCorrelation t0_diff_ms vs lag_ms: r=%.3f\n',r);

% how often does |t0_diff - lag| < 50ms?
diff_abs=abs(Tg.t0_diff_ms-Tg.lag_ms);
fprintf('|t0_diff - lag| < 50ms:  %d/%d (%.1f%%) — t0 explains lag\n',...
    sum(diff_abs<50),height(Tg),100*mean(diff_abs<50));
fprintf('|t0_diff - lag| < 200ms: %d/%d (%.1f%%)\n',...
    sum(diff_abs<200),height(Tg),100*mean(diff_abs<200));
fprintf('|t0_diff - lag| > 500ms: %d/%d (%.1f%%) — t0 does NOT explain lag\n',...
    sum(diff_abs>500),height(Tg),100*mean(diff_abs>500));

% distribution of actual lags
fprintf('\nActual lag_ms distribution:\n');
fprintf('  min=%.1f  p25=%.1f  median=%.1f  p75=%.1f  max=%.1f\n',...
    min(Tg.lag_ms),quantile(Tg.lag_ms,0.25),median(Tg.lag_ms),...
    quantile(Tg.lag_ms,0.75),max(Tg.lag_ms));

% check if lags cluster around specific values
edges=[-3000 -500 -250 -50 50 250 500 3000];
counts=histcounts(Tg.lag_ms,edges);
labels={'<-500ms','-500 to -250ms','-250 to -50ms','-50 to +50ms',...
        '+50 to +250ms','+250 to +500ms','>+500ms'};
fprintf('\nLag clustering:\n');
for i=1:numel(counts), fprintf('  %-20s: %d (%.1f%%)\n',labels{i},counts(i),100*counts(i)/height(Tg)); end

% check per-subject: is the lag consistent within a subject?
fprintf('\nPer-subject lag consistency:\n');
fprintf('%-20s %8s %8s %8s %8s  interpretation\n','Subject','n','median','std','range');
subj_list=unique(Tg.subject);
for si=1:numel(subj_list)
    s=subj_list{si};
    v=Tg.lag_ms(strcmp(Tg.subject,s));
    v=v(abs(v)<3000);
    if numel(v)<2, continue; end
    interp_str=local_ternary(std(v)<100,'CONSISTENT','VARIABLE');
    fprintf('%-20s %8d %8.1f %8.1f %8.1f  %s\n',...
        strrep(s,'subject_',''),numel(v),median(v),std(v),range(v),interp_str);
end

% check if the lag is always positive or can be negative
fprintf('\nSign of lag:\n');
fprintf('  Positive (audio ahead of NIDAQ): %d (%.1f%%)\n',...
    sum(Tg.lag_ms>50),100*mean(Tg.lag_ms>50));
fprintf('  Near zero (|lag|<50ms):          %d (%.1f%%)\n',...
    sum(abs(Tg.lag_ms)<=50),100*mean(abs(Tg.lag_ms)<=50));
fprintf('  Negative (NIDAQ ahead of audio): %d (%.1f%%)\n',...
    sum(Tg.lag_ms<-50),100*mean(Tg.lag_ms<-50));

% scatter plot
fig=figure('Position',[50 50 1200 500]);
tl=tiledlayout(1,2,'TileSpacing','compact');
title(tl,'Root cause: does t0\_unix difference explain cross-correlation lag?','FontWeight','bold');

nexttile; hold on;
scatter(Tg.t0_diff_ms,Tg.lag_ms,15,[0.4 0.6 0.8],'filled','MarkerFaceAlpha',0.4);
pf=polyfit(Tg.t0_diff_ms(isfinite(Tg.t0_diff_ms)&isfinite(Tg.lag_ms)),...
           Tg.lag_ms(isfinite(Tg.t0_diff_ms)&isfinite(Tg.lag_ms)),1);
xl=[min(Tg.t0_diff_ms) max(Tg.t0_diff_ms)];
plot(xl,polyval(pf,xl),'r-','LineWidth',1.5);
plot(xl,xl,'k--','LineWidth',1,'DisplayName','perfect match');
xlabel('t0\_diff\_ms (audiomixer - NIDAQ t0)'); ylabel('lag\_ms (cross-corr)');
title(sprintf('t0 diff vs actual lag\nr=%.3f',r),'FontSize',10);
legend('data','OLS','1:1 line','FontSize',8); grid on; box on;

nexttile;
histogram(Tg.lag_ms,60,'FaceColor',[0.4 0.6 0.8],'EdgeColor','none');
xline(median(Tg.lag_ms),'r--','LineWidth',1.5,'DisplayName',sprintf('median=%.1fms',median(Tg.lag_ms)));
xlabel('Measured lag (ms)'); ylabel('Count');
title('Distribution of measured lags','FontSize',10);
legend('FontSize',8); grid on;

exportgraphics(fig,fullfile(cfg.output_root,'figures','sensor_quality','sync_root_cause.png'),'Resolution',150);
fprintf('\nFigure saved.\n');

function out=local_ternary(c,a,b), if c,out=a; else,out=b; end, end