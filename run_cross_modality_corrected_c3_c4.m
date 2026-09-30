%% cross_modality_corrected_c3_c4.m
clear; clc; cfg = config();

CI  = load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact'); T_CI=CI.T_impact;
EDA = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T_coll'); Ec=EDA.T_coll;
EYE = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T_coll'); Yc=EYE.T_coll;

LOWER_SCR=-0.5; UPPER_SCR=5.0;

%% C3: peak_accel_g_nidaq -> log(SCR+offset) — training only
fprintf('\n=== C3 corrected: peak_accel_g_nidaq -> log(phasic SCR) ===\n');

T_CI_tr = T_CI(strcmp(T_CI.phase_type,'training'),:);
Ec_tr   = Ec(strcmp(Ec.phase_type,'training'),:);
J_c3 = innerjoin(T_CI_tr, Ec_tr, ...
    'Keys',{'subject','phase','repetition','collision_idx'}, ...
    'RightVariables',{'scr_amp_local_bc'});
hap_c3 = local_find_haptic(J_c3);

bad = J_c3.scr_amp_local_bc<LOWER_SCR | J_c3.scr_amp_local_bc>UPPER_SCR;
fprintf('C3 hard-bound exclusions: %d (%.2f%%)\n',sum(bad),100*mean(bad));
J_c3 = J_c3(~bad & isfinite(J_c3.scr_amp_local_bc) & isfinite(J_c3.peak_accel_g_nidaq),:);

offset_scr = abs(min(J_c3.scr_amp_local_bc))+0.01;
J_c3.log_scr = log(J_c3.scr_amp_local_bc+offset_scr);
fprintf('SCR offset: %.4f  n=%d\n',offset_scr,height(J_c3));

subj_u=unique(J_c3.subject); J_c3.accel_z=nan(height(J_c3),1);
for si=1:numel(subj_u)
    s=subj_u{si}; idx=strcmp(J_c3.subject,s); v=J_c3.peak_accel_g_nidaq(idx);
    J_c3.accel_z(idx)=(v-mean(v,'omitnan'))./(std(v,'omitnan')+1e-12);
end
J_c3.haptic_cat  = categorical(J_c3.(hap_c3),logical([0 1]),{'N','H'});
J_c3.subject_cat = categorical(J_c3.subject);

lme_c3=fitlme(J_c3,'log_scr ~ accel_z * haptic_cat + (1|subject_cat)', ...
    'FitMethod','REML','DummyVarCoding','reference','Verbose',false);
fprintf('\nC3 LMM: peak_accel_g_nidaq -> log(SCR+offset)\n');
disp(lme_c3.Coefficients(:,{'Name','Estimate','SE','tStat','pValue'}));
disp(anova(lme_c3));

% per-subject Spearman rho
rho_N=nan(numel(subj_u),1); rho_H=nan(numel(subj_u),1); is_H=false(numel(subj_u),1);
for si=1:numel(subj_u)
    s=subj_u{si}; Js=J_c3(strcmp(J_c3.subject,s),:); is_H(si)=any(Js.(hap_c3));
    if height(Js)<5, continue; end
    r=corr(Js.accel_z,Js.log_scr,'Type','Spearman','Rows','complete');
    if is_H(si), rho_H(si)=r; else, rho_N(si)=r; end
end
rN=rho_N(~is_H&isfinite(rho_N)); rH=rho_H(is_H&isfinite(rho_H));
[~,p_rN0]=ttest(rN); [~,p_rH0]=ttest(rH); [~,p_rNH]=ttest2(rN,rH,'Vartype','unequal');
fprintf('Per-subject rho NHF: mean=%.3f p_vs0=%.4f\n',mean(rN),p_rN0);
fprintf('Per-subject rho HF:  mean=%.3f p_vs0=%.4f\n',mean(rH),p_rH0);
fprintf('NHF vs HF: p=%.4f\n',p_rNH);

%% C4: peak_accel_g_nidaq -> pupil_response_norm — training only
fprintf('\n=== C4 corrected: peak_accel_g_nidaq -> pupil dilation ===\n');

T_CI_tr2 = T_CI(strcmp(T_CI.phase_type,'training'),:);
Yc_tr    = Yc(strcmp(Yc.phase_type,'training'),:);
J_c4 = innerjoin(T_CI_tr2, Yc_tr, ...
    'Keys',{'subject','phase','repetition','collision_idx'}, ...
    'RightVariables',{'pupil_response_norm'});
hap_c4 = local_find_haptic(J_c4);
J_c4 = J_c4(isfinite(J_c4.pupil_response_norm) & isfinite(J_c4.peak_accel_g_nidaq),:);
fprintf('C4 n=%d\n',height(J_c4));

subj_u=unique(J_c4.subject); J_c4.accel_z=nan(height(J_c4),1);
for si=1:numel(subj_u)
    s=subj_u{si}; idx=strcmp(J_c4.subject,s); v=J_c4.peak_accel_g_nidaq(idx);
    J_c4.accel_z(idx)=(v-mean(v,'omitnan'))./(std(v,'omitnan')+1e-12);
end
J_c4.haptic_cat  = categorical(J_c4.(hap_c4),logical([0 1]),{'N','H'});
J_c4.subject_cat = categorical(J_c4.subject);

lme_c4=fitlme(J_c4,'pupil_response_norm ~ accel_z * haptic_cat + (1|subject_cat)', ...
    'FitMethod','REML','DummyVarCoding','reference','Verbose',false);
fprintf('\nC4 LMM: peak_accel_g_nidaq -> pupil dilation\n');
disp(lme_c4.Coefficients(:,{'Name','Estimate','SE','tStat','pValue'}));
disp(anova(lme_c4));

rho_N=nan(numel(subj_u),1); rho_H=nan(numel(subj_u),1); is_H=false(numel(subj_u),1);
for si=1:numel(subj_u)
    s=subj_u{si}; Js=J_c4(strcmp(J_c4.subject,s),:); is_H(si)=any(Js.(hap_c4));
    if height(Js)<5, continue; end
    r=corr(Js.accel_z,Js.pupil_response_norm,'Type','Spearman','Rows','complete');
    if is_H(si), rho_H(si)=r; else, rho_N(si)=r; end
end
rN=rho_N(~is_H&isfinite(rho_N)); rH=rho_H(is_H&isfinite(rho_H));
[~,p_rN0]=ttest(rN); [~,p_rH0]=ttest(rH); [~,p_rNH]=ttest2(rN,rH,'Vartype','unequal');
fprintf('Per-subject rho NHF: mean=%.3f p_vs0=%.4f\n',mean(rN),p_rN0);
fprintf('Per-subject rho HF:  mean=%.3f p_vs0=%.4f\n',mean(rH),p_rH0);
fprintf('NHF vs HF: p=%.4f\n',p_rNH);

save(fullfile(cfg.output_root,'cross_modality_c3_c4_corrected.mat'),'lme_c3','lme_c4','offset_scr');
fprintf('\nSaved cross_modality_c3_c4_corrected.mat\n');

function hap_col=local_find_haptic(T)
    for k={'haptic','haptic_x','haptic_y'}
        if ismember(k{1},T.Properties.VariableNames)&&islogical(T.(k{1})), hap_col=k{1}; return; end
    end
    error('No logical haptic column. Available: %s',strjoin(T.Properties.VariableNames,', '));
end