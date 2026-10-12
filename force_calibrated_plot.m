%% force_calibrated_plot.m
clear; clc;

output_root = fullfile(expanduser('~'), 'Desktop', 'Virtues_Data');
mat_folder  = fullfile(output_root, 'subject_s30N', 'Test1/');
cal_path    = fullfile(output_root, 'FT29125.cal');

L = load(fullfile(mat_folder,'force.mat')); FORCE=L.FORCE;
L = load(fullfile(mat_folder,'events.mat')); EVENTS=L.EVENTS;
event_times = EVENTS.time_rel;

C = load_ati_cal(cal_path);
cfg = config();

t_f = FORCE.time_rel(:);
rv  = FORCE.data;

t_start = event_times(1); t_end = event_times(end);
bm = t_f>=(t_start-1.0) & t_f<t_start;
if sum(bm)<3, bm=t_f<(t_f(1)+1.0); end
bias = mean(rv(bm,:),1,'omitnan');
F_cal = (C*(rv-bias)')';   % [n x 6] N and N·m

tm = t_f>=t_start & t_f<=t_end;
t_win = t_f(tm);
F_trial = F_cal(tm,:);

%% OLD formula: magnitude of Fx,Fy,Fz then square
Fmag_old = sqrt(sum(F_trial(:,1:3).^2, 2));
nf_old   = median(Fmag_old) + cfg.force_noise_k_mad * mad(Fmag_old,1);
Fmag_thresh_old = Fmag_old;
Fmag_thresh_old(Fmag_thresh_old < nf_old) = 0;
integrand_old = Fmag_thresh_old.^2;   % per-sample contribution (N²)
tssf_old = sum(integrand_old);

%% NEW formula: signed sum of Fx+Fy+Fz then square (same structure as TSSV)
F_sum_new = sum(F_trial(:,1:3), 2);   % Fx + Fy + Fz, signed
nf_new    = median(abs(F_sum_new)) + cfg.force_noise_k_mad * mad(F_sum_new,1);
F_sum_thresh = F_sum_new;
F_sum_thresh(abs(F_sum_thresh) < nf_new) = 0;
integrand_new = F_sum_thresh.^2;      % per-sample contribution (N²)
tssf_new = sum(integrand_new);

fprintf('=== s30N level_L4 rep_06 ===\n');
fprintf('OLD (magnitude): noise_floor=%.3f N   TSSF=%.4e N²\n', nf_old, tssf_old);
fprintf('NEW (signed sum): noise_floor=%.3f N   TSSF=%.4e N²\n', nf_new, tssf_new);
fprintf('Ratio OLD/NEW: %.1f×\n', tssf_old/tssf_new);

%% Figure 1: all 6 calibrated channels
ch_names = {'Fx (N)','Fy (N)','Fz (N)','Tx (N·m)','Ty (N·m)','Tz (N·m)'};
cols6 = {[0.8 0.1 0.1],[0.1 0.6 0.1],[0.1 0.2 0.8],[1.0 0.5 0],[0 0.7 0.7],[0.6 0 0.8]};

figure('Position',[50 50 1800 900]);
ax=gobjects(6,1);
for k=1:6
    ax(k)=subplot(6,1,k); hold on;
    plot(t_f, F_cal(:,k), 'Color',cols6{k}, 'LineWidth',0.6);
    for e=1:numel(event_times)
        xline(event_times(e),'--','Color',[0.9 0.6 0],'LineWidth',1.0,'Alpha',0.7);
    end
    xline(t_start,'k-','LineWidth',1.5,'HandleVisibility','off');
    xline(t_end,  'k-','LineWidth',1.5,'HandleVisibility','off');
    ylabel(ch_names{k},'FontSize',8); grid on;
    title(ch_names{k},'FontWeight','normal','FontSize',9);
end
linkaxes(ax,'x'); xlabel(ax(6),'Time (s)');
sgtitle('s30N Test1 — Calibrated force channels (orange=events, black=trial window)', ...
    'FontWeight','bold','FontSize',11);

%% Figure 2: old vs new formula comparison
figure('Position',[50 50 1800 900]);
tl = tiledlayout(3,1,'TileSpacing','compact','Padding','compact');
sgtitle(sprintf('s30N Test1 — OLD vs NEW TSSF formula\nOLD=%.3e N²   NEW=%.3e N²   Ratio=%.1f×', ...
    tssf_old, tssf_new, tssf_old/tssf_new), 'FontWeight','bold','FontSize',11);

% Panel 1: raw signals being combined
nexttile; hold on;
plot(t_win, F_trial(:,1), 'Color',[0.8 0.1 0.1], 'LineWidth',0.6, 'DisplayName','Fx');
plot(t_win, F_trial(:,2), 'Color',[0.1 0.6 0.1], 'LineWidth',0.6, 'DisplayName','Fy');
plot(t_win, F_trial(:,3), 'Color',[0.1 0.2 0.8], 'LineWidth',0.6, 'DisplayName','Fz');
yline(0,'k--','LineWidth',0.8,'HandleVisibility','off');
xlabel('Time (s)'); ylabel('Force (N)');
title('Individual force components (trial window only)','FontSize',9);
legend('FontSize',8,'Location','best'); grid on;

% Panel 2: OLD integrand — magnitude squared
nexttile; hold on;
plot(t_win, integrand_old, 'Color',[0.8 0.3 0.1], 'LineWidth',0.8, 'DisplayName', ...
    sprintf('OLD: |F|² (magnitude²)\nTSSF=%.3e N²  nf=%.3f N',tssf_old,nf_old));
yline(nf_old^2, 'r--', 'LineWidth',1.2, 'DisplayName',sprintf('noise floor² = %.2f N²',nf_old^2));
xlabel('Time (s)'); ylabel('N²');
title(sprintf('OLD formula: Fmag² where Fmag=sqrt(Fx²+Fy²+Fz²), thresholded at %.3f N',nf_old),'FontSize',9);
legend('FontSize',8,'Location','best'); grid on;

% Panel 3: NEW integrand — signed sum squared
nexttile; hold on;
plot(t_win, integrand_new, 'Color',[0.1 0.4 0.8], 'LineWidth',0.8, 'DisplayName', ...
    sprintf('NEW: (Fx+Fy+Fz)² (signed sum²)\nTSSF=%.3e N²  nf=%.3f N',tssf_new,nf_new));
yline(nf_new^2, 'r--', 'LineWidth',1.2, 'DisplayName',sprintf('noise floor² = %.2f N²',nf_new^2));
xlabel('Time (s)'); ylabel('N²');
title(sprintf('NEW formula: (Fx+Fy+Fz)², thresholded at %.3f N — same structure as TSSV',nf_new),'FontSize',9);
legend('FontSize',8,'Location','best'); grid on;

function p=expanduser(p)
    if strncmp(p,'~',1)
        home=getenv('HOME');
        if isempty(home), home=getenv('USERPROFILE'); end
        p=[home p(2:end)];
    end
end