%% add_peak_accel_nidaq_to_collision_features.m
clear; clc; cfg = config();
BP_LOW=80; BP_HIGH=1000; SENS=cfg.accel_sensitivity_ms2_per_V;
INTENSITY_WIN=0.10;   % ±100ms

loaded=load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact');
T=loaded.T_impact;
T.peak_accel_g_nidaq=nan(height(T),1);

all_phases=[cfg.baseline_phases, cfg.training_levels, cfg.test_phases];
n_filled=0; n_miss=0;

for si=1:numel(cfg.all_subjects)
    subj=cfg.all_subjects{si};
    subj_dir=fullfile(cfg.data_root,subj);

    for ph_idx=1:numel(all_phases)
        phase=all_phases{ph_idx};
        phase_dir=fullfile(subj_dir,phase);
        if ~isfolder(phase_dir), continue; end

        is_training=ismember(phase,cfg.training_levels);
        is_baseline=ismember(phase,cfg.baseline_phases);

        if is_training
            acquisitions=arrayfun(@(k)sprintf('rep_%02d',k),1:cfg.n_training_reps,'UniformOutput',false);
        elseif is_baseline
            acquisitions=arrayfun(@(k)sprintf('Level%d',k),1:numel(cfg.level_names),'UniformOutput',false);
        else
            acquisitions={'main'};
        end

        for ai=1:numel(acquisitions)
            acq=acquisitions{ai};
            if ismember(phase,cfg.test_phases), acq_dir=phase_dir;
            else
                acq_dir=fullfile(phase_dir,acq);
                if ~isfolder(acq_dir)
                    if isfolder([acq_dir '_R']), acq_dir=[acq_dir '_R'];
                    else, continue; end
                end
            end

            ac_path=fullfile(acq_dir,'accel.mat');
            ev_path=fullfile(acq_dir,'events.mat');
            if ~isfile(ac_path)||~isfile(ev_path), continue; end

            % find matching rows in T
            row_mask=strcmp(T.subject,subj)&strcmp(T.phase,phase)&strcmp(T.acquisition,acq);
            if ~any(row_mask), continue; end

            [t_start,t_end]=safe_trial_window(ev_path);
            if isnan(t_start)||isnan(t_end), continue; end

            LA=load(ac_path,'ACCEL');
            t_a=LA.ACCEL.time_rel(:); fs=LA.ACCEL.fs_nominal;
            rv=LA.ACCEL.data;

            % bias from 1s pre-trial
            bm=t_a>=(t_start-1.0)&t_a<t_start;
            if sum(bm)<3, bm=t_a<(t_a(1)+1.0); end
            bias_a=mean(rv(bm,:),1,'omitnan');
            rv_ms2=(rv-bias_a)*SENS;

            % bandpass full recording
            if fs/2>BP_HIGH
                [b,a_f]=butter(4,[BP_LOW BP_HIGH]/(fs/2),'bandpass');
                rv_bp=zeros(size(rv_ms2));
                for c=1:6, rv_bp(:,c)=filtfilt(b,a_f,double(rv_ms2(:,c))); end
            else
                rv_bp=rv_ms2;
            end

            % signed sum per instrument
            A_left =sum(rv_bp(:,1:3),2);
            A_right=sum(rv_bp(:,4:6),2);

            % for each collision in this acquisition compute peak in window
            row_idx=find(row_mask);
            if ismember('collision_t_nidaq', T.Properties.VariableNames)
                coll_t = T.collision_t_nidaq(row_idx);
            else
                coll_t = T.collision_t(row_idx);
            end

            for ci=1:numel(row_idx)
                t0=coll_t(ci);
                win_mask=t_a>=(t0-INTENSITY_WIN)&t_a<=(t0+INTENSITY_WIN);
                if sum(win_mask)<2, n_miss=n_miss+1; continue; end
                seg_L=A_left(win_mask); seg_R=A_right(win_mask);
                % peak of absolute signed sum, converted to g
                peak_ms2=max(max(abs(seg_L)),max(abs(seg_R)));
                T.peak_accel_g_nidaq(row_idx(ci))=peak_ms2/9.81;
                n_filled=n_filled+1;
            end
        end
    end
    fprintf('Processed %s\n',subj);
end

fprintf('\nFilled: %d  Missing: %d  Total rows: %d\n',n_filled,n_miss,height(T));
fprintf('NaN rate: %.1f%%\n',100*mean(isnan(T.peak_accel_g_nidaq)));

% compare old vs new
valid=isfinite(T.peak_accel_g)&isfinite(T.peak_accel_g_nidaq);
r=corr(T.peak_accel_g(valid),T.peak_accel_g_nidaq(valid));
fprintf('\nCorrelation old (audiomixer) vs new (NIDAQ): r=%.3f (n=%d)\n',r,sum(valid));
fprintf('Old median=%.3fg  New median=%.3fg\n',...
    median(T.peak_accel_g(valid)),median(T.peak_accel_g_nidaq(valid)));

T_impact=T;
save(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact');
fprintf('Saved updated collision_impact_features.mat\n');