function [T, T_coll] = eye_extract_features_v2(cfg)
% Rebuilds eye feature tables using eye_preprocess_v2. NaN-pads missing
% acquisitions to preserve repetition order. Adds all new metrics.
% Saves eye_features_v2.mat.

    PRE_WIN  = 1.0;  POST_WIN = 5.0;
    all_phases=[cfg.baseline_phases,cfg.training_levels,cfg.test_phases];
    qual_file=fullfile(cfg.output_root,'eye_quality.mat');
    if ~isfile(qual_file), error('Run eye_quality_report first.'); end
    T_qual=load(qual_file,'T_qual'); T_qual=T_qual.T_qual;

    rows={}; coll_rows={};
    for si=1:numel(cfg.all_subjects)
        subj=cfg.all_subjects{si}; group=subj(end); haptic=strcmp(group,'H');
        subj_dir=fullfile(cfg.data_root,subj);
        rest_ref=eye_rest_baseline(subj,cfg);
        has_rest=~isempty(rest_ref);
        if ~has_rest, fprintf('  [no eye rest] %s\n',subj); end

        for ph_idx=1:numel(all_phases)
            phase=all_phases{ph_idx}; phase_dir=fullfile(subj_dir,phase);
            if ~isfolder(phase_dir), continue; end
            is_training=ismember(phase,cfg.training_levels); is_baseline=ismember(phase,cfg.baseline_phases); is_test=ismember(phase,cfg.test_phases);
            if is_training
                phase_type='training'; level_num=str2double(regexp(phase,'\d+','match','once'));
                acquisitions=arrayfun(@(k)sprintf('rep_%02d',k),1:cfg.n_training_reps,'UniformOutput',false); rep_nums=1:cfg.n_training_reps;
            elseif is_baseline
                phase_type='baseline'; level_num=NaN;
                acquisitions=arrayfun(@(k)sprintf('Level%d',k),1:numel(cfg.level_names),'UniformOutput',false); rep_nums=nan(1,numel(acquisitions));
            else
                phase_type='test'; level_num=NaN; acquisitions={'main'}; rep_nums=NaN;
            end

            for ai=1:numel(acquisitions)
                acq=acquisitions{ai}; rep_this=rep_nums(ai);
                if is_training, level_this=level_num; elseif is_baseline, level_this=ai; else, level_this=NaN; end
                if is_test, acq_dir=phase_dir;
                else
                    acq_dir=fullfile(phase_dir,acq);
                    if ~isfolder(acq_dir)&&isfolder([acq_dir '_R']), acq_dir=[acq_dir '_R']; end
                end

                % Check quality flag — NaN-pad if flagged or missing
                q_row=T_qual(strcmp(T_qual.subject,subj)&strcmp(T_qual.phase,phase)&strcmp(T_qual.acquisition,acq),:);
                is_flagged=isempty(q_row)||any(q_row.flagged)||any(isnan(q_row.n_samples));

                if is_flagged
                    rows(end+1,:)=local_nan_row(subj,group,haptic,phase_type,phase,acq,level_this,rep_this); %#ok<AGROW>
                    continue;
                end

                eye_path=fullfile(acq_dir,'eye.mat'); ev_path=fullfile(acq_dir,'events.mat');
                coll_path=fullfile(acq_dir,'collision_results.mat');
                if ~isfile(eye_path)||~isfile(ev_path), rows(end+1,:)=local_nan_row(subj,group,haptic,phase_type,phase,acq,level_this,rep_this); continue; end %#ok<AGROW>
                [t_start,t_end]=safe_trial_window(ev_path);
                if isnan(t_start)||isnan(t_end), rows(end+1,:)=local_nan_row(subj,group,haptic,phase_type,phase,acq,level_this,rep_this); continue; end %#ok<AGROW>

                try, proc=eye_preprocess_v2(eye_path,cfg,t_start,t_end);
                catch ME, fprintf('  [skip] %s/%s/%s: %s\n',subj,phase,acq,ME.message); rows(end+1,:)=local_nan_row(subj,group,haptic,phase_type,phase,acq,level_this,rep_this); continue; end %#ok<AGROW>

                dur=proc.valid_duration_s; pct_valid=proc.pct_valid; blink_frac=mean(proc.blink);

                % Pupil features
                vp=proc.pupil(isfinite(proc.pupil));
                pupil_mean=local_mn(vp); pupil_median=local_med(vp); pupil_max=local_mx(vp);
                if has_rest&&isfinite(rest_ref.pupil_mean)&&rest_ref.pupil_mean>0
                    bref=rest_ref.pupil_mean;
                    pupil_mean_norm=(pupil_mean-bref)/bref; pupil_median_norm=(pupil_median-bref)/bref; pupil_max_norm=(pupil_max-bref)/bref;
                else, pupil_mean_norm=NaN; pupil_median_norm=NaN; pupil_max_norm=NaN; end

                % Fixation features
                n_fix=numel(proc.fixation_dur);
                fix_rate=local_div(n_fix,dur/60);
                fix_mean_dur=local_mn(proc.fixation_dur); fix_median_dur=local_med(proc.fixation_dur);

                % Saccade features
                n_sac=numel(proc.saccade_times);
                sac_rate=local_div(n_sac,dur/60);
                sac_mean_amp=local_mn(proc.saccade_amp);

                % Dispersion and entropy
                xv=proc.x(isfinite(proc.x)&isfinite(proc.y)); yv=proc.y(isfinite(proc.x)&isfinite(proc.y));
                gaze_disp=local_ternary(numel(xv)>=2,sqrt(var(xv)+var(yv)),NaN);
                gaze_entropy=proc.gaze_entropy;

                % Collision-locked pupil response (individual collision level)
                coll_pupil_resp_mean=NaN; n_coll=0;
                if isfile(coll_path)
                    try
                        C=load(coll_path); coll_t=C.results.collision_rel; intens=C.results.peak_accel_g;
                        n_coll=numel(coll_t);
                        if n_coll>0
                            resps=nan(n_coll,1);
                            for ci=1:n_coll
                                t0=coll_t(ci);
                                bl_mask=proc.time>=t0-PRE_WIN&proc.time<t0;
                                rsp_mask=proc.time>t0&proc.time<=t0+POST_WIN;
                                bl_val=mean(proc.pupil(bl_mask),'omitnan');
                                if any(rsp_mask)&&isfinite(bl_val)&&bl_val>0
                                    pk=max(proc.pupil(rsp_mask),[],'omitnan');
                                    if isfinite(pk), resps(ci)=(pk-bl_val)/bl_val; end
                                end
                                coll_rows(end+1,:)={subj,group,haptic,phase_type,phase,acq,level_this,rep_this,ci,coll_t(ci),resps(ci),local_idx(intens,ci)}; %#ok<AGROW>
                            end
                            coll_pupil_resp_mean=mean(resps,'omitnan');
                        end
                    catch ME, fprintf('  [skip coll pupil] %s/%s/%s: %s\n',subj,phase,acq,ME.message); end
                end

                rows(end+1,:)={subj,group,haptic,phase_type,phase,acq,level_this,rep_this,dur,pct_valid,blink_frac,pupil_mean,pupil_median,pupil_max,pupil_mean_norm,pupil_median_norm,pupil_max_norm,n_fix,fix_rate,fix_mean_dur,fix_median_dur,n_sac,sac_rate,sac_mean_amp,gaze_disp,gaze_entropy,n_coll,coll_pupil_resp_mean}; %#ok<AGROW>
            end
        end
        fprintf('Processed %s\n',subj);
    end

    vn={'subject','group','haptic','phase_type','phase','acquisition','level','repetition','valid_duration_s','pct_valid','blink_frac','pupil_mean','pupil_median','pupil_max','pupil_mean_norm','pupil_median_norm','pupil_max_norm','fixation_count','fixation_rate','fixation_mean_dur','fixation_median_dur','saccade_count','saccade_rate','saccade_mean_amp_px','gaze_dispersion','gaze_entropy','n_collisions','collision_pupil_response_mean'};
    T=cell2table(rows,'VariableNames',vn);
    if height(T)>0, T.haptic=logical(T.haptic); end
    cvn={'subject','group','haptic','phase_type','phase','acquisition','level','repetition','collision_idx','collision_t','pupil_response_norm','peak_accel_g'};
    T_coll=cell2table(coll_rows,'VariableNames',cvn);
    if height(T_coll)>0, T_coll.haptic=logical(T_coll.haptic); end
    if ~exist(cfg.output_root,'dir'), mkdir(cfg.output_root); end
    save(fullfile(cfg.output_root,'eye_features_v2.mat'),'T','T_coll');
    fprintf('Saved eye_features_v2: block=%d rows, collision=%d rows\n',height(T),height(T_coll));
end

function row=local_nan_row(subj,group,haptic,phase_type,phase,acq,level,rep)
    row={subj,group,haptic,phase_type,phase,acq,level,rep,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN};
end
function v=local_mn(x),  if isempty(x)||all(isnan(x)), v=NaN; else, v=mean(x,'omitnan'); end, end
function v=local_med(x), if isempty(x)||all(isnan(x)), v=NaN; else, v=median(x,'omitnan'); end, end
function v=local_mx(x),  if isempty(x)||all(isnan(x)), v=NaN; else, v=max(x,[],'omitnan'); end, end
function v=local_div(a,b), if isnan(b)||b==0, v=NaN; else, v=a/b; end, end
function v=local_idx(x,i), if i<=numel(x), v=x(i); else, v=NaN; end, end
function out=local_ternary(c,a,b), if c, out=a; else, out=b; end, end