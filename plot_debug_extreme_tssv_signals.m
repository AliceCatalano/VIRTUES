%% plot_extreme_tssv_signals.m
clear; clc; close all; cfg = config();
FV = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); T=FV.T;

Tvalid = T(isfinite(T.tssv) & T.tssv > 0, :);
Tvalid.log_tssv = log(Tvalid.tssv);
Tvalid = sortrows(Tvalid, 'log_tssv', 'ascend');

cases = {Tvalid(1,:),   'LOWEST TSSV';
         Tvalid(end,:), 'HIGHEST TSSV'};

BP_LOW = 80; BP_HIGH = 1000;
fig = figure('Position',[50 50 1600 900]);
tl  = tiledlayout(2, 3, 'TileSpacing','compact','Padding','compact');

for ci = 1:2
    r   = cases{ci,1};
    lbl = cases{ci,2};
    subj = r.subject{1}; phase = r.phase{1}; acq = r.acquisition{1};

    % resolve acquisition directory
    if strcmp(r.phase_type{1}, 'test')
        acq_dir = fullfile(cfg.data_root, subj, phase);
    else
        acq_dir = fullfile(cfg.data_root, subj, phase, acq);
        if ~isfolder(acq_dir), acq_dir = [acq_dir '_R']; end
    end

    ev_path = fullfile(acq_dir, 'events.mat');
    ac_path = fullfile(acq_dir, 'accel.mat');
    if ~isfile(ev_path) || ~isfile(ac_path)
        fprintf('Missing files for %s\n', lbl); continue;
    end

    [t_start, t_end] = safe_trial_window(ev_path);
    LA = load(ac_path, 'ACCEL');
    t_a = LA.ACCEL.time_rel(:); fs = LA.ACCEL.fs_nominal; dt = 1/fs;

    bm = t_a >= (t_start-1.0) & t_a < t_start;
    if sum(bm) < 3, bm = t_a < (t_a(1)+1.0); end
    bias = mean(LA.ACCEL.data(bm,:), 1, 'omitnan');
    raw_ms2 = (LA.ACCEL.data - bias) * cfg.accel_sensitivity_ms2_per_V;

    tm = t_a >= t_start & t_a <= t_end;
    seg = raw_ms2(tm,:); t_win = t_a(tm) - t_start;

    seg_bp = seg;
    if fs/2 > BP_HIGH
        [b,a] = butter(4, [BP_LOW BP_HIGH]/(fs/2), 'bandpass');
        for c = 1:6, seg_bp(:,c) = filtfilt(b,a,double(seg(:,c))); end
    end

    A_left  = sum(seg_bp(:,1:3), 2);
    A_right = sum(seg_bp(:,4:6), 2);
    AL = A_left;  AR = A_right;
    AL(abs(AL) < cfg.tssv_noise_threshold_ms2) = 0;
    AR(abs(AR) < cfg.tssv_noise_threshold_ms2) = 0;
    A_comb = AL + AR;

    title_str = sprintf('%s\n%s | %s | %s | rep%s\nlog-TSSV=%.3f  raw=%.3e (m/s²)²·s', ...
        lbl, strrep(subj,'subject_',''), phase, acq, ...
        num2str(r.repetition), log(r.tssv), r.tssv);

    % Raw signal panel
    nexttile; hold on;
    plot(t_win, seg(:,1), 'Color',[0.6 0.6 0.6], 'LineWidth',0.5, 'DisplayName','Lx raw');
    plot(t_win, seg(:,4), 'Color',[0.3 0.3 0.9], 'LineWidth',0.5, 'DisplayName','Rx raw');
    xlabel('Time (s)'); ylabel('m/s²');
    title([title_str newline 'Raw (bias removed)'], 'FontSize',7);
    legend('FontSize',7); grid on;

    % Bandpassed per side
    nexttile; hold on;
    plot(t_win, A_left,  'Color',[0.1 0.6 0.1], 'LineWidth',0.8, 'DisplayName','Left signed sum');
    plot(t_win, A_right, 'Color',[0.8 0.2 0.1], 'LineWidth',0.8, 'DisplayName','Right signed sum');
    yline( cfg.tssv_noise_threshold_ms2,'k--','LineWidth',1,'HandleVisibility','off');
    yline(-cfg.tssv_noise_threshold_ms2,'k--','LineWidth',1,'HandleVisibility','off');
    xlabel('Time (s)'); ylabel('m/s²');
    title('Bandpassed 80–1000 Hz signed sums', 'FontSize',8);
    legend('FontSize',7); grid on;

    % Combined thresholded signal and TSSV integrand
    nexttile; hold on;
    plot(t_win, A_comb.^2 * dt, 'k-', 'LineWidth',0.8, 'DisplayName','A²·dt integrand');
    area(t_win, A_comb.^2 * dt, 'FaceColor',[0.2 0.5 0.8], 'FaceAlpha',0.3, 'EdgeColor','none', 'HandleVisibility','off');
    xlabel('Time (s)'); ylabel('(m/s²)²·s per sample');
    title(sprintf('TSSV integrand (sum=%.4e)', r.tssv), 'FontSize',8);
    legend('FontSize',7); grid on;
end

sgtitle('Extreme TSSV values: lowest and highest clean acquisition', 'FontWeight','bold','FontSize',11);
exportgraphics(fig, fullfile(cfg.output_root,'figures','extreme_tssv_signals.png'), 'Resolution',150);
fprintf('Saved extreme_tssv_signals.png\n');

%% inspect_extreme_tssf_subjects.m
clear; clc; close all; cfg = config();
C_force = load_ati_cal(cfg.force_cal_path);

cases = {
    'subject_s37N', 'level_L4', 'rep_05', 'MAX: s37N L4r5 (raw=19M N²)'
    'subject_s27N', 'level_L4', 'rep_04', 'MIN: s27N L4r4 (raw=870 N²)'
    'subject_s38H', 'level_L4', 'rep_06', 'HIGH: s38H L4r6 (raw=35M N²)'
    'subject_s40H', 'level_L3', 'rep_05', 'NORMAL reference (s40H L3r5)'
};

fig = figure('Position',[50 50 1800 1200]);
tl = tiledlayout(4, 3, 'TileSpacing','compact','Padding','compact');
sgtitle('Raw force traces: extreme TSSF values vs normal reference','FontWeight','bold');

for ci = 1:size(cases,1)
    subj = cases{ci,1}; phase = cases{ci,2};
    acq  = cases{ci,3}; lbl   = cases{ci,4};

    acq_dir = fullfile(cfg.data_root, subj, phase, acq);
    if ~isfolder(acq_dir), acq_dir = [acq_dir '_R']; end
    if ~isfolder(acq_dir)
        fprintf('Missing: %s\n', lbl); continue;
    end

    ev_path = fullfile(acq_dir,'events.mat');
    fo_path = fullfile(acq_dir,'force.mat');
    if ~isfile(ev_path) || ~isfile(fo_path)
        fprintf('Missing files: %s\n', lbl); continue;
    end

    [t_start, t_end] = safe_trial_window(ev_path);
    LF = load(fo_path,'FORCE');
    t_f = LF.FORCE.time_rel(:);
    rv  = LF.FORCE.data;

    % bias removal
    bm = t_f >= (t_start-1.0) & t_f < t_start;
    if sum(bm) < 3, bm = t_f < (t_f(1)+1.0); end
    bias = mean(rv(bm,:), 1, 'omitnan');

    % calibrate
    F_cal = (C_force * (rv - bias)')';
    Fmag  = sqrt(sum(F_cal(:,1:3).^2, 2));
    tm    = t_f >= t_start & t_f <= t_end;
    t_win = t_f(tm) - t_start;

    % compute TSSF for this trial
    Fmag_trial = Fmag(tm);
    nf = median(Fmag_trial) + cfg.force_noise_k_mad * mad(Fmag_trial,1);
    Fm_thresh = Fmag_trial; Fm_thresh(Fm_thresh < nf) = 0;
    tssf_val = sum(Fm_thresh.^2);

    % Panel 1: raw force magnitude full trial
    nexttile; hold on;
    plot(t_win, Fmag_trial, 'k-', 'LineWidth',0.5);
    yline(nf, 'r--', 'LineWidth',1.2, 'DisplayName',sprintf('noise floor=%.2f N',nf));
    xlabel('Time (s)'); ylabel('Force magnitude (N)');
    title(sprintf('%s\nTSSF=%.2e N²  max_Fmag=%.1f N', lbl, tssf_val, max(Fmag_trial)), 'FontSize',8, 'Interpreter','none');
    grid on; legend('FontSize',7);

    % Panel 2: zoom on first 5 seconds
    nexttile; hold on;
    zm = t_win <= 5;
    plot(t_win(zm), Fmag_trial(zm), 'b-', 'LineWidth',0.8);
    yline(nf, 'r--', 'LineWidth',1.2);
    xlabel('Time (s)'); ylabel('Force magnitude (N)');
    title(sprintf('First 5 seconds\nmax=%.1f N  mean=%.2f N', max(Fmag_trial(zm)), mean(Fmag_trial(zm))), 'FontSize',8);
    grid on;

    % Panel 3: all 6 calibrated channels
    nexttile; hold on;
    ch_names = {'Fx','Fy','Fz','Tx','Ty','Tz'};
    cols6 = lines(6);
    for c = 1:6
        plot(t_win, F_cal(tm,c), 'Color',cols6(c,:), 'LineWidth',0.4, 'DisplayName',ch_names{c});
    end
    xlabel('Time (s)'); ylabel('N or N·m');
    title('All 6 calibrated channels', 'FontSize',8);
    legend('FontSize',6,'NumColumns',2); grid on;
end

exportgraphics(fig, fullfile(cfg.output_root,'figures','extreme_tssf_inspection.png'), 'Resolution',150);
fprintf('Saved extreme_tssf_inspection.png\n');