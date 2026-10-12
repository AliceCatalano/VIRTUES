%% find_tssv_outlier_subjects.m
clear; clc; cfg = config();
FV=load(fullfile(cfg.output_root,'force_vibration_features.mat'),'T'); FV=FV.T;

phase_types={'baseline','training','test'};
for pt=1:numel(phase_types)
    ptype=phase_types{pt};
    Tsub=FV(strcmp(FV.phase_type,ptype)&isfinite(FV.tssv)&FV.tssv>0,:);
    subj=unique(Tsub.subject);
    xs=nan(numel(subj),1); ihs=false(numel(subj),1);
    for si=1:numel(subj)
        s=subj{si};
        xs(si)=mean(Tsub.tssv(strcmp(Tsub.subject,s)),'omitnan');
        ihs(si)=any(Tsub.haptic(strcmp(Tsub.subject,s)));
    end
    fprintf('\n=== %s ===\n',ptype);
    for grp=[false true]
        glbl=local_ternary(grp,'HF','NHF');
        v=xs(ihs==grp&isfinite(xs));
        s_g=subj(ihs==grp&isfinite(xs));
        med=median(v); mad_v=mad(v,1);
        outliers=abs(v-med)>3*mad_v;
        if any(outliers)
            fprintf('%s outliers (>3 MAD from median=%.4f):\n',glbl,med);
            for k=find(outliers)'
                fprintf('  %-20s  mean_tssv=%.4f (%.1f MAD from median)\n',...
                    strrep(s_g{k},'subject_',''),v(k),abs(v(k)-med)/mad_v);
            end
        else
            fprintf('%s: no outliers\n',glbl);
        end
    end
end

function out=local_ternary(c,a,b), if c,out=a; else,out=b; end, end