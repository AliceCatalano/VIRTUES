%% apply_outlier_exclusions_revised.m
clear; clc; cfg = config();
FV_raw = load(fullfile(cfg.output_root,'force_vibration_features.mat'),'T'); T=FV_raw.T;

% TSSV whole-subject exclusions
tssv_subj_excl = {'subject_s09N','subject_s10H','subject_s11N','subject_s12H','subject_s23H','subject_s44N','subject_s02N','subject_s48N','subject_s05N'};
for si=1:numel(tssv_subj_excl)
    s=tssv_subj_excl{si};
    n=sum(strcmp(T.subject,s)&isfinite(T.tssv)&T.tssv>0);
    T.tssv(strcmp(T.subject,s))=NaN;
    fprintf('TSSV whole-subject exclusion: %s (%d reps)\n',s,n);
end

% TSSV specific acquisition exclusions (s45H noisy baseline/test)
tssv_acq_excl = {'subject_s45H','Baseline1','Level2'
    'subject_s45H','Baseline1','Level3'
    'subject_s45H','Baseline1','Level5'
    'subject_s45H','Test1','main'
};
for ai=1:size(tssv_acq_excl,1)
    s=tssv_acq_excl{ai,1}; ph=tssv_acq_excl{ai,2}; acq=tssv_acq_excl{ai,3};
    mask=strcmp(T.subject,s)&strcmp(T.phase,ph)&strcmp(T.acquisition,acq);
    n=sum(mask&isfinite(T.tssv)&T.tssv>0);
    T.tssv(mask)=NaN;
    fprintf('TSSV acq exclusion: %s/%s/%s (%d reps)\n',s,ph,acq,n);
end

% TSSV level-dependent p99 only (no p1 — low vibration is physically meaningful)
fprintf('\nTSSV: applying p99 upper bound only (no p1 lower bound)\n');
excl_all=tssv_subj_excl;
n_removed_p99=0;
for lv=1:5
    mask=strcmp(T.phase_type,'training')&T.level==lv&isfinite(T.tssv)&T.tssv>0&~ismember(T.subject,excl_all);
    v=log(T.tssv(mask));
    p99=quantile(v,0.99);
    lv_idx=find(mask);
    out=mask; log_v=nan(height(T),1); log_v(mask)=v;
    out=mask&(log_v>p99);
    T.tssv(out)=NaN; n_removed_p99=n_removed_p99+sum(out);
    fprintf('  L%d: p99=%.3f (raw=%.2f)  removed=%d\n',lv,p99,exp(p99),sum(out));
end
for lv=1:5
    mask=strcmp(T.phase_type,'baseline')&T.level==lv&isfinite(T.tssv)&T.tssv>0&~ismember(T.subject,excl_all);
    v=log(T.tssv(mask)); if numel(v)<6, continue; end
    p99=quantile(v,0.99); log_v=nan(height(T),1); log_v(mask)=v;
    out=mask&(log_v>p99); T.tssv(out)=NaN; n_removed_p99=n_removed_p99+sum(out);
end
mask=strcmp(T.phase_type,'test')&isfinite(T.tssv)&T.tssv>0&~ismember(T.subject,excl_all);
v=log(T.tssv(mask)); p99=quantile(v,0.99); log_v=nan(height(T),1); log_v(mask)=v;
out=mask&(log_v>p99); T.tssv(out)=NaN; n_removed_p99=n_removed_p99+sum(out);
fprintf('Total removed by p99: %d\n',n_removed_p99);

% TSSF whole-subject exclusions
tssf_subj_excl={'subject_s02N','subject_s05N','subject_s03H','subject_s04H'};
for si=1:numel(tssf_subj_excl)
    s=tssf_subj_excl{si}; n=sum(strcmp(T.subject,s)&isfinite(T.tssf)&T.tssf>0);
    T.tssf(strcmp(T.subject,s))=NaN;
    fprintf('TSSF whole-subject exclusion: %s (%d reps)\n',s,n);
end

% TSSF level-dependent p1/p99
fprintf('\nTSSF: applying level-dependent p1/p99\n');
n_removed_tssf=0;
for lv=1:5
    mask=strcmp(T.phase_type,'training')&T.level==lv&isfinite(T.tssf)&T.tssf>0&~ismember(T.subject,tssf_subj_excl);
    v=log(T.tssf(mask)); p1=quantile(v,0.01); p99=quantile(v,0.99);
    log_v=nan(height(T),1); log_v(mask)=v;
    out=mask&(log_v<p1|log_v>p99); T.tssf(out)=NaN; n_removed_tssf=n_removed_tssf+sum(out);
    fprintf('  L%d: p1=%.3f p99=%.3f removed=%d\n',lv,p1,p99,sum(out));
end
for lv=1:5
    mask=strcmp(T.phase_type,'baseline')&T.level==lv&isfinite(T.tssf)&T.tssf>0&~ismember(T.subject,tssf_subj_excl);
    v=log(T.tssf(mask)); if numel(v)<6, continue; end
    p1=quantile(v,0.01); p99=quantile(v,0.99);
    log_v=nan(height(T),1); log_v(mask)=v;
    out=mask&(log_v<p1|log_v>p99); T.tssf(out)=NaN; n_removed_tssf=n_removed_tssf+sum(out);
end
mask=strcmp(T.phase_type,'test')&isfinite(T.tssf)&T.tssf>0&~ismember(T.subject,tssf_subj_excl);
v=log(T.tssf(mask)); p1=quantile(v,0.01); p99=quantile(v,0.99);
log_v=nan(height(T),1); log_v(mask)=v;
out=mask&(log_v<p1|log_v>p99); T.tssf(out)=NaN; n_removed_tssf=n_removed_tssf+sum(out);
fprintf('Total TSSF removed: %d\n',n_removed_tssf);

fprintf('\n=== Final counts ===\n');
fprintf('TSSV valid: %d  NaN: %d\n',sum(isfinite(T.tssv)&T.tssv>0),sum(~isfinite(T.tssv)|T.tssv<=0));
fprintf('TSSF valid: %d  NaN: %d\n',sum(isfinite(T.tssf)&T.tssf>0),sum(~isfinite(T.tssf)|T.tssf<=0));

save(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T');
fprintf('Saved.\n');