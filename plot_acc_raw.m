%% Accelerometer_6panel.m
clear; clc; close all;

output_root = fullfile(expanduser('~'), 'Desktop', 'Virtues_Data');
mat_folder  = fullfile(output_root, 'subject_s03H', 'level_L5/rep_05');

bp_lo = 80; bp_hi = 1000;

L = load(fullfile(mat_folder,'accel.mat')); ACCEL = L.ACCEL;
has_event = isfile(fullfile(mat_folder,'events.mat'));
event_times = [];
if has_event
    L = load(fullfile(mat_folder,'events.mat')); event_times = L.EVENTS.time_rel;
end

t  = ACCEL.time_rel;
fs = ACCEL.fs_nominal;

get_ch = @(name) ACCEL.data(:, find(strcmp(ACCEL.channel_names,name),1));
xL = get_ch('ai9');  yL = get_ch('ai10'); zL = get_ch('ai11');
xR = get_ch('ai12'); yR = get_ch('ai13'); zR = get_ch('ai14');

bp = @(x) bandpass(x,[bp_lo bp_hi],fs);
xLb=bp(xL); yLb=bp(yL); zLb=bp(zL);
xRb=bp(xR); yRb=bp(yR); zRb=bp(zR);

labels = {'Left X','Left Y','Left Z','Right X','Right Y','Right Z'};
data   = {xLb, yLb, zLb, xRb, yRb, zRb};
cols   = {[0.8 0.1 0.1],[0.1 0.6 0.1],[0.1 0.2 0.8], ...
          [1.0 0.5 0.0],[0.0 0.7 0.7],[0.6 0.0 0.8]};

fig = figure();
ax  = gobjects(6,1);
for k = 1:6
    ax(k) = subplot(6,1,k); hold on;
    plot(t, data{k}, 'Color', cols{k}, 'LineWidth', 0.6);
    for e = 1:numel(event_times)
        xline(event_times(e),'--','Color',[0.9 0.6 0],'LineWidth',1.2,'Alpha',0.8);
    end
    ylabel('m/s²'); title(labels{k},'FontWeight','normal'); grid on;
end
linkaxes(ax,'x');
xlabel(ax(6),'Time (s)');
sgtitle(sprintf('Bandpassed [%d–%d Hz] — Left (top 3) and Right (bottom 3) | %s', ...
    bp_lo, bp_hi, strrep(mat_folder,output_root,'')),'FontWeight','bold','FontSize',10);

function p = expanduser(p)
    if strncmp(p,'~',1)
        home=getenv('HOME'); if isempty(home), home=getenv('USERPROFILE'); end
        p=[home p(2:end)];
    end
end