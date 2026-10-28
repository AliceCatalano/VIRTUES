clear; clc;

rec_dir   = '/home/acatalano/Desktop/Virtues_Data/subject_io/Test2';
force_cal = '/home/acatalano/Desktop/Virtues_Data/FT29125.cal';

accel_sens_ms2_per_V = 98.1;
BP_LOW               = 80;
BP_HIGH              = 1000;
force_noise_k_mad    = 5;
accel_noise_k_mad    = 5;

PEAK_MIN_DIST_SEC    = 1;
AUDIO_THRESH         = 0.02;
INTENSITY_WIN_SEC    = 0.10;
TARGET_FS            = 500;
V2G                  = 1/0.4;
N_BASELINE           = 50;

accel_path = fullfile(rec_dir, 'accel.mat');
force_path = fullfile(rec_dir, 'force.mat');
audio_path = fullfile(rec_dir, 'audio.mat');
ev_path    = fullfile(rec_dir, 'events.mat');

assert(isfile(accel_path), 'accel.mat not found');
assert(isfile(ev_path),    'events.mat not found');
assert(isfile(audio_path), 'audio.mat not found');

LA = load(accel_path, 'ACCEL');
EV = load(ev_path,    'EVENTS');
AU = load(audio_path, 'AUDIO');

has_force = isfile(force_path);
if has_force
    LF      = load(force_path, 'FORCE');
    C_force = load_ati_cal(force_cal);
end

[t_start, t_end] = safe_trial_window(ev_path);
fprintf('Trial window: %.3f → %.3f s  (%.3f s)\n', t_start, t_end, t_end-t_start);

% accel — g scale for collision detection (same as CollisionDetection_Local)
t_niq    = LA.ACCEL.time_rel(:);
ACCEL_FS = 1/median(diff(t_niq));
accel_raw = LA.ACCEL.data;

xL = loc_baseline_scale(accel_raw(:,1), N_BASELINE, V2G);
yL = loc_baseline_scale(accel_raw(:,2), N_BASELINE, V2G);
zL = loc_baseline_scale(accel_raw(:,3), N_BASELINE, V2G);
xR = loc_baseline_scale(accel_raw(:,4), N_BASELINE, V2G);
yR = loc_baseline_scale(accel_raw(:,5), N_BASELINE, V2G);
zR = loc_baseline_scale(accel_raw(:,6), N_BASELINE, V2G);

mag_nat = max(sqrt(xL.^2+yL.^2+zL.^2), sqrt(xR.^2+yR.^2+zR.^2));
ds = max(1, round(ACCEL_FS/TARGET_FS));
[mag_ds, t_ds] = loc_downsample(mag_nat, t_niq, ACCEL_FS, 4, ds);

% accel — m/s² for TSSV
t_a  = LA.ACCEL.time_rel(:);
fs_a = 1/median(diff(t_a));
rv_a = LA.ACCEL.data;

bm_a = t_a >= (t_start-1.0) & t_a < t_start;
if sum(bm_a) < 3, bm_a = t_a < (t_a(1)+1.0); end
bias_a  = mean(rv_a(bm_a,:), 1, 'omitnan');
raw_ms2 = (rv_a - bias_a) * accel_sens_ms2_per_V;

base_ms2 = raw_ms2(bm_a,:);
AmagBL   = sqrt(sum(base_ms2(:,1:3).^2,2));
AmagBR   = sqrt(sum(base_ms2(:,4:6).^2,2));
thr_L    = median(AmagBL) + accel_noise_k_mad * mad(AmagBL,1);
thr_R    = median(AmagBR) + accel_noise_k_mad * mad(AmagBR,1);

tm_a    = t_a >= t_start & t_a <= t_end;
t_w     = t_a(tm_a);
seg_ms2 = raw_ms2(tm_a,:);
dt_a    = 1/fs_a;

if fs_a/2 > BP_HIGH
    [b,a_f] = butter(4,[BP_LOW BP_HIGH]/(fs_a/2),'bandpass');
    for c = 1:6
        seg_ms2(:,c) = filtfilt(b,a_f,double(seg_ms2(:,c)));
    end
else
    warning('Nyquist <= BP_HIGH — bandpass skipped');
end

AmagL     = sqrt(sum(seg_ms2(:,1:3).^2,2));
AmagR     = sqrt(sum(seg_ms2(:,4:6).^2,2));
AmagL_thr = AmagL; AmagL_thr(AmagL_thr < thr_L) = 0;
AmagR_thr = AmagR; AmagR_thr(AmagR_thr < thr_R) = 0;

tssv_left  = sum(AmagL_thr.^2) * dt_a;
tssv_right = sum(AmagR_thr.^2) * dt_a;
tssv_total = tssv_left + tssv_right;
cumL       = cumsum(AmagL_thr.^2) * dt_a;
cumR       = cumsum(AmagR_thr.^2) * dt_a;

fprintf('TSSV L=%.4f  R=%.4f  Total=%.4f m²/s³\n', tssv_left, tssv_right, tssv_total);

% force — TSSF
if has_force
    t_f  = LF.FORCE.time_rel(:);
    rv_f = LF.FORCE.data;
    fs_f = 1/median(diff(t_f));

    bm_f   = t_f >= (t_start-1.0) & t_f < t_start;
    if sum(bm_f) < 3, bm_f = t_f < (t_f(1)+1.0); end
    bias_f = mean(rv_f(bm_f,:),1,'omitnan');

    F_base    = (C_force * (rv_f(bm_f,:)-bias_f)')';
    Fmag_base = sqrt(sum(F_base(:,1:3).^2,2));
    nf        = median(Fmag_base) + force_noise_k_mad * mad(Fmag_base,1);

    tm_f     = t_f >= t_start & t_f <= t_end;
    t_f_w    = t_f(tm_f);
    F_cal    = (C_force * (rv_f(tm_f,:)-bias_f)')';
    Fmag     = sqrt(sum(F_cal(:,1:3).^2,2));
    Fmag_thr = Fmag; Fmag_thr(Fmag_thr < nf) = 0;
    tssf     = sum(Fmag_thr.^2) / fs_f;
    cum_f    = cumsum(Fmag_thr.^2) / fs_f;
    fprintf('TSSF: %.4f N²·s\n', tssf);
end

% audio — collision detection
t_aud    = AU.AUDIO.time_rel(:);
fs_audio = AU.AUDIO.fs_estimated;
ch_names = AU.AUDIO.channel_names;

% scheme_new: L=ch11/12/13  R=ch14/16/17
get_ch = @(name) double(AU.AUDIO.data(:, find(strcmp(ch_names,name),1)));
bp     = @(x) bandpass(x - mean(x,'omitnan'), [BP_LOW BP_HIGH], fs_audio);
sum_L  = bp(get_ch('ch11')) + bp(get_ch('ch12')) + bp(get_ch('ch13'));
sum_R  = bp(get_ch('ch14')) + bp(get_ch('ch16')) + bp(get_ch('ch17'));
audio_bp = max(abs(sum_L), abs(sum_R));

fprintf('\naudio_bp range: min=%.5f  max=%.5f  mean=%.5f\n', ...
        min(audio_bp), max(audio_bp), mean(audio_bp,'omitnan'));
fprintf('AUDIO_THRESH = %.4f — adjust if needed\n', AUDIO_THRESH);

in_trial   = t_aud >= t_start & t_aud <= t_end;
t_trial    = t_aud(in_trial);
env_trial  = audio_bp(in_trial);

% remove non-monotonic timestamps
keep = true(size(t_trial));
last_t = -inf;
for k = 1:numel(t_trial)
    if t_trial(k) > last_t, last_t = t_trial(k);
    else, keep(k) = false; end
end
t_trial   = t_trial(keep);
env_trial = env_trial(keep);

[~, locs] = findpeaks(env_trial, t_trial, ...
    'MinPeakDistance', PEAK_MIN_DIST_SEC, ...
    'MinPeakHeight',   AUDIO_THRESH);
coll_t = locs(:);
n_coll = numel(coll_t);
fprintf('Collisions detected: %d\n', n_coll);

% intensity
[intens_g, intens_audio] = loc_compute_intensity(coll_t, mag_ds, t_ds, ...
    audio_bp, t_aud, INTENSITY_WIN_SEC, TARGET_FS, fs_audio);

fprintf('\n%-4s  %-10s  %-10s  %-12s\n','#','t (s)','Peak (g)','Peak audio');
for k = 1:n_coll
    fprintf('%-4d  %-10.3f  %-10.4f  %-12.5f\n', k, coll_t(k), intens_g(k), intens_audio(k));
end

% figure 1 — collision detection (CollisionDetection_Local style)
ds2 = max(1, round(ACCEL_FS/200));
td  = t_niq(1:ds2:end);

figure('Name','Collision Detection','Units','normalized','Position',[0.02 0.05 0.96 0.88]);
ax = gobjects(4,1);

ax(1) = subplot(4,1,1); hold on;
plot(t_aud, audio_bp,'Color',[0.6 0.1 0.1],'LineWidth',0.8,'DisplayName','audio');
yline(AUDIO_THRESH,'k--','LineWidth',1,'HandleVisibility','off');
loc_draw_window(ax(1), t_start, t_end);
loc_draw_collisions(ax(1), coll_t, audio_bp, t_aud, intens_g, intens_audio, 'audio');
ylabel('Amplitude (V)');
title(sprintf('Audio BP [%d–%d Hz] | thresh=%.4f | %d collisions', BP_LOW, BP_HIGH, AUDIO_THRESH, n_coll));
grid on;

ax(2) = subplot(4,1,2); hold on;
plot(t_ds, mag_ds,'Color',[0.2 0.45 0.8],'LineWidth',0.8,'DisplayName','Accel magnitude');
loc_draw_window(ax(2), t_start, t_end);
loc_draw_collisions(ax(2), coll_t, mag_ds, t_ds, intens_g, intens_audio, 'accel');
ylabel('Magnitude (g)');
title(sprintf('Accel magnitude — downsampled to %d Hz', TARGET_FS));
grid on;

ax(3) = subplot(4,1,3); hold on;
plot(td, xL(1:ds2:end),'r','LineWidth',0.5,'DisplayName','X');
plot(td, yL(1:ds2:end),'g','LineWidth',0.5,'DisplayName','Y');
plot(td, zL(1:ds2:end),'b','LineWidth',0.5,'DisplayName','Z');
loc_draw_window(ax(3), t_start, t_end);
ylabel('g'); title('Left sensor — X Y Z'); grid on;

ax(4) = subplot(4,1,4); hold on;
plot(td, xR(1:ds2:end),'r','LineWidth',0.5,'DisplayName','X');
plot(td, yR(1:ds2:end),'g','LineWidth',0.5,'DisplayName','Y');
plot(td, zR(1:ds2:end),'b','LineWidth',0.5,'DisplayName','Z');
loc_draw_window(ax(4), t_start, t_end);
ylabel('g'); title('Right sensor — X Y Z'); grid on;

linkaxes(ax,'x');
margin = (t_end-t_start)*0.05;
xlim(ax(1),[t_start-margin, t_end+margin]);
xlabel(ax(4),'Time (s)');
sgtitle(sprintf('Collision Detection | %d collisions | TSSV=%.4f m²/s³', n_coll, tssv_total),...
        'FontWeight','bold','FontSize',11);

%% figure 2 — left sensor TSSV
figure('Name','LEFT','Units','normalized','Position',[0.02 0.05 0.45 0.85]);
tiledlayout(5,1,'TileSpacing','compact','Padding','compact');
ax = gobjects(5,1);

ax(1) = nexttile; plot(t_w,seg_ms2(:,1),'Color',[0.8 0.1 0.1],'LineWidth',0.5);
hold on; ylabel('X (m/s²)'); title('Left — X'); grid on;

ax(2) = nexttile; plot(t_w,seg_ms2(:,2),'Color',[0.1 0.6 0.1],'LineWidth',0.5);
hold on; ylabel('Y (m/s²)'); title('Left — Y'); grid on;

ax(3) = nexttile; plot(t_w,seg_ms2(:,3),'Color',[0.1 0.2 0.8],'LineWidth',0.5);
hold on; ylabel('Z (m/s²)'); title('Left — Z'); grid on;

ax(4) = nexttile;
plot(t_w,AmagL,'Color',[0.5 0.5 0.5],'LineWidth',0.6,'DisplayName','raw');
hold on;
plot(t_w,AmagL_thr,'Color',[0.2 0.5 0.9],'LineWidth',0.8,'DisplayName','thresholded');

ylabel('|A| (m/s²)'); title('Left — magnitude');
legend('FontSize',7,'Location','best'); grid on;

ax(5) = nexttile;
plot(t_w,cumL,'Color',[0.2 0.5 0.9],'LineWidth',1.2);
hold on; loc_add_ev(gca,coll_t);
yline(cumL(end),'--',sprintf('TSSV=%.4f',tssv_left),...
      'Color',[0.2 0.5 0.9],'LineWidth',1,'FontSize',7,'LabelHorizontalAlignment','left');
ylabel('cumul. TSSV (m²/s³)'); title('Left — cumulative TSSV'); grid on;

linkaxes(ax,'x'); xlabel(ax(5),'Time (s)');
sgtitle(sprintf('LEFT | BP [%d–%d Hz]',BP_LOW,BP_HIGH),'FontWeight','bold');

%% figure 3 — right sensor TSSV
figure('Name','RIGHT','Units','normalized','Position',[0.52 0.05 0.45 0.85]);
tiledlayout(5,1,'TileSpacing','compact','Padding','compact');
ax = gobjects(5,1);

ax(1) = nexttile; plot(t_w,seg_ms2(:,4),'Color',[0.8 0.1 0.1],'LineWidth',0.5);
hold on; ylabel('X (m/s²)'); title('Right — X'); grid on;

ax(2) = nexttile; plot(t_w,seg_ms2(:,5),'Color',[0.1 0.6 0.1],'LineWidth',0.5);
hold on; ylabel('Y (m/s²)'); title('Right — Y'); grid on;

ax(3) = nexttile; plot(t_w,seg_ms2(:,6),'Color',[0.1 0.2 0.8],'LineWidth',0.5);
hold on; ylabel('Z (m/s²)'); title('Right — Z'); grid on;

ax(4) = nexttile;
plot(t_w,AmagR,'Color',[0.5 0.5 0.5],'LineWidth',0.6,'DisplayName','raw');
hold on;
plot(t_w,AmagR_thr,'Color',[0.9 0.3 0.2],'LineWidth',0.8,'DisplayName','thresholded');

loc_add_ev(gca,coll_t);
ylabel('|A| (m/s²)'); title('Right — magnitude');
legend('FontSize',7,'Location','best'); grid on;

ax(5) = nexttile;
plot(t_w,cumR,'Color',[0.9 0.3 0.2],'LineWidth',1.2);
hold on; loc_add_ev(gca,coll_t);
yline(cumR(end),'--',sprintf('TSSV=%.4f',tssv_right),...
      'Color',[0.9 0.3 0.2],'LineWidth',1,'FontSize',7,'LabelHorizontalAlignment','left');
ylabel('cumul. TSSV (m²/s³)'); title('Right — cumulative TSSV'); grid on;

linkaxes(ax,'x'); xlabel(ax(5),'Time (s)');
sgtitle(sprintf('RIGHT | BP [%d–%d Hz]',BP_LOW,BP_HIGH),'FontWeight','bold');

% figure 4 — force
if has_force
    figure('Name','FORCE','Units','normalized','Position',[0.02 0.05 0.45 0.65]);
    tiledlayout(3,1,'TileSpacing','compact','Padding','compact');
    ax = gobjects(3,1);

    ax(1) = nexttile;
    plot(t_f_w,Fmag,'Color',[0.5 0.5 0.5],'LineWidth',0.6,'DisplayName','raw');
    hold on;
    plot(t_f_w,Fmag_thr,'Color',[0.1 0.6 0.4],'LineWidth',0.8,'DisplayName','thresholded');
    yline(nf,'r--','LineWidth',1,'DisplayName','threshold');
    loc_add_ev(gca,coll_t);
    ylabel('|F| (N)'); title('Force magnitude');
    legend('FontSize',7,'Location','best'); grid on;

    ax(2) = nexttile;
    plot(t_f_w,cum_f,'Color',[0.1 0.6 0.4],'LineWidth',1.2);
    hold on; loc_add_ev(gca,coll_t);
    yline(tssf,'--',sprintf('TSSF=%.4f N²·s',tssf),...
          'Color',[0.1 0.6 0.4],'LineWidth',1,'FontSize',7,'LabelHorizontalAlignment','left');
    ylabel('cumul. TSSF (N²·s)'); title('Force — cumulative TSSF'); grid on;

    ax(3) = nexttile;
    plot(t_f_w,F_cal(:,1),'r','LineWidth',0.5,'DisplayName','Fx'); hold on;
    plot(t_f_w,F_cal(:,2),'g','LineWidth',0.5,'DisplayName','Fy');
    plot(t_f_w,F_cal(:,3),'b','LineWidth',0.5,'DisplayName','Fz');
    loc_add_ev(gca,coll_t);
    ylabel('F (N)'); title('Fx Fy Fz');
    legend('FontSize',7,'Location','best'); grid on;

    linkaxes(ax,'x'); xlabel(ax(3),'Time (s)');
    sgtitle('FORCE','FontWeight','bold');
end

fprintf('\nTrial : %.3f s\n',      t_end-t_start);
fprintf('fs_a  : %.1f Hz\n',      fs_a);
fprintf('TSSV L: %.4f m²/s³\n',  tssv_left);
fprintf('TSSV R: %.4f m²/s³\n',  tssv_right);
fprintf('TSSV  : %.4f m²/s³\n',  tssv_total);
if has_force, fprintf('TSSF  : %.4f N²·s\n', tssf); end
fprintf('Collis: %d\n',           n_coll);

function ch = loc_baseline_scale(raw, n_base, V2G)
    n_bl = min(n_base, numel(raw));
    ch   = (raw - mean(raw(1:n_bl))) * V2G;
end

function [sd, td] = loc_downsample(sig, t, fi, ord, ds)
    Wn = min(0.99, (fi/ds/2*0.9)/(fi/2));
    [b,a] = butter(ord, Wn, 'low');
    sf = filtfilt(b, a, double(sig));
    nd = floor(numel(sf)/ds);
    sd = zeros(nd,1); td = zeros(nd,1);
    for k = 1:nd
        idx   = (k-1)*ds+1:k*ds;
        sd(k) = mean(sf(idx));
        td(k) = t(idx(1));
    end
end

function [ig, ia] = loc_compute_intensity(ct, mag_ds, t_ds, audio_bp, t_aud, win_sec, tgt_fs, fs_aud)
    n   = numel(ct);
    ig  = nan(n,1); ia = nan(n,1);
    hwa = round(win_sec*tgt_fs);
    hwu = round(win_sec*fs_aud);
    for ci = 1:n
        [~,ic] = min(abs(t_ds  - ct(ci)));
        [~,iu] = min(abs(t_aud - ct(ci)));
        ig(ci) = max(mag_ds(  max(1,ic-hwa):min(numel(mag_ds),  ic+hwa)));
        ia(ci) = max(audio_bp(max(1,iu-hwu):min(numel(audio_bp),iu+hwu)));
    end
end

function loc_draw_window(ax, tw_s, tw_e)
    yl = ylim(ax);
    fill(ax,[tw_s tw_e tw_e tw_s],[yl(1) yl(1) yl(2) yl(2)],...
         [0.85 0.95 0.75],'EdgeColor','none','FaceAlpha',0.25,'HandleVisibility','off');
    xline(ax,tw_s,'--','START','Color',[0.25 0.55 0.25],'LineWidth',1.2,...
          'HandleVisibility','off','LabelHorizontalAlignment','right');
    xline(ax,tw_e,'--','END',  'Color',[0.65 0.15 0.15],'LineWidth',1.2,...
          'HandleVisibility','off','LabelHorizontalAlignment','left');
end

function loc_draw_collisions(ax, ct, ref_sig, ref_t, intens_g, intens_audio, mode)
    clr = [0.85 0.18 0.08];
    for ci = 1:numel(ct)
        [~,ix] = min(abs(ref_t - ct(ci)));
        yval   = ref_sig(ix) * 1.18;
        dn = ''; if ci==1, dn='Collision'; end
        stem(ax,ct(ci),yval,'Color',clr,'LineWidth',2,'Marker','v',...
             'MarkerSize',7,'MarkerFaceColor',clr,'DisplayName',dn);
        switch mode
            case 'audio', lbl = sprintf('#%d\n%.4fV',ci,intens_audio(ci));
            case 'accel', lbl = sprintf('#%d\n%.2fg',ci,intens_g(ci));
            otherwise,    lbl = sprintf('#%d',ci);
        end
        text(ax,ct(ci),yval*1.06,lbl,'HorizontalAlignment','center',...
             'FontSize',7,'Color',clr,'FontWeight','bold');
    end
end

function loc_add_ev(ax, coll_t)
    if isempty(coll_t), return; end
    yl = ylim(ax);
    for k = 1:numel(coll_t)
        xline(ax,coll_t(k),'--','Color',[0.85 0.18 0.08],'LineWidth',1.2,'Alpha',0.8);
    end
    ylim(ax,yl);
end