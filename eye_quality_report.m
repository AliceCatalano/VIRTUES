%% eye_quality_report.m  (updated: reordering removed from exclusion criterion)
clear; clc; cfg = config();
all_phases=[cfg.baseline_phases,cfg.training_levels,cfg.test_phases];
rows={};
for si=1:numel(cfg.all_subjects)
    subj=cfg.all_subjects{si}; subj_dir=fullfile(cfg.data_root,subj);
    for ph_idx=1:numel(all_phases)
        phase=all_phases{ph_idx}; phase_dir=fullfile(subj_dir,phase);
        if ~isfolder(phase_dir), continue; end
        is_training=ismember(phase,cfg.training_levels); is_baseline=ismember(phase,cfg.baseline_phases); is_test=ismember(phase,cfg.test_phases);
        if is_training
            acquisitions=arrayfun(@(k)sprintf('rep_%02d',k),1:cfg.n_training_reps,'UniformOutput',false); rep_nums=1:cfg.n_training_reps; level_num=str2double(regexp(phase,'\d+','match','once')); phase_type='training';
        elseif is_baseline
            acquisitions=arrayfun(@(k)sprintf('Level%d',k),1:numel(cfg.level_names),'UniformOutput',false); rep_nums=nan(1,numel(acquisitions)); level_num=NaN; phase_type='baseline';
        else
            acquisitions={'main'}; rep_nums=NaN; level_num=NaN; phase_type='test';
        end
        for ai=1:numel(acquisitions)
            acq=acquisitions{ai};
            if is_test, acq_dir=phase_dir;
            else
                acq_dir=fullfile(phase_dir,acq);
                if ~isfolder(acq_dir)&&isfolder([acq_dir '_R']), acq_dir=[acq_dir '_R']; end
                if ~isfolder(acq_dir), rows(end+1,:)={subj,phase_type,phase,acq,rep_nums(ai),level_num,NaN,NaN,NaN,NaN,NaN,NaN,'missing_folder',false}; continue; end %#ok<AGROW>
            end
            eye_path=fullfile(acq_dir,'eye.mat'); ev_path=fullfile(acq_dir,'events.mat');
            if ~isfile(eye_path), rows(end+1,:)={subj,phase_type,phase,acq,rep_nums(ai),level_num,NaN,NaN,NaN,NaN,NaN,NaN,'no_eye_mat',false}; continue; end %#ok<AGROW>
            if ~isfile(ev_path), rows(end+1,:)={subj,phase_type,phase,acq,rep_nums(ai),level_num,NaN,NaN,NaN,NaN,NaN,NaN,'no_events_mat',false}; continue; end %#ok<AGROW>
            [t_start,t_end]=safe_trial_window(ev_path);
            if isnan(t_start)||isnan(t_end), rows(end+1,:)={subj,phase_type,phase,acq,rep_nums(ai),level_num,NaN,NaN,NaN,NaN,NaN,NaN,'no_trial_window',false}; continue; end %#ok<AGROW>
            try
                proc=eye_preprocess_v2(eye_path,cfg,t_start,t_end);
                n_samp=numel(proc.time); blink_frac=mean(proc.blink);
                pct_valid=proc.pct_valid; n_reord=proc.n_reordered;
                n_out_speed=proc.n_outlier_speed; n_out_local=proc.n_outlier_local;
                % Only flag on signal quality: low valid OR high blink
                % n_reordered is REPORTED but NOT used for flagging (upstream format artifact, not signal quality)
                fail_low_valid=pct_valid<70; fail_blink=blink_frac>0.40;
                flag_acq=fail_low_valid||fail_blink;
                status_str='ok'; if fail_low_valid, status_str='low_valid'; end
                if fail_blink, status_str=[status_str '+high_blink']; end
                rows(end+1,:)={subj,phase_type,phase,acq,rep_nums(ai),level_num,n_samp,blink_frac,pct_valid,n_reord,n_out_speed,n_out_local,status_str,flag_acq}; %#ok<AGROW>
            catch ME
                rows(end+1,:)={subj,phase_type,phase,acq,rep_nums(ai),level_num,NaN,NaN,NaN,NaN,NaN,NaN,ME.message,true}; %#ok<AGROW>
            end
        end
    end
    fprintf('Quality checked: %s\n',subj);
end
T_qual=cell2table(rows,'VariableNames',{'subject','phase_type','phase','acquisition','repetition','level','n_samples','blink_frac','pct_valid','n_reordered','n_outlier_speed','n_outlier_local','status','flagged'});
if ~exist(cfg.output_root,'dir'), mkdir(cfg.output_root); end
save(fullfile(cfg.output_root,'eye_quality.mat'),'T_qual');
writetable(T_qual,fullfile(cfg.output_root,'eye_quality.csv'));

fprintf('\n=== EYE QUALITY SUMMARY (flagging: pct_valid<70%% OR blink_frac>0.40 only) ===\n');
fprintf('Total acquisitions checked: %d\n',height(T_qual));
fprintf('Flagged: %d (%.1f%%)\n',sum(T_qual.flagged),100*mean(T_qual.flagged));
fprintf('  low valid (<70%%): %d\n',sum(T_qual.pct_valid<70,'omitnan'));
fprintf('  high blink (>0.40): %d\n',sum(T_qual.blink_frac>0.40,'omitnan'));
fprintf('  error/missing: %d\n',sum(isnan(T_qual.n_samples)));
fprintf('  n_reordered >100 (descriptive only, NOT used for exclusion): %d\n',sum(T_qual.n_reordered>100,'omitnan'));

subj_list=unique(T_qual.subject); fprintf('\nPer-subject flagged acquisition count:\n');
for si=1:numel(subj_list)
    s=subj_list{si}; Ts=T_qual(strcmp(T_qual.subject,s),:); n_flag=sum(Ts.flagged); n_tot=height(Ts);
    if n_flag>0, fprintf('  %-20s %d/%d flagged\n',s,n_flag,n_tot); end
end

fig=figure('Position',[50 50 1400 400]);
sgtitle('Eye tracking signal quality (reordering shown descriptively only)','FontWeight','bold');
subplot(1,3,1); histogram(T_qual.pct_valid,20,'FaceColor',[0.3 0.6 0.8]); xline(70,'r--','LineWidth',1.5); xlabel('Valid sample % per acquisition'); ylabel('Count'); title('Valid sample fraction'); grid on;
subplot(1,3,2); histogram(T_qual.blink_frac,20,'FaceColor',[0.8 0.5 0.2]); xline(0.40,'r--','LineWidth',1.5); xlabel('Blink fraction'); ylabel('Count'); title('Blink fraction'); grid on;
subplot(1,3,3); histogram(log10(max(T_qual.n_reordered,0.1)),25,'FaceColor',[0.5 0.7 0.4]); xlabel('log_{10}(n reordered samples)'); ylabel('Count'); title('Reordered samples (descriptive, not used for exclusion)'); grid on;
exportgraphics(fig,fullfile(cfg.output_root,'figures','eye_quality_summary_v2.png'),'Resolution',150); close(fig);
fprintf('Saved eye_quality.mat/.csv\n');