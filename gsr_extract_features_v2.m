function [T, T_coll] = gsr_extract_features_v2(cfg)
    PRE_WIN_BC = 2.0; POST_WIN_SCR = 5.0;
    all_phases = [cfg.baseline_phases, cfg.training_levels, cfg.test_phases];
    rows = {}; coll_rows = {};
    for si = 1:numel(cfg.all_subjects)
        subj = cfg.all_subjects{si}; group = subj(end); haptic = strcmp(group,'H');
        subj_dir = fullfile(cfg.data_root, subj);
        rest_ref = gsr_rest_baseline(subj, cfg);
        has_rest = ~isempty(rest_ref);
        phasic_norm_denom = NaN;
        if has_rest
            if isfinite(rest_ref.tonic_mean) && rest_ref.tonic_mean > 0
                phasic_norm_denom = rest_ref.tonic_mean;
            else
                fprintf('  [degenerate tonic_mean=%.4g] %s\n', rest_ref.tonic_mean, subj);
            end
        else
            fprintf('  [no rest baseline] %s\n', subj);
        end
        for ph_idx = 1:numel(all_phases)
            phase = all_phases{ph_idx}; phase_dir = fullfile(subj_dir, phase);
            if ~isfolder(phase_dir), continue; end
            is_training = ismember(phase, cfg.training_levels);
            is_baseline = ismember(phase, cfg.baseline_phases);
            is_test     = ismember(phase, cfg.test_phases);
            if is_training
                phase_type = 'training'; level_num = str2double(regexp(phase,'\d+','match','once'));
                acquisitions = arrayfun(@(k) sprintf('rep_%02d',k), 1:cfg.n_training_reps,'UniformOutput',false);
                rep_nums = 1:cfg.n_training_reps;
            elseif is_baseline
                phase_type = 'baseline';
                acquisitions = arrayfun(@(k) sprintf('Level%d',k), 1:numel(cfg.level_names),'UniformOutput',false);
                rep_nums = nan(1,numel(acquisitions));
            else
                phase_type = 'test'; acquisitions = {'main'}; rep_nums = NaN;
            end
            for ai = 1:numel(acquisitions)
                acq = acquisitions{ai};
                if is_test, acq_dir = phase_dir;
                else
                    acq_dir = fullfile(phase_dir, acq);
                    if ~isfolder(acq_dir)
                        if isfolder([acq_dir '_R']), acq_dir = [acq_dir '_R']; else, continue; end
                    end
                end
                gsr_path = fullfile(acq_dir,'gsr.mat'); ev_path = fullfile(acq_dir,'events.mat');
                coll_path = fullfile(acq_dir,'collision_results.mat');

                if ~isfile(gsr_path), continue; end
                if ~isfile(ev_path), fprintf('  [skip no events] %s/%s/%s\n',subj,phase,acq); continue; end

                [t_start, t_end] = safe_trial_window(ev_path);
                if isnan(t_start)||isnan(t_end), fprintf('  [skip no window] %s/%s/%s\n',subj,phase,acq); continue; end

                try, proc = gsr_preprocess(gsr_path, cfg, t_start, t_end);
                catch ME, fprintf('  [skip GSR] %s/%s/%s: %s\n',subj,phase,acq,ME.message); continue; end
                
                t_gsr = proc.time; gsr_us = proc.gsr_us; tonic = proc.tonic; phasic = proc.phasic;
                if numel(t_gsr)<2, continue; end
                
                duration_s = t_gsr(end)-t_gsr(1);
                [pk_vals,~] = findpeaks(phasic,'MinPeakHeight',cfg.scr_min_amp,'MinPeakProminence',cfg.scr_min_amp,'MinPeakDistance',cfg.scr_min_dist);
                n_scr = numel(pk_vals);
                scr_freq = local_div(n_scr,duration_s/60);
                scr_mean_amp = local_mean(pk_vals); 
                scr_max_amp = local_max(pk_vals);
                scr_auc = trapz(t_gsr,max(phasic,0));
                scl_mean = mean(tonic); 
                scl_range = max(tonic)-min(tonic);
                gsr_mean_ = mean(gsr_us); 
                gsr_std_ = std(gsr_us); 
                gsr_rms_ = sqrt(mean(gsr_us.^2));
                pp = polyfit(t_gsr,tonic,1); scl_slope = pp(1);
                if has_rest
                    scl_mean_bc = scl_mean-rest_ref.tonic_mean; 
                    scl_mean_pctchg = 100*scl_mean_bc/rest_ref.tonic_mean;
                    gsr_mean_bc = gsr_mean_-rest_ref.gsr_mean;  
                    gsr_mean_pctchg = 100*gsr_mean_bc/rest_ref.gsr_mean;
                else
                    scl_mean_bc=NaN; scl_mean_pctchg=NaN; gsr_mean_bc=NaN; gsr_mean_pctchg=NaN;
                end
                scr_mean_amp_bc = scr_mean_amp / phasic_norm_denom;
                coll_scr_amp_mean=NaN; 
                coll_response_rate=NaN; 
                coll_scr_amp_mean_bc=NaN; 
                n_coll=0;
                rep_this = rep_nums(ai);
                if is_training, level_this=level_num; elseif is_baseline, level_this=ai; else, level_this=NaN; end
                if isfile(coll_path)
                    try
                        C = load(coll_path); coll_t = C.results.collision_rel; intens = C.results.peak_accel_g;
                        n_coll = numel(coll_t);
                        if n_coll>0
                            coll_amps=nan(n_coll,1); coll_amps_lbc=nan(n_coll,1); coll_resp=false(n_coll,1);
                            for ci=1:n_coll
                                t0=coll_t(ci);
                                scr_mask=(t_gsr>=t0)&(t_gsr<t0+POST_WIN_SCR);
                                bl_mask=(t_gsr>=t0-PRE_WIN_BC)&(t_gsr<t0);
                                if any(scr_mask)
                                    pk=max(phasic(scr_mask)); 
                                    coll_amps(ci)=pk; 
                                    coll_resp(ci)=pk>cfg.scr_min_amp; 
                                end
                                if any(bl_mask)&&any(scr_mask)
                                    coll_amps_lbc(ci)=max(phasic(scr_mask))-min(phasic(bl_mask)); 
                                end
                                coll_rows(end+1,:) = {subj,group,haptic,phase_type,phase,acq,level_this,rep_this,ci,t0,coll_amps(ci),coll_resp(ci),coll_amps_lbc(ci),local_idx(intens,ci)}; %#ok<AGROW>
                            end
                            coll_scr_amp_mean = mean(coll_amps,'omitnan'); 
                            coll_response_rate=mean(coll_resp);
                            coll_scr_amp_mean_bc = coll_scr_amp_mean/phasic_norm_denom;
                        end
                    catch ME
                        fprintf('  [skip coll] %s/%s/%s: %s\n',subj,phase,acq,ME.message);
                    end
                end
                rows(end+1,:) = {subj,group,haptic,phase_type,phase,acq,level_this,rep_this,duration_s,scl_mean,scl_range,scl_slope,scr_freq,...
                    scr_mean_amp,scr_max_amp,scr_auc,gsr_mean_,gsr_std_,gsr_rms_,scl_mean_bc,scl_mean_pctchg,gsr_mean_bc,gsr_mean_pctchg,...
                    scr_mean_amp_bc,n_coll,coll_scr_amp_mean,coll_response_rate,coll_scr_amp_mean_bc}; %#ok<AGROW>
            end
        end
        fprintf('Processed %s\n', subj);
    end
    varnames = {'subject','group','haptic','phase_type','phase','acquisition','level','repetition','duration_s','scl_mean','scl_range','scl_slope','scr_freq','scr_mean_amp','scr_max_amp','scr_auc','gsr_mean','gsr_std','gsr_rms','scl_mean_bc','scl_mean_pctchg','gsr_mean_bc','gsr_mean_pctchg','scr_mean_amp_bc','n_collisions','collision_scr_amp_mean','collision_response_rate','collision_scr_amp_mean_bc'};
    T = cell2table(rows,'VariableNames',varnames);
    if height(T)>0, T.haptic=logical(T.haptic); end
    coll_varnames = {'subject','group','haptic','phase_type','phase','acquisition','level','repetition','collision_idx','collision_t','scr_amp','scr_response','scr_amp_local_bc','peak_accel_g'};
    T_coll = cell2table(coll_rows,'VariableNames',coll_varnames);
    if height(T_coll)>0, T_coll.haptic=logical(T_coll.haptic); end
    if ~exist(cfg.output_root,'dir'), mkdir(cfg.output_root); end
    save(fullfile(cfg.output_root,'eda_features_v2.mat'),'T','T_coll');
    fprintf('Saved block-level (%d rows) collision-level (%d rows)\n',height(T),height(T_coll));
end
function v=local_div(a,b), if b==0||~isfinite(b), v=NaN; else, v=a/b; end, end
function v=local_mean(x),  if isempty(x), v=NaN; else, v=mean(x,'omitnan'); end, end
function v=local_max(x),   if isempty(x), v=NaN; else, v=max(x); end, end
function v=local_idx(x,i), if i<=numel(x), v=x(i); else, v=NaN; end, end