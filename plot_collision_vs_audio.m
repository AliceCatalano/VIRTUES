function plot_collision_vs_audio(audio, channels, fs_audio, bp_lo, bp_hi, ...
        collision_times, collision_source, mag_accel_ds, t_ds, ...
        event_times_kb, event_times_start, event_times_end, fig_title)

    figure('Name',['Collision-Audio: ' fig_title],'Position',[70 70 1600 600]);
    sgtitle([fig_title ' | Collision Detection vs Audio Mixer Spikes'], ...
        'FontWeight','bold','FontSize',10);

    % Build audio sum
    audio_sum_bp = zeros(height(audio),1);
    for k = 1:numel(channels)
        raw = double(audio.(channels{k})) - mean(double(audio.(channels{k})),'omitnan');
        if numel(raw) > 10*fs_audio
            raw_bp = bandpass(raw,[bp_lo bp_hi],fs_audio);
        else
            raw_bp = raw;
        end
        audio_sum_bp = audio_sum_bp + raw_bp;
    end
    audio_rms = sqrt(movmean(audio_sum_bp.^2, max(3,round(fs_audio*0.05))));

    ax1 = subplot(2,1,1);
    hold on;
    plot(t_ds, mag_accel_ds, 'Color',[0.2 0.4 0.9], 'LineWidth',0.8, 'DisplayName','|Accel|');
    mark_collisions_colored(collision_times, collision_source);
    add_events_differentiated(event_times_kb, event_times_start, event_times_end);
    ylabel('|Accel| (g)');  title('Accelerometer magnitude — detected collisions');
    legend({'|Accel|','Accel collision','Force collision','Both'},'Location','northeast','FontSize',7);
    grid on;

    ax2 = subplot(2,1,2);
    hold on;
    plot(audio.t, audio_rms, 'Color',[0.8 0.3 0.1],'LineWidth',0.8,'DisplayName','Audio RMS');
    mark_collisions_colored(collision_times, collision_source);
    add_events_differentiated(event_times_kb, event_times_start, event_times_end);
    ylabel('RMS (V)');  title('Audio mixer RMS envelope — collision markers overlaid');
    legend({'Audio RMS','Accel collision','Force collision','Both'},'Location','northeast','FontSize',7);
    grid on;

    linkaxes([ax1 ax2],'x');
    xlabel(ax2,'Time (s)');
end