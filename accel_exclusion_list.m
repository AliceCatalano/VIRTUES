%% apply_outlier_exclusions_revised.m
% Hard-coded, visually-confirmed exclusions ONLY -- no statistical
% (p1/p99 or otherwise) outlier removal. Every exclusion here was
% visually verified against the raw signal, not derived from a
% quantile/MAD threshold.

clear; clc; cfg = config();
FV_raw = load(fullfile(cfg.output_root,'force_vibration_features.mat'),'T'); T=FV_raw.T;

fprintf('Before cleaning: %d rows\n',height(T));
fprintf('  TSSV valid: %d  NaN: %d\n',sum(isfinite(T.tssv)&T.tssv>0),sum(~isfinite(T.tssv)|T.tssv<=0));
fprintf('  TSSF valid: %d  NaN: %d\n',sum(isfinite(T.tssf)&T.tssf>0),sum(~isfinite(T.tssf)|T.tssf<=0));

% TSSV whole-subject exclusions
tssv_subj_excl = {'subject_s02N','subject_s05N','subject_s09N','subject_s10H','subject_s11N', ...
    'subject_s12H','subject_s23H','subject_s44N',};
for si=1:numel(tssv_subj_excl)
    s=tssv_subj_excl{si};
    n=sum(strcmp(T.subject,s)&isfinite(T.tssv)&T.tssv>0);
    T.tssv(strcmp(T.subject,s))=NaN;
    fprintf('TSSV whole-subject exclusion: %s (%d reps)\n',s,n);
end

% TSSV specific acquisition exclusions (visually confirmed)
tssv_acq_excl = {'subject_s45H','Baseline1','Level1'
    'subject_s45H','Baseline1','Level2'
    'subject_s45H','Baseline1','Level3'
    'subject_s45H','Baseline1','Level4'
    'subject_s45H','Baseline1','Level5'
    'subject_s45H','Test1','main'
    'subject_s20N','Baseline1','Level1'   % TODO: fill in N -- which level(s) in Baseline1
    'subject_s20N','Baseline1','Level2'
    'subject_s20N','Baseline1','Level3'
    'subject_s20N','Baseline1','Level4'
    'subject_s20N','Baseline1','Level5'
    'subject_s20N','Test1','main'          % already NaN via Gate 2 (sensor fully off) -- kept here for the audit trail
};
for ai=1:size(tssv_acq_excl,1)
    s=tssv_acq_excl{ai,1}; ph=tssv_acq_excl{ai,2}; acq=tssv_acq_excl{ai,3};
    mask=strcmp(T.subject,s)&strcmp(T.phase,ph)&strcmp(T.acquisition,acq);
    n=sum(mask&isfinite(T.tssv)&T.tssv>0);
    T.tssv(mask)=NaN;
    fprintf('TSSV acq exclusion: %s/%s/%s (%d reps)\n',s,ph,acq,n);
end

% TSSF whole-subject exclusions
tssf_subj_excl={'subject_s02N','subject_s05N','subject_s03H','subject_s04H'};
for si=1:numel(tssf_subj_excl)
    s=tssf_subj_excl{si}; n=sum(strcmp(T.subject,s)&isfinite(T.tssf)&T.tssf>0);
    T.tssf(strcmp(T.subject,s))=NaN;
    fprintf('TSSF whole-subject exclusion: %s (%d reps)\n',s,n);
end

% TSSF specific acquisition exclusions (visually confirmed)
tssf_acq_excl = {'subject_s20N','Baseline1','Level1'   % TODO: fill in N -- which level(s) in Baseline1
    'subject_s20N','Baseline1','Level2'
    'subject_s20N','Baseline1','Level3'
    'subject_s20N','Baseline1','Level4'
    'subject_s20N','Baseline1','Level5'
    'subject_s20N','Test1','main' 
    'subject_s23H','Baseline2','Level1'   % TODO: fill in N -- which level(s) in Baseline1
    'subject_s23H','Baseline2','Level2'
    'subject_s23H','Baseline2','Level3'% TSSF: Test1 bad, Test2 good -- value-based, Gate 2 did not catch this one
};
for ai=1:size(tssf_acq_excl,1)
    s=tssf_acq_excl{ai,1}; ph=tssf_acq_excl{ai,2}; acq=tssf_acq_excl{ai,3};
    mask=strcmp(T.subject,s)&strcmp(T.phase,ph)&strcmp(T.acquisition,acq);
    n=sum(mask&isfinite(T.tssf)&T.tssf>0);
    T.tssf(mask)=NaN;
    fprintf('TSSF acq exclusion: %s/%s/%s (%d reps)\n',s,ph,acq,n);
end

fprintf('\n=== Final counts ===\n');
fprintf('TSSV valid: %d  NaN: %d\n',sum(isfinite(T.tssv)&T.tssv>0),sum(~isfinite(T.tssv)|T.tssv<=0));
fprintf('TSSF valid: %d  NaN: %d\n',sum(isfinite(T.tssf)&T.tssf>0),sum(~isfinite(T.tssf)|T.tssf<=0));

save(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T');
fprintf('Saved.\n');
