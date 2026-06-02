function plot_force_7panel(force_raw,force_cols,t_ds,force_mag_ds,event_times,fig_title)
    figure('Name',fig_title,'Position',[80 80 1400 1200]);
    sgtitle(fig_title,'FontWeight','bold','FontSize',10);
    clrs = lines(numel(force_cols));  ax = gobjects(7,1);
    for k = 1:numel(force_cols)
        c = force_cols{k};
        ax(k) = subplot(7,1,k);
        plot(force_raw.t,force_raw.(c),'Color',clrs(k,:),'LineWidth',0.6);
        ylabel([c ' (V)']); title(c); grid on; add_event_lines(event_times);
    end
    ax(7)=subplot(7,1,7);
    plot(t_ds,force_mag_ds,'Color',[0.5 0 0.5],'LineWidth',1.0);
    ylabel('|Force| (V)'); title('Force magnitude (downsampled)'); grid on; add_event_lines(event_times);
    linkaxes(ax,'x');  xlabel(ax(7),'Time (s)');
end