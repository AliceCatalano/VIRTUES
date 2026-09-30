%% Setup
cfg=config();
COLOR_N=[55 138 221]/255; COLOR_H=[212 83 126]/255;

%% Extract TSSV
all_phases=[cfg.baseline_phases,cfg.training_levels,cfg.test_phases];
rows={};

for si=1:numel(cfg.all_subjects)
    subj=cfg.all_subjects{si}; group=subj(end); haptic=strcmp(group,'H');
    subj_dir=fullfile(cfg.data_root,subj);

    for pi=1:numel(all_phases)
        phase=all_phases{pi}; phase_dir=fullfile(subj_dir,phase);
        if ~isfolder(phase_dir),continue,end

        if ismember(phase,cfg.training_levels)
            phase_type='training'; level=str2double(regexp(phase,'\d+','match','once'));
            acquisitions=arrayfun(@(k)sprintf('rep_%02d',k),1:cfg.n_training_reps,'UniformOutput',false);
            repetitions=1:cfg.n_training_reps;
        elseif ismember(phase,cfg.baseline_phases)
            phase_type='baseline'; level=NaN; acquisitions=cfg.level_names; repetitions=nan(1,5);
        else
            phase_type='test'; level=NaN; acquisitions={'main'}; repetitions=NaN;
        end

        for ai=1:numel(acquisitions)
            acquisition=acquisitions{ai};
            if strcmp(phase_type,'test'), acq_dir=phase_dir;
            else, acq_dir=fullfile(phase_dir,acquisition);
                if ~isfolder(acq_dir)
                    if isfolder([acq_dir '_R']), acq_dir=[acq_dir '_R']; else, continue; end
                end
            end

            events_path=fullfile(acq_dir,'events.mat'); accel_path=fullfile(acq_dir,'accel.mat');
            if ~isfile(events_path)||~isfile(accel_path),continue,end

            [t_start,t_end]=safe_trial_window(events_path);
            if isnan(t_start)||isnan(t_end),continue,end

            L=load(accel_path,'ACCEL');
            mask=L.ACCEL.time_rel>=t_start & L.ACCEL.time_rel<=t_end;
            if ~any(mask),continue,end

            raw=L.ACCEL.data(mask,:);
            accel=(raw-mean(raw,1,'omitnan'))*cfg.accel_sensitivity_ms2_per_V;
            aL=sqrt(sum(accel(:,1:3).^2,2)); aR=sqrt(sum(accel(:,4:6).^2,2));
            A=sqrt(aL.^2+aR.^2); A(A<cfg.tssv_noise_threshold_ms2)=0;
            tssv=sum(A.^2);

            rows(end+1,:)={subj,group,haptic,phase_type,phase,acquisition,level,repetitions(ai),numel(A),t_end-t_start,tssv};
        end
    end
    fprintf('Processed %s\n',subj);
end

TSSV=cell2table(rows,'VariableNames',{'subject','group','haptic','phase_type','phase','acquisition','level','repetition','n_samples','duration_s','tssv'});
if ~exist(cfg.output_root,'dir'),mkdir(cfg.output_root);end
save(fullfile(cfg.output_root,'TSSV_values.mat'),'TSSV','-v7.3');

%% Split into phase tables
load(fullfile(cfg.output_root,'TSSV_values.mat'),'TSSV');
phase_tables=struct();

for p=1:numel(all_phases)
    phase=all_phases{p}; tp=TSSV(strcmp(TSSV.phase,phase),:);
    if ismember(phase,cfg.training_levels), name=['Level' regexp(phase,'\d+','match','once') '_tssv'];
    else, name=[phase '_tssv']; end
    phase_tables.(name)=tp;
    S=struct(); S.(name)=tp;
    save(fullfile(cfg.output_root,[name '.mat']),'-struct','S');
    writetable(tp,fullfile(cfg.output_root,[name '.csv']));
end

save(fullfile(cfg.output_root,'TSSV_phase_tables.mat'),'phase_tables','-v7.3');

%% Plot
load(fullfile(cfg.output_root,'TSSV_phase_tables.mat'),'phase_tables');

for p=1:numel(all_phases)
    phase=all_phases{p}; tp=TSSV(strcmp(TSSV.phase,phase),:);
    if ismember(phase,cfg.training_levels), name=['Level' regexp(phase,'\d+','match','once') '_tssv'];
    else, name=[phase '_tssv']; end
    phase_tables.(name)=tp;
    S=struct(); S.(name)=tp;
    writetable(tp,fullfile(cfg.output_root,[name '.csv']));
    save(fullfile(cfg.output_root,[name '.mat']),'-struct','S');
end
save(fullfile(cfg.output_root,'TSSV_phase_tables.mat'),'phase_tables');

COLOR_N=[55 138 221]/255; COLOR_H=[212 83 126]/255;
bar_width=0.32; jitter_width=0.12;

% Training
figure; hold on;
for p=1:5
    tp=phase_tables.(sprintf('Level%d_tssv',p));
    for gi=1:2
        if gi==1, g='N'; c=COLOR_N; x0=p-0.18; else, g='H'; c=COLOR_H; x0=p+0.18; end
        y=tp.tssv(strcmp(tp.group,g)); y=y(~isnan(y));
        if isempty(y), continue; end
        med=median(y); mu=mean(y); sd=std(y);
        bar(x0,med,bar_width,'FaceColor','none','EdgeColor','none');
        x=x0+(rand(size(y))-0.5)*jitter_width;
        scatter(x,y,20,'filled','MarkerFaceColor',c,'MarkerEdgeColor','none');
        plot(x0+[-bar_width/2 bar_width/2],[med med],'k-','LineWidth',1);
        plot(x0,mu,'d','MarkerSize',7,'MarkerFaceColor','w','MarkerEdgeColor','k','LineWidth',1);
        errorbar(x0,mu,sd,sd,'k','LineWidth',1,'CapSize',8,'HandleVisibility','off');
    end
end
xticks(1:5); xticklabels({'Level1','Level2','Level3','Level4','Level5'});
xlabel('Training level'); ylabel('TSSV'); title('TSSV across training levels'); grid on; hold off;

% Baseline
figure; hold on;
for p=1:2
    tp=phase_tables.([cfg.baseline_phases{p} '_tssv']);
    for gi=1:2
        if gi==1, g='N'; c=COLOR_N; x0=p-0.18; else, g='H'; c=COLOR_H; x0=p+0.18; end
        y=tp.tssv(strcmp(tp.group,g)); y=y(~isnan(y));
        if isempty(y), continue; end
        med=median(y); mu=mean(y); sd=std(y);
        bar(x0,med,bar_width,'FaceColor','none','EdgeColor','none');
        x=x0+(rand(size(y))-0.5)*jitter_width;
        scatter(x,y,20,'filled','MarkerFaceColor',c,'MarkerEdgeColor','none');
        plot(x0+[-bar_width/2 bar_width/2],[med med],'k-','LineWidth',1);
        plot(x0,mu,'d','MarkerSize',7,'MarkerFaceColor','w','MarkerEdgeColor','k','LineWidth',1);
        errorbar(x0,mu,sd,sd,'k','LineWidth',1,'CapSize',8,'HandleVisibility','off');
    end
end
xticks(1:2); xticklabels(cfg.baseline_phases);
xlabel('Baseline phase'); ylabel('TSSV'); title('Baseline TSSV'); grid on; hold off;

% Test
figure; hold on;
for p=1:2
    tp=phase_tables.([cfg.test_phases{p} '_tssv']);
    for gi=1:2
        if gi==1, g='N'; c=COLOR_N; x0=p-0.18; else, g='H'; c=COLOR_H; x0=p+0.18; end
        y=tp.tssv(strcmp(tp.group,g)); y=y(~isnan(y));
        if isempty(y), continue; end
        med=median(y); mu=mean(y); sd=std(y);
        bar(x0,med,bar_width,'FaceColor','none','EdgeColor','none');
        x=x0+(rand(size(y))-0.5)*jitter_width;
        scatter(x,y,20,'filled','MarkerFaceColor',c,'MarkerEdgeColor','none');
        plot(x0+[-bar_width/2 bar_width/2],[med med],'k-','LineWidth',1);
        plot(x0,mu,'d','MarkerSize',7,'MarkerFaceColor','w','MarkerEdgeColor','k','LineWidth',1);
        errorbar(x0,mu,sd,sd,'k','LineWidth',1,'CapSize',8,'HandleVisibility','off');
    end
end
xticks(1:2); xticklabels(cfg.test_phases);
xlabel('Test phase'); ylabel('TSSV'); title('Test TSSV'); grid on; hold off;