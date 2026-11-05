%% check_false_positives.m
clear; clc; cfg = config();
BP_LOW = 80; BP_HIGH = 1000;
SENS   = cfg.accel_sensitivity_ms2_per_V;

cases = {
    'subject_s24N','level_L1','rep_09';
    'subject_s24N','level_L1','rep_10';
    'subject_s39N','level_L3','rep_01';};

for ci = 1:size(cases,1)
    subj=cases{ci,1}; phase=cases{ci,2}; acq=cases{ci,3};
    if ismember(phase,cfg.test_phases), acq_dir=fullfile(cfg.data_root,subj,phase);
    else
        acq_dir=fullfile(cfg.data_root,subj,phase,acq);
        if ~isfolder(acq_dir), acq_dir=[acq_dir '_R']; end
    end
    [t_start,t_end]=safe_trial_window(fullfile(acq_dir,'events.mat'));
    LA=load(fullfile(acq_dir,'accel.mat'),'ACCEL');
    t_a=LA.ACCEL.time_rel(:); fs=LA.ACCEL.fs_nominal; rv=LA.ACCEL.data;
    bm=t_a>=(t_start-1.0)&t_a<t_start;
    if sum(bm)<3, bm=t_a<(t_a(1)+1.0); end
    bias_a=mean(rv(bm,:),1,'omitnan');
    rv_ms2=(rv-bias_a)*SENS;
    tm=t_a>=t_start&t_a<=t_end;
    seg=rv_ms2(tm,:); pre_seg=rv_ms2(bm,:);
    n_unique=mean(arrayfun(@(c) numel(unique(rv(tm,c))),1:6));
    seg_bp=seg; pre_bp=pre_seg;
    if fs/2>BP_HIGH
        [b,a_f]=butter(4,[BP_LOW BP_HIGH]/(fs/2),'bandpass');
        for c=1:6
            seg_bp(:,c)=filtfilt(b,a_f,double(seg(:,c)));
            pre_bp(:,c)=filtfilt(b,a_f,double(pre_seg(:,c)));
        end
    end
    rms_bp=mean(sqrt(mean(seg_bp.^2,1)));
    var_trial=mean(var(seg_bp)); var_pre=mean(var(pre_bp));
    var_ratio=var_trial/(var_pre+1e-12);
    fprintf('[%s/%s/%s]\n  n_unique=%.1f  rms_bp=%.5f  var_ratio=%.2f\n', ...
        strrep(subj,'subject_',''),phase,acq,n_unique,rms_bp,var_ratio);
end