%% compare_nidaq_vs_audiomixer_full.m
clear; clc; close all; 
cfg = config();
BP_LOW=80; BP_HIGH=1000;

subjects = {'subject_s27N', 'level_L5', 'rep_09', 'HF'
    'subject_s27N', 'level_L5', 'rep_01', 'HF'
};

CN=[64 96 179]/255; CH=[139 82 168]/255;

for si=1:2
    subj=subjects{si,1}; phase=subjects{si,2}; acq=subjects{si,3}; grp=subjects{si,4};
    col=local_ternary(si==1,CH,CN);
    acq_dir=fullfile(cfg.data_root,subj,phase,acq);
    if ~isfolder(acq_dir), acq_dir=[acq_dir '_R']; end

    [t_start,t_end]=safe_trial_window(fullfile(acq_dir,'events.mat'));

    LA =load(fullfile(acq_dir,'accel.mat'),'ACCEL');
    LA2=load(fullfile(acq_dir,'audio.mat'),'AUDIO');

    % real fs from timestamps
    t_n=LA.ACCEL.time_rel(:);
    dt_n=diff(t_n(t_n>=t_start&t_n<=t_end));
    fs_n_real=1/median(dt_n(dt_n>0));

    t_a=LA2.AUDIO.time_rel(:);
    dt_a=diff(t_a(t_a>=t_start&t_a<=t_end));
    fs_a_real=1/median(dt_a(dt_a>0));

    fprintf('\n=== %s [%s/%s/%s] ===\n',grp,strrep(subj,'subject_',''),phase,acq);
    fprintf('NIDAQ:     fs_nominal=%.1f  fs_real=%.2f Hz\n',LA.ACCEL.fs_nominal,fs_n_real);
    fprintf('Audiomixer: fs_nominal=%.1f  fs_real=%.2f Hz\n',LA2.AUDIO.fs_estimated,fs_a_real);

    % bias removal
    rv_n=LA.ACCEL.data; rv_a=LA2.AUDIO.data;
    bm_n=t_n>=(t_start-1.0)&t_n<t_start; if sum(bm_n)<3, bm_n=t_n<(t_n(1)+1.0); end
    bm_a=t_a>=(t_start-1.0)&t_a<t_start; if sum(bm_a)<3, bm_a=t_a<(t_a(1)+1.0); end
    bias_n=mean(rv_n(bm_n,:),1,'omitnan');
    bias_a=mean(rv_a(bm_a,:),1,'omitnan');
    rv_n_bc=rv_n-bias_n;   % NIDAQ in raw V
    rv_a_bc=rv_a-bias_a;   % audiomixer in raw V

    % bandpass — using real fs
    [b_n,a_n]=butter(4,[BP_LOW BP_HIGH]/(fs_n_real/2),'bandpass');
    [b_a,a_a]=butter(4,[BP_LOW BP_HIGH]/(fs_a_real/2),'bandpass');

    % trial window
    tm_n=t_n>=t_start&t_n<=t_end; t_win_n=t_n(tm_n);
    tm_a=t_a>=t_start&t_a<=t_end; t_win_a=t_a(tm_a);

    % bandpass per channel — keep in raw V throughout
    rv_n_bp=zeros(sum(tm_n),size(rv_n_bc,2));
    rv_a_bp=zeros(sum(tm_a),size(rv_a_bc,2));
    for c=1:size(rv_n_bc,2), rv_n_bp(:,c)=filtfilt(b_n,a_n,double(rv_n_bc(tm_n,c))); end
    for c=1:size(rv_a_bc,2), rv_a_bp(:,c)=filtfilt(b_a,a_a,double(rv_a_bc(tm_a,c))); end

    % signed sum — NIDAQ left+right, audiomixer left+right
    % identify left/right channels
    ch_n=LA.ACCEL.channel_names;
    left_n =find(ismember(ch_n,{'ai9','ai10','ai11'}));
    right_n=find(ismember(ch_n,{'ai12','ai13','ai14'}));
    ch_a=LA2.AUDIO.channel_names;
    left_a =find(ismember(ch_a,{'ch12','ch13','ch14','ch11'}));
    right_a=find(ismember(ch_a,{'ch16','ch17','ch18'}));
    if isempty(left_a),  left_a =1:3; end
    if isempty(right_a), right_a=4:6; end

    A_n=sum(rv_n_bp(:,left_n),2)+sum(rv_n_bp(:,right_n),2);   % V
    A_a=sum(rv_a_bp(:,left_a),2)+sum(rv_a_bp(:,right_a),2);   % V

    % statistics — both in raw V
    rms_n=sqrt(mean(A_n.^2));
    rms_a=sqrt(mean(A_a.^2));
    fprintf('NIDAQ combined RMS (V, bandpassed): %.5f\n',rms_n);
    fprintf('Audiomixer combined RMS (V, bandpassed): %.6f\n',rms_a);
    fprintf('Ratio audio/NIDAQ (V/V): %.4f  (%.2f dB)\n',rms_a/rms_n,20*log10(rms_a/rms_n));

    % correlation (interpolate audiomixer onto NIDAQ timebase)
    [t_a_u,ia]=unique(t_win_a);
    A_a_u=A_a(ia);
    A_a_interp=interp1(t_a_u,A_a_u,t_win_n,'linear','extrap');
    r_full=corr(A_n,A_a_interp,'Rows','complete');
    fprintf('Correlation (full trial): r=%.3f\n',r_full);

    % split into collision and non-collision periods
    coll_path=fullfile(acq_dir,'collision_results.mat');
    if isfile(coll_path)
        CR=load(coll_path,'results');
        coll_t=CR.results.collision_rel(CR.results.collision_rel>=t_start&CR.results.collision_rel<=t_end);
        WIN=0.10;
        is_coll=false(numel(t_win_n),1);
        for ci=1:numel(coll_t)
            is_coll=is_coll|(t_win_n>=(coll_t(ci)-WIN)&t_win_n<=(coll_t(ci)+WIN));
        end
        r_coll   =corr(A_n(is_coll), A_a_interp(is_coll), 'Rows','complete');
        r_nocoll =corr(A_n(~is_coll),A_a_interp(~is_coll),'Rows','complete');
        rms_n_coll  =sqrt(mean(A_n(is_coll).^2));
        rms_a_coll  =sqrt(mean(A_a_interp(is_coll).^2));
        rms_n_nocoll=sqrt(mean(A_n(~is_coll).^2));
        rms_a_nocoll=sqrt(mean(A_a_interp(~is_coll).^2));
        fprintf('Collision periods    : corr=%.3f  NIDAQ_rms=%.5fV  Audio_rms=%.6fV  ratio=%.2fdB\n',...
            r_coll,rms_n_coll,rms_a_coll,20*log10(rms_a_coll/rms_n_coll));
        fprintf('Non-collision periods: corr=%.3f  NIDAQ_rms=%.5fV  Audio_rms=%.6fV  ratio=%.2fdB\n',...
            r_nocoll,rms_n_nocoll,rms_a_nocoll,20*log10(rms_a_nocoll/rms_n_nocoll));
        fprintf('n_collisions in window: %d  collision_samples=%d/%d (%.1f%%)\n',...
            numel(coll_t),sum(is_coll),numel(t_win_n),100*mean(is_coll));
    end

    % PSD comparison — full trial
    nfft=min(2048,floor(numel(A_n)/4));
    [pxx_n,f_n]=pwelch(double(A_n),nfft,[],[],fs_n_real);
    [pxx_a,f_a]=pwelch(double(A_a),nfft,[],[],fs_a_real);
    in_band_n=f_n>=BP_LOW&f_n<=BP_HIGH;
    in_band_a=f_a>=BP_LOW&f_a<=BP_HIGH;
    pow_ratio=sum(pxx_a(in_band_a))/sum(pxx_n(in_band_n));
    fprintf('In-band power ratio audio/NIDAQ: %.4f (%.2f dB)\n',pow_ratio,10*log10(pow_ratio));

    % figures
    fig=figure('Position',[2000 2000 1600 900],'Name',sprintf('%s %s',grp,strrep(subj,'subject_','')));
    tl=tiledlayout(3,2,'TileSpacing','compact','Padding','compact');
    title(tl,sprintf('[%s] %s — NIDAQ vs Audiomixer (both in raw V, bandpassed %d-%dHz)',grp,strrep(subj,'subject_',''),BP_LOW,BP_HIGH),'FontWeight','bold','FontSize',11);

    nexttile([1 2]); hold on;
    plot(t_win_n-t_win_n(1),A_n./max(abs(A_n)),'Color',col,'LineWidth',0.7,'DisplayName','NIDAQ (normalised)');
    plot(t_win_n-t_win_n(1),A_a_interp./max(abs(A_a_interp)),'Color',[0.6 0.6 0.6],'LineWidth',0.7,'DisplayName','Audiomixer (normalised)');
    if isfile(coll_path)
        for ci=1:numel(coll_t)
            xline(coll_t(ci)-t_win_n(1),'r:','LineWidth',0.8,'HandleVisibility','off');
        end
    end
    xlabel('Time (s)'); ylabel('Normalised amplitude (V/Vmax)');
    title(sprintf('Full trial — normalised to own max  |  corr=%.3f  ratio=%.2fdB',r_full,20*log10(rms_a/rms_n)),'FontSize',9);
    legend('FontSize',8); grid on;

    nexttile; hold on;
    plot(f_n,10*log10(pxx_n),'Color',col,'LineWidth',1.5,'DisplayName',sprintf('NIDAQ (fs=%.0fHz)',fs_n_real));
    plot(f_a,10*log10(pxx_a),'Color',[0.5 0.5 0.5],'LineWidth',1.5,'DisplayName',sprintf('Audiomixer (fs=%.0fHz)',fs_a_real));
    xline(BP_LOW,'k:','LineWidth',1,'HandleVisibility','off');
    xline(BP_HIGH,'k:','LineWidth',1,'HandleVisibility','off');
    xlabel('Frequency (Hz)'); ylabel('PSD (dB re V^2/Hz)','FontSize',9);
    title(sprintf('PSD comparison (in-band ratio=%.2fdB)',10*log10(pow_ratio)),'FontSize',9);
    legend('FontSize',8); xlim([0 min(fs_n_real,fs_a_real)/2]); grid on;

    nexttile; hold on;
    scatter(A_n,A_a_interp,4,col,'filled','MarkerFaceAlpha',0.1);
    pf=polyfit(A_n(isfinite(A_a_interp)),A_a_interp(isfinite(A_a_interp)),1);
    xl=[min(A_n) max(A_n)];
    plot(xl,polyval(pf,xl),'k--','LineWidth',1.5);
    xlabel('NIDAQ (V)'); ylabel('Audiomixer (V)','FontSize',9);
    title(sprintf('Sample scatter  r=%.3f  slope=%.4f',r_full,pf(1)),'FontSize',9);
    grid on; box on;

    nexttile; hold on;
    if isfile(coll_path) && numel(coll_t)>0
        t0=coll_t(ceil(numel(coll_t)/2));
        zm=0.15;
        zm_n=t_win_n>=(t0-zm)&t_win_n<=(t0+zm);
        zm_a=t_win_a>=(t0-zm)&t_win_a<=(t0+zm);
        An_z=A_n(zm_n); Aa_z=A_a(zm_a);
        tn_z=(t_win_n(zm_n)-t0)*1000; ta_z=(t_win_a(zm_a)-t0)*1000;
        yyaxis left;
        plot(tn_z,An_z,'Color',col,'LineWidth',1.2,'DisplayName','NIDAQ (V)');
        ylabel('NIDAQ (V)','FontSize',9);
        yyaxis right;
        plot(ta_z,Aa_z,'Color',[0.5 0.5 0.5],'LineWidth',1.2,'DisplayName','Audiomixer (V)');
        ylabel('Audiomixer (V)','FontSize',9);
        xline(0,'k--','LineWidth',1,'HandleVisibility','off');
        xlabel('Time from collision (ms)');
        title('Collision zoom ±150ms','FontSize',9);
        legend('FontSize',8); grid on;
    end

    fname=sprintf('nidaq_vs_audiomixer_%s.png',grp);
    exportgraphics(fig,fullfile(cfg.output_root,'figures','sensor_quality',fname),'Resolution',150);
    %fprintf('Figure saved: %s\n',fname);
end

function out=local_ternary(c,a,b), if c,out=a; else,out=b; end, end