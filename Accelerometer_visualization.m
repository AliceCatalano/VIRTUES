%% Accelerometer_visualization.m
% Standalone visualization for a single session level.
% IMPORTANT: run with a clean workspace (clear all) to avoid stale variables
% contaminating the time axis.

clear; clc; close all;

session_folder = '/home/acatalano/VIRTUES/resting_state';
session_folder = replace(session_folder, '~', getenv('HOME'));

accel_fs = 3000;   % Hz
bp_lo    = 80;
bp_hi    = 1000;

%% ── Load ─────────────────────────────────────────────────────────────────────
fprintf('Loading: %s\n\n', session_folder);

nidaq_file  = fullfile(session_folder, 'acc_test_20260312_103619.csv');
% events_file = fullfile(session_folder, 'events.csv');

if ~isfile(nidaq_file), error('accel.csv not found in %s', session_folder); end
nidaq = readtable(nidaq_file);
fprintf('Loaded accel.csv: %d rows\n', height(nidaq));

%% ── Build tables ─────────────────────────────────────────────────────────────
accel        = table();
accel.xL     = nidaq.ai1;
accel.yL     = nidaq.ai2;
accel.zL     = nidaq.ai3;
accel.xR     = nidaq.ai4;
accel.yR     = nidaq.ai5;
accel.zR     = nidaq.ai6;
accel.t_pc   = nidaq.pc_time;

force        = table();
force.F1     = nidaq.ai7  - nidaq.ai13;
force.F2     = nidaq.ai8  - nidaq.ai14;
force.F3     = nidaq.ai9  - nidaq.ai15;
force.F4     = nidaq.ai10 - nidaq.ai16;
force.F5     = nidaq.ai11 - nidaq.ai17;
force.F6     = nidaq.ai12 - nidaq.ai18;
force.t_pc   = nidaq.pc_time;

%% ── Time axis — defined from THIS data, never from workspace ─────────────────
% t0 is the first timestamp IN THIS FILE.
% Using anything else (e.g. a t0 left over from Analysis.m) will silently
% compress or shift the time axis, hiding real gaps.
t0      = accel.t_pc(1);
accel.t = accel.t_pc - t0;
force.t = force.t_pc - t0;

%% ── Sanity-check the time axis ───────────────────────────────────────────────
dt_check = diff(accel.t);
fs_est   = 1 / median(dt_check(dt_check > 0));
duration = accel.t(end);
n_gaps   = sum(dt_check > 5/accel_fs);   % gaps > 5 samples

fprintf('\nTime axis sanity check:\n');
fprintf('  Duration          : %.3f s\n',  duration);
fprintf('  Samples           : %d\n',       height(accel));
fprintf('  Expected samples  : %d\n',       round(duration * accel_fs));
fprintf('  Missing samples   : %d\n',       round(duration * accel_fs) - height(accel));
fprintf('  Estimated fs      : %.2f Hz\n',  fs_est);
fprintf('  Gaps (>5 samples) : %d\n',       n_gaps);
if n_gaps > 0
    gap_pos = find(dt_check > 5/accel_fs);
    fprintf('  Largest gap: %.4f s at t=%.3f s\n', max(dt_check(gap_pos)), accel.t(gap_pos(1)));
end

%% ── Events ───────────────────────────────────────────────────────────────────
% event_times = [];
% if isfile(events_file)
%     events = readtable(events_file);
%     col = intersect({'recording_time','pc_time'}, events.Properties.VariableNames);
%     if ~isempty(col)
%         event_times = events.(col{1}) - t0;
%         fprintf('Loaded %d events\n', numel(event_times));
%     end
% end

%% ── Force total ──────────────────────────────────────────────────────────────
force_cols  = {'F1','F2','F3','F4','F5','F6'};
force.total = zeros(height(force), 1);
for i = 1:numel(force_cols)
    force.total = force.total + force.(force_cols{i});
end

%% ── Raw 6-axis overview ──────────────────────────────────────────────────────
chan_names  = {'xL','yL','zL','xR','yR','zR'};
ch_colors   = {[0.8 0.1 0.1],[0.1 0.6 0.1],[0.1 0.2 0.8], ...
               [1.0 0.5 0.0],[0.0 0.7 0.7],[0.6 0.0 0.8]};
side_labels = {'Left','Left','Left','Right','Right','Right'};
axis_labels = {'X','Y','Z','X','Y','Z'};

figure('Name','Raw Accelerometer','Position',[50 50 1400 900]);
ax_raw = gobjects(6,1);
for k = 1:6
    ax_raw(k) = subplot(6,1,k);
    plot(accel.t, accel.(chan_names{k}), 'Color',ch_colors{k}, 'LineWidth',0.5);
    % hold on; add_event_markers(gca, event_times);
    ylabel('V'); grid on;
    title(sprintf('%s — %s', side_labels{k}, axis_labels{k}), 'FontWeight','normal');
end
linkaxes(ax_raw,'x');
xlabel(ax_raw(6),'Time (s)');
sgtitle('Raw Accelerometer — All 6 Axes','FontWeight','bold');

%% ── Bandpassed panels ────────────────────────────────────────────────────────
plot_accel_6panel(accel.t, accel.xL, accel.yL, accel.zL, event_times, accel_fs, bp_lo, bp_hi, 'Left sensor');
plot_accel_6panel(accel.t, accel.xR, accel.yR, accel.zR, event_times, accel_fs, bp_lo, bp_hi, 'Right sensor');

%% ── Force channels ───────────────────────────────────────────────────────────
f_colors = lines(6);
figure('Name','Force Channels','Position',[100 50 1400 900]);
ax_force = gobjects(6,1);
for k = 1:6
    ax_force(k) = subplot(6,1,k);
    plot(force.t, force.(force_cols{k}), 'Color',f_colors(k,:), 'LineWidth',0.5);
    hold on; add_event_markers(gca, event_times);
    ylabel('V'); grid on;
    title(force_cols{k}, 'FontWeight','normal');
end
linkaxes(ax_force,'x');
xlabel(ax_force(6),'Time (s)');
sgtitle('Force Channels (differential pairs)','FontWeight','bold');


%% ════════════════════════════════════════════════════════════════════════════
function plot_accel_6panel(t, x, y, z, event_times, Fs, bp_lo, bp_hi, label)
    xbp   = bandpass(x, [bp_lo bp_hi], Fs);
    ybp   = bandpass(y, [bp_lo bp_hi], Fs);
    zbp   = bandpass(z, [bp_lo bp_hi], Fs);
    sumbp = xbp + ybp + zbp;
    [SPEC_f, freq] = positiveFFT(sumbp, Fs);

    figure('Name',['Accel 6-panel: ' label],'Position',[50 50 1400 1100]);
    sgtitle(sprintf('Accel — Bandpass [%d–%d Hz] | %s', bp_lo, bp_hi, label), ...
        'FontWeight','bold','FontSize',10);

    ax1 = subplot(5,1,1);
    plot(t, xbp,'Color',[0.8 0.1 0.1],'LineWidth',0.6);
    hold on; add_event_markers(gca, event_times);
    ylabel('X (V)'); title('X axis (bandpassed)'); grid on;

    ax2 = subplot(5,1,2);
    plot(t, ybp,'Color',[0.1 0.6 0.1],'LineWidth',0.6);
    hold on; add_event_markers(gca, event_times);
    ylabel('Y (V)'); title('Y axis (bandpassed)'); grid on;

    ax3 = subplot(5,1,3);
    plot(t, zbp,'Color',[0.1 0.2 0.8],'LineWidth',0.6);
    hold on; add_event_markers(gca, event_times);
    ylabel('Z (V)'); title('Z axis (bandpassed)'); grid on;

    ax4 = subplot(5,1,4);
    plot(t, sumbp,'Color',[0.5 0 0.7],'LineWidth',0.6);
    hold on; add_event_markers(gca, event_times);
    ylabel('Sum (V)'); title('Sum X+Y+Z (bandpassed)'); grid on;

    ax5 = subplot(5,1,5);
    plot(freq, abs(SPEC_f),'k','LineWidth',0.7);
    xlabel('Frequency (Hz)'); ylabel('|FFT|');
    title('Spectrum of Sum (bandpassed)'); grid on;
    xlim([0 Fs/2]);

    linkaxes([ax1 ax2 ax3 ax4],'x');
    xlabel(ax4,'Time (s)');
end

function [Y, f] = positiveFFT(x, Fs)
    N = length(x);
    Y = fft(x) / N;
    Y = Y(1:floor(N/2)+1);
    Y(2:end-1) = 2*Y(2:end-1);
    f = Fs*(0:floor(N/2))/N;
end

function add_event_markers(ax, event_times)
    if isempty(event_times), return; end
    yl = ylim(ax);
    for k = 1:numel(event_times)
        xline(ax, event_times(k), '--', 'Color',[0.9 0.6 0.0], 'LineWidth',1.2, 'Alpha',0.8);
    end
    ylim(ax, yl);
end