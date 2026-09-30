function T_impact = collision_impact_features(cfg)

    if isnan(cfg.accel_sensitivity_ms2_per_V)
        error('collision_impact_features: cfg.accel_sensitivity_ms2_per_V must be set.');
    end

    INTENSITY_WIN_SEC = 0.10;
    BP_LOW  = 80; BP_HIGH = 1000;
    C_force = load_ati_cal(cfg.force_cal_path);
    all_phases = [cfg.baseline_phases, cfg.training_levels, cfg.test_phases];
    rows = {};
    % load once before subject loop
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
                phase_type='training'; level_num=str2double(regexp(phase,'\d+','match','once'));
                acquisitions=arrayfun(@(k)sprintf('rep_%02d',k),1:cfg.n_training_reps,'UniformOutput',false);
                rep_nums=1:cfg.n_training_reps;
            elseif is_baseline
                phase_type='baseline'; level_num=NaN;
                acquisitions=arrayfun(@(k)sprintf('Level%d',k),1:numel(cfg.level_names),'UniformOutput',false);
                rep_nums=nan(1,numel(acquisitions));
            else
                phase_type='test'; level_num=NaN;
                acquisitions={'main'}; rep_nums=NaN;
            end

            for ai = 1:numel(acquisitions)
                acq=acquisitions{ai};
                if is_test, acq_dir=phase_dir;
                else
                    acq_dir=fullfile(phase_dir,acq);
                    if ~isfolder(acq_dir)
                        if isfolder([acq_dir '_R']), acq_dir=[acq_dir '_R'];
                        else, continue; end
                    end
                end

                coll_path=fullfile(acq_dir,'collision_results.mat');
                if ~isfile(coll_path), continue; end
                C=load(coll_path,'results');
                coll_t=C.results.collision_rel; n_coll=numel(coll_t);
                if n_coll==0, continue; end
                peak_audio_all=C.results.peak_audio;

                ev_path=fullfile(acq_dir,'events.mat');
                [t_start,t_end]=safe_trial_window(ev_path);
                if isnan(t_start)||isnan(t_end), continue; end
                % gate 3: hard-coded visual inspection exclusions
                if local_is_hardcoded_exclusion(T_excl, subj, phase, acq)
                    continue
                end
                rep_this=rep_nums(ai);
                if is_training, level_this=level_num;
                elseif is_baseline, level_this=ai;
                else, level_this=NaN; end

                % --- force ---
                have_force=false; force_path=fullfile(acq_dir,'force.mat');
                F_cal_full=[]; t_force=[];
                if isfile(force_path)
                    LF=load(force_path,'FORCE');
                    t_force=LF.FORCE.time_rel(:); raw_V_f=LF.FORCE.data;
                    bias_mask_f=t_force>=(t_start-1.0)&t_force<t_start;
                    if sum(bias_mask_f)<3, bias_mask_f=t_force<(t_force(1)+1.0); end
                    bias_f=mean(raw_V_f(bias_mask_f,:),1,'omitnan');
                    F_cal_full=(C_force*(raw_V_f-bias_f)')';
                    have_force=true;
                end

                % --- accel ---
                have_accel=false; accel_path=fullfile(acq_dir,'accel.mat');
                accel_ms2_full=[]; t_accel=[]; dt_accel=NaN;
                if isfile(accel_path)
                    LA=load(accel_path,'ACCEL');
                    t_accel=LA.ACCEL.time_rel(:);
                    fs=LA.ACCEL.fs_nominal; dt_accel=1/fs;

                    % gate 1: missing samples
                    trial_mask_check=t_accel>=t_start&t_accel<=t_end;
                    expected_samp=round((t_end-t_start)*fs);
                    pct_missing=max(0,(expected_samp-sum(trial_mask_check))/expected_samp*100);

                    % gate 2: noise detection
                    if pct_missing > cfg.accel_max_pct_missing
                        warning('collision_impact: %.1f%% missing — impact_tssv=NaN for %s/%s/%s',pct_missing,subj,phase,acq);
                    elseif local_accel_is_noise(LA,t_start,t_end,cfg,BP_LOW,BP_HIGH)
                        warning('collision_impact: noise signal — impact_tssv=NaN for %s/%s/%s',subj,phase,acq);
                    else
                        bias_mask_a=t_accel>=(t_start-1.0)&t_accel<t_start;
                        if sum(bias_mask_a)<3, bias_mask_a=t_accel<(t_accel(1)+1.0); end
                        bias_a=mean(LA.ACCEL.data(bias_mask_a,:),1,'omitnan');
                        raw_V=LA.ACCEL.data-bias_a;
                        raw_ms2=raw_V*cfg.accel_sensitivity_ms2_per_V;
                        if fs/2>BP_HIGH
                            raw_ms2=local_bandpass(raw_ms2,BP_LOW,BP_HIGH,fs);
                        else
                            warning('collision_impact: Nyquist<=1000Hz, bandpass skipped: %s/%s/%s',subj,phase,acq);
                        end
                        accel_ms2_full=raw_ms2;
                        have_accel=true;
                    end
                end

                for ci2=1:n_coll
                    t0=coll_t(ci2);
                    win_lo=t0-INTENSITY_WIN_SEC; win_hi=t0+INTENSITY_WIN_SEC;

                    impact_tssf=NaN;
                    if have_force
                        mask_f=t_force>=win_lo&t_force<=win_hi;
                        if sum(mask_f)>2
                            Fmag=sqrt(sum(F_cal_full(mask_f,1:3).^2,2));
                            nf=median(Fmag)+cfg.force_noise_k_mad*mad(Fmag,1);
                            Fmag(Fmag<nf)=0; impact_tssf=sum(Fmag.^2);
                        end
                    end

                    impact_tssv=NaN;
                    if have_accel
                        mask_a=t_accel>=win_lo&t_accel<=win_hi;
                        if sum(mask_a)>2
                            seg=accel_ms2_full(mask_a,:);
                            A_left=sum(seg(:,1:3),2); A_right=sum(seg(:,4:6),2);
                            thr=cfg.tssv_noise_threshold_ms2;
                            A_left(abs(A_left)<thr)=0; A_right(abs(A_right)<thr)=0;
                            impact_tssv=sum((A_left+A_right).^2)*dt_accel;
                        end
                    end

                    impact_audio_peak=NaN;
                    if ci2<=numel(peak_audio_all), impact_audio_peak=peak_audio_all(ci2); end

                    rows(end+1,:)={subj,group,haptic,phase_type,phase,acq,...
                        level_this,rep_this,ci2,t0,...
                        impact_audio_peak,impact_tssv,impact_tssf}; %#ok<AGROW>
                end
            end
        end
        fprintf('Processed %s\n',subj);
    end

    varnames={'subject','group','haptic','phase_type','phase','acquisition',...
        'level','repetition','collision_idx','collision_t',...
        'impact_audio_peak','impact_tssv','impact_tssf'};
    T_impact=cell2table(rows,'VariableNames',varnames);
    if height(T_impact)>0, T_impact.haptic=logical(T_impact.haptic); end

    T_impact.impact_tier_audio=local_tertile_tier(T_impact.impact_audio_peak);
    T_impact.impact_tier_tssv =local_tertile_tier(T_impact.impact_tssv);
    T_impact.impact_tier_tssf =local_tertile_tier(T_impact.impact_tssf);

    if ~exist(cfg.output_root,'dir'), mkdir(cfg.output_root); end
    save(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact');
    writetable(T_impact,fullfile(cfg.output_root,'collision_impact_features.csv'));
    n_nan=sum(~isfinite(T_impact.impact_tssv));
    fprintf('\nSaved collision-impact table (%d events, %d impact_tssv=NaN)\n',height(T_impact),n_nan);

    valid=isfinite(T_impact.impact_audio_peak)&isfinite(T_impact.impact_tssv);
    if sum(valid)>2
        r=corr(T_impact.impact_audio_peak(valid),T_impact.impact_tssv(valid));
        fprintf('[sanity] impact_audio_peak vs impact_tssv: r=%.3f (n=%d)\n',r,sum(valid));
    end
end

function out=local_bandpass(data,lo,hi,fs)
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
    is_excluded = any(strcmp(T_excl.subject,subj) & ...
                      strcmp(T_excl.phase,phase)   & ...
                      strcmp(T_excl.acquisition,acq));
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

function tier=local_tertile_tier(x)
    tier=repmat(categorical({'NaN'}),numel(x),1);
    valid=isfinite(x);
    if sum(valid)<3, return; end
    cuts=quantile(x(valid),[1/3,2/3]);
    labels=strings(numel(x),1); labels(:)="NaN";
    labels(valid&x<=cuts(1))="Low";
    labels(valid&x>cuts(1)&x<=cuts(2))="Mid";
    labels(valid&x>cuts(2))="High";
    tier=categorical(labels,{'Low','Mid','High','NaN'},'Ordinal',true);
end