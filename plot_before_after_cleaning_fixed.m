%% plot_before_after_cleaning_fixed.m
% Uses the ACTUAL exclusion lists from apply_outlier_exclusions_revised.m
% instead of hardcoded lists. Run AFTER apply_outlier_exclusions_revised.m
% has saved force_vibration_features_clean.mat

clear; clc; close all; cfg = config();
CN = [64 96 179]/255; CH = [139 82 168]/255;
fig_dir = fullfile(cfg.output_root,'figures','before_after');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

%% Load RAW and CLEAN tables
FV_raw = load(fullfile(cfg.output_root,'force_vibration_features.mat'),'T'); 
T_raw = FV_raw.T;
FV_cln = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); 
T_cln = FV_cln.T;

%% Derive excluded subjects DIRECTLY from comparing raw vs clean tables
% A subject is "whole-subject excluded" for TSSV if ALL their training 
% tssv values are NaN in clean but valid in raw
subj_list_all = unique(T_raw.subject);

tssv_excl_derived = {};
tssf_excl_derived = {};

for si = 1:numel(subj_list_all)
    s = subj_list_all{si};
    
    % TSSV: check training rows
    raw_tssv = T_raw.tssv(strcmp(T_raw.subject,s) & strcmp(T_raw.phase_type,'training'));
    cln_tssv = T_cln.tssv(strcmp(T_cln.subject,s) & strcmp(T_cln.phase_type,'training'));
    
    n_raw_valid = sum(isfinite(raw_tssv) & raw_tssv > 0);
    n_cln_valid = sum(isfinite(cln_tssv) & cln_tssv > 0);
    
    if n_raw_valid > 0 && n_cln_valid == 0
        tssv_excl_derived{end+1} = s;
        fprintf('TSSV whole-subject exclusion detected: %s (had %d valid, now 0)\n', ...
            strrep(s,'subject_',''), n_raw_valid);
    end
    
    % TSSF: same check
    raw_tssf = T_raw.tssf(strcmp(T_raw.subject,s) & strcmp(T_raw.phase_type,'training'));
    cln_tssf = T_cln.tssf(strcmp(T_cln.subject,s) & strcmp(T_cln.phase_type,'training'));
    
    n_raw_valid_f = sum(isfinite(raw_tssf) & raw_tssf > 0);
    n_cln_valid_f = sum(isfinite(cln_tssf) & cln_tssf > 0);
    
    if n_raw_valid_f > 0 && n_cln_valid_f == 0
        tssf_excl_derived{end+1} = s;
        fprintf('TSSF whole-subject exclusion detected: %s (had %d valid, now 0)\n', ...
            strrep(s,'subject_',''), n_raw_valid_f);
    end
end

fprintf('\nDerived TSSV exclusions (%d): %s\n', numel(tssv_excl_derived), ...
    strjoin(strrep(tssv_excl_derived,'subject_',''), ', '));
fprintf('Derived TSSF exclusions (%d): %s\n', numel(tssf_excl_derived), ...
    strjoin(strrep(tssf_excl_derived,'subject_',''), ', '));

%% Also find acquisition-level exclusions (rows that changed from valid to NaN)
fprintf('\n--- Acquisition-level exclusions ---\n');
for mi = 1:2
    oc = local_ternary(mi==1,'tssv','tssf');
    excl_subj = local_ternary(mi==1, tssv_excl_derived, tssf_excl_derived);
    
    fprintf('\n%s acquisition exclusions:\n',upper(oc));
    for si = 1:numel(subj_list_all)
        s = subj_list_all{si};
        if ismember(s, excl_subj), continue; end % already whole-subject excluded
        
        % Find rows that were valid in raw but NaN in clean
        tr_raw = T_raw(strcmp(T_raw.subject,s),:);
        tr_cln = T_cln(strcmp(T_cln.subject,s),:);
        
        for ri = 1:height(tr_raw)
            v_raw = tr_raw.(oc)(ri);
            if ~isfinite(v_raw) || v_raw <= 0, continue; end
            
            % find matching row in clean
            match = strcmp(tr_cln.phase, tr_raw.phase{ri}) & ...
                    strcmp(tr_cln.acquisition, tr_raw.acquisition{ri});
            if ~any(match), continue; end
            v_cln = tr_cln.(oc)(find(match,1));
            
            if ~isfinite(v_cln) || v_cln <= 0
                fprintf('  %s / %s / %s (log_raw=%.3f)\n', ...
                    strrep(s,'subject_',''), tr_raw.phase{ri}, tr_raw.acquisition{ri}, log(v_raw));
            end
        end
    end
end

%% FIGURE 1: Distribution before vs after — per training level
metrics = {'tssv','tssf'};
ylabels = {'log-TSSV [(m/s²)²·s]','log-TSSF [N²]'};

for mi = 1:2
    oc = metrics{mi};
    yl = ylabels{mi};
    excl_subj = local_ternary(mi==1, tssv_excl_derived, tssf_excl_derived);
    
    % Count what changed
    T_tr_raw = T_raw(strcmp(T_raw.phase_type,'training') & ...
                     isfinite(T_raw.(oc)) & T_raw.(oc)>0, :);
    T_tr_cln = T_cln(strcmp(T_cln.phase_type,'training') & ...
                     isfinite(T_cln.(oc)) & T_cln.(oc)>0, :);
    
    n_removed_total = height(T_tr_raw) - height(T_tr_cln);
    n_whole_subj = sum(ismember(T_tr_raw.subject, excl_subj));
    n_acq_level = n_removed_total - n_whole_subj;
    
    fprintf('\n%s: %d total removed (%d whole-subject, %d acquisition-level)\n', ...
        upper(oc), n_removed_total, n_whole_subj, n_acq_level);
    
    fig = figure('Position',[50 50 1800 500]);
    tl = tiledlayout(1,5,'TileSpacing','compact','Padding','compact');
    title(tl, sprintf('%s: RAW (all subjects, grey) vs CLEAN (blue=NHF, violet=HF) per training level', upper(oc)), ...
        'FontWeight','bold','FontSize',11);
    
    for lv = 1:5
        vr_N = log(T_tr_raw.(oc)(T_tr_raw.level==lv & ~T_tr_raw.haptic));
        vr_H = log(T_tr_raw.(oc)(T_tr_raw.level==lv &  T_tr_raw.haptic));
        vc_N = log(T_tr_cln.(oc)(T_tr_cln.level==lv & ~T_tr_cln.haptic));
        vc_H = log(T_tr_cln.(oc)(T_tr_cln.level==lv &  T_tr_cln.haptic));
        
        n_removed_lv = (numel(vr_N)+numel(vr_H)) - (numel(vc_N)+numel(vc_H));
        
        nexttile; hold on;
        % RAW: all as grey outline histogram
        all_raw = [vr_N; vr_H];
        all_cln = [vc_N; vc_H];
        histogram(all_raw, 30, 'FaceColor',[0.8 0.8 0.8], 'EdgeColor','none', ...
            'Normalization','probability', 'DisplayName', sprintf('RAW n=%d',numel(all_raw)));
        % CLEAN: NHF blue, HF violet
        histogram(vc_N, 25, 'FaceColor',CN, 'EdgeColor','none', 'FaceAlpha',0.7, ...
            'Normalization','probability', 'DisplayName', sprintf('CLEAN NHF n=%d',numel(vc_N)));
        histogram(vc_H, 25, 'FaceColor',CH, 'EdgeColor','none', 'FaceAlpha',0.7, ...
            'Normalization','probability', 'DisplayName', sprintf('CLEAN HF n=%d',numel(vc_H)));
        
        xlabel(yl,'FontSize',8); ylabel('Proportion','FontSize',8);
        title(sprintf('L%d\nremoved=%d trials\n(%d whole-subj excl)', ...
            lv, n_removed_lv, sum(ismember(unique(T_tr_raw.subject(T_tr_raw.level==lv)), excl_subj))), ...
            'FontSize',8);
        if lv==1, legend('FontSize',7,'Location','best'); end
        grid on;
    end
    exportgraphics(fig, fullfile(fig_dir, sprintf('%s_raw_vs_clean_derived.png',oc)), 'Resolution',150);
    fprintf('Saved %s_raw_vs_clean_derived.png\n',oc);
end

%% FIGURE 2: Show the EXCLUDED subjects' signals to justify exclusion
% What did the excluded subjects look like?
fig2 = figure('Position',[50 50 1400 600]);
tl2 = tiledlayout(2, max(numel(tssv_excl_derived), numel(tssf_excl_derived)), ...
    'TileSpacing','compact','Padding','compact');
title(tl2, 'Excluded subjects: their log-TSSV (top) and log-TSSF (bottom) trajectories across training', ...
    'FontWeight','bold','FontSize',11);

% Row 1: TSSV excluded subjects
for si = 1:numel(tssv_excl_derived)
    s = tssv_excl_derived{si};
    Ts = T_raw(strcmp(T_raw.subject,s) & strcmp(T_raw.phase_type,'training') & ...
               isfinite(T_raw.tssv) & T_raw.tssv>0, :);
    
    nexttile; hold on;
    for lv = 1:5
        Tl = Ts(Ts.level==lv,:);
        if isempty(Tl), continue; end
        plot(Tl.repetition, log(Tl.tssv), 'o-', 'Color', [lv/5 0.3 1-lv/5], ...
            'LineWidth',1.2, 'MarkerSize',4, 'DisplayName',sprintf('L%d',lv));
    end
    title(sprintf('%s\n(TSSV excluded)', strrep(s,'subject_','')),'FontSize',8);
    xlabel('Repetition'); ylabel('log-TSSV');
    ylim([-6 4]); xlim([0.5 10.5]); grid on;
    if si==1, legend('FontSize',6,'Location','best'); end
end

% Row 2: TSSF excluded subjects  
for si = 1:numel(tssf_excl_derived)
    s = tssf_excl_derived{si};
    Ts = T_raw(strcmp(T_raw.subject,s) & strcmp(T_raw.phase_type,'training') & ...
               isfinite(T_raw.tssf) & T_raw.tssf>0, :);
    
    nexttile; hold on;
    for lv = 1:5
        Tl = Ts(Ts.level==lv,:);
        if isempty(Tl), continue; end
        plot(Tl.repetition, log(Tl.tssf), 's-', 'Color', [lv/5 0.3 1-lv/5], ...
            'LineWidth',1.2, 'MarkerSize',4, 'DisplayName',sprintf('L%d',lv));
    end
    title(sprintf('%s\n(TSSF excluded)', strrep(s,'subject_','')),'FontSize',8);
    xlabel('Repetition'); ylabel('log-TSSF');
    ylim([4 20]); xlim([0.5 10.5]); grid on;
end
exportgraphics(fig2, fullfile(fig_dir,'excluded_subjects_trajectories.png'), 'Resolution',150);
fprintf('Saved excluded_subjects_trajectories.png\n');

%% FIGURE 3: Impact on group means — the key "before/after" story
fig3 = figure('Position',[50 50 1400 520]);
tl3 = tiledlayout(2, 5,'TileSpacing','compact','Padding','compact');
title(tl3, 'Impact of exclusions on group means: RAW (dashed) vs CLEAN (solid)', ...
    'FontWeight','bold','FontSize',11);

for mi = 1:2
    oc = metrics{mi};
    yl = ylabels{mi};
    
    for lv = 1:5
        nexttile; hold on;
        
        for grp = [false true]
            col = local_ternary(grp, CH, CN);
            lbl = local_ternary(grp, 'HF','NHF');
            
            % RAW group mean at this level
            T_lv_raw = T_raw(strcmp(T_raw.phase_type,'training') & T_raw.level==lv & ...
                             isfinite(T_raw.(oc)) & T_raw.(oc)>0 & T_raw.haptic==grp,:);
            subj_r = unique(T_lv_raw.subject);
            mu_r = nan(numel(subj_r),1);
            for si=1:numel(subj_r)
                v=log(T_lv_raw.(oc)(strcmp(T_lv_raw.subject,subj_r{si})));
                mu_r(si)=mean(v,'omitnan');
            end
            
            % CLEAN group mean
            T_lv_cln = T_cln(strcmp(T_cln.phase_type,'training') & T_cln.level==lv & ...
                             isfinite(T_cln.(oc)) & T_cln.(oc)>0 & T_cln.haptic==grp,:);
            subj_c = unique(T_lv_cln.subject);
            mu_c = nan(numel(subj_c),1);
            for si=1:numel(subj_c)
                v=log(T_lv_cln.(oc)(strcmp(T_lv_cln.subject,subj_c{si})));
                mu_c(si)=mean(v,'omitnan');
            end
            
            % Individual dots (clean only, small)
            scatter(ones(numel(mu_c),1)*1.5 + (rand(numel(mu_c),1)-0.5)*0.2, mu_c, ...
                12, col, 'filled','MarkerFaceAlpha',0.3,'HandleVisibility','off');
            
            % Mean ± SE — RAW (dashed)
            errorbar(local_ternary(grp,1.7,1.3), mean(mu_r,'omitnan'), ...
                std(mu_r,'omitnan')/sqrt(numel(mu_r))*1.96, 'o--', ...
                'Color',col,'MarkerFaceColor','w','LineWidth',1.5,'MarkerSize',7,...
                'DisplayName',sprintf('%s RAW n=%d',lbl,numel(mu_r)));
            
            % Mean ± SE — CLEAN (solid)
            errorbar(local_ternary(grp,1.7,1.3), mean(mu_c,'omitnan'), ...
                std(mu_c,'omitnan')/sqrt(numel(mu_c))*1.96, 'o-', ...
                'Color',col,'MarkerFaceColor',col,'LineWidth',2,'MarkerSize',8,...
                'DisplayName',sprintf('%s CLEAN n=%d',lbl,numel(mu_c)));
        end
        
        xlim([0.8 2.2]); xticks([1.3 1.7]); xticklabels({'NHF','HF'});
        ylabel(yl,'FontSize',7);
        
        if mi==1
            title(sprintf('TSSV L%d',lv),'FontSize',9);
        else
            title(sprintf('TSSF L%d',lv),'FontSize',9);
        end
        grid on; box on;
        if lv==1 && mi==1, legend('FontSize',6,'Location','best'); end
    end
end
exportgraphics(fig3, fullfile(fig_dir,'group_means_raw_vs_clean.png'), 'Resolution',150);
fprintf('Saved group_means_raw_vs_clean.png\n');

fprintf('\n=== Summary ===\n');
fprintf('Figures saved to: %s\n', fig_dir);
fprintf('\nKey for supervisor:\n');
fprintf('1. excluded_subjects_trajectories.png — what the excluded subjects looked like\n');
fprintf('2. tssv_raw_vs_clean_derived.png — distribution change after exclusion\n');
fprintf('3. tssf_raw_vs_clean_derived.png — distribution change after exclusion\n');
fprintf('4. group_means_raw_vs_clean.png — impact on group means (RAW=dashed, CLEAN=solid)\n');

function out = local_ternary(c,a,b)
    if c, out=a; else, out=b; end
end