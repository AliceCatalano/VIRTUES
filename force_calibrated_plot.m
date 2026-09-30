%% force_calibrated_plot.m
clear; clc;

output_root = fullfile(expanduser('~'), 'Desktop', 'Virtues_Data');
mat_folder  = fullfile(output_root, 'subject_s47H', 'Baseline2/Level2');
cal_path    = fullfile(output_root, 'FT29125.cal');

L = load(fullfile(mat_folder,'force.mat')); FORCE=L.FORCE;
L = load(fullfile(mat_folder,'events.mat')); EVENTS=L.EVENTS;
event_times = EVENTS.time_rel;

C = load_ati_cal(cal_path);
t_f = FORCE.time_rel(:);
rv  = FORCE.data;

% bias from 1s pre-trial
t_start = event_times(1); t_end = event_times(end);
bm = t_f>=(t_start-1.0) & t_f<t_start;
if sum(bm)<3, bm=t_f<(t_f(1)+1.0); end
bias = mean(rv(bm,:),1,'omitnan');
F_cal = (C*(rv-bias)')';   % [n x 6]  N and N·m

ch_names = {'Fx (N)','Fy (N)','Fz (N)','Tx (N·m)','Ty (N·m)','Tz (N·m)'};
cols = {[0.8 0.1 0.1],[0.1 0.6 0.1],[0.1 0.2 0.8],[1.0 0.5 0],[0 0.7 0.7],[0.6 0 0.8]};

figure('Position',[2500 100 1800 1900]);
ax=gobjects(6,1);
for k=1:6
    ax(k)=subplot(6,1,k); hold on;
    plot(t_f,F_cal(:,k),'Color',cols{k},'LineWidth',0.6);
    for e=1:numel(event_times), xline(event_times(e),'--','Color',[0.9 0.6 0],'LineWidth',1.2,'Alpha',0.8); end
    ylabel(ch_names{k},'FontSize',8); grid on;
    title(ch_names{k},'FontWeight','normal','FontSize',9);
end
linkaxes(ax,'x'); xlabel(ax(6),'Time (s)');
sgtitle(sprintf('Calibrated force — %s',strrep(mat_folder,output_root,'')),'FontWeight','bold');

function p=expanduser(p)
    if strncmp(p,'~',1), home=getenv('HOME'); if isempty(home), home=getenv('USERPROFILE'); end; p=[home p(2:end)]; end
end