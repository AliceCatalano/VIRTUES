function plot_resting_gsr(gsr, gsr_col, event_times, cvx_ok, fig_title)
    gsr_label = 'GSR (Ohm)';
    if contains(gsr_col,'CAL'), gsr_label = 'GSR (kOhm)'; end

    n_rows = 2 + cvx_ok;
    figure('Name',['Resting GSR: ' fig_title], 'Position',[50 50 1400 240*n_rows]);
    sgtitle([fig_title ' | GSR — Resting State Baseline'], 'FontWeight','bold','FontSize',10);

    ax1 = subplot(n_rows,1,1);
    plot(gsr.t, gsr.(gsr_col), 'b', 'LineWidth', 1.0);
    ylabel(gsr_label);  title('Raw GSR signal');  grid on;  hold on;
    add_event_lines(event_times);
    % Overlay mean ± std band
    gm = mean(gsr.(gsr_col),'omitnan');  gs = std(gsr.(gsr_col),'omitnan');
    yline(gm,   '-k', 'LineWidth',1.5, 'Label',sprintf('Mean=%.1f',gm));
    yline(gm+gs,'--','Color',[0.5 0.5 0.5],'LineWidth',1,'Label','+1 SD');
    yline(gm-gs,'--','Color',[0.5 0.5 0.5],'LineWidth',1,'Label','-1 SD');

    ax2 = subplot(n_rows,1,2);
    win = max(5, round(numel(gsr.(gsr_col))*0.02));
    plot(gsr.t, movmean(gsr.(gsr_col),win,'omitnan'), 'Color',[0.2 0.5 0.9],'LineWidth',1.2);
    ylabel(gsr_label);  title('GSR — slow trend (2% moving average)');  grid on;  hold on;
    add_event_lines(event_times);

    if cvx_ok && ismember('scl', gsr.Properties.VariableNames)
        ax3 = subplot(n_rows,1,3);
        hold on;
        plot(gsr.t, gsr.scl, 'b', 'LineWidth',1.2, 'DisplayName','Tonic SCL');
        plot(gsr.t, gsr.scr, 'r', 'LineWidth',0.8, 'DisplayName','Phasic SCR');
        ylabel('z-µS');  title('cvxEDA: Tonic SCL (blue) + Phasic SCR (red)');
        legend('Location','best');  grid on;
        add_event_lines(event_times);
        linkaxes([ax1 ax2 ax3], 'x');
    else
        linkaxes([ax1 ax2], 'x');
    end
    xlabel('Time (s)');
end