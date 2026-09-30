%% add_peak_accel_g_to_collision_features.m
clear; clc; cfg = config();

loaded=load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact');
T=loaded.T_impact;
T.peak_accel_g=nan(height(T),1);
n_filled=0; n_miss=0;

all_phases=[cfg.baseline_phases, cfg.training_levels, cfg.test_phases];

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
            coll_path=fullfile(acq_dir,'collision_results.mat');
            if ~isfile(coll_path), continue; end
            C=load(coll_path,'results');
            if ~isfield(C.results,'peak_accel_g')||isempty(C.results.peak_accel_g), continue; end
            g_vals=C.results.peak_accel_g(:);
            row_mask=strcmp(T.subject,subj)&strcmp(T.phase,phase)&strcmp(T.acquisition,acq);
            row_idx=find(row_mask);
            if numel(row_idx)~=numel(g_vals)
                fprintf('MISMATCH: %s/%s/%s table=%d coll=%d\n',subj,phase,acq,numel(row_idx),numel(g_vals));
                continue;
            end
            [~,ord]=sort(T.collision_idx(row_idx));
            T.peak_accel_g(row_idx(ord))=g_vals;
            n_filled=n_filled+numel(g_vals);
        end
    end
    fprintf('Processed %s\n',subj);
end

fprintf('Filled: %d  NaN: %d\n',n_filled,sum(isnan(T.peak_accel_g)));
T_impact=T;
save(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact');
fprintf('Saved with peak_accel_g column\n');