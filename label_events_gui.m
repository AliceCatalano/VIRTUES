function label_events_gui(subj_folder, phase, acquisition)
% Click near an event on either plot, then choose Collision/Movement/Undo.
% Saves manual_labels.mat in the acquisition folder. Right-click or Enter to finish.

acq_folder = fullfile(subj_folder, phase, acquisition);
A = load(fullfile(acq_folder,'accel.mat')); ACCEL = A.ACCEL;
U = load(fullfile(acq_folder,'audio.mat')); AUDIO = U.AUDIO;
E = load(fullfile(acq_folder,'events.mat')); EVENTS = E.EVENTS;

V2G = 1/0.4; N_BL = 50;
ch = arrayfun(@(c) baseline_and_scale(ACCEL.data(:,c),N_BL,V2G), 1:6, 'UniformOutput', false);
mag_a = max(sqrt(ch{1}.^2+ch{2}.^2+ch{3}.^2), sqrt(ch{4}.^2+ch{5}.^2+ch{6}.^2));
t_a = ACCEL.time_rel;

fs_u = AUDIO.fs_estimated;
env_u = rms_envelope(bandpass_channels(AUDIO.data, fs_u, 80, 1000), fs_u, 0.02);
t_u = AUDIO.time_rel;

t_ws = EVENTS.t_trial_start; t_we = EVENTS.t_trial_end;

fig = figure('Units','normalized','Position',[.05 .1 .9 .8]);
ax1 = subplot(2,1,1); plot(t_a,mag_a,'k'); xlim([t_ws t_we]); ylabel('NIDAQ accel (g)'); grid on; hold on;
title(sprintf('%s | %s | %s  —  click an event, right-click/Enter when done',phase,acquisition,ACCEL.source_file),'Interpreter','none');
ax2 = subplot(2,1,2); plot(t_u,env_u,'b'); xlim([t_ws t_we]); ylabel('Audiomixer env'); xlabel('time (s)'); grid on; hold on;
linkaxes([ax1 ax2],'x');

labels = struct('t',{},'type',{});
markers = {};

while true
    [x,~,btn] = ginput(1);
    if isempty(x) || btn == 3, break; end
    choice = questdlg(sprintf('Event at t = %.3f s',x),'Label event','Collision','Movement','Undo last','Collision');
    switch choice
        case 'Collision'
            labels(end+1) = struct('t',x,'type','collision'); %#ok<AGROW>
            markers{end+1} = plot_marker(ax1,ax2,t_a,mag_a,t_u,env_u,x,'ro');
        case 'Movement'
            labels(end+1) = struct('t',x,'type','movement'); %#ok<AGROW>
            markers{end+1} = plot_marker(ax1,ax2,t_a,mag_a,t_u,env_u,x,'gs');
        case 'Undo last'
            if ~isempty(labels), labels(end) = []; delete(markers{end}); markers(end) = []; end
    end
end

out.subject = subj_folder; out.phase = phase; out.acquisition = acquisition;
out.t0_unix = ACCEL.t0_unix; out.labels = labels;
save(fullfile(acq_folder,'manual_labels.mat'),'out');
n_c = sum(strcmp({labels.type},'collision')); n_m = sum(strcmp({labels.type},'movement'));
fprintf('Saved %d labels (%d collision, %d movement) -> %s\n', numel(labels), n_c, n_m, fullfile(acq_folder,'manual_labels.mat'));
close(fig);
end

function h = plot_marker(ax1,ax2,t_a,mag_a,t_u,env_u,x,style)
h1 = plot(ax1,x,interp1(t_a,mag_a,x),style,'MarkerSize',9,'LineWidth',2);
h2 = plot(ax2,x,interp1(t_u,env_u,x),style,'MarkerSize',9,'LineWidth',2);
h = [h1 h2];
end

function ch = baseline_and_scale(raw,n_base,V2G)
n_bl = min(n_base,numel(raw)); ch = (raw - mean(raw(1:n_bl))) * V2G;
end

function out = bandpass_channels(mat,fs,flo,fhi)
out = zeros(size(mat,1),1);
for k = 1:size(mat,2)
    col = double(mat(:,k)) - mean(double(mat(:,k)),'omitnan');
    if numel(col) > 10*fs, col = bandpass(col,[flo fhi],fs); end
    out = max(out,abs(col));
end
end

function env = rms_envelope(sig,fs,win_sec)
win = max(3,round(fs*win_sec)); env = sqrt(movmean(sig.^2,win));
end

function compile_manual_labels(base_folder, subjects)
% Walks subject/phase/acquisition folders, gathers manual_labels.mat into one table.
rows = {};
for s = 1:numel(subjects)
    subj_folder = fullfile(base_folder, subjects{s});
    phases = dir(subj_folder); phases = phases([phases.isdir] & ~startsWith({phases.name},'.'));
    for p = 1:numel(phases)
        phase_folder = fullfile(subj_folder, phases(p).name);
        acqs = dir(phase_folder); acqs = acqs([acqs.isdir] & ~startsWith({acqs.name},'.'));
        for a = 1:numel(acqs)
            lf = fullfile(phase_folder, acqs(a).name, 'manual_labels.mat');
            if ~isfile(lf), continue; end
            L = load(lf); out = L.out;
            for k = 1:numel(out.labels)
                rows(end+1,:) = {subjects{s}, phases(p).name, acqs(a).name, out.labels(k).t, out.labels(k).type}; %#ok<AGROW>
            end
        end
    end
end
T = cell2table(rows, 'VariableNames', {'subject','phase','acquisition','t_rel','type'});
save(fullfile(base_folder,'labels_dataset.mat'),'T');
writetable(T, fullfile(base_folder,'labels_dataset.csv'));
fprintf('Compiled %d labels -> %s\n', height(T), fullfile(base_folder,'labels_dataset.csv'));
end