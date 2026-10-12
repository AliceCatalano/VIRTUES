%% rebuild_collision_final.m
% Run this ONCE after collision_impact_features(cfg) to add all patch columns.
% Never run collision_impact_features(cfg) again unless starting from scratch,
% as it will wipe all patch columns.

clear; clc; cfg = config();

%% Step 1: load base table
loaded=load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact');
T=loaded.T_impact;
fprintf('Base table: %d rows, %d columns\n',height(T),width(T));

%% Step 2: add collision_t_nidaq (timestamp correction)
T_sync=load(fullfile(cfg.output_root,'sync_check_results.mat'),'T'); T_sync=T_sync.T;
T.collision_t_nidaq=T.collision_t;
T.lag_ms_applied=zeros(height(T),1);
n_corr=0;
all_phases=[cfg.baseline_phases,cfg.training_levels,cfg.test_phases];
for si=1:numel(cfg.all_subjects)
    subj=cfg.all_subjects{si};
    for ph_idx=1:numel(all_phases)
        phase=all_phases{ph_idx};
        if ismember(phase,cfg.training_levels)
            acquisitions=arrayfun(@(k)sprintf('rep_%02d',k),1:cfg.n_training_reps,'UniformOutput',false);
        elseif ismember(phase,cfg.baseline_phases)
            acquisitions=arrayfun(@(k)sprintf('Level%d',k),1:numel(cfg.level_names),'UniformOutput',false);
        else
            acquisitions={'main'};
        end
        for ai=1:numel(acquisitions)
            acq=acquisitions{ai};
            sync_mask=strcmp(T_sync.subject,subj)&strcmp(T_sync.phase,phase)&strcmp(T_sync.acquisition,acq);
            if ~any(sync_mask), continue; end
            sync_row=T_sync(sync_mask,:);
            if isnan(sync_row.lag_ms)||isnan(sync_row.max_xcorr), continue; end
            if sync_row.max_xcorr<0.3||abs(sync_row.lag_ms)<50||abs(sync_row.lag_ms)>600, continue; end
            row_mask=strcmp(T.subject,subj)&strcmp(T.phase,phase)&strcmp(T.acquisition,acq);
            if ~any(row_mask), continue; end
            lag_s=sync_row.lag_ms/1000;
            T.collision_t_nidaq(row_mask)=T.collision_t(row_mask)-lag_s;
            T.lag_ms_applied(row_mask)=sync_row.lag_ms;
            n_corr=n_corr+sum(row_mask);
        end
    end
end
fprintf('Step 2: collision_t_nidaq corrected for %d events\n',n_corr);

%% Step 3: add peak_accel_g (audiomixer, from collision_results.mat)
T.peak_accel_g=nan(height(T),1);
n_filled=0;
for si=1:numel(cfg.all_subjects)
    subj=cfg.all_subjects{si};
    subj_dir=fullfile(cfg.data_root,subj);
    for ph_idx=1:numel(all_phases)
        phase=all_phases{ph_idx};
        phase_dir=fullfile(subj_dir,phase);
        if ~isfolder(phase_dir), continue; end
        if ismember(phase,cfg.training_levels)
            acquisitions=arrayfun(@(k)sprintf('rep_%02d',k),1:cfg.n_training_reps,'UniformOutput',false);
        elseif ismember(phase,cfg.baseline_phases)
            acquisitions=arrayfun(@(k)sprintf('Level%d',k),1:numel(cfg.level_names),'UniformOutput',false);
        else
            acquisitions={'main'};
        end
        for ai=1:numel(acquisitions)
            acq=acquisitions{ai};
            if ismember(phase,cfg.test_phases), acq_dir=phase_dir;
            else
                acq_dir=fullfile(phase_dir,acq);
                if ~isfolder(acq_dir), if isfolder([acq_dir '_R']), acq_dir=[acq_dir '_R']; else, continue; end; end
            end
            coll_path=fullfile(acq_dir,'collision_results.mat');
            if ~isfile(coll_path), continue; end
            C=load(coll_path,'results');
            if ~isfield(C.results,'peak_accel_g')||isempty(C.results.peak_accel_g), continue; end
            g_vals=C.results.peak_accel_g(:);
            row_mask=strcmp(T.subject,subj)&strcmp(T.phase,phase)&strcmp(T.acquisition,acq);
            row_idx=find(row_mask);
            if numel(row_idx)~=numel(g_vals), continue; end
            [~,ord]=sort(T.collision_idx(row_idx));
            T.peak_accel_g(row_idx(ord))=g_vals;
            n_filled=n_filled+numel(g_vals);
        end
    end
end
fprintf('Step 3: peak_accel_g filled for %d events\n',n_filled);

%% Step 4: add peak_accel_g_nidaq (NIDAQ, using corrected timestamps)
BP_LOW=80; BP_HIGH=1000; SENS=cfg.accel_sensitivity_ms2_per_V; WIN=0.10;
T.peak_accel_g_nidaq=nan(height(T),1);
n_nidaq=0;
for si=1:numel(cfg.all_subjects)
    subj=cfg.all_subjects{si};
    subj_dir=fullfile(cfg.data_root,subj);
    for ph_idx=1:numel(all_phases)
        phase=all_phases{ph_idx};
        phase_dir=fullfile(subj_dir,phase);
        if ~isfolder(phase_dir), continue; end
        if ismember(phase,cfg.training_levels)
            acquisitions=arrayfun(@(k)sprintf('rep_%02d',k),1:cfg.n_training_reps,'UniformOutput',false);
        elseif ismember(phase,cfg.baseline_phases)
            acquisitions=arrayfun(@(k)sprintf('Level%d',k),1:numel(cfg.level_names),'UniformOutput',false);
        else
            acquisitions={'main'};
        end
        for ai=1:numel(acquisitions)
            acq=acquisitions{ai};
            if ismember(phase,cfg.test_phases), acq_dir=phase_dir;
            else
                acq_dir=fullfile(phase_dir,acq);
                if ~isfolder(acq_dir), if isfolder([acq_dir '_R']), acq_dir=[acq_dir '_R']; else, continue; end; end
            end
            ac_path=fullfile(acq_dir,'accel.mat');
            ev_path=fullfile(acq_dir,'events.mat');
            if ~isfile(ac_path)||~isfile(ev_path), continue; end
            row_mask=strcmp(T.subject,subj)&strcmp(T.phase,phase)&strcmp(T.acquisition,acq);
            if ~any(row_mask), continue; end
            [t_start,t_end]=safe_trial_window(ev_path);
            if isnan(t_start)||isnan(t_end), continue; end
            LA=load(ac_path,'ACCEL');
            t_a=LA.ACCEL.time_rel(:);
            dt_a=diff(t_a(t_a>=t_start&t_a<=t_end));
            fs_real=1/median(dt_a(dt_a>0));
            if fs_real/2<=BP_HIGH, continue; end
            rv=LA.ACCEL.data;
            bm=t_a>=(t_start-1.0)&t_a<t_start;
            if sum(bm)<3, bm=t_a<(t_a(1)+1.0); end
            bias_a=mean(rv(bm,:),1,'omitnan');
            rv_ms2=(rv-bias_a)*SENS;
            [b,a_f]=butter(4,[BP_LOW BP_HIGH]/(fs_real/2),'bandpass');
            rv_bp=zeros(size(rv_ms2));
            for c=1:6, rv_bp(:,c)=filtfilt(b,a_f,double(rv_ms2(:,c))); end
            A_left=sum(rv_bp(:,1:3),2); A_right=sum(rv_bp(:,4:6),2);
            row_idx=find(row_mask);
            coll_t=T.collision_t_nidaq(row_idx);
            for ci=1:numel(row_idx)
                t0=coll_t(ci);
                wm=t_a>=(t0-WIN)&t_a<=(t0+WIN);
                if sum(wm)<2, continue; end
                peak_ms2=max(max(abs(A_left(wm))),max(abs(A_right(wm))));
                T.peak_accel_g_nidaq(row_idx(ci))=peak_ms2/9.81;
                n_nidaq=n_nidaq+1;
            end
        end
    end
    fprintf('Step 4: processed %s\n',subj);
end
fprintf('Step 4: peak_accel_g_nidaq filled for %d events\n',n_nidaq);

%% Step 5: clean — NaN excluded subjects
tssv_excl={'subject_s09N','subject_s10H','subject_s11N','subject_s12H',...
           'subject_s23H','subject_s44N','subject_s48N','subject_s02N'};
tssf_excl={'subject_s03H','subject_s04H'};
for si=1:numel(tssv_excl)
    s=tssv_excl{si};
    T.impact_tssv(strcmp(T.subject,s))=NaN;
    T.peak_accel_g_nidaq(strcmp(T.subject,s))=NaN;
    T.peak_accel_g(strcmp(T.subject,s))=NaN;
end
for si=1:numel(tssf_excl)
    T.impact_tssf(strcmp(T.subject,tssf_excl{si}))=NaN;
end
fprintf('Step 5: exclusions applied\n');

%% Save once at the end
T_impact=T;
save(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact');
fprintf('\nSaved. Final columns:\n'); disp(T_impact.Properties.VariableNames');
cols={'peak_accel_g','peak_accel_g_nidaq','collision_t_nidaq'};
for c=cols
    fprintf('%-25s: %d valid / %d total\n',c{1},...
        sum(isfinite(T_impact.(c{1}))),height(T_impact));
end

% sanity check
valid=isfinite(T_impact.peak_accel_g)&isfinite(T_impact.peak_accel_g_nidaq);
if sum(valid)>100
    r=corr(T_impact.peak_accel_g(valid),T_impact.peak_accel_g_nidaq(valid));
    fprintf('\nSanity: corr(peak_accel_g, peak_accel_g_nidaq) = %.3f (n=%d)\n',r,sum(valid));
end
valid2=isfinite(T_impact.impact_audio_peak)&isfinite(T_impact.impact_tssv);
if sum(valid2)>100
    r2=corr(T_impact.impact_audio_peak(valid2),T_impact.impact_tssv(valid2));
    fprintf('Sanity: corr(impact_audio_peak, impact_tssv) = %.3f (n=%d)\n',r2,sum(valid2));
end