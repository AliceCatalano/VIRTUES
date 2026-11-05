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
%% tssf_tssv_range_without_excluded.m
clear; clc; cfg = config();
FV = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); T=FV.T;

excl_tssv = {'subject_s09N','subject_s10H','subject_s11N','subject_s12H','subject_s23H','subject_s44N','subject_s48N'};
excl_tssf = {'subject_s03H','subject_s04H'};

fprintf('=== TSSV range (non-excluded subjects only, after cleaning) ===\n');
Tv = T(isfinite(T.tssv)&T.tssv>0&~ismember(T.subject,excl_tssv),:);
Tv = sortrows(Tv, 'tssv', 'ascend');
fprintf('n valid rows: %d\n', height(Tv));
fprintf('MIN: %s / %s / %s / rep%d  log=%.3f  raw=%.4f (m/s²)²s\n',...
    strrep(Tv.subject{1},'subject_',''), Tv.phase{1}, Tv.acquisition{1}, ...
    Tv.repetition(1), log(Tv.tssv(1)), Tv.tssv(1));
fprintf('MAX: %s / %s / %s / rep%d  log=%.3f  raw=%.4f (m/s²)²s\n',...
    strrep(Tv.subject{end},'subject_',''), Tv.phase{end}, Tv.acquisition{end}, ...
    Tv.repetition(end), log(Tv.tssv(end)), Tv.tssv(end));
fprintf('Ratio max/min: %.1f×\n', Tv.tssv(end)/Tv.tssv(1));
fprintf('Log difference: %.2f\n\n', log(Tv.tssv(end)) - log(Tv.tssv(1)));

fprintf('=== TSSF range (non-excluded subjects only, after cleaning) ===\n');
Tf = T(isfinite(T.tssf)&T.tssf>0&~ismember(T.subject,excl_tssf),:);
Tf = sortrows(Tf, 'tssf', 'ascend');
fprintf('n valid rows: %d\n', height(Tf));
fprintf('MIN: %s / %s / %s / rep%d  log=%.3f  raw=%.2f N²\n',...
    strrep(Tf.subject{1},'subject_',''), Tf.phase{1}, Tf.acquisition{1}, ...
    Tf.repetition(1), log(Tf.tssf(1)), Tf.tssf(1));
fprintf('MAX: %s / %s / %s / rep%d  log=%.3f  raw=%.2f N²\n',...
    strrep(Tf.subject{end},'subject_',''), Tf.phase{end}, Tf.acquisition{end}, ...
    Tf.repetition(end), log(Tf.tssf(end)), Tf.tssf(end));
fprintf('Ratio max/min: %.1f×\n', Tf.tssf(end)/Tf.tssf(1));
fprintf('Log difference: %.2f\n\n', log(Tf.tssf(end)) - log(Tf.tssf(1)));

% Plot distributions side by side
fig = figure('Position',[50 50 1400 500]);
tl = tiledlayout(1,2,'TileSpacing','compact');

nexttile; hold on;
histogram(log(Tv.tssv(~Tv.haptic)), 40, 'FaceColor',[64 96 179]/255, ...
    'EdgeColor','none','FaceAlpha',0.6,'Normalization','probability','DisplayName','NHF');
histogram(log(Tv.tssv( Tv.haptic)), 40, 'FaceColor',[139 82 168]/255, ...
    'EdgeColor','none','FaceAlpha',0.6,'Normalization','probability','DisplayName','HF');
xlabel('log(TSSV) [(m/s²)²·s]'); ylabel('Proportion');
title(sprintf('TSSV distribution (non-excluded subjects)\nRange: %.2f log-units = %.0f× ratio',...
    log(Tv.tssv(end))-log(Tv.tssv(1)), Tv.tssv(end)/Tv.tssv(1)));
legend('FontSize',9); grid on;

nexttile; hold on;
histogram(log(Tf.tssf(~Tf.haptic)), 40, 'FaceColor',[64 96 179]/255, ...
    'EdgeColor','none','FaceAlpha',0.6,'Normalization','probability','DisplayName','NHF');
histogram(log(Tf.tssf( Tf.haptic)), 40, 'FaceColor',[139 82 168]/255, ...
    'EdgeColor','none','FaceAlpha',0.6,'Normalization','probability','DisplayName','HF');
xlabel('log(TSSF) [N²]'); ylabel('Proportion');
title(sprintf('TSSF distribution (non-excluded subjects)\nRange: %.2f log-units = %.0f× ratio',...
    log(Tf.tssf(end))-log(Tf.tssf(1)), Tf.tssf(end)/Tf.tssf(1)));
legend('FontSize',9); grid on;

sgtitle('TSSV and TSSF value ranges after cleaning (whole-subject exclusions removed)', ...
    'FontWeight','bold','FontSize',11);
exportgraphics(fig, fullfile(cfg.output_root,'figures','tssf_tssv_range_clean.png'), 'Resolution',150);
fprintf('Saved tssf_tssv_range_clean.png\n');
function out=local_ternary(c,a,b), if c,out=a; else,out=b; end, end