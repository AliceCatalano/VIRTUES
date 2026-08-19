%% Accelerometer_visualization.m
% MAT-ONLY comparison for a single session — NIDAQ accel vs audiomixer accel.
% Reads exclusively from the .mat files produced by convert2mat.m
% (accel.mat, force.mat, audio.mat, events.mat). No CSV access anywhere.
%
% Run with a clean workspace (clear all) to avoid stale-variable time axis bugs.

clear; clc; close all;

output_root    = fullfile(expanduser('~'), 'Desktop', 'Virtues_Data');
mat_folder     = fullfile(output_root, 'subject_s04H', 'Baseline1', 'Level1');

bp_lo = 80; bp_hi = 1000;

fprintf('MAT folder: %s\n\n', mat_folder);

% ── Load converted MAT files ──────────────────────────────────────────────
accel_mat_file  = fullfile(mat_folder, 'accel.mat');
force_mat_file  = fullfile(mat_folder, 'force.mat');
audio_mat_file  = fullfile(mat_folder, 'audio.mat');
events_mat_file = fullfile(mat_folder, 'events.mat');

has_accel = isfile(accel_mat_file);
has_force = isfile(force_mat_file);
has_audio = isfile(audio_mat_file);
has_event = isfile(events_mat_file);

if ~has_accel, error('accel.mat not found in %s — run convert2mat.m for this session first.', mat_folder); end

L = load(accel_mat_file); ACCEL = L.ACCEL;
fprintf('Loaded accel.mat : %d samples, channels: %s\n', size(ACCEL.data,1), strjoin(ACCEL.channel_names,', '));

if has_force
    L = load(force_mat_file); FORCE = L.FORCE;
    fprintf('Loaded force.mat : %d samples, channels: %s\n', size(FORCE.data,1), strjoin(FORCE.channel_names,', '));
else
    fprintf('force.mat NOT FOUND — force panels will be skipped.\n');
end

if has_audio
    L = load(audio_mat_file); AUDIO = L.AUDIO;
    fprintf('Loaded audio.mat : %d samples, channels: %s\n', size(AUDIO.data,1), strjoin(AUDIO.channel_names,', '));
else
    fprintf('audio.mat NOT FOUND — audiomixer panels will be skipped.\n');
end

if has_event
    L = load(events_mat_file); EVENTS = L.EVENTS;
    fprintf('Loaded events.mat : %d events\n', numel(EVENTS.time_rel));
else
    fprintf('events.mat NOT FOUND — no event markers will be drawn.\n');
end

% ── Canonical t0 — every sensor was converted relative to the same t0_unix ─
t0 = ACCEL.t0_unix;
fprintf('\nt0 (from accel.mat) = %.6f\n', t0);

if has_audio
    audio_t0 = double(AUDIO.time_unix(1));
    if abs(audio_t0 - t0) > 1e-6
        msg = sprintf(['AUDIO.t0_unix (%.6f) differs from ACCEL.t0_unix (%.6f) — these were not ' ...
            'converted with a shared origin. Re-run convert2mat.m for this session.'], audio_t0, t0);
        warning(msg);
    end
end
if has_event && abs(EVENTS.t0_unix - t0) > 1e-6
    warning('EVENTS.t0_unix (%.6f) differs from ACCEL.t0_unix (%.6f).', EVENTS.t0_unix, t0);
end

% ── NIDAQ accel table (already relative time, no unit conversion) ────────
accel = table();
accel.xL = get_channel(ACCEL, 'ai9');
accel.yL = get_channel(ACCEL, 'ai10');
accel.zL = get_channel(ACCEL, 'ai11');
accel.xR = get_channel(ACCEL, 'ai12');
accel.yR = get_channel(ACCEL, 'ai13');
accel.zR = get_channel(ACCEL, 'ai14');
accel.t  = ACCEL.time_rel;
accel_fs = ACCEL.fs_nominal;

% ── Force table from force.mat (already the differential pairs) ─────────
if has_force
    force = table();
    for k = 1:numel(FORCE.channel_names)
        force.(FORCE.channel_names{k}) = FORCE.data(:,k);
    end
    force.t = FORCE.time_rel;
    force_cols = FORCE.channel_names;
end

% ── Audiomixer table from audio.mat ───────────────────────────────────────
% Mapping ch12/13/14 -> Left xyz, ch16/17/18 -> Right xyz matches this
% repo's convention (see audio_channels in the unified analysis scripts).
if has_audio
    audio = table();
    audio.xL = get_channel(AUDIO, 'ch12');
    audio.yL = get_channel(AUDIO, 'ch13');
    audio.zL = get_channel(AUDIO, 'ch14');
    audio.xR = get_channel(AUDIO, 'ch16');
    audio.yR = get_channel(AUDIO, 'ch17');
    audio.zR = get_channel(AUDIO, 'ch18');
    audio.t  = AUDIO.time_rel;
    audio_fs = AUDIO.fs_estimated;
end

% ── Time axis sanity checks ───────────────────────────────────────────────
report_time_axis('NIDAQ accel', accel.t, accel_fs);
if has_audio, report_time_axis('Audiomixer', audio.t, audio_fs); end

% ── Events ───────────────────────────────────────────────────────────────
event_times = [];
if has_event
    event_times = EVENTS.time_rel;
    fprintf('\nUsing %d events\n', numel(event_times));
end

%% ── Bandpassed panels: NIDAQ vs Audiomixer, same band, same time axis ────
plot_bp_6panel(accel.t, accel.xL, accel.yL, accel.zL, event_times, accel_fs, bp_lo, bp_hi, 'Left sensor (NIDAQ)');
plot_bp_6panel(accel.t, accel.xR, accel.yR, accel.zR, event_times, accel_fs, bp_lo, bp_hi, 'Right sensor (NIDAQ)');
if has_audio
    plot_bp_6panel(audio.t, audio.xL, audio.yL, audio.zL, event_times, audio_fs, bp_lo, bp_hi, 'Left sensor (Audiomixer)');
    plot_bp_6panel(audio.t, audio.xR, audio.yR, audio.zR, event_times, audio_fs, bp_lo, bp_hi, 'Right sensor (Audiomixer)');
end

% ── Raw 6-axis overview ──────────────────────────────────────────────────
chan_names  = {'xL','yL','zL','xR','yR','zR'};
side_labels = {'Left','Left','Left','Right','Right','Right'};
axis_labels = {'X','Y','Z','X','Y','Z'};
plot_raw6(accel.t, accel, chan_names, side_labels, axis_labels, event_times, 'Raw NIDAQ Accelerometer — All 6 Axes');
if has_audio
    plot_raw6(audio.t, audio, chan_names, side_labels, axis_labels, event_times, 'Raw Audiomixer Accelerometer — All 6 Axes');
end

% ── Force channels ───────────────────────────────────────────────────────
if has_force
    f_colors = lines(numel(force_cols));
    figure('Name','Force Channels','Position',[100 50 1400 900]);
    ax_force = gobjects(numel(force_cols),1);
    for k = 1:numel(force_cols)
        ax_force(k) = subplot(numel(force_cols),1,k);
        plot(force.t, force.(force_cols{k}), 'Color',f_colors(k,:), 'LineWidth',0.5);
        hold on; add_event_markers(gca, event_times);
        ylabel('V'); grid on; title(force_cols{k}, 'FontWeight','normal');
    end
    linkaxes(ax_force,'x'); xlabel(ax_force(end),'Time (s)');
    sgtitle('Force Channels (differential pairs, from force.mat)','FontWeight','bold');
end

% ── NIDAQ vs Audiomixer accel consistency check ──────────────────────────
if has_audio
    fprintf('\n--- NIDAQ accel vs Audiomixer accel ---\n');
    for c = chan_names
        c = c{1};
        n = min(numel(accel.(c)), numel(audio.(c)));
        d = corrcoef(accel.(c)(1:n), audio.(c)(1:n));
        fprintf('  %-3s : samples nidaq=%d audiomixer=%d  corr=%.3f\n', ...
            c, numel(accel.(c)), numel(audio.(c)), d(1,2));
    end
end

% ── Known pipeline issue flag ────────────────────────────────────────────
if has_audio && any(strcmp(AUDIO.channel_names,'pc_time'))
    warning(['AUDIO.mat channel_names contains ''pc_time'' — convert2mat.m does not exclude it ' ...
        'from AUDIO.data. AUDIO.data column order is unreliable for this subject until ' ...
        'convert2mat.m''s skip_cols is fixed and the session is reconverted.']);
end

%%
function vec = get_channel(S, name)
    idx = find(strcmp(S.channel_names, name), 1);
    if isempty(idx)
        error('Channel "%s" not found. Available: %s', name, strjoin(S.channel_names, ', '));
    end
    vec = S.data(:, idx);
end

function report_time_axis(name, t, fs_nominal)
    dt = diff(t); fs_est = 1/median(dt(dt>0)); n_gaps = sum(dt > 5/fs_nominal);
    fprintf('\n%s time axis:\n', name);
    fprintf('  Duration : %.3f s\n', t(end));
    fprintf('  Samples  : %d\n', numel(t));
    fprintf('  fs_nominal=%.1f Hz  fs_estimated=%.2f Hz\n', fs_nominal, fs_est);
    fprintf('  Gaps (>5 nominal samples): %d\n', n_gaps);
    if n_gaps > 0
        gp = find(dt > 5/fs_nominal);
        fprintf('  Largest gap: %.4f s at t=%.3f s\n', max(dt(gp)), t(gp(1)));
    end
end

function plot_bp_6panel(t, x, y, z, event_times, Fs, bp_lo, bp_hi, label)
    xbp = bandpass(x,[bp_lo bp_hi],Fs); ybp = bandpass(y,[bp_lo bp_hi],Fs); zbp = bandpass(z,[bp_lo bp_hi],Fs);
    sumbp = xbp + ybp + zbp;
    [SPEC_f, freq] = positiveFFT(sumbp, Fs);

    figure('Name',['Bandpass 6-panel: ' label],'Position',[50 50 1400 1100]);
    sgtitle(sprintf('Bandpass [%d–%d Hz] | %s', bp_lo, bp_hi, label),'FontWeight','bold','FontSize',10);

    ax1 = subplot(5,1,1); plot(t,xbp,'Color',[0.8 0.1 0.1],'LineWidth',0.6); hold on; add_event_markers(gca,event_times);
    ylabel('X'); title('X axis (bandpassed)'); grid on;
    ax2 = subplot(5,1,2); plot(t,ybp,'Color',[0.1 0.6 0.1],'LineWidth',0.6); hold on; add_event_markers(gca,event_times);
    ylabel('Y'); title('Y axis (bandpassed)'); grid on;
    ax3 = subplot(5,1,3); plot(t,zbp,'Color',[0.1 0.2 0.8],'LineWidth',0.6); hold on; add_event_markers(gca,event_times);
    ylabel('Z'); title('Z axis (bandpassed)'); grid on;
    ax4 = subplot(5,1,4); plot(t,sumbp,'Color',[0.5 0 0.7],'LineWidth',0.6); hold on; add_event_markers(gca,event_times);
    ylabel('Sum'); title('Sum X+Y+Z (bandpassed)'); grid on;
    ax5 = subplot(5,1,5); plot(freq,abs(SPEC_f),'k','LineWidth',0.7);
    xlabel('Frequency (Hz)'); ylabel('|FFT|'); title('Spectrum of Sum'); grid on; xlim([0 Fs/2]);

    linkaxes([ax1 ax2 ax3 ax4],'x'); xlabel(ax4,'Time (s)');
end

function plot_raw6(t, tbl, chan_names, side_labels, axis_labels, event_times, ttl)
    ch_colors = {[0.8 0.1 0.1],[0.1 0.6 0.1],[0.1 0.2 0.8],[1.0 0.5 0.0],[0.0 0.7 0.7],[0.6 0.0 0.8]};
    figure('Name',ttl,'Position',[50 50 1400 900]);
    ax = gobjects(6,1);
    for k = 1:6
        ax(k) = subplot(6,1,k);
        plot(t, tbl.(chan_names{k}), 'Color',ch_colors{k}, 'LineWidth',0.5);
        hold on; add_event_markers(gca, event_times);
        ylabel('V'); grid on; title(sprintf('%s — %s', side_labels{k}, axis_labels{k}), 'FontWeight','normal');
    end
    linkaxes(ax,'x'); xlabel(ax(6),'Time (s)'); sgtitle(ttl,'FontWeight','bold');
end

function [Y, f] = positiveFFT(x, Fs)
    N = length(x); Y = fft(x)/N; Y = Y(1:floor(N/2)+1); Y(2:end-1) = 2*Y(2:end-1); f = Fs*(0:floor(N/2))/N;
end

function add_event_markers(ax, event_times)
    if isempty(event_times), return; end
    yl = ylim(ax);
    for k = 1:numel(event_times)
        xline(ax, event_times(k), '--', 'Color',[0.9 0.6 0.0], 'LineWidth',1.2, 'Alpha',0.8);
    end
    ylim(ax, yl);
end

function p = expanduser(p)
    if strncmp(p,'~',1)
        home = getenv('HOME'); if isempty(home), home = getenv('USERPROFILE'); end
        p = [home, p(2:end)];
    end
end