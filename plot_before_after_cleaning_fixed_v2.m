%% plot_before_after_cleaning_fixed_v2.m
% Correctly detects exclusions by finding NaN values in clean vs valid in raw

clear; clc; close all; cfg = config();
CN = [64 96 179]/255; CH = [139 82 168]/255;
fig_dir = fullfile(cfg.output_root,'figures','before_after');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

%% Load RAW and CLEAN tables
FV_raw = load(fullfile(cfg.output_root,'force_vibration_features.mat'),'T');
T_raw = FV_raw.T;
FV_cln = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T');
T_cln = FV_cln.T;

fprintf('RAW table: %d rows\n', height(T_raw));
fprintf('CLEAN table: %d rows\n', height(T_cln));
fprintf('Same number of rows: %s\n', mat2str(height(T_raw)==height(T_cln)));

%% Verify that exclusions set values to NaN (not remove rows)
% The tables should have SAME rows, but clean has NaN where raw has values
if height(T_raw) == height(T_cln)
    tssv_was_valid = isfinite(T_raw.tssv) & T_raw.tssv > 0;
    tssv_now_nan   = ~isfinite(T_cln.tssv) | T_cln.tssv <= 0;
    tssf_was_valid = isfinite(T_raw.tssf) & T_raw.tssf > 0;
    tssf_now_nan   = ~isfinite(T_cln.tssf) | T_cln.tssf <= 0;
    
    tssv_excluded_rows = tssv_was_valid & tssv_now_nan;
    tssf_excluded_rows = tssf_was_valid & tssf_now_nan;
    
    fprintf('\nTSSV: %d rows changed from valid to NaN\n', sum(tssv_excluded_rows));
    fprintf('TSSF: %d rows changed from valid to NaN\n', sum(tssf_excluded_rows));
else
    error('Tables have different row counts — exclusions removed rows instead of NaN-ing. Check apply_outlier_exclusions_revised.m');
end

%% Identify whole-subject vs acquisition-level exclusions
subj_list = unique(T_raw.subject);

tssv_whole_subj = {};
tssf_whole_subj = {};

fprintf('\n=== TSSV exclusion breakdown ===\n');
for si = 1:numel(subj_list)
    s = subj_list{si};
    mask_s = strcmp(T_raw.subject, s);
    
    % How many training rows were valid in raw and now NaN in clean?
    tr_mask = mask_s & strcmp(T_raw.phase_type,'training');
    n_raw_valid = sum(isfinite(T_raw.tssv(tr_mask)) & T_raw.tssv(tr_mask)>0);
    n_cln_valid = sum(isfinite(T_cln.tssv(tr_mask)) & T_cln.tssv(tr_mask)>0);
    n_excluded = n_raw_valid - n_cln_valid;
    
    if n_excluded == 0, continue; end
    
    if n_cln_valid == 0 && n_raw_valid > 0
        % All training rows excluded = whole-subject exclusion
        tssv_whole_subj{end+1} = s;
        fprintf('  WHOLE SUBJECT: %s (%d training trials all NaN''d)\n', ...
            strrep(s,'subject_',''), n_raw_valid);
    else
        % Some rows excluded = acquisition-level exclusion
        fprintf('  PARTIAL: %s (%d/%d training trials excluded)\n', ...
            strrep(s,'subject_',''), n_excluded, n_raw_valid);
        
        % List specific excluded acquisitions
        excl_rows = strcmp(T_raw.subject,s) & tssv_excluded_rows;
        T_excl = T_raw(excl_rows,:);
        for ri = 1:height(T_excl)
            fprintf('    %s / %s / %s (log_raw=%.3f)\n', ...
                T_excl.phase{ri}, T_excl.acquisition{ri}, ...
                T_excl.phase_type{ri}, log(T_excl.tssv(ri)));
        end
    end
end

fprintf('\n=== TSSF exclusion breakdown ===\n');
for si = 1:numel(subj_list)
    s = subj_list{si};
    mask_s = strcmp(T_raw.subject, s);
    
    tr_mask = mask_s & strcmp(T_raw.phase_type,'training');
    n_raw_valid = sum(isfinite(T_raw.tssf(tr_mask)) & T_raw.tssf(tr_mask)>0);
    n_cln_valid = sum(isfinite(T_cln.tssf(tr_mask)) & T_cln.tssf(tr_mask)>0);
    n_excluded = n_raw_valid - n_cln_valid;
    
    if n_excluded == 0, continue; end
    
    if n_cln_valid == 0 && n_raw_valid > 0
        tssf_whole_subj{end+1} = s;
        fprintf('  WHOLE SUBJECT: %s (%d training trials all NaN''d)\n', ...
            strrep(s,'subject_',''), n_raw_valid);
    else
        fprintf('  PARTIAL: %s (%d/%d training trials excluded)\n', ...
            strrep(s,'subject_',''), n_excluded, n_raw_valid);
        
        excl_rows = strcmp(T_raw.subject,s) & tssf_excluded_rows;
        T_excl = T_raw(excl_rows,:);
        for ri = 1:height(T_excl)
            fprintf('    %s / %s / %s (log_raw=%.3f)\n', ...
                T_excl.phase{ri}, T_excl.acquisition{ri}, ...
                T_excl.phase_type{ri}, log(T_excl.tssf(ri)));
        end
    end
end

fprintf('\nTSSV whole-subject exclusions (%d): %s\n', numel(tssv_whole_subj), ...
    strjoin(strrep(tssv_whole_subj,'subject_',''), ', '));
fprintf('TSSF whole-subject exclusions (%d): %s\n', numel(tssf_whole_subj), ...
    strjoin(strrep(tssf_whole_subj,'subject_',''), ', '));

%% FIGURE 1: Distribution histograms per level — RAW vs CLEAN
metrics  = {'tssv','tssf'};
ylabels  = {'log-TSSV [(m/s²)²·s]','log-TSSF [N²]'};
excl_all = {tssv_excluded_rows, tssf_excluded_rows};

for mi = 1:2
    oc = metrics{mi};
    yl = ylabels{mi};
    excl_rows = excl_all{mi};
    
    % Training rows only
    tr_raw = strcmp(T_raw.phase_type,'training') & isfinite(T_raw.(oc)) & T_raw.(oc)>0;
    tr_cln = strcmp(T_cln.phase_type,'training') & isfinite(T_cln.(oc)) & T_cln.(oc)>0;
    
    n_raw = sum(tr_raw);
    n_cln = sum(tr_cln);
    n_removed = n_raw - n_cln;
    
    fig = figure('Position',[50 50 1800 500]);
    tl = tiledlayout(1,5,'TileSpacing','compact','Padding','compact');
    title(tl, sprintf('%s: RAW (grey) vs CLEAN per training level  |  Total removed: %d trials', ...
        upper(oc), n_removed), 'FontWeight','bold','FontSize',11);
    
    for lv = 1:5
        lv_raw = tr_raw & T_raw.level==lv;
        lv_cln = tr_cln & T_cln.level==lv;
        lv_excl = excl_rows & strcmp(T_raw.phase_type,'training') & T_raw.level==lv;
        
        v_raw_N = log(T_raw.(oc)(lv_raw & ~T_raw.haptic));
        v_raw_H = log(T_raw.(oc)(lv_raw &  T_raw.haptic));
        v_cln_N = log(T_cln.(oc)(lv_cln & ~T_cln.haptic));
        v_cln_H = log(T_cln.(oc)(lv_cln &  T_cln.haptic));
        v_excl   = log(T_raw.(oc)(lv_excl));  % the removed values
        
        n_excl_lv = sum(lv_excl);
        
        nexttile; hold on;
        
        % RAW: both groups together as grey background
        all_raw = [v_raw_N; v_raw_H];
        if ~isempty(all_raw)
            histogram(all_raw, 30, 'FaceColor',[0.85 0.85 0.85], 'EdgeColor','none', ...
                'Normalization','probability', 'DisplayName', sprintf('RAW n=%d',numel(all_raw)));
        end
        
        % CLEAN: NHF blue, HF violet
        if ~isempty(v_cln_N)
            histogram(v_cln_N, 25, 'FaceColor',CN, 'EdgeColor','none', 'FaceAlpha',0.7, ...
                'Normalization','probability', 'DisplayName', sprintf('Clean NHF n=%d',numel(v_cln_N)));
        end
        if ~isempty(v_cln_H)
            histogram(v_cln_H, 25, 'FaceColor',CH, 'EdgeColor','none', 'FaceAlpha',0.7, ...
                'Normalization','probability', 'DisplayName', sprintf('Clean HF n=%d',numel(v_cln_H)));
        end
        
        % Mark excluded values with red vertical lines
        for ei = 1:numel(v_excl)
            xline(v_excl(ei), 'r-', 'LineWidth', 2, 'HandleVisibility','off');
        end
        if n_excl_lv > 0
            plot(nan, nan, 'r-', 'LineWidth',2, 'DisplayName', sprintf('Excluded n=%d',n_excl_lv));
        end
        
        xlabel(yl,'FontSize',7); ylabel('Proportion','FontSize',7);
        title(sprintf('L%d  (removed=%d)',lv,n_excl_lv),'FontSize',9);
        legend('FontSize',6,'Location','best');
        grid on;
    end
    
    exportgraphics(fig, fullfile(fig_dir,sprintf('%s_raw_vs_clean.png',oc)),'Resolution',150);
    fprintf('Saved %s_raw_vs_clean.png\n',oc);
    close(fig);
end

%% FIGURE 2: Show excluded subjects' FULL trajectories
% Only plot if there are actual exclusions
has_tssv_excl = numel(tssv_whole_subj) > 0 || sum(tssv_excluded_rows & strcmp(T_raw.phase_type,'training')) > 0;
has_tssf_excl = numel(tssf_whole_subj) > 0 || sum(tssf_excluded_rows & strcmp(T_raw.phase_type,'training')) > 0;

if has_tssv_excl || has_tssf_excl
    % Get all subjects with ANY exclusion
    tssv_partial_subj = unique(T_raw.subject(tssv_excluded_rows & strcmp(T_raw.phase_type,'training')));
    tssf_partial_subj = unique(T_raw.subject(tssf_excluded_rows & strcmp(T_raw.phase_type,'training')));
    
    all_excl_subj_tssv = unique([tssv_whole_subj(:); tssv_partial_subj(:)]);
    all_excl_subj_tssf = unique([tssf_whole_subj(:); tssf_partial_subj(:)]);
    
    for mi = 1:2
        oc = metrics{mi};
        yl = ylabels{mi};
        excl_rows_mi = excl_all{mi};
        excl_subj_mi = local_ternary(mi==1, all_excl_subj_tssv, all_excl_subj_tssf);
        whole_subj_mi = local_ternary(mi==1, tssv_whole_subj, tssf_whole_subj);
        
        if isempty(excl_subj_mi), continue; end
        
        n_excl_s = numel(excl_subj_mi);
        fig = figure('Position',[50 50 min(400*n_excl_s,1800) 550]);
        tl = tiledlayout(1, n_excl_s, 'TileSpacing','compact','Padding','compact');
        title(tl, sprintf('%s — Excluded subjects (red=excluded trials, blue=kept)', upper(oc)), ...
            'FontWeight','bold','FontSize',11);
        
        for si = 1:n_excl_s
            s = excl_subj_mi{si};
            is_whole = ismember(s, whole_subj_mi);
            
            Ts_raw = T_raw(strcmp(T_raw.subject,s) & strcmp(T_raw.phase_type,'training'),:);
            Ts_cln = T_cln(strcmp(T_cln.subject,s) & strcmp(T_cln.phase_type,'training'),:);
            
            nexttile; hold on;
            
            for lv = 1:5
                Tl_raw = Ts_raw(Ts_raw.level==lv,:);
                Tl_cln = Ts_cln(Ts_cln.level==lv & isfinite(Ts_cln.(oc)) & Ts_cln.(oc)>0,:);
                
                % Plot ALL raw values first
                v_all = Tl_raw.(oc);
                v_all = v_all(isfinite(v_all) & v_all>0);
                reps_all = Tl_raw.repetition(isfinite(Tl_raw.(oc)) & Tl_raw.(oc)>0);
                
                if ~isempty(v_all)
                    plot(reps_all, log(v_all), 'o--', ...
                        'Color',[0.6 0.6 0.6], 'LineWidth',0.8, 'MarkerSize',4, ...
                        'HandleVisibility','off');
                end
                
                % Highlight KEPT (clean) values in level color
                if ~isempty(Tl_cln) && any(isfinite(Tl_cln.(oc)) & Tl_cln.(oc)>0)
                    v_kept = log(Tl_cln.(oc)(isfinite(Tl_cln.(oc)) & Tl_cln.(oc)>0));
                    r_kept = Tl_cln.repetition(isfinite(Tl_cln.(oc)) & Tl_cln.(oc)>0);
                    col_lv = [0 lv/6 1-lv/6];
                    plot(r_kept, v_kept, 'o-', 'Color',col_lv, 'LineWidth',1.5, ...
                        'MarkerFaceColor',col_lv, 'MarkerSize',5, ...
                        'DisplayName', sprintf('L%d kept',lv));
                end
                
                % Highlight EXCLUDED values in red
                excl_mask = strcmp(T_raw.subject,s) & T_raw.level==lv & ...
                           excl_rows_mi & strcmp(T_raw.phase_type,'training');
                if any(excl_mask)
                    v_excl = log(T_raw.(oc)(excl_mask));
                    r_excl = T_raw.repetition(excl_mask);
                    scatter(r_excl, v_excl, 80, 'rx', 'LineWidth',2.5, ...
                        'HandleVisibility', local_ternary(lv==1,'on','off'), ...
                        'DisplayName','EXCLUDED');
                end
            end
            
            excl_label = local_ternary(is_whole,'WHOLE SUBJECT','PARTIAL');
            title(sprintf('%s\n(%s excl.)',strrep(s,'subject_',''),excl_label),'FontSize',8);
            xlabel('Repetition'); ylabel(yl,'FontSize',7);
            xlim([0.5 10.5]); set(gca,'XTick',1:10,'FontSize',7);
            legend('FontSize',6,'Location','best');
            grid on; box on;
        end
        
        exportgraphics(fig, fullfile(fig_dir,sprintf('%s_excluded_subjects.png',oc)),'Resolution',150);
        fprintf('Saved %s_excluded_subjects.png\n',oc);
        close(fig);
    end
end

%% FIGURE 3: Group means comparison — what changed
fig3 = figure('Position',[50 50 1400 520]);
tl3 = tiledlayout(2,5,'TileSpacing','compact','Padding','compact');
title(tl3,'Impact of exclusions on group-level means: RAW (dashed) vs CLEAN (solid)', ...
    'FontWeight','bold','FontSize',11);

for mi = 1:2
    oc = metrics{mi};
    yl = ylabels{mi};
    
    for lv = 1:5
        nexttile; hold on;
        
        for grp = [false true]
            col = local_ternary(grp, CH, CN);
            lbl = local_ternary(grp, 'HF','NHF');
            
            % RAW: subject-level means
            T_lv_raw = T_raw(strcmp(T_raw.phase_type,'training') & T_raw.level==lv & ...
                             isfinite(T_raw.(oc)) & T_raw.(oc)>0 & T_raw.haptic==grp,:);
            subj_r = unique(T_lv_raw.subject);
            mu_r = nan(numel(subj_r),1);
            for si=1:numel(subj_r)
                v = log(T_lv_raw.(oc)(strcmp(T_lv_raw.subject,subj_r{si})));
                mu_r(si) = mean(v,'omitnan');
            end
            
            % CLEAN: subject-level means
            T_lv_cln = T_cln(strcmp(T_cln.phase_type,'training') & T_cln.level==lv & ...
                             isfinite(T_cln.(oc)) & T_cln.(oc)>0 & T_cln.haptic==grp,:);
            subj_c = unique(T_lv_cln.subject);
            mu_c = nan(numel(subj_c),1);
            for si=1:numel(subj_c)
                v = log(T_lv_cln.(oc)(strcmp(T_lv_cln.subject,subj_c{si})));
                mu_c(si) = mean(v,'omitnan');
            end
            
            % Individual dots (clean)
            jx = local_ternary(grp, 2.1, 0.9);
            scatter(jx + (rand(numel(mu_c),1)-0.5)*0.15, mu_c, ...
                14, col, 'filled','MarkerFaceAlpha',0.4,'HandleVisibility','off');
            
            xpos_raw   = local_ternary(grp, 2.1, 0.9);
            xpos_clean = local_ternary(grp, 1.9, 1.1);
            
            % RAW mean (dashed marker)
            if ~isempty(mu_r)
                errorbar(xpos_raw, mean(mu_r,'omitnan'), ...
                    std(mu_r,'omitnan')/sqrt(numel(mu_r))*1.96, ...
                    'd--', 'Color',col*0.6, 'MarkerFaceColor','w', ...
                    'LineWidth',1.5,'MarkerSize',8, ...
                    'DisplayName',sprintf('%s RAW (n=%d)',lbl,numel(mu_r)));
            end
            
            % CLEAN mean (solid marker)
            if ~isempty(mu_c)
                errorbar(xpos_clean, mean(mu_c,'omitnan'), ...
                    std(mu_c,'omitnan')/sqrt(numel(mu_c))*1.96, ...
                    'o-', 'Color',col, 'MarkerFaceColor',col, ...
                    'LineWidth',2,'MarkerSize',9, ...
                    'DisplayName',sprintf('%s CLEAN (n=%d)',lbl,numel(mu_c)));
            end
        end
        
        xlim([0.5 2.5]); xticks([0.9 1.1 1.9 2.1]);
        xticklabels({'NHF','NHF','HF','HF'});
        ylabel(yl,'FontSize',7);
        
        if mi==1
            title(sprintf('TSSV L%d',lv),'FontSize',9);
        else
            title(sprintf('TSSF L%d',lv),'FontSize',9);
        end
        grid on; box on;
        if lv==1, legend('FontSize',6,'Location','best'); end
    end
end
exportgraphics(fig3, fullfile(fig_dir,'group_means_raw_vs_clean.png'),'Resolution',150);
fprintf('Saved group_means_raw_vs_clean.png\n');
close(fig3);

%% FIGURE 4: Across-phase summary — both groups, raw vs clean
fig4 = figure('Position',[50 50 1200 500]);
tl4 = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
title(tl4,'Exclusion impact: group mean trajectories across all phases (RAW=dashed, CLEAN=solid)', ...
    'FontWeight','bold','FontSize',11);

phases_ord = {'Baseline1','Training_L1','Training_L2','Training_L3','Training_L4','Training_L5','Baseline2','Test1','Test2'};
xlabels_p  = {'BL1','L1','L2','L3','L4','L5','BL2','T1','T2'};
n_ph = numel(phases_ord);

for mi = 1:2
    oc = metrics{mi};
    yl = ylabels{mi};
    
    nexttile; hold on;
    
    for grp = [false true]
        col = local_ternary(grp, CH, CN);
        lbl = local_ternary(grp, 'HF','NHF');
        
        mu_raw   = nan(1,n_ph);
        mu_clean = nan(1,n_ph);
        se_clean = nan(1,n_ph);
        
        for k = 1:n_ph
            ph = phases_ord{k};
            
            % Get right subset
            if startsWith(ph,'Training')
                lv = str2double(ph(end));
                mask_raw = strcmp(T_raw.phase_type,'training') & T_raw.level==lv & ...
                           T_raw.haptic==grp & isfinite(T_raw.(oc)) & T_raw.(oc)>0;
                mask_cln = strcmp(T_cln.phase_type,'training') & T_cln.level==lv & ...
                           T_cln.haptic==grp & isfinite(T_cln.(oc)) & T_cln.(oc)>0;
            else
                mask_raw = strcmp(T_raw.phase,ph) & T_raw.haptic==grp & ...
                           isfinite(T_raw.(oc)) & T_raw.(oc)>0;
                mask_cln = strcmp(T_cln.phase,ph) & T_cln.haptic==grp & ...
                           isfinite(T_cln.(oc)) & T_cln.(oc)>0;
            end
            
            % Subject means
            subj_r = unique(T_raw.subject(mask_raw));
            xs_r = nan(numel(subj_r),1);
            for si=1:numel(subj_r)
                v=log(T_raw.(oc)(mask_raw & strcmp(T_raw.subject,subj_r{si})));
                xs_r(si)=mean(v,'omitnan');
            end
            
            subj_c = unique(T_cln.subject(mask_cln));
            xs_c = nan(numel(subj_c),1);
            for si=1:numel(subj_c)
                v=log(T_cln.(oc)(mask_cln & strcmp(T_cln.subject,subj_c{si})));
                xs_c(si)=mean(v,'omitnan');
            end
            
            mu_raw(k)   = mean(xs_r,'omitnan');
            mu_clean(k) = mean(xs_c,'omitnan');
            se_clean(k) = std(xs_c,'omitnan')/sqrt(sum(isfinite(xs_c)));
        end
        
        % RAW: dashed line, no CI
        plot(1:n_ph, mu_raw, '--', 'Color',col*0.5, 'LineWidth',1.2, ...
            'DisplayName',sprintf('%s RAW',lbl));
        
        % CLEAN: solid with CI
        fill([1:n_ph fliplr(1:n_ph)], ...
             [mu_clean+1.96*se_clean fliplr(mu_clean-1.96*se_clean)], ...
             col,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
        plot(1:n_ph, mu_clean, 'o-', 'Color',col,'LineWidth',2, ...
            'MarkerFaceColor',col,'MarkerSize',6, ...
            'DisplayName',sprintf('%s CLEAN',lbl));
    end
    
    set(gca,'XTick',1:n_ph,'XTickLabel',xlabels_p,'FontSize',9);
    xline(1.5,'k:','LineWidth',1,'HandleVisibility','off');
    xline(6.5,'k:','LineWidth',1,'HandleVisibility','off');
    ylabel(yl,'FontSize',10); xlabel('Phase','FontSize',10);
    title(upper(oc),'FontSize',11);
    legend('Location','best','FontSize',8);
    grid on; box on;
end
exportgraphics(fig4, fullfile(fig_dir,'raw_vs_clean_all_phases.png'),'Resolution',150);
fprintf('Saved raw_vs_clean_all_phases.png\n');
close(fig4);

fprintf('\n=== All figures saved to: %s ===\n', fig_dir);
fprintf('\nFigures for supervisor presentation:\n');
fprintf('1. tssv_raw_vs_clean.png — distribution change per level\n');
fprintf('2. tssf_raw_vs_clean.png — distribution change per level\n');
fprintf('3. tssv_excluded_subjects.png — what excluded subjects looked like\n');
fprintf('4. tssf_excluded_subjects.png — what excluded subjects looked like\n');
fprintf('5. group_means_raw_vs_clean.png — impact on group means per level\n');
fprintf('6. raw_vs_clean_all_phases.png — impact across all phases\n');

function out = local_ternary(c,a,b)
    if c, out=a; else, out=b; end
end