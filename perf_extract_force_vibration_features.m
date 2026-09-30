function T = perf_extract_force_vibration_features(cfg)

    if isnan(cfg.accel_sensitivity_ms2_per_V)
        error('perf_extract_force_vibration_features: cfg.accel_sensitivity_ms2_per_V must be set.');
    end

    BP_LOW  = 80;
    BP_HIGH = 1000;

    C_force = load_ati_cal(cfg.force_cal_path);
    all_phases = [cfg.baseline_phases, cfg.training_levels, cfg.test_phases];
    rows = {};
    % load outlier subjects matrix
    excl_path = fullfile(cfg.output_root,'accel_exclusions.mat');
    if isfile(excl_path)
        T_excl = load(excl_path,'T_excl'); T_excl = T_excl.T_excl;
    else
        T_excl = table(); warning('accel_exclusions.mat not found — no hard-coded exclusions applied.');
    end

    for si = 1:numel(cfg.all_subjects)
        subj     = cfg.all_subjects{si};
        group    = subj(end);
        haptic   = strcmp(group,'H');
        subj_dir = fullfile(cfg.data_root,subj);

        for ph_idx = 1:numel(all_phases)
            phase     = all_phases{ph_idx};
            phase_dir = fullfile(subj_dir,phase);
            if ~isfolder(phase_dir), continue; end

            is_training = ismember(phase,cfg.training_levels);
            is_baseline = ismember(phase,cfg.baseline_phases);
            is_test     = ismember(phase,cfg.test_phases);

            if is_training
                phase_type = 'training';
                level_num  = str2double(regexp(phase,'\d+','match','once'));
                acquisitions = arrayfun(@(k)sprintf('rep_%02d',k),1:cfg.n_training_reps,'UniformOutput',false);
                rep_nums   = 1:cfg.n_training_reps;
            elseif is_baseline
                phase_type = 'baseline'; level_num = NaN;
                acquisitions = arrayfun(@(k)sprintf('Level%d',k),1:numel(cfg.level_names),'UniformOutput',false);
                rep_nums   = nan(1,numel(acquisitions));
            else
                phase_type = 'test'; level_num = NaN;
                acquisitions = {'main'}; rep_nums = NaN;
            end

            for ai = 1:numel(acquisitions)
                acq = acquisitions{ai};
                if is_test, acq_dir = phase_dir;
                else
                    acq_dir = fullfile(phase_dir,acq);
                    if ~isfolder(acq_dir)
                        if isfolder([acq_dir '_R']), acq_dir=[acq_dir '_R'];
                        else, continue; end
                    end
                end

                ev_path = fullfile(acq_dir,'events.mat');
                if ~isfile(ev_path), continue; end
                [t_start,t_end] = safe_trial_window(ev_path);
                if isnan(t_start)||isnan(t_end), continue; end
                % gate 3: hard-coded visual inspection exclusions
                if local_is_hardcoded_exclusion(T_excl, subj, phase, acq)
                    % tssv stays NaN — row still added so repetition order is preserved
                    rows(end+1,:) = {subj,group,haptic,phase_type,phase,acq,level_this,rep_this,tssf,NaN};
                    continue
                end

                rep_this = rep_nums(ai);
                if is_training,     level_this = level_num;
                elseif is_baseline, level_this = ai;
                else,               level_this = NaN; end

                % --- tssf ---
                tssf = NaN;
                force_path = fullfile(acq_dir,'force.mat');
                if isfile(force_path)
                    LF = load(force_path,'FORCE');
                    t_force = LF.FORCE.time_rel(:); raw_V_f = LF.FORCE.data;
                    bias_mask_f = t_force>=(t_start-1.0)&t_force<t_start;
                    
                    if sum(bias_mask_f)<3, bias_mask_f=t_force<(t_force(1)+1.0); end
                    
                    bias_f = mean(raw_V_f(bias_mask_f,:),1,'omitnan');
                    trial_mask_f = t_force>=t_start&t_force<=t_end;
                    
                    if any(trial_mask_f)
                        F_cal = (C_force*(raw_V_f(trial_mask_f,:)-bias_f)')';
                        Fmag  = sqrt(sum(F_cal(:,1:3).^2,2));
                        nf    = median(Fmag) + cfg.force_noise_k_mad*mad(Fmag,1);
                        Fmag(Fmag < nf) = 0;
                        tssf  = sum(Fmag.^2);
                    end
                end

                % --- tssv ---
                tssv = NaN;
                accel_path = fullfile(acq_dir,'accel.mat');
                if isfile(accel_path)
                    LA = load(accel_path,'ACCEL');
                    t_accel = LA.ACCEL.time_rel(:);
                    fs = LA.ACCEL.fs_nominal; dt = 1/fs;

                    % gate 1: missing samples
                    trial_mask_check = t_accel>=t_start&t_accel<=t_end;
                    expected_samp    = round((t_end-t_start)*fs);
                    pct_missing      = max(0,(expected_samp-sum(trial_mask_check))/expected_samp*100);
                    if pct_missing > cfg.accel_max_pct_missing
                        warning('perf_extract: %.1f%% missing — tssv=NaN for %s/%s/%s',pct_missing,subj,phase,acq);
                        rows(end+1,:)={subj,group,haptic,phase_type,phase,acq,level_this,rep_this,tssf,NaN}; %#ok<AGROW>
                        continue
                    end

                    % gate 2: noise detection
                    if local_accel_is_noise(LA,t_start,t_end,cfg,BP_LOW,BP_HIGH)
                        warning('perf_extract: noise signal detected — tssv=NaN for %s/%s/%s',subj,phase,acq);
                        rows(end+1,:)={subj,group,haptic,phase_type,phase,acq,level_this,rep_this,tssf,NaN}; %#ok<AGROW>
                        continue
                    end

                    % bias
                    bias_mask_a = t_accel>=(t_start-1.0)&t_accel<t_start;
                    if sum(bias_mask_a)<3, bias_mask_a=t_accel<(t_accel(1)+1.0); end
                    bias_a = mean(LA.ACCEL.data(bias_mask_a,:),1,'omitnan');
                    raw_V  = LA.ACCEL.data-bias_a;
                    raw_ms2 = raw_V*cfg.accel_sensitivity_ms2_per_V;

                    trial_mask_a = t_accel>=t_start&t_accel<=t_end;
                    if sum(trial_mask_a)>2
                        seg_ms2 = raw_ms2(trial_mask_a,:);
                        if fs/2>BP_HIGH
                            seg_ms2=local_bandpass(seg_ms2,BP_LOW,BP_HIGH,fs);
                        else
                            warning('perf_extract: Nyquist<=1000Hz, bandpass skipped: %s/%s/%s',subj,phase,acq);
                        end
                        A_left  = sum(seg_ms2(:,1:3),2);
                        A_right = sum(seg_ms2(:,4:6),2);
                        thr = cfg.tssv_noise_threshold_ms2; % quite acceleration noise
                        A_left( abs(A_left) <thr) = 0;
                        A_right(abs(A_right)<thr) = 0;
                        tssv = sum((A_left+A_right).^2)*dt;
                    end
                end

                rows(end+1,:)={subj,group,haptic,phase_type,phase,acq,...
                    level_this,rep_this,tssf,tssv}; %#ok<AGROW>
            end
        end
        fprintf('Processed %s\n',subj);
    end

    varnames={'subject','group','haptic','phase_type','phase','acquisition','level','repetition','tssf','tssv'};
    T=cell2table(rows,'VariableNames',varnames);
    if height(T)>0, T.haptic=logical(T.haptic); end
    if ~exist(cfg.output_root,'dir'), mkdir(cfg.output_root); end
    save(fullfile(cfg.output_root,'force_vibration_features.mat'),'T');
    fprintf('\nSaved force/vibration table (%d rows, %d tssv=NaN)\n',height(T), sum(~isfinite(T.tssv)));
end

function out = local_bandpass(data,lo,hi,fs)
    [b,a]=butter(4,[lo hi]/(fs/2),'bandpass');
    out=zeros(size(data));
    for c=1:size(data,2), out(:,c)=filtfilt(b,a,double(data(:,c))); end
end
function is_excluded = local_is_hardcoded_exclusion(T_excl, subj, phase, acq)
% Returns true if this acquisition is in the hard-coded exclusion list.
% Whole-subject exclusions use acquisition='*'.
    if isempty(T_excl), is_excluded=false; return; end
    whole_subj = strcmp(T_excl.subject,subj) & strcmp(T_excl.acquisition,'*');
    if any(whole_subj), is_excluded=true; return; end
    is_excluded = any(strcmp(T_excl.subject,subj) & strcmp(T_excl.phase,phase)   & strcmp(T_excl.acquisition,acq));
end
function is_bad = local_accel_is_noise(LA, t_start, t_end, cfg, BP_LOW, BP_HIGH)
% Detects electronic noise (unpowered sensor, floating ADC input).
% Uses only two metrics that do not depend on pre-trial window:
%   1. n_unique_raw < 50  : toggling noise has very few ADC codes (bad=20, good=650+)
%   2. rms_bp < 0.01 m/s² : noise has near-zero energy after bandpass (bad=0.003, good=0.03+)
% var_ratio is NOT used — it fires false positives when pre-trial window is active.

    is_bad  = false;
    t_a     = LA.ACCEL.time_rel(:);
    fs      = LA.ACCEL.fs_nominal;
    rv      = LA.ACCEL.data;
    tm      = t_a >= t_start & t_a <= t_end;
    if sum(tm) < 10, is_bad = true; return; end

    % metric 1: unique ADC codes in raw trial data
    n_unique = mean(arrayfun(@(c) numel(unique(rv(tm,c))), 1:6));
    if n_unique < 50, is_bad = true; return; end

    % metric 2: RMS of bandpassed signal
    seg    = (rv(tm,:) - mean(rv(tm,:),1,'omitnan')) * cfg.accel_sensitivity_ms2_per_V;
    seg_bp = seg;
    if fs/2 > BP_HIGH
        [b,a_f] = butter(4,[BP_LOW BP_HIGH]/(fs/2),'bandpass');
        for c = 1:6, seg_bp(:,c) = filtfilt(b,a_f,double(seg(:,c))); end
    end
    if mean(sqrt(mean(seg_bp.^2,1))) < 0.01, is_bad = true; return; end
end