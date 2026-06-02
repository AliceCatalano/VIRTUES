function plot_nidaq_gaps(pc_time, accel_fs, fig_title)
    dt         = diff(pc_time);
    dt_nominal = 1 / accel_fs;
    t_axis     = (1:numel(dt))';
    figure('Name',fig_title,'Position',[100 100 1400 700]);
    sgtitle(fig_title,'FontWeight','bold','FontSize',10);
    ax1 = subplot(3,1,1);
    plot(t_axis,dt*1000,'Color',[0.2 0.4 0.8],'LineWidth',0.4); hold on;
    yline(dt_nominal*1000,  'r--','LineWidth',1.2,'Label','nominal dt');
    yline(5*dt_nominal*1000,'k:' ,'LineWidth',1.0,'Label','5x nominal');
    ylabel('dt (ms)'); title('Inter-sample interval (full range)'); grid on;
    ax2 = subplot(3,1,2);
    plot(t_axis,dt*1000,'Color',[0.2 0.4 0.8],'LineWidth',0.4); hold on;
    yline(dt_nominal*1000,'r--','LineWidth',1.2);
    ylim([0  10*dt_nominal*1000]);
    ylabel('dt (ms)'); title('Inter-sample interval (clamped to 10x nominal)');
    grid on; xlabel('Sample index');
    ax3 = subplot(3,1,3);
    dt_clip = dt(dt < 50*dt_nominal);
    histogram(dt_clip*1000,200,'FaceColor',[0.2 0.6 0.4],'EdgeColor','none'); hold on;
    xline(dt_nominal*1000,  'r--','LineWidth',1.5,'Label','nominal');
    xline(5*dt_nominal*1000,'k:' ,'LineWidth',1.2,'Label','5x nominal');
    xlabel('dt (ms)'); ylabel('Count');
    title(sprintf('dt histogram  (%d outliers > 50x nominal not shown)',sum(dt>=50*dt_nominal)));
    grid on;
    linkaxes([ax1 ax2],'x');
    gap_mask = dt > 5*dt_nominal;
    gap_sizes = dt(gap_mask);  gap_times = pc_time(find(gap_mask)+1);
    fprintf('\n  Gap report  (threshold = 5x nominal = %.2f ms)\n',5*dt_nominal*1000);
    fprintf('  Total gaps : %d\n',numel(gap_sizes));
    if ~isempty(gap_sizes)
        fprintf('  min/median/max : %.4f/%.4f/%.4f s\n',min(gap_sizes),median(gap_sizes),max(gap_sizes));
        for g = 1:min(20,numel(gap_times))
            fprintf('    gap %2d:  pc_time=%.4f  dt=%.4f s\n',g,gap_times(g),gap_sizes(g)); end
        if numel(gap_times) > 20, fprintf('    ... and %d more\n',numel(gap_times)-20); end
    end
end