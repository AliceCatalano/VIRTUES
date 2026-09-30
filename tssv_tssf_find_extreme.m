%% find_extreme_tssv_tssf.m
clear; clc; cfg = config();
FV = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); T=FV.T;
N=5;

for mi=1:2
    oc=local_ternary(mi==1,'tssv','tssf');
    fprintf('\n========== %s ==========\n',upper(oc));
    Tall=T(isfinite(T.(oc))&T.(oc)>0,:);
    Tall.lv=log(Tall.(oc));
    Tall=sortrows(Tall,'lv','ascend');

    fprintf('\n--- GLOBAL LOWEST %d ---\n',N);
    for ki=1:min(N,height(Tall))
        r=Tall(ki,:);
        fprintf('  %-20s %-15s %-10s rep%-3s  log=%.3f  raw=%.4e\n',...
            strrep(r.subject{1},'subject_',''),r.phase{1},r.acquisition{1},...
            local_ternary(isfinite(r.repetition),num2str(r.repetition),'--'),r.lv,r.(oc));
    end

    fprintf('\n--- GLOBAL HIGHEST %d ---\n',N);
    n=height(Tall);
    for ki=max(1,n-N+1):n
        r=Tall(ki,:);
        fprintf('  %-20s %-15s %-10s rep%-3s  log=%.3f  raw=%.4e\n',...
            strrep(r.subject{1},'subject_',''),r.phase{1},r.acquisition{1},...
            local_ternary(isfinite(r.repetition),num2str(r.repetition),'--'),r.lv,r.(oc));
    end

    fprintf('\n--- TRAINING: bottom/top %d per level ---\n',N);
    for lv=1:5
        Tl=Tall(strcmp(Tall.phase_type,'training')&Tall.level==lv,:);
        if isempty(Tl), continue; end
        fprintf('\n  L%d (n=%d):\n',lv,height(Tl));
        fprintf('  LOW:  ');
        for ki=1:min(N,height(Tl))
            r=Tl(ki,:);
            fprintf('%s/rep%s(%.2f)  ',strrep(r.subject{1},'subject_',''),num2str(r.repetition),r.lv);
        end
        fprintf('\n  HIGH: ');
        for ki=max(1,height(Tl)-N+1):height(Tl)
            r=Tl(ki,:);
            fprintf('%s/rep%s(%.2f)  ',strrep(r.subject{1},'subject_',''),num2str(r.repetition),r.lv);
        end
        fprintf('\n');
    end

    fprintf('\n--- BASELINE: bottom/top 3 per phase/level ---\n');
    for bi=1:2
        bl=sprintf('Baseline%d',bi);
        for lv=1:5
            Tl=Tall(strcmp(Tall.phase,bl)&Tall.level==lv,:);
            if height(Tl)<2, continue; end
            fprintf('  %s L%d: LOW=%s(%.2f)  HIGH=%s(%.2f)\n',bl,lv,...
                strrep(Tl.subject{1},'subject_',''),Tl.lv(1),...
                strrep(Tl.subject{end},'subject_',''),Tl.lv(end));
        end
    end

    fprintf('\n--- PER-SUBJECT min/max ---\n');
    for s=unique(Tall.subject)'
        v=Tall.lv(strcmp(Tall.subject,s{1}));
        fprintf('  %-20s  min=%.3f(%.3e)  max=%.3f(%.3e)\n',...
            strrep(s{1},'subject_',''),min(v),exp(min(v)),max(v),exp(max(v)));
    end
end
%%
%% what_was_removed_and_why.m
clear; clc; cfg = config();
FV_raw   = load(fullfile(cfg.output_root,'force_vibration_features.mat'),'T'); Traw=FV_raw.T;
FV_clean = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); Tclean=FV_clean.T;

excl_tssv = {'subject_s09N','subject_s10H','subject_s11N','subject_s12H','subject_s23H','subject_s44N'};
excl_tssf = {'subject_s03H','subject_s04H'};

for mi=1:2
    oc=local_ternary(mi==1,'tssv','tssf');
    excl=local_ternary(mi==1,excl_tssv,excl_tssf);
    fprintf('\n========== %s removed reps ==========\n',upper(oc));

    % was valid in raw but NaN in clean = removed by outlier process
    was_valid = isfinite(Traw.(oc)) & Traw.(oc)>0;
    now_nan   = ~isfinite(Tclean.(oc)) | Tclean.(oc)<=0;
    removed   = was_valid & now_nan;

    for si=1:height(Traw)
        if ~removed(si), continue; end
        r=Traw(si,:);
        log_val=log(r.(oc));

        % determine reason
        if ismember(r.subject{1},excl)
            reason='WHOLE-SUBJECT exclusion';
        else
            % recompute level-specific bounds on raw data (excluding whole-subj)
            Tref=Traw(~ismember(Traw.subject,excl)&isfinite(Traw.(oc))&Traw.(oc)>0,:);
            if strcmp(r.phase_type{1},'training')
                Tref=Tref(Tref.level==r.level,:);
            elseif strcmp(r.phase_type{1},'baseline')
                Tref=Tref(strcmp(Tref.phase_type,'baseline')&Tref.level==r.level,:);
            else
                Tref=Tref(strcmp(Tref.phase_type,'test'),:);
            end
            lv=log(Tref.(oc));
            p1=quantile(lv,0.01); p99=quantile(lv,0.99);
            if log_val<p1
                reason=sprintf('p1 bound (%.3f < p1=%.3f)',log_val,p1);
            elseif log_val>p99
                reason=sprintf('p99 bound (%.3f > p99=%.3f)',log_val,p99);
            else
                reason='unknown';
            end
        end

        fprintf('  %-20s  %-15s  %-8s  rep%-3s  log=%.3f  raw=%.3e  --> %s\n',...
            strrep(r.subject{1},'subject_',''),r.phase{1},r.acquisition{1},...
            local_ternary(isfinite(r.repetition),num2str(r.repetition),'--'),...
            log_val,r.(oc),reason);
    end
end

function out=local_ternary(c,a,b), if c,out=a; else,out=b; end, end