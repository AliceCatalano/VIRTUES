%% apply_outlier_exclusions_level_dependent.m
% Level-dependent p1/p99 outlier removal for TSSV and TSSF.
% Rationale: collision intensity and force scale with task difficulty.
% A trial that would be extreme at Level 1 is normal at Level 4.
% Pooling levels before computing bounds conflates difficulty with outliers.
%
% Strategy:
%   Training:  bounds per level (L1-L5)
%   Baseline:  bounds per level (Level1-Level5) — same difficulty structure
%   Test:      single bound across all test trials (small n, one difficulty)

clear; clc; cfg = config();
FV_raw = load(fullfile(cfg.output_root,'force_vibration_features.mat'),'T'); T=FV_raw.T;

fprintf('Before cleaning: %d rows\n',height(T));
fprintf('  TSSV valid: %d  NaN: %d\n',sum(isfinite(T.tssv)&T.tssv>0),sum(~isfinite(T.tssv)|T.tssv<=0));
fprintf('  TSSF valid: %d  NaN: %d\n',sum(isfinite(T.tssf)&T.tssf>0),sum(~isfinite(T.tssf)|T.tssf<=0));

%% Whole-subject exclusions (unchanged)
tssv_subj_excl = {'subject_s09N','subject_s12H'};
tssf_subj_excl = {'subject_s03H','subject_s04H'};
for si=1:numel(tssv_subj_excl)
    s=tssv_subj_excl{si};
    n=sum(strcmp(T.subject,s)&isfinite(T.tssv)&T.tssv>0);
    T.tssv(strcmp(T.subject,s))=NaN;
    fprintf('TSSV whole-subject exclusion: %s (%d reps)\n',s,n);
end
for si=1:numel(tssf_subj_excl)
    s=tssf_subj_excl{si};
    n=sum(strcmp(T.subject,s)&isfinite(T.tssf)&T.tssf>0);
    T.tssf(strcmp(T.subject,s))=NaN;
    fprintf('TSSF whole-subject exclusion: %s (%d reps)\n',s,n);
end

metrics = {'tssv','tssf'};
bounds_log = struct();

for mi = 1:2
    oc = metrics{mi};
    fprintf('\n=== %s level-dependent p1/p99 bounds ===\n',upper(oc));
    n_removed = 0;

    %% Training: per level
    fprintf('Training:\n');
    for lv = 1:5
        mask = strcmp(T.phase_type,'training') & T.level==lv & isfinite(T.(oc)) & T.(oc)>0;
        v = log(T.(oc)(mask));
        if numel(v)<10, continue; end
        p1=quantile(v,0.01); p99=quantile(v,0.99);
        out = mask;
        log_v = nan(height(T),1); log_v(mask)=v;
        out = mask & (log_v<p1 | log_v>p99);
        T.(oc)(out)=NaN;
        n_removed=n_removed+sum(out);
        fprintf('  L%d: n=%d  p1=%.3f(%.3f raw)  p99=%.3f(%.3f raw)  removed=%d\n',lv,sum(mask),p1,exp(p1),p99,exp(p99),sum(out));
        bounds_log.(oc).(sprintf('training_L%d',lv))=struct('p1',p1,'p99',p99);
    end

    %% Baseline: per level
    fprintf('Baseline:\n');
    for lv = 1:5
        lv_name = sprintf('Level%d',lv);
        mask = strcmp(T.phase_type,'baseline') & T.level==lv & isfinite(T.(oc)) & T.(oc)>0;
        v = log(T.(oc)(mask));
        if numel(v)<6
            fprintf('  BL L%d: n=%d — insufficient for level-specific bounds, skipping\n',lv,numel(v));
            continue;
        end
        p1=quantile(v,0.01); p99=quantile(v,0.99);
        log_v=nan(height(T),1); log_v(mask)=v;
        out = mask & (log_v<p1 | log_v>p99);
        T.(oc)(out)=NaN;
        n_removed=n_removed+sum(out);
        fprintf('  BL L%d: n=%d  p1=%.3f  p99=%.3f  removed=%d\n',lv,sum(mask),p1,p99,sum(out));
        bounds_log.(oc).(sprintf('baseline_L%d',lv))=struct('p1',p1,'p99',p99);
    end

    %% Test: single bound across all test trials
    fprintf('Test:\n');
    mask = strcmp(T.phase_type,'test') & isfinite(T.(oc)) & T.(oc)>0;
    v = log(T.(oc)(mask));
    if numel(v)>=6
        p1=quantile(v,0.01); p99=quantile(v,0.99);
        log_v=nan(height(T),1); log_v(mask)=v;
        out = mask & (log_v<p1 | log_v>p99);
        T.(oc)(out)=NaN;
        n_removed=n_removed+sum(out);
        fprintf('  Test: n=%d  p1=%.3f(%.3f raw)  p99=%.3f(%.3f raw)  removed=%d\n',numel(v),p1,exp(p1),p99,exp(p99),sum(out));
        bounds_log.(oc).test=struct('p1',p1,'p99',p99);
    end

    fprintf('Total removed for %s: %d\n',upper(oc),n_removed);
end

%% Summary
fprintf('\n=== After level-dependent cleaning ===\n');
fprintf('  TSSV valid: %d  NaN: %d\n',sum(isfinite(T.tssv)&T.tssv>0),sum(~isfinite(T.tssv)|T.tssv<=0));
fprintf('  TSSF valid: %d  NaN: %d\n',sum(isfinite(T.tssf)&T.tssf>0),sum(~isfinite(T.tssf)|T.tssf<=0));

fprintf('\n=== Comparison ===\n');
fprintf('Strategy          TSSV NaN   TSSF NaN\n');
fprintf('3-MAD global:        524        536\n');
fprintf('p1/p99 global:       404        216\n');
fprintf('p1/p99 per-level:    %3d        %3d\n',...
    sum(~isfinite(T.tssv)|T.tssv<=0), sum(~isfinite(T.tssf)|T.tssf<=0));

fprintf('\n=== Per-subject TSSV NaN after level-dependent cleaning ===\n');
fprintf('%-22s %6s %6s %6s\n','Subject','n_tot','valid','NaN');
subj_list=unique(T.subject);
for si=1:numel(subj_list)
    s=subj_list{si}; Ts=T(strcmp(T.subject,s),:);
    n_ok=sum(isfinite(Ts.tssv)&Ts.tssv>0);
    n_nan=sum(~isfinite(Ts.tssv)|Ts.tssv<=0);
    if n_nan>5
        fprintf('%-22s %6d %6d %6d\n',s,height(Ts),n_ok,n_nan);
    end
end

fprintf('\n=== Per-subject TSSF NaN after level-dependent cleaning ===\n');
for si=1:numel(subj_list)
    s=subj_list{si}; Ts=T(strcmp(T.subject,s),:);
    n_ok=sum(isfinite(Ts.tssf)&Ts.tssf>0);
    n_nan=sum(~isfinite(Ts.tssf)|Ts.tssf<=0);
    if n_nan>5
        fprintf('%-22s %6d %6d %6d\n',s,height(Ts),n_ok,n_nan);
    end
end

save(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T','bounds_log');
fprintf('\nSaved force_vibration_features_clean.mat with level-dependent bounds\n');