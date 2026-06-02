function plot_unified_overview_full(accel_raw, force_raw, force_mag_ds, t_ds, ...
        mag_accel_ds, gsr, audio, audio_present_ch, eye, ...
        event_times_kb, event_times_start, event_times_end, ...
        all_collisions, collision_source, ...
        accel_fs, bp_lo, bp_hi, audio_bp_lo, audio_bp_hi, ...
        pupil_smooth_sec, cvx_ok, t_trial_start, t_trial_end, fig_title)

    gsr_col   = get_gsr_col(gsr);
    gsr_label = 'GSR (Ohm)';
    if contains(gsr_col,'CAL'), gsr_label = 'GSR (kOhm)'; end

    has_audio = ~isempty(audio) && ~isempty(audio_present_ch);
    has_eye   = ~isempty(eye) && all(ismember({'pupil_diameter_left','pupil_diameter_right',...
                 'timestamp_unix_seconds'},eye.Properties.VariableNames));

    n_rows = 3 + has_audio + has_eye;
    figure('Name',['OVERVIEW: ' fig_title],'Position',[20 20 1700 220*n_rows]);
    sgtitle(sprintf('%s  |  Unified Overview',fig_title),'FontWeight','bold','FontSize',11);

    ax = gobjects(n_rows,1);
    row = 0;

    % Row 1: Accel sum ------------------------------------------------
    row = row+1;  ax(row) = subplot(n_rows,1,row);  hold on;
    ds_f  = max(1,round(accel_fs/500));
    tA_ds = accel_raw.t(1:ds_f:end);
    sumL  = bandpass(accel_raw.xL,[bp_lo bp_hi],accel_fs) + ...
            bandpass(accel_raw.yL,[bp_lo bp_hi],accel_fs) + ...
            bandpass(accel_raw.zL,[bp_lo bp_hi],accel_fs);
    sumR  = bandpass(accel_raw.xR,[bp_lo bp_hi],accel_fs) + ...
            bandpass(accel_raw.yR,[bp_lo bp_hi],accel_fs) + ...
            bandpass(accel_raw.zR,[bp_lo bp_hi],accel_fs);
    plot(tA_ds, sumL(1:ds_f:end),'Color',[0.2 0.4 0.9],'LineWidth',0.6,'DisplayName','Accel L');
    plot(tA_ds, sumR(1:ds_f:end),'Color',[0.9 0.3 0.1],'LineWidth',0.6,'DisplayName','Accel R');
    ylabel('Sum (g)');  title(sprintf('Accel X+Y+Z  (bandpassed %d–%d Hz)',bp_lo,bp_hi));
    legend('Location','northeast','FontSize',7);  grid on;
    add_events_differentiated(event_times_kb, event_times_start, event_times_end);
    mark_collisions_colored(all_collisions, collision_source);
    mark_trial(t_trial_start, t_trial_end);

    % Row 2 (opt): Audio ----------------------------------------------
    if has_audio
        row = row+1;  ax(row) = subplot(n_rows,1,row);  hold on;
        fs_audio     = 1/median(diff(audio.t(diff(audio.t)>0)));
        audio_sum_bp = zeros(height(audio),1);
        clrs_a       = lines(numel(audio_present_ch));
        for k = 1:numel(audio_present_ch)
            ch = audio_present_ch{k};
            raw = double(audio.(ch)) - mean(double(audio.(ch)),'omitnan');
            if numel(raw) > 10*fs_audio
                raw_bp = bandpass(raw,[audio_bp_lo audio_bp_hi],fs_audio);
            else, raw_bp = raw; end
            audio_sum_bp = audio_sum_bp + raw_bp;
            plot(audio.t,raw_bp,'Color',[clrs_a(k,:) 0.35],'LineWidth',0.4,'DisplayName',ch);
        end
        plot(audio.t,audio_sum_bp,'Color',[0.1 0.1 0.7],'LineWidth',1.2,'DisplayName','Sum');
        ylabel('V');  title(sprintf('Audio mixer  (bandpassed %d–%d Hz)',audio_bp_lo,audio_bp_hi));
        legend('Location','northeast','FontSize',7);  grid on;
        add_events_differentiated(event_times_kb, event_times_start, event_times_end);
        mark_collisions_colored(all_collisions, collision_source);
        mark_trial(t_trial_start, t_trial_end);
    end

    % Row 3: Force ----------------------------------------------------
    row = row+1;  ax(row) = subplot(n_rows,1,row);  hold on;
    plot(t_ds, force_mag_ds,'Color',[0.5 0 0.5],'LineWidth',0.8,'DisplayName','|Force|');
    ylabel('|Force| (V)');  title('Force sensor magnitude (downsampled)');  grid on;
    add_events_differentiated(event_times_kb, event_times_start, event_times_end);
    mark_collisions_colored(all_collisions, collision_source);
    mark_trial(t_trial_start, t_trial_end);

    % Row 4: GSR ------------------------------------------------------
    row = row+1;  ax(row) = subplot(n_rows,1,row);  hold on;
    if cvx_ok && ismember('scl',gsr.Properties.VariableNames)
        yyaxis left;
        plot(gsr.t,gsr.(gsr_col),'Color',[0.6 0.6 1.0],'LineWidth',0.6,'DisplayName','GSR raw');
        ylabel(gsr_label);
        yyaxis right;
        plot(gsr.t,gsr.scl,'b','LineWidth',1.2,'DisplayName','SCL (tonic)');
        plot(gsr.t,gsr.scr,'r','LineWidth',0.7,'DisplayName','SCR (phasic)');
        ylabel('z-µS');  yyaxis left;
    else
        plot(gsr.t,gsr.(gsr_col),'b','LineWidth',1.0,'DisplayName','GSR raw');
        ylabel(gsr_label);
    end
    title('GSR  (blue=tonic SCL  red=phasic SCR  if cvxEDA available)');
    legend('Location','northeast','FontSize',7);  grid on;
    add_events_differentiated(event_times_kb, event_times_start, event_times_end);
    mark_collisions_colored(all_collisions, collision_source);
    mark_trial(t_trial_start, t_trial_end);

    % Row 5 (opt): Pupil ----------------------------------------------
    if has_eye
        row = row+1;  ax(row) = subplot(n_rows,1,row);  hold on;
        fs_eye  = 1/median(diff(eye.timestamp_unix_seconds));
        win_pts = max(3,round(fs_eye*pupil_smooth_sec));
        pL_sm   = movmean(eye.pupil_diameter_left,  win_pts,'omitnan');
        pR_sm   = movmean(eye.pupil_diameter_right, win_pts,'omitnan');
        plot(eye.t,eye.pupil_diameter_left, 'Color',[0.7 0.7 1.0],'LineWidth',0.4,'DisplayName','L raw');
        plot(eye.t,eye.pupil_diameter_right,'Color',[0.7 1.0 0.7],'LineWidth',0.4,'DisplayName','R raw');
        plot(eye.t,pL_sm,'b','LineWidth',1.4,'DisplayName','L smooth');
        plot(eye.t,pR_sm,'Color',[0 0.6 0],'LineWidth',1.4,'DisplayName','R smooth');
        ylabel('Diameter (mm)');
        title(sprintf('Pupil diameter  (%.2f s avg, %.0f Hz)',pupil_smooth_sec,fs_eye));
        legend('Location','northeast','FontSize',7);  grid on;
        add_events_differentiated(event_times_kb, event_times_start, event_times_end);
        mark_collisions_colored(all_collisions, collision_source);
        mark_trial(t_trial_start, t_trial_end);
    end

    linkaxes(ax(1:row),'x');
    xlabel(ax(row),'Time (s)');

    % Annotate event labels on top panel
    if ~isempty(event_times_kb) || ~isempty(event_times_start) || ~isempty(event_times_end)
        axes(ax(1));
        yl = ylim;
        for et = event_times_kb(:)'
            text(et, yl(2), 'KB', 'FontSize',5,'Color',[0.2 0.2 0.9], ...
                'Rotation',90,'VerticalAlignment','bottom',...
                'HorizontalAlignment','right','Interpreter','none');
        end
        for et = event_times_start(:)'
            text(et, yl(2), 'START', 'FontSize',5,'Color',[0 0.7 0], ...
                'Rotation',90,'VerticalAlignment','bottom',...
                'HorizontalAlignment','right','Interpreter','none');
        end
        for et = event_times_end(:)'
            text(et, yl(2), 'END', 'FontSize',5,'Color',[0.9 0.5 0], ...
                'Rotation',90,'VerticalAlignment','bottom',...
                'HorizontalAlignment','right','Interpreter','none');
        end
    end
end
