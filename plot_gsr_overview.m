function plot_gsr_overview(gsr,mag_accel_ds,force_mag_ds,t_ds,collision_times,collision_source,...
        gsr_responses,title_str,has_cvx,t_trial_start,t_trial_end)
    gsr_col   = get_gsr_col(gsr);
    gsr_label = 'GSR (Ohm)';  if contains(gsr_col,'CAL'), gsr_label = 'GSR (kOhm)'; end
    n_plots   = 3+has_cvx;
    figure('Name',['GSR Overview: ' title_str],'Position',[30 30 1600 210*n_plots]);
    p=0;
    p=p+1; subplot(n_plots,1,p);
    plot(t_ds,mag_accel_ds,'b','LineWidth',0.8); hold on;
    mark_collisions(collision_times); mark_trial(t_trial_start,t_trial_end);
    ylabel('|accel| (g)'); title('Accelerometer magnitude'); grid on;
    p=p+1; subplot(n_plots,1,p);
    plot(t_ds,force_mag_ds,'Color',[0.5 0 0.5],'LineWidth',0.8); hold on;
    mark_collisions(collision_times); mark_trial(t_trial_start,t_trial_end);
    ylabel('|force| (V)'); title('Force magnitude'); grid on;
    p=p+1; subplot(n_plots,1,p);
    plot(gsr.t,gsr.(gsr_col),'b','LineWidth',1); hold on;
    yl = ylim;
    for i = 1:numel(collision_times)
        switch collision_source(i)
            case 1, ls='-';  src_sym='A';
            case 2, ls='--'; src_sym='F';
            case 3, ls=':';  src_sym='B';
            otherwise, ls='--'; src_sym='?';
        end
        r = gsr_responses(i);
        if r.has_scr && r.has_scl, col=[0.8 0 0];
        elseif r.has_scr,          col=[0.8 0 0.8];
        elseif r.has_scl,          col=[0 0.6 0.7];
        else,                      col=[0.4 0.4 0.4]; end
        xline(collision_times(i),ls,'Color',col,'LineWidth',2,'HandleVisibility','off');
        text(collision_times(i),yl(2),sprintf('%d%s',i,src_sym),'FontSize',7,'Color',col,...
            'HorizontalAlignment','center','VerticalAlignment','top');
    end
    mark_trial(t_trial_start,t_trial_end);
    ylabel(gsr_label); title('Raw GSR  (red=SCR+SCL  magenta=SCR  cyan=SCL  grey=none)'); grid on;
    if has_cvx
        p=p+1; subplot(n_plots,1,p); hold on;
        plot(gsr.t,gsr.scl,'b','LineWidth',1.2,'DisplayName','Tonic SCL');
        plot(gsr.t,gsr.scr,'r','LineWidth',0.8,'DisplayName','Phasic SCR');
        mark_collisions(collision_times); mark_trial(t_trial_start,t_trial_end);
        legend('Location','best'); ylabel('z-uS');
        title('cvxEDA: Tonic SCL (blue) + Phasic SCR (red)'); grid on;
    end
    sgtitle([title_str ' | solid=accel  dash=force  dot=both | red=SCR+SCL  mag=SCR  cyan=SCL  grey=none'],...
        'FontWeight','bold','FontSize',8);
end