%% inspect_tssf_extreme_trials.m
clear; clc; close all; cfg = config();
C_force = load_ati_cal(cfg.force_cal_path);
FV_raw  = load(fullfile(cfg.output_root,'force_vibration_features.mat'),'T'); T_raw=FV_raw.T;
FV_cln  = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); T_cln=FV_cln.T;

% Subjects and metrics to inspect
inspect = {
    'subject_s37N','tssf','training','Extreme HIGH: raw max=17.9  clean max=16.6'
    'subject_s38H','tssf','training','Extreme HIGH: raw max=17.4  clean max=16.8'
    'subject_s42N','tssf','training','Extreme LOW+HIGH: low~5.3  high~16.7'
    'subject_s40H','tssf','training','HIGH 3MAD (30%%) but p1p99 ok — is it natural width?'
    'subject_s09N','tssv','training','WHOLE EXCLUDED: sensor anomaly'
    'subject_s44N','tssv','training','PARTIAL EXCLUDED: selective channel noise'
    'subject_s41H','tssv','training','8 removed by p1 — very gentle contacts?'
};

fig_dir = fullfile(cfg.output_root,'figures','trial_inspection');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

for ii = 1:size(inspect,1)
    subj   = inspect{ii,1};
    metric = inspect{ii,2};
    ptype  = inspect{ii,3};
    lbl    = inspect{ii,4};

    % get all training rows for this subject, sorted by log value
    T_s = T_raw(strcmp(T_raw.subject,subj) & strcmp(T_raw.phase_type,ptype) & ...
                isfinite(T_raw.(metric)) & T_raw.(metric)>0, :);
    if isempty(T_s), fprintf('No rows: %s\n',subj); continue; end
    T_s.log_m = log(T_s.(metric));
    T_s = sortrows(T_s,'log_m','ascend');

    % identify which rows were removed in clean
    T_sc = T_cln(strcmp(T_cln.subject,subj) & strcmp(T_cln.phase_type,ptype), :);
    is_removed = false(height(T_s),1);
    for ri = 1:height(T_s)
        match = strcmp(T_sc.phase,T_s.phase{ri}) & ...
                strcmp(T_sc.acquisition,T_s.acquisition{ri}) & ...
                (isnan(T_sc.(metric)) | T_sc.(metric)<=0);
        is_removed(ri) = any(match);
    end

    % pick trials to plot: 3 lowest, 3 highest, 2 middle
    n = height(T_s);
    idx_plot = unique([1 2 3  round(n/2)-1 round(n/2)  n-2 n-1 n]);
    idx_plot = idx_plot(idx_plot>=1 & idx_plot<=n);
    n_plot = numel(idx_plot);

    fig = figure('Position',[2000 2000 1800 250*n_plot]);
    tl  = tiledlayout(n_plot,3,'TileSpacing','compact','Padding','compact');
    title(tl,sprintf('%s — %s\n%s',strrep(subj,'subject_',''),upper(metric),lbl),...
        'FontWeight','bold','FontSize',10);

    for ki = 1:n_plot
        ri   = idx_plot(ki);
        row  = T_s(ri,:);
        ph   = row.phase{1}; acq = row.acquisition{1};
        rmvd_flag = is_removed(ri);
        title_str = sprintf('L%d r%d  log=%.2f  raw=%.2e  %s',...
            row.level, row.repetition, row.log_m, row.(metric),...
            local_ternary(rmvd_flag,'[REMOVED]','[kept]'));

        % resolve acquisition directory
        if strcmp(row.phase_type{1},'test')
            acq_dir = fullfile(cfg.data_root,subj,ph);
        else
            acq_dir = fullfile(cfg.data_root,subj,ph,acq);
            if ~isfolder(acq_dir), acq_dir=[acq_dir '_R']; end
        end

        ev_path = fullfile(acq_dir,'events.mat');
        if strcmp(metric,'tssf')
            sig_path = fullfile(acq_dir,'force.mat');
        else
            sig_path = fullfile(acq_dir,'accel.mat');
        end

        if ~isfile(sig_path)||~isfile(ev_path)
            for k=1:3, nexttile; title(sprintf('Missing files\n%s',title_str),'FontSize',7); end
            continue
        end

        [t_start,t_end] = safe_trial_window(ev_path);

        if strcmp(metric,'tssf')
            LF=load(sig_path,'FORCE'); t_f=LF.FORCE.time_rel(:); rv=LF.FORCE.data;
            bm=t_f>=(t_start-1)&t_f<t_start; if sum(bm)<3, bm=t_f<(t_f(1)+1); end
            bias=mean(rv(bm,:),1,'omitnan');
            F_cal=(C_force*(rv-bias)')';
            tm=t_f>=t_start&t_f<=t_end; t_win=t_f(tm)-t_start;

            % old formula
            Fmag_old=sqrt(sum(F_cal(tm,1:3).^2,2));
            nf_old=median(Fmag_old)+cfg.force_noise_k_mad*mad(Fmag_old,1);
            Fm_old=Fmag_old; Fm_old(Fm_old<nf_old)=0;

            % new formula
            F_sum=sum(F_cal(tm,1:3),2);
            nf_new=median(abs(F_sum))+cfg.force_noise_k_mad*mad(F_sum,1);
            Fs_new=F_sum; Fs_new(abs(Fs_new)<nf_new)=0;

            col=local_ternary(rmvd_flag,[0.8 0.2 0.2],[0.2 0.5 0.8]);

            nexttile; hold on;
            plot(t_win,F_cal(tm,1),'r-','LineWidth',0.5,'DisplayName','Fx');
            plot(t_win,F_cal(tm,2),'g-','LineWidth',0.5,'DisplayName','Fy');
            plot(t_win,F_cal(tm,3),'b-','LineWidth',0.5,'DisplayName','Fz');
            yline(0,'k--','LineWidth',0.8,'HandleVisibility','off');
            xlabel('t (s)'); ylabel('N'); title(sprintf('Components\n%s',title_str),'FontSize',7,'Interpreter','none');
            legend('FontSize',6,'Location','best'); grid on;

            nexttile; hold on;
            plot(t_win,Fmag_old,'Color',col,'LineWidth',0.7,'DisplayName',sprintf('OLD mag  tssf=%.2e',sum(Fm_old.^2)));
            yline(nf_old,'r--','LineWidth',1,'DisplayName',sprintf('nf=%.2fN',nf_old));
            xlabel('t (s)'); ylabel('N'); title('OLD: |F| magnitude','FontSize',8);
            legend('FontSize',6,'Location','best'); grid on;

            nexttile; hold on;
            plot(t_win,F_sum,'Color',col,'LineWidth',0.7,'DisplayName',sprintf('NEW sum  tssf=%.2e',sum(Fs_new.^2)));
            yline( nf_new,'r--','LineWidth',1,'DisplayName',sprintf('nf=%.2fN',nf_new));
            yline(-nf_new,'r--','LineWidth',1,'HandleVisibility','off');
            xlabel('t (s)'); ylabel('N'); title('NEW: Fx+Fy+Fz signed sum','FontSize',8);
            legend('FontSize',6,'Location','best'); grid on;

        else  % tssv
            LA=load(sig_path,'ACCEL'); t_a=LA.ACCEL.time_rel(:); fs=LA.ACCEL.fs_nominal; dt=1/fs;
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
            AL(abs(AL)<cfg.tssv_noise_threshold_ms2)=0;
            AR(abs(AR)<cfg.tssv_noise_threshold_ms2)=0;
            A_comb=AL+AR;
            col=local_ternary(rmvd_flag,[0.8 0.2 0.2],[0.2 0.5 0.8]);

            nexttile; hold on;
            plot(t_win,seg(:,1),'Color',[0.6 0.6 0.6],'LineWidth',0.5,'DisplayName','Lx raw');
            xlabel('t (s)'); ylabel('m/s²');
            title(sprintf('Raw Lx\n%s',title_str),'FontSize',7,'Interpreter','none');
            legend('FontSize',6); grid on;

            nexttile; hold on;
            plot(t_win,AL,'Color',col,'LineWidth',0.7,'DisplayName','Left signed sum');
            plot(t_win,AR,'Color',col*0.6,'LineWidth',0.7,'DisplayName','Right signed sum');
            yline( cfg.tssv_noise_threshold_ms2,'r--','LineWidth',1,'HandleVisibility','off');
            yline(-cfg.tssv_noise_threshold_ms2,'r--','LineWidth',1,'HandleVisibility','off');
            xlabel('t (s)'); ylabel('m/s²'); title('Bandpassed signed sums','FontSize',8);
            legend('FontSize',6); grid on;

            nexttile; hold on;
            plot(t_win,A_comb.^2*dt,'Color',col,'LineWidth',0.7,...
                'DisplayName',sprintf('integrand  tssv=%.4f',sum(A_comb.^2)*dt));
            xlabel('t (s)'); ylabel('(m/s²)²·s'); title('TSSV integrand','FontSize',8);
            legend('FontSize',6); grid on;
        end
    end

    fname = sprintf('inspect_%s_%s.png',strrep(subj,'subject_',''),metric);
    exportgraphics(fig,fullfile(fig_dir,fname),'Resolution',120);
    fprintf('Saved %s\n',fname);
end

function out=local_ternary(c,a,b), if c,out=a; else,out=b; end, end