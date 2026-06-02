function plot_pupil(eye,event_times,smooth_sec,fig_title)
    fs_eye   = 1/median(diff(eye.timestamp_unix_seconds));
    win_pts  = max(3,round(fs_eye*smooth_sec));
    pL_smooth = movmean(eye.pupil_diameter_left,  win_pts,'omitnan');
    pR_smooth = movmean(eye.pupil_diameter_right, win_pts,'omitnan');
    figure('Name',[fig_title ' | Pupil'],'Position',[60 60 1400 400]);
    sgtitle(sprintf('%s | Pupil diameter  (%.2f s smoothing, %.0f Hz)',fig_title,smooth_sec,fs_eye),...
        'FontWeight','bold','FontSize',10);
    plot(eye.t,eye.pupil_diameter_left, 'Color',[0.6 0.6 1.0],'LineWidth',0.5,'DisplayName','Left raw');  hold on;
    plot(eye.t,eye.pupil_diameter_right,'Color',[0.6 1.0 0.6],'LineWidth',0.5,'DisplayName','Right raw');
    plot(eye.t,pL_smooth,'b','LineWidth',1.5,'DisplayName','Left smoothed');
    plot(eye.t,pR_smooth,'g','LineWidth',1.5,'DisplayName','Right smoothed');
    add_event_lines(event_times);
    xlabel('Time (s)'); ylabel('Pupil diameter (mm)'); legend('Location','best'); grid on;
end