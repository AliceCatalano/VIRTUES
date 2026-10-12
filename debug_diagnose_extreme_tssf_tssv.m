%% diagnose_extreme_tssf_tssv.m
clear; clc; close all; cfg = config();
C_force = load_ati_cal(cfg.force_cal_path);
fig_dir = fullfile(cfg.output_root,'figures','diagnosis');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

FV_raw = load(fullfile(cfg.output_root,'force_vibration_features.mat'),'T'); T_raw=FV_raw.T;

% -------------------------------------------------------------------------
% TSSF: the 3 subjects with actual removals in the clean table For each subject take their 3 highest and 3 lowest training trials
% and compute both old and new formula so you can explain exactly why
% -------------------------------------------------------------------------
tssf_subjects = {'subject_s37N','subject_s38H','subject_s42N'};

for si = 1:numel(tssf_subjects)
    subj = tssf_subjects{si};
    T_s  = T_raw(strcmp(T_raw.subject,subj) & strcmp(T_raw.phase_type,'training') & ...
                 isfinite(T_raw.tssf) & T_raw.tssf>0,:);
    T_s.log_tssf = log(T_s.tssf);
    T_s = sortrows(T_s,'log_tssf','ascend');

    idx_plot = unique([1 2 3  height(T_s)-2 height(T_s)-1 height(T_s)]);
    n_plot   = numel(idx_plot);

    fig = figure('Position',[2000 2000 1400 300*n_plot]);
    tl  = tiledlayout(n_plot,4,'TileSpacing','compact','Padding','compact');
    title(tl,sprintf('TSSF diagnosis — %s',strrep(subj,'subject_','')),'FontWeight','bold','FontSize',11);

    for ki = 1:n_plot
        ri  = idx_plot(ki);
        row = T_s(ri,:);
        ph  = row.phase{1}; acq = row.acquisition{1};
        acq_dir = fullfile(cfg.data_root,subj,ph,acq);
        if ~isfolder(acq_dir), acq_dir=[acq_dir '_R']; end

        ev_path = fullfile(acq_dir,'events.mat');
        fo_path = fullfile(acq_dir,'force.mat');
        if ~isfile(ev_path)||~isfile(fo_path)
            for k=1:4, nexttile; end; continue
        end

        [t_start,t_end] = safe_trial_window(ev_path);
        LF = load(fo_path,'FORCE'); t_f=LF.FORCE.time_rel(:); rv=LF.FORCE.data;
        bm = t_f>=(t_start-1)&t_f<t_start;
        if sum(bm)<3, bm=t_f<(t_f(1)+1); end
        bias = mean(rv(bm,:),1,'omitnan');
        F_cal = (C_force*(rv-bias)')';
        tm = t_f>=t_start&t_f<=t_end; t_win=t_f(tm)-t_start;
        F_trial = F_cal(tm,:);
        dur = t_end-t_start;
        n_samp = sum(tm);

        % old formula
        Fmag_old = sqrt(sum(F_trial(:,1:3).^2,2));
        nf_old   = median(Fmag_old)+cfg.force_noise_k_mad*mad(Fmag_old,1);
        Fm_old   = Fmag_old; Fm_old(Fm_old<nf_old)=0;
        tssf_old = sum(Fm_old.^2);

        % new formula
        F_sum    = sum(F_trial(:,1:3),2);
        nf_new   = median(abs(F_sum))+cfg.force_noise_k_mad*mad(F_sum,1);
        Fs_new   = F_sum; Fs_new(abs(Fs_new)<nf_new)=0;
        tssf_new = sum(Fs_new.^2);

        avg_F_old = sqrt(tssf_old/n_samp);
        avg_F_new = sqrt(tssf_new/n_samp);
        max_Fx = max(abs(F_trial(:,1))); max_Fy=max(abs(F_trial(:,2))); max_Fz=max(abs(F_trial(:,3)));

        rank_lbl = local_ternary(ki<=3,'LOWEST','HIGHEST');
        title_str = sprintf('%s #%d | L%d r%d | dur=%.1fs | log=%.2f\nOLD=%.2eN²(avg%.1fN) NEW=%.2eN²(avg%.1fN) ratio=%.1fx',...
            rank_lbl,ki,row.level,row.repetition,dur,...
            tssf_old,avg_F_old,tssf_new,avg_F_new,tssf_old/max(tssf_new,1e-10));

        col_rank = local_ternary(ki<=3,[0.1 0.5 0.1],[0.8 0.2 0.2]);

        % Panel 1: Fx Fy Fz components
        nexttile; hold on;
        plot(t_win,F_trial(:,1),'r-','LineWidth',0.6,'DisplayName',sprintf('Fx max=%.1fN',max_Fx));
        plot(t_win,F_trial(:,2),'g-','LineWidth',0.6,'DisplayName',sprintf('Fy max=%.1fN',max_Fy));
        plot(t_win,F_trial(:,3),'b-','LineWidth',0.6,'DisplayName',sprintf('Fz max=%.1fN',max_Fz));
        yline(0,'k--','LineWidth',0.8,'HandleVisibility','off');
        xlabel('t (s)'); ylabel('N');
        title(title_str,'FontSize',6.5,'Interpreter','none');
        legend('FontSize',6,'Location','best'); grid on;

        % Panel 2: old formula signal
        nexttile; hold on;
        plot(t_win,Fmag_old,'Color',col_rank,'LineWidth',0.7);
        yline(nf_old,'r--','LineWidth',1.2,'DisplayName',sprintf('noise floor=%.2fN',nf_old));
        area(t_win,Fm_old,'FaceColor',col_rank,'FaceAlpha',0.2,'EdgeColor','none');
        xlabel('t (s)'); ylabel('N');
        title(sprintf('OLD: |F| magnitude\nTSSF=%.2e  avg_per_sample=%.2fN',tssf_old,avg_F_old),'FontSize',7);
        legend('FontSize',6); grid on;

        % Panel 3: new formula signal
        nexttile; hold on;
        plot(t_win,F_sum,'Color',col_rank,'LineWidth',0.7);
        yline( nf_new,'r--','LineWidth',1.2,'DisplayName',sprintf('noise floor=%.2fN',nf_new));
        yline(-nf_new,'r--','LineWidth',1.2,'HandleVisibility','off');
        area(t_win,Fs_new,'FaceColor',col_rank,'FaceAlpha',0.2,'EdgeColor','none');
        xlabel('t (s)'); ylabel('N');
        title(sprintf('NEW: Fx+Fy+Fz signed sum\nTSSF=%.2e  avg_per_sample=%.2fN',tssf_new,avg_F_new),'FontSize',7);
        legend('FontSize',6); grid on;

        % Panel 4: Fx vs Fy scatter — shows if they are opposing (cancellation)
        nexttile; hold on;
        scatter(F_trial(:,1),F_trial(:,2),4,col_rank,'filled','MarkerFaceAlpha',0.3);
        r_xy = corr(F_trial(:,1),F_trial(:,2),'Rows','complete');
        xlabel('Fx (N)'); ylabel('Fy (N)');
        title(sprintf('Fx vs Fy  r=%.3f\n(negative r = opposing = OLD inflated)',r_xy),'FontSize',7);
        grid on; box on;
        xline(0,'k--','LineWidth',0.8,'HandleVisibility','off');
        yline(0,'k--','LineWidth',0.8,'HandleVisibility','off');
    end

    fname = sprintf('diagnosis_tssf_%s.png',strrep(subj,'subject_',''));
    exportgraphics(fig,fullfile(fig_dir,fname),'Resolution',130);
    fprintf('Saved %s\n',fname); close(fig);
end

% -------------------------------------------------------------------------
% TSSV: s44N (selective channel noise) and s41H (very gentle contacts)
% Show the raw channels separately so you can see which ones are noisy
% -------------------------------------------------------------------------
tssv_cases = {
    'subject_s44N','level_L3','rep_07','HIGH removed: selective channel noise'
    'subject_s44N','level_L1','rep_01','Compare: same subject, normal-looking rep'
    'subject_s41H','level_L1','rep_05','LOW removed: very gentle contact'
    'subject_s41H','level_L3','rep_05','Compare: same subject, normal rep'
};

fig_v = figure('Position',[2000 2000 1600 280*size(tssv_cases,1)]);
tl_v  = tiledlayout(size(tssv_cases,1),4,'TileSpacing','compact','Padding','compact');
title(tl_v,'TSSV diagnosis — channel-by-channel inspection','FontWeight','bold','FontSize',11);

for ci = 1:size(tssv_cases,1)
    subj=tssv_cases{ci,1}; ph=tssv_cases{ci,2}; acq=tssv_cases{ci,3}; lbl=tssv_cases{ci,4};
    acq_dir=fullfile(cfg.data_root,subj,ph,acq);
    if ~isfolder(acq_dir), acq_dir=[acq_dir '_R']; end
    ev_path=fullfile(acq_dir,'events.mat'); ac_path=fullfile(acq_dir,'accel.mat');
    if ~isfile(ev_path)||~isfile(ac_path)
        for k=1:4, nexttile; end; continue
    end

    [t_start,t_end]=safe_trial_window(ev_path);
    LA=load(ac_path,'ACCEL'); t_a=LA.ACCEL.time_rel(:); fs=LA.ACCEL.fs_nominal; dt=1/fs;
    rv=LA.ACCEL.data;
    bm=t_a>=(t_start-1)&t_a<t_start; if sum(bm)<3, bm=t_a<(t_a(1)+1); end
    bias=mean(rv(bm,:),1,'omitnan');
    raw_ms2=(rv-bias)*cfg.accel_sensitivity_ms2_per_V;
    tm=t_a>=t_start&t_a<=t_end; t_win=t_a(tm)-t_start;
    seg=raw_ms2(tm,:);
    seg_bp=seg;
    if fs/2>1000
        [b,a_f]=butter(4,[80 1000]/(fs/2),'bandpass');
        for c=1:6, seg_bp(:,c)=filtfilt(b,a_f,double(seg(:,c))); end
    end
    AL=sum(seg_bp(:,1:3),2); AR=sum(seg_bp(:,4:6),2);
    AL_t=AL; AR_t=AR;
    AL_t(abs(AL_t)<cfg.tssv_noise_threshold_ms2)=0;
    AR_t(abs(AR_t)<cfg.tssv_noise_threshold_ms2)=0;
    tssv_val=sum((AL_t+AR_t).^2)*dt;

    rms_ch=sqrt(mean(seg_bp.^2,1));
    ch_names={'Lx','Ly','Lz','Rx','Ry','Rz'};

    % Panel 1: left tool channels
    nexttile; hold on;
    cols3={[0.8 0.1 0.1],[0.1 0.6 0.1],[0.1 0.2 0.8]};
    for c=1:3, plot(t_win,seg_bp(:,c),'Color',cols3{c},'LineWidth',0.5,...
        'DisplayName',sprintf('%s rms=%.4f',ch_names{c},rms_ch(c))); end
    yline(cfg.tssv_noise_threshold_ms2,'k--','LineWidth',0.8,'HandleVisibility','off');
    xlabel('t(s)'); ylabel('m/s²');
    title(sprintf('%s | %s/%s\nLeft tool  TSSV=%.4f',lbl,ph,acq,tssv_val),'FontSize',7,'Interpreter','none');
    legend('FontSize',6,'Location','best'); grid on;

    % Panel 2: right tool channels
    nexttile; hold on;
    for c=4:6, plot(t_win,seg_bp(:,c),'Color',cols3{c-3},'LineWidth',0.5,...
        'DisplayName',sprintf('%s rms=%.4f',ch_names{c},rms_ch(c))); end
    yline(cfg.tssv_noise_threshold_ms2,'k--','LineWidth',0.8,'HandleVisibility','off');
    xlabel('t(s)'); ylabel('m/s²');
    title('Right tool (bandpassed)','FontSize',8);
    legend('FontSize',6,'Location','best'); grid on;

    % Panel 3: signed sums and threshold
    nexttile; hold on;
    plot(t_win,AL,'Color',[0.2 0.5 0.8],'LineWidth',0.7,'DisplayName','Left sum');
    plot(t_win,AR,'Color',[0.8 0.3 0.1],'LineWidth',0.7,'DisplayName','Right sum');
    yline( cfg.tssv_noise_threshold_ms2,'k--','LineWidth',1,'HandleVisibility','off');
    yline(-cfg.tssv_noise_threshold_ms2,'k--','LineWidth',1,'HandleVisibility','off');
    xlabel('t(s)'); ylabel('m/s²');
    title(sprintf('Signed sums  thr=%.4f m/s²',cfg.tssv_noise_threshold_ms2),'FontSize',8);
    legend('FontSize',6); grid on;

    % Panel 4: RMS bar chart per channel — immediately shows which channel is noisy
    nexttile; hold on;
    bar_col=[cols3{1};cols3{2};cols3{3};cols3{1};cols3{2};cols3{3}]*0.7;
    b=bar(1:6,rms_ch,0.6); b.FaceColor='flat';
    for c=1:6, b.CData(c,:)=bar_col(c,:); end
    yline(cfg.tssv_noise_threshold_ms2,'r--','LineWidth',1.5,'DisplayName',sprintf('thr=%.4f',cfg.tssv_noise_threshold_ms2));
    set(gca,'XTick',1:6,'XTickLabel',ch_names,'FontSize',8);
    xlabel('Channel'); ylabel('RMS (m/s²)');
    title('RMS per channel — noisy channel visible here','FontSize',8);
    legend('FontSize',7); grid on;
end

fname_v='diagnosis_tssv_channels.png';
exportgraphics(fig_v,fullfile(fig_dir,fname_v),'Resolution',130);
fprintf('Saved %s\n',fname_v);

function out=local_ternary(c,a,b), if c,out=a; else,out=b; end, end