%% batch_sync_check_all.m
% Checks NIDAQ vs audiomixer synchronisation for every acquisition.
% Flags acquisitions where cross-correlation lag > 50ms or max_xcorr < 0.2
% (indicating the two streams are not synchronised).

clear; clc; cfg = config();
BP_LOW=80; BP_HIGH=1000;
LAG_THRESH_MS  = 50;    % flag if lag > this
XCORR_THRESH   = 0.20;  % flag if max xcorr < this
FS_THRESH      = 5000;  % flag if audiomixer fs > this (wrong fs)

all_phases=[cfg.baseline_phases, cfg.training_levels, cfg.test_phases];
rows={};

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
            au_path=fullfile(acq_dir,'audio.mat');
            ev_path=fullfile(acq_dir,'events.mat');
            if ~isfile(ac_path)||~isfile(au_path)||~isfile(ev_path), continue; end

            try
                [t_start,t_end]=safe_trial_window(ev_path);
                if isnan(t_start)||isnan(t_end), continue; end

                LA =load(ac_path,'ACCEL');
                LA2=load(au_path,'AUDIO');

                t_n=LA.ACCEL.time_rel(:); rv_n=LA.ACCEL.data;
                t_a=LA2.AUDIO.time_rel(:); rv_a=LA2.AUDIO.data;

                % t0 difference
                t0_diff_ms=(double(LA2.AUDIO.time_unix(1))-LA.ACCEL.t0_unix)*1000;

                % real fs
                dt_n=diff(t_n(t_n>=t_start&t_n<=t_end));
                dt_a=diff(t_a(t_a>=t_start&t_a<=t_end));
                fs_n=1/median(dt_n(dt_n>0));
                fs_a=1/median(dt_a(dt_a>0));

                % wrong fs flag
                if fs_a>FS_THRESH
                    rows(end+1,:)={subj,phase,acq,t0_diff_ms,fs_n,fs_a,NaN,NaN,'wrong_fs'};
                    continue;
                end

                % skip if bandpass not feasible
                if fs_n/2<=BP_HIGH||fs_a/2<=BP_HIGH, continue; end

                % bias removal
                bm_n=t_n>=(t_start-1.0)&t_n<t_start; if sum(bm_n)<3, bm_n=t_n<(t_n(1)+1.0); end
                bm_a=t_a>=(t_start-1.0)&t_a<t_start; if sum(bm_a)<3, bm_a=t_a<(t_a(1)+1.0); end
                bias_n=mean(rv_n(bm_n,:),1,'omitnan');
                bias_a=mean(rv_a(bm_a,:),1,'omitnan');

                tm_n=t_n>=t_start&t_n<=t_end;
                tm_a=t_a>=t_start&t_a<=t_end;
                if sum(tm_n)<100||sum(tm_a)<100, continue; end

                % bandpass — one representative channel pair each side
                [b_n,a_n]=butter(4,[BP_LOW BP_HIGH]/(fs_n/2),'bandpass');
                [b_a,a_a]=butter(4,[BP_LOW BP_HIGH]/(fs_a/2),'bandpass');

                ch_n=LA.ACCEL.channel_names;
                left_n=find(ismember(ch_n,{'ai9','ai10','ai11'}));
                right_n=find(ismember(ch_n,{'ai12','ai13','ai14'}));
                ch_a=LA2.AUDIO.channel_names;
                left_a=find(ismember(ch_a,{'ch12','ch13','ch14','ch11'}));
                right_a=find(ismember(ch_a,{'ch16','ch17','ch18'}));
                if isempty(left_a),  left_a=1:min(3,size(rv_a,2)); end
                if isempty(right_a), right_a=min(4,size(rv_a,2)):min(6,size(rv_a,2)); end

                rv_n_bp=zeros(sum(tm_n),6);
                for c=1:6, rv_n_bp(:,c)=filtfilt(b_n,a_n,double(rv_n(tm_n,c)-bias_n(c))); end
                A_n=sum(rv_n_bp(:,left_n),2)+sum(rv_n_bp(:,right_n),2);

                rv_a_bp=zeros(sum(tm_a),size(rv_a,2));
                for c=1:size(rv_a,2), rv_a_bp(:,c)=filtfilt(b_a,a_a,double(rv_a(tm_a,c)-bias_a(c))); end
                A_a=sum(rv_a_bp(:,left_a),2)+sum(rv_a_bp(:,right_a),2);

                % interpolate to common timebase
                t_win_n=t_n(tm_n); t_win_a=t_a(tm_a);
                [t_a_u,ia]=unique(t_win_a); A_a_u=A_a(ia);
                A_a_i=interp1(t_a_u,A_a_u,t_win_n,'linear','extrap');

                % cross-correlation — search ±3s
                max_lag_s=round(fs_n*3);
                n_cc=min(numel(A_n),numel(A_a_i));
                [xc,lags]=xcorr(A_n(1:n_cc),A_a_i(1:n_cc),max_lag_s,'normalized');
                [max_xc,idx_max]=max(abs(xc));
                lag_ms=lags(idx_max)/fs_n*1000;

                % flag if problematic
                if abs(lag_ms)>LAG_THRESH_MS
                    flag='large_lag';
                elseif max_xc<XCORR_THRESH
                    flag='low_xcorr';
                else
                    flag='ok';
                end

                rows(end+1,:)={subj,phase,acq,t0_diff_ms,fs_n,fs_a,lag_ms,max_xc,flag};

            catch ME
                rows(end+1,:)={subj,phase,acq,NaN,NaN,NaN,NaN,NaN,['error:' ME.message(1:min(40,end))]};
            end
        end
    end
    fprintf('Checked %s\n',subj);
end

T=cell2table(rows,'VariableNames',{'subject','phase','acquisition','t0_diff_ms','fs_nidaq','fs_audio','lag_ms','max_xcorr','flag'});

% summary
fprintf('\n=== Summary ===\n');
flags=unique(T.flag);
for fi=1:numel(flags)
    n=sum(strcmp(T.flag,flags{fi}));
    fprintf('  %-20s: %d acquisitions\n',flags{fi},n);
end

% flagged acquisitions
Tbad=T(~strcmp(T.flag,'ok'),:);
fprintf('\n=== Flagged acquisitions (%d total) ===\n',height(Tbad));
fprintf('%-22s %-15s %-10s %10s %10s %10s  %s\n',...
    'Subject','Phase','Acq','t0_diff_ms','lag_ms','max_xcorr','Flag');
Tbad=sortrows(Tbad,'flag');
for i=1:height(Tbad)
    r=Tbad(i,:);
    fprintf('%-22s %-15s %-10s %10.1f %10.1f %10.3f  %s\n',...
        strrep(r.subject{1},'subject_',''),r.phase{1},r.acquisition{1},...
        r.t0_diff_ms,r.lag_ms,r.max_xcorr,r.flag{1});
end

% per-subject summary of flagged
fprintf('\n=== Per-subject flagged count ===\n');
subj_list=unique(Tbad.subject);
for si=1:numel(subj_list)
    s=subj_list{si};
    n_bad=sum(strcmp(Tbad.subject,s));
    n_tot=sum(strcmp(T.subject,s));
    flags_this=unique(Tbad.flag(strcmp(Tbad.subject,s)));
    fprintf('  %-20s: %d/%d flagged  [%s]\n',...
        strrep(s,'subject_',''),n_bad,n_tot,strjoin(flags_this,', '));
end

save(fullfile(cfg.output_root,'sync_check_results.mat'),'T','Tbad');
writetable(T,fullfile(cfg.output_root,'sync_check_results.csv'));
writetable(Tbad,fullfile(cfg.output_root,'sync_check_flagged.csv'));
fprintf('\nSaved sync_check_results.mat and .csv\n');