clear; clc; cfg = config();
FV = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); FV = FV.T;

Tsub = FV(strcmp(FV.phase_type,'test') & isfinite(FV.tssv) & FV.tssv > 0, :);
subj = unique(Tsub.subject);
xs   = nan(numel(subj),2);
for si = 1:numel(subj)
    s = subj{si};
    v1 = Tsub.tssv(strcmp(Tsub.subject,s) & strcmp(Tsub.phase,'Test1'));
    v2 = Tsub.tssv(strcmp(Tsub.subject,s) & strcmp(Tsub.phase,'Test2'));
    if ~isempty(v1), xs(si,1) = v1; end
    if ~isempty(v2), xs(si,2) = v2; end
end

[min_t1, imin_t1] = min(xs(:,1));
[max_t1, imax_t1] = max(xs(:,1));
[min_t2, imin_t2] = min(xs(:,2));
[max_t2, imax_t2] = max(xs(:,2));

cases = {subj{imin_t1}, sprintf('Min TSSV Test1  (%.3f m²/s³)', min_t1); ...
         subj{imax_t1}, sprintf('Max TSSV Test1  (%.3f m²/s³)', max_t1); ...
         subj{imin_t2}, sprintf('Min TSSV Test2  (%.3f m²/s³)', min_t2); ...
         subj{imax_t2}, sprintf('Max TSSV Test2  (%.3f m²/s³)', max_t2)};

fprintf('Extreme subjects:\n');
for ci = 1:4
    fprintf('  %s  —  %s\n', cases{ci,1}, cases{ci,2});
end

LR = load(fullfile(cfg.output_root,'tssv_left_right.mat'),'T'); LR = LR.T;

BP_HIGH = 1000;
BP_LOW  = 80;
phases_to_plot = {'Test1','Test2'};
colors_LR = [0.2 0.5 0.9; 0.9 0.3 0.2];   % left=blue, right=red

all_segs   = cell(4,2);  
all_t_w    = cell(4,2);
all_ev     = cell(4,2);
all_AmagL  = cell(4,2);
all_AmagR  = cell(4,2);
all_vals   = nan(4,4);    % figure 1 values: rows=cases, cols=[T1L T1R T2L T2R]

for ci = 1:4
    s = cases{ci,1};

    %figure 1 values ---
    for pi = 1:2
        ph  = sprintf('Test%d',pi);
        row = LR(strcmp(LR.subject,s) & strcmp(LR.phase,ph), :);
        if ~isempty(row)
            all_vals(ci,(pi-1)*2+1) = row.tssv_left;
            all_vals(ci,(pi-1)*2+2) = row.tssv_right;
        end
    end

    %accel signals ---
    for pi = 1:numel(phases_to_plot)
        ph         = phases_to_plot{pi};
        accel_path = fullfile(cfg.data_root, s, ph, 'accel.mat');
        ev_path    = fullfile(cfg.data_root, s, ph, 'events.mat');
        if ~isfile(accel_path), continue; end

        LA      = load(accel_path,'ACCEL');
        [t_start, t_end] = safe_trial_window(ev_path);
        t       = LA.ACCEL.time_rel(:);
        fs      = 1 / median(diff(t));
        rv      = LA.ACCEL.data;

        bm = t >= (t_start-1.0) & t < t_start;
        if sum(bm) < 3, bm = t < (t(1)+1.0); end
        bias = mean(rv(bm,:),1,'omitnan');
        ms2  = (rv - bias) * cfg.accel_sensitivity_ms2_per_V;

        tm  = t >= t_start & t <= t_end;
        t_w = t(tm);
        seg = ms2(tm,:);

        if fs/2 > BP_HIGH
            [b,a_f] = butter(4,[BP_LOW BP_HIGH]/(fs/2),'bandpass');
            for c = 1:6
                seg(:,c) = filtfilt(b,a_f,double(seg(:,c)));
            end
        else
            warning('Nyquist <= BP_HIGH, skipped for %s/%s',s,ph);
        end

        ev_times = [];
        if isfile(ev_path)
            EV = load(ev_path,'EVENTS');
            ev_times = EV.EVENTS.time_rel;
        end

        all_segs{ci,pi}  = seg;
        all_t_w{ci,pi}   = t_w;
        all_ev{ci,pi}    = ev_times;
        all_AmagL{ci,pi} = sqrt(sum(seg(:,1:3).^2,2));
        all_AmagR{ci,pi} = sqrt(sum(seg(:,4:6).^2,2));
    end
end

%%compute global y-limits across all cases and phases ---

% figure 1: same y-axis for all 4 dot plots
ylim_fig1 = [0, max(all_vals(:),[],'omitnan') * 1.15];

% figure 2: separate global limits for XYZ channels and magnitude
all_xyz_vals = [];
all_mag_vals = [];
for ci = 1:4
    for pi = 1:2
        if isempty(all_segs{ci,pi}), continue; end
        all_xyz_vals = [all_xyz_vals; all_segs{ci,pi}(:)];       %#ok<AGROW>
        all_mag_vals = [all_mag_vals; all_AmagL{ci,pi}; all_AmagR{ci,pi}]; %#ok<AGROW>
    end
end
xyz_abs_max  = max(abs(all_xyz_vals),[],'omitnan');
ylim_xyz     = [-xyz_abs_max, xyz_abs_max];
ylim_mag     = [0, max(all_mag_vals,[],'omitnan') * 1.1];


%  FIGURE 1 — dot plot, shared y-axis

figure('Name','Figure 1 — TSSV left vs right, Test1 & Test2', ...
       'Units','normalized','Position',[0.05 0.1 0.85 0.5]);
tl = tiledlayout(1,4,'TileSpacing','compact','Padding','compact');

x_pos    = [1 2 3 4];
x_labels = {'T1 Left','T1 Right','T2 Left','T2 Right'};
dot_colors = [colors_LR(1,:); colors_LR(2,:); colors_LR(1,:); colors_LR(2,:)];

for ci = 1:4
    s     = cases{ci,1};
    label = cases{ci,2};
    vals  = all_vals(ci,:);

    nexttile; hold on;
    for k = 1:4
        scatter(x_pos(k), vals(k), 120, dot_colors(k,:), 'filled');
    end
   
    set(gca,'XTick',x_pos,'XTickLabel',x_labels,'XTickLabelRotation',30,'FontSize',8);
    xlim([0.5 4.5]);
    ylim(ylim_fig1);           % <-- shared y-axis
    ylabel('TSSV (m²/s³)','FontSize',9);
    title(sprintf('%s\n%s', strrep(s,'_','\_'), label),'FontSize',8);
    grid on; box on;
end
sgtitle('TSSV Left vs Right hand | Test1 & Test2 | 4 extreme subjects','FontWeight','bold');


%  FIGURE 2 — accel signals, shared y-axes across all subjects/phases

for ci = 1:4
    s     = cases{ci,1};
    label = cases{ci,2};

    figure('Name', sprintf('Fig2 — %s', s), ...
           'Units','normalized','Position',[0.02 0.05 0.96 0.88]);
    tiledlayout(4, 4, 'TileSpacing','compact','Padding','compact');

    for pi = 1:numel(phases_to_plot)
        ph = phases_to_plot{pi};
        if isempty(all_segs{ci,pi})
            fprintf('No data for %s / %s — skipping\n', s, ph);
            continue;
        end

        seg    = all_segs{ci,pi};
        t_w    = all_t_w{ci,pi};
        ev_t   = all_ev{ci,pi};
        Amag_L = all_AmagL{ci,pi};
        Amag_R = all_AmagR{ci,pi};

        % column offset: Test1 = cols 1-2, Test2 = cols 3-4
        col_L = (pi-1)*2 + 1;
        col_R = (pi-1)*2 + 2;

        % LEFT — X
        ax = nexttile(col_L); 
        plot(t_w, seg(:,1),'Color',[0.8 0.1 0.1],'LineWidth',0.5);
        hold on; add_ev(ax,ev_t); ylabel('X (m/s²)');
        title(sprintf('LEFT %s — X', ph)); ylim(ylim_xyz); grid on;

        % RIGHT — X
        ax = nexttile(col_R);
        plot(t_w, seg(:,4),'Color',[0.8 0.1 0.1],'LineWidth',0.5);
        hold on; add_ev(ax,ev_t); ylabel('X (m/s²)');
        title(sprintf('RIGHT %s — X', ph)); ylim(ylim_xyz); grid on;
    end

    % Y row
    for pi = 1:numel(phases_to_plot)
        if isempty(all_segs{ci,pi}), nexttile; nexttile; continue; end
        seg  = all_segs{ci,pi};
        t_w  = all_t_w{ci,pi};
        ev_t = all_ev{ci,pi};
        col_L = (pi-1)*2 + 1;
        col_R = (pi-1)*2 + 2;

        ax = nexttile(4 + col_L);
        plot(t_w, seg(:,2),'Color',[0.1 0.6 0.1],'LineWidth',0.5);
        hold on; add_ev(ax,ev_t); ylabel('Y (m/s²)');
        ylim(ylim_xyz); grid on;

        ax = nexttile(4 + col_R);
        plot(t_w, seg(:,5),'Color',[0.1 0.6 0.1],'LineWidth',0.5);
        hold on; add_ev(ax,ev_t); ylabel('Y (m/s²)');
        ylim(ylim_xyz); grid on;
    end

    % Z row
    for pi = 1:numel(phases_to_plot)
        if isempty(all_segs{ci,pi}), nexttile; nexttile; continue; end
        seg  = all_segs{ci,pi};
        t_w  = all_t_w{ci,pi};
        ev_t = all_ev{ci,pi};
        col_L = (pi-1)*2 + 1;
        col_R = (pi-1)*2 + 2;

        ax = nexttile(8 + col_L);
        plot(t_w, seg(:,3),'Color',[0.1 0.2 0.8],'LineWidth',0.5);
        hold on; add_ev(ax,ev_t); ylabel('Z (m/s²)');
        ylim(ylim_xyz); grid on;

        ax = nexttile(8 + col_R);
        plot(t_w, seg(:,6),'Color',[0.1 0.2 0.8],'LineWidth',0.5);
        hold on; add_ev(ax,ev_t); ylabel('Z (m/s²)');
        ylim(ylim_xyz); grid on;
    end

    % magnitude row
    for pi = 1:numel(phases_to_plot)
        if isempty(all_segs{ci,pi}), nexttile; nexttile; continue; end
        t_w    = all_t_w{ci,pi};
        ev_t   = all_ev{ci,pi};
        Amag_L = all_AmagL{ci,pi};
        Amag_R = all_AmagR{ci,pi};
        col_L  = (pi-1)*2 + 1;
        col_R  = (pi-1)*2 + 2;

        ax = nexttile(12 + col_L);
        plot(t_w, Amag_L,'Color',[0.2 0.5 0.9],'LineWidth',0.8);
        hold on; add_ev(ax,ev_t); ylabel('|A| (m/s²)');
        xlabel('Time (s)'); ylim(ylim_mag); grid on;

        ax = nexttile(12 + col_R);
        plot(t_w, Amag_R,'Color',[0.9 0.3 0.2],'LineWidth',0.8);
        hold on; add_ev(ax,ev_t); ylabel('|A| (m/s²)');
        xlabel('Time (s)'); ylim(ylim_mag); grid on;
    end

    sgtitle(sprintf('%s | %s | BP [%d–%d Hz]', ...
            strrep(s,'_','\_'), strrep(label,'_','\_'), BP_LOW, BP_HIGH), ...
            'FontWeight','bold','FontSize',10);
end

function add_ev(ax, ev_times)
    if isempty(ev_times), return; end
    yl = ylim(ax);
    for k = 1:numel(ev_times)
        xline(ax, ev_times(k), '--', 'Color',[0.9 0.6 0.0], 'LineWidth',1.2, 'Alpha',0.8);
    end
    ylim(ax, yl);
end