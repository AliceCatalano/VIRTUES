function plot_resting_pupil(eye, event_times, smooth_sec, fig_title)
    fs_eye   = 1 / median(diff(eye.timestamp_unix_seconds));
    win_pts  = max(3, round(fs_eye * smooth_sec));
    pL_sm    = movmean(eye.pupil_diameter_left,  win_pts, 'omitnan');
    pR_sm    = movmean(eye.pupil_diameter_right, win_pts, 'omitnan');

    figure('Name',['Resting Pupil: ' fig_title], 'Position',[80 80 1400 500]);
    sgtitle(sprintf('%s | Pupil Diameter — Resting State  (%.0f Hz)', fig_title, fs_eye), ...
        'FontWeight','bold','FontSize',10);

    ax1 = subplot(2,1,1);
    hold on;
    plot(eye.t, eye.pupil_diameter_left,  'Color',[0.7 0.7 1.0],'LineWidth',0.5,'DisplayName','L raw');
    plot(eye.t, eye.pupil_diameter_right, 'Color',[0.7 1.0 0.7],'LineWidth',0.5,'DisplayName','R raw');
    plot(eye.t, pL_sm, 'b', 'LineWidth',1.5, 'DisplayName','L smooth');
    plot(eye.t, pR_sm, 'Color',[0 0.6 0],'LineWidth',1.5,'DisplayName','R smooth');
    % Baseline mean lines
    yline(mean(eye.pupil_diameter_left,'omitnan'), '--b', 'LineWidth',1,'Label','L mean');
    yline(mean(eye.pupil_diameter_right,'omitnan'),'--','Color',[0 0.6 0],'LineWidth',1,'Label','R mean');
    ylabel('Diameter (mm)'); title('Pupil diameter (raw + smoothed)');
    legend('Location','best','FontSize',7);  grid on;
    add_event_lines(event_times);

    ax2 = subplot(2,1,2);
    hold on;
    if ismember('blink', eye.Properties.VariableNames)
        area(eye.t, double(eye.blink)*max([eye.pupil_diameter_left;eye.pupil_diameter_right],[],'omitnan'), ...
            'FaceColor',[1 0.85 0.85], 'EdgeColor','none', 'DisplayName','Blink');
    end
    plot(eye.t, pL_sm, 'b', 'LineWidth',1.2, 'DisplayName','L smooth');
    plot(eye.t, pR_sm, 'Color',[0 0.6 0],'LineWidth',1.2,'DisplayName','R smooth');
    ylabel('Diameter (mm)');  title('Pupil (smoothed) with blink overlay');
    legend('Location','best','FontSize',7);  grid on;
    add_event_lines(event_times);

    linkaxes([ax1 ax2],'x');
    xlabel(ax2,'Time (s)');
end