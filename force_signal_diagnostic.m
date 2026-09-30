%% force_signal_diagnostic.m
clear; clc; cfg = config();
C_force = load_ati_cal(cfg.force_cal_path);
fig_dir = fullfile(cfg.output_root,'figures','sensor_quality');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

subj_list = cfg.all_subjects;
rows = {};

for si = 1:numel(subj_list)
    subj = subj_list{si};
    subj_dir = fullfile(cfg.data_root, subj);
    phase = 'level_L3'; acq = 'rep_05';
    acq_dir = fullfile(subj_dir, phase, acq);
    if ~isfolder(acq_dir), acq_dir=[acq_dir '_R']; end
    if ~isfolder(acq_dir), continue; end
    fo_path = fullfile(acq_dir,'force.mat');
    ev_path = fullfile(acq_dir,'events.mat');
    if ~isfile(fo_path)||~isfile(ev_path), continue; end
    [t_start,t_end]=safe_trial_window(ev_path);
    if isnan(t_start)||isnan(t_end), continue; end
    LF=load(fo_path,'FORCE'); t_f=LF.FORCE.time_rel(:); rv_f=LF.FORCE.data;
    bm=t_f>=(t_start-1.0)&t_f<t_start;
    if sum(bm)<3, bm=t_f<(t_f(1)+1.0); end
    bias_f=mean(rv_f(bm,:),1,'omitnan');
    tm=t_f>=t_start&t_f<=t_end;
    if sum(tm)<10, continue; end
    F_cal=(C_force*(rv_f(tm,:)-bias_f)')';
    Fmag=sqrt(sum(F_cal(:,1:3).^2,2));
    rms_F=sqrt(mean(Fmag.^2));
    max_F=max(Fmag);
    n_unique_F=mean(arrayfun(@(c)numel(unique(rv_f(tm,c))),1:6));
    % flag if extremely low (sensor dead) or extremely high (spike)
    flag='ok';
    if rms_F < 0.01, flag='dead_signal'; end
    if max_F > 500,  flag='spike'; end
    if n_unique_F < 20, flag='few_unique_codes'; end
    rows(end+1,:)={subj,rms_F,max_F,n_unique_F,flag};
    fprintf('%s: rms=%.3f N  max=%.1f N  n_unique=%.0f  flag=%s\n',...
        strrep(subj,'subject_',''),rms_F,max_F,n_unique_F,flag);
end
T_fq=cell2table(rows,'VariableNames',{'subject','rms_F_N','max_F_N','n_unique_raw','flag'});
writetable(T_fq,fullfile(cfg.output_root,'sensor_quality','force_signal_check.csv'));
fprintf('\nSaved force_signal_check.csv\n');