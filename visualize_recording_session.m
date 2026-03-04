%% ========================================================================
% Unified Multi-Sensor Visualization (PC Timestamp Aligned)
% Signals plotted in true chronological order
% ========================================================================
%------------------------------------------------------------------------
% Session path
%% ------------------------------------------------------------------------
session_folder = '/home/acatalano/VIRTUES/recordings/subject_yh01/level_L1/rep_02';
session_folder = replace(session_folder, '~', getenv('HOME'));
 %------------------------------------------------------------------------
% Load CSV files
% ------------------------------------------------------------------------
gsr_file    = fullfile(session_folder,'gsr.csv');
eye_file    = fullfile(session_folder,'eye.csv');
accel_file  = fullfile(session_folder,'accel.csv');
events_file = fullfile(session_folder,'events.csv');

if exist(gsr_file,'file'),   gsr   = readtable(gsr_file);   else, gsr   = []; end
if exist(eye_file,'file'),   eye   = readtable(eye_file);   else, eye   = []; end
if exist(accel_file,'file'), accel = readtable(accel_file); else, accel = []; end
if exist(events_file,'file'),events = readtable(events_file);else, events=[]; end

fprintf('Loaded samples:\n');
fprintf('  GSR:    %d\n', height(gsr));
fprintf('  Eye:    %d\n', height(eye));
fprintf('  Accel:  %d\n', height(accel));
fprintf('  Events: %d\n\n', height(events));

%% ------------------------------------------------------------------------
% Extract PC timestamps (ABSOLUTE timeline)
% ------------------------------------------------------------------------
% These define when each signal actually occurred on the same clock

all_pc_times = [];

if ~isempty(gsr)
    gsr.t_pc = gsr.pc_time;
    all_pc_times = [all_pc_times; gsr.t_pc];
end

if ~isempty(eye)
    eye.t_pc = eye.pc_timestamp;
    all_pc_times = [all_pc_times; eye.t_pc];
end

if ~isempty(accel)
    accel.t_pc = accel.pc_time;
    all_pc_times = [all_pc_times; accel.t_pc];
end

if ~isempty(events)
    events.t_pc = events.recording_time;
    all_pc_times = [all_pc_times; events.t_pc];
end

% Global reference (earliest PC timestamp)
t0 = min(all_pc_times);

% Convert to relative seconds (for plotting)
if ~isempty(gsr),   gsr.t   = gsr.t_pc   - t0; end
if ~isempty(eye),   eye.t   = eye.t_pc   - t0; end
if ~isempty(accel), accel.t = accel.t_pc - t0; end
if ~isempty(events)
    event_times = events.t_pc - t0;
else
    event_times = [];
end

fprintf('Unified PC timeline:\n');
fprintf('  Start: %.3f s\n', 0);
fprintf('  End:   %.3f s\n\n', max(all_pc_times - t0));

%% ------------------------------------------------------------------------
% PUPIL NOISE ANALYSIS (unchanged logic, uses raw eye signal)
%% ------------------------------------------------------------------------
if ~isempty(eye)

    left_raw  = eye.pupil_diameter_left;
    right_raw = eye.pupil_diameter_right;

    detr_left  = detrend(left_raw);
    detr_right = detrend(right_raw);

    fprintf('Noise STD   L: %.4f | R: %.4f\n', ...
        std(detr_left,'omitnan'), std(detr_right,'omitnan'));

    fs = 1 / median(diff(eye.recording_time));

    [pxxL,fL] = pwelch(left_raw,[],[],[],fs);
    [pxxR,fR] = pwelch(right_raw,[],[],[],fs);

    cutoff = 1; % Hz
    hfL = trapz(fL(fL>cutoff), pxxL(fL>cutoff)) / trapz(fL,pxxL);
    hfR = trapz(fR(fR>cutoff), pxxR(fR>cutoff)) / trapz(fR,pxxR);

    fprintf('HF ratio    L: %.3f | R: %.3f\n', hfL, hfR);

    fprintf('RMS diff    L: %.4f | R: %.4f\n\n', ...
        rms(diff(left_raw),'omitnan'), rms(diff(right_raw),'omitnan'));
end

%% ------------------------------------------------------------------------
% Blink signal (already provided by Neon)
%% ------------------------------------------------------------------------
if ~isempty(eye)
    blink = eye.blink;
end

%% ------------------------------------------------------------------------
% VISUALIZATION (PC-time aligned)
%% ------------------------------------------------------------------------
nPlots = 0;
if ~isempty(gsr),   nPlots = nPlots + 1; end
if ~isempty(eye),   nPlots = nPlots + 5; end
if ~isempty(accel), nPlots = nPlots + 3; end

figure('Name','Unified Multi-Sensor Timeline (PC Time)', ...
       'Position',[100 50 1500 220*nPlots]);

p = 1;

%% GSR
if ~isempty(gsr)
    subplot(nPlots,1,p)
    plot(gsr.t, gsr.GSR_ohm,'b','LineWidth',1)
    ylabel('GSR (Ω)')
    title('GSR – Shimmer (PC-aligned)')
    grid on; hold on
    for t = event_times', xline(t,'k--','LineWidth',1.2); end
    p = p + 1;
end

%% Eye tracking
if ~isempty(eye)
    % subplot(nPlots,1,p)
    % scatter(eye.x, eye.y,'r')
    % ylabel('Gaze X')
    % title('Gaze X – Neon')
    % grid on; hold on
    % for t = event_times', xline(t,'k--'); end
    %p = p + 1;
    % 
    % subplot(nPlots,1,p)
    % plot(eye.t, eye.y,'r')
    % ylabel('Gaze Y')
    % title('Gaze Y – Neon')
    % grid on; hold on
    % for t = event_times', xline(t,'k--'); end
    % p = p + 1;

    subplot(nPlots,1,p)
    plot(eye.t, eye.pupil_diameter_left,'b'); hold on
    plot(eye.t, eye.pupil_diameter_right,'g')
    ylabel('Pupil (mm)')
    title('Pupil Diameter')
    legend('Left','Right')
    grid on
    for t = event_times', xline(t,'k--'); end
    p = p + 1;

    subplot(nPlots,1,p)
    stairs(eye.t, blink,'k','LineWidth',1.5)
    ylabel('Blink')
    ylim([-0.1 1.1])
    title('Blink Detection')
    grid on
    for t = event_times', xline(t,'k--'); end
    p = p + 1;
end

%% Accelerometer (example: first 3 channels)
if ~isempty(accel)
    subplot(nPlots,1,p)
    plot(accel.t, accel.ai1)
    ylabel('Accel 1'); grid on; hold on
    for t = event_times', xline(t,'k--'); end
    p = p + 1;

    subplot(nPlots,1,p)
    plot(accel.t, accel.ai2)
    ylabel('Accel 2'); grid on; hold on
    for t = event_times', xline(t,'k--'); end
    p = p + 1;

    subplot(nPlots,1,p)
    plot(accel.t, accel.ai3)
    ylabel('Accel 3'); grid on; hold on
    for t = event_times', xline(t,'k--'); end
    p = p + 1;
end

xlabel('Time (s) – PC unified timeline')
linkaxes(findall(gcf,'Type','axes'),'x')

fprintf('PC-aligned visualization complete.\n');

figure;
    scatter(eye.x, eye.y,'r')
    ylabel('Gaze X')
    title('Gaze X – Neon')