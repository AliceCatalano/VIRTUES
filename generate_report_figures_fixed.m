%% generate_report_figures_fixed.m
% Runs only the sections that work, skips broken ones cleanly

clear; clc; close all;
cfg = config();
fig_dir = fullfile(cfg.output_root,'figures');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end
CN = [64 96 179]/255; CH = [139 82 168]/255;

fprintf('=== Generating report figures (fixed version) ===\n\n');

%% SECTION 1: Outlier story — USE THE FIXED SCRIPT
fprintf('--- Section 1: Outlier story ---\n');
try
    run('plot_before_after_cleaning_fixed.m');
    fprintf('Outlier story done.\n');
catch ME
    fprintf('SKIP: %s\n', ME.message);
end

%% SECTION 2: EDA summary
fprintf('\n--- Section 2: EDA figures ---\n');
try
    T_eda = load(fullfile(cfg.output_root,'eda_features_v2.mat'),'T'); 
    T_eda = T_eda.T;
    local_plot_eda_summary(T_eda, CN, CH, fig_dir);
    fprintf('EDA summary done.\n');
catch ME
    fprintf('SKIP EDA: %s\n', ME.message);
end

%% SECTION 3: Eye tracking
fprintf('\n--- Section 3: Eye tracking ---\n');
try
    T_eye = load(fullfile(cfg.output_root,'eye_features_v2.mat'),'T'); 
    T_eye = T_eye.T;
    local_plot_eye_summary(T_eye, CN, CH, fig_dir);
    fprintf('Eye tracking done.\n');
catch ME
    fprintf('SKIP eye: %s\n', ME.message);
end

%% SECTION 4: TSSV/TSSF
fprintf('\n--- Section 4: TSSV/TSSF ---\n');
try
    FV = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); 
    FV = FV.T;
    CI = load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact'); 
    CI = CI.T_impact;
    local_plot_tss_summary(FV, CI, CN, CH, fig_dir);
    fprintf('TSSV/TSSF done.\n');
catch ME
    fprintf('SKIP TSSV/TSSF: %s\n', ME.message);
end

%% SECTION 5: LMM figures
fprintf('\n--- Section 5: LMM figures ---\n');
try
    lmm_tssv_tssf_analysis(cfg);
    fprintf('LMM done.\n');
catch ME
    fprintf('SKIP LMM: %s\n', ME.message);
end

%% SECTION 6: Cross-modality
fprintf('\n--- Section 6: Cross-modality ---\n');
try
    cross_modality_tssv_tssf_eda_pupil(cfg);
    fprintf('Cross-modality done.\n');
catch ME
    fprintf('SKIP cross-modal: %s\n', ME.message);
end

%% SECTION 7: Performance
fprintf('\n--- Section 7: Performance ---\n');
try
    T_perf = load(fullfile(cfg.output_root,'perf_features.mat'),'T'); 
    T_perf = T_perf.T;
    local_plot_perf_summary(T_perf, CN, CH, fig_dir);
    fprintf('Performance done.\n');
catch ME
    fprintf('SKIP performance: %s\n', ME.message);
end

%% SECTION 8: Learning curves (existing functions, fixed)
fprintf('\n--- Section 8: Learning curves ---\n');
try
    plot_learning_curves(cfg);
    fprintf('Learning curves (EDA+perf) done.\n');
catch ME
    fprintf('SKIP learning curves: %s\n', ME.message);
end

try
    plot_level_divergence(cfg);
    fprintf('Level divergence done.\n');
catch ME
    fprintf('SKIP level divergence: %s\n', ME.message);
end

try
    plot_transfer_curves(cfg);
    fprintf('Transfer curves done.\n');
catch ME
    fprintf('SKIP transfer curves: %s\n', ME.message);
end

fprintf('\n=== Done. Figures in: %s ===\n', fig_dir);

%% ---- LOCAL PLOT FUNCTIONS ----

function local_plot_eda_summary(T, CN, CH, fig_dir)
    % H1: SCL across phases — simplified version that actually works
    phases_ord = {'Baseline1','Test1','Training_L1','Training_L2','Training_L3','Training_L4','Training_L5','Baseline2','Test2'};
    xlabels = {'BL1','T1','L1','L2','L3','L4','L5','BL2','T2'};
    n_ph = numel(phases_ord);
    
    mu_N = nan(1,n_ph); mu_H = nan(1,n_ph);
    se_N = nan(1,n_ph); se_H = nan(1,n_ph);
    
    for k = 1:n_ph
        ph = phases_ord{k};
        if startsWith(ph,'Training')
            lv = str2double(ph(end));
            Tsub = T(strcmp(T.phase_type,'training') & T.level==lv & isfinite(T.scl_mean_bc),:);
        else
            Tsub = T(strcmp(T.phase,ph) & isfinite(T.scl_mean_bc),:);
        end
        if isempty(Tsub), continue; end
        
        subj = unique(Tsub.subject);
        xa = nan(numel(subj),1); ih = false(numel(subj),1);
        for si=1:numel(subj)
            s=subj{si};
            xa(si) = mean(Tsub.scl_mean_bc(strcmp(Tsub.subject,s)),'omitnan');
            ih(si) = any(Tsub.haptic(strcmp(Tsub.subject,s)));
        end
        xN = xa(~ih & isfinite(xa)); xH = xa(ih & isfinite(xa));
        mu_N(k) = mean(xN,'omitnan'); mu_H(k) = mean(xH,'omitnan');
        se_N(k) = std(xN,'omitnan')/sqrt(numel(xN));
        se_H(k) = std(xH,'omitnan')/sqrt(numel(xH));
    end
    
    fig = figure('Position',[50 50 1100 420]); hold on;
    x = 1:n_ph;
    fill([x fliplr(x)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    fill([x fliplr(x)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    plot(x,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
    plot(x,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
    xline(1.5,'k:','LineWidth',1,'HandleVisibility','off');
    xline(6.5,'k:','LineWidth',1,'HandleVisibility','off');
    set(gca,'XTick',1:n_ph,'XTickLabel',xlabels,'FontSize',9);
    ylabel('Tonic SCL above resting (\muS)','FontSize',10);
    xlabel('Phase','FontSize',10);
    legend('Location','northwest','FontSize',10);
    title('H1 — Tonic SCL: NHF vs HF across all phases (mean \pm 95% CI)','FontSize',11);
    yline(0,'k--','LineWidth',0.8,'HandleVisibility','off');
    grid on; box on;
    exportgraphics(fig, fullfile(fig_dir,'H1_scl_all_phases.png'),'Resolution',180);
    close(fig);
    
    % SCR freq — same structure
    mu_N2 = nan(1,n_ph); mu_H2 = nan(1,n_ph);
    se_N2 = nan(1,n_ph); se_H2 = nan(1,n_ph);
    
    for k = 1:n_ph
        ph = phases_ord{k};
        if startsWith(ph,'Training')
            lv = str2double(ph(end));
            Tsub = T(strcmp(T.phase_type,'training') & T.level==lv & isfinite(T.scr_freq),:);
        else
            Tsub = T(strcmp(T.phase,ph) & isfinite(T.scr_freq),:);
        end
        if isempty(Tsub), continue; end
        
        subj = unique(Tsub.subject);
        xa = nan(numel(subj),1); ih = false(numel(subj),1);
        for si=1:numel(subj)
            s=subj{si};
            xa(si) = mean(Tsub.scr_freq(strcmp(Tsub.subject,s)),'omitnan');
            ih(si) = any(Tsub.haptic(strcmp(Tsub.subject,s)));
        end
        xN = xa(~ih & isfinite(xa)); xH = xa(ih & isfinite(xa));
        mu_N2(k) = mean(xN,'omitnan'); mu_H2(k) = mean(xH,'omitnan');
        se_N2(k) = std(xN,'omitnan')/sqrt(numel(xN));
        se_H2(k) = std(xH,'omitnan')/sqrt(numel(xH));
    end
    
    fig = figure('Position',[50 50 1100 420]); hold on;
    fill([x fliplr(x)],[mu_N2+1.96*se_N2 fliplr(mu_N2-1.96*se_N2)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    fill([x fliplr(x)],[mu_H2+1.96*se_H2 fliplr(mu_H2-1.96*se_H2)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    plot(x,mu_N2,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
    plot(x,mu_H2,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
    xline(1.5,'k:','LineWidth',1,'HandleVisibility','off');
    xline(6.5,'k:','LineWidth',1,'HandleVisibility','off');
    set(gca,'XTick',1:n_ph,'XTickLabel',xlabels,'FontSize',9);
    ylabel('SCR frequency (events/min)','FontSize',10);
    xlabel('Phase','FontSize',10);
    legend('Location','best','FontSize',10);
    title('SCR Frequency: NHF vs HF across all phases — note L5 divergence','FontSize',11);
    grid on; box on;
    exportgraphics(fig, fullfile(fig_dir,'H1_scr_freq_all_phases.png'),'Resolution',180);
    close(fig);
end

function local_plot_eye_summary(T, CN, CH, fig_dir)
    outcomes_eye = {
        'gaze_entropy',    'Gaze entropy (bits)'
        'fixation_rate',   'Fixation rate (fix/min)'
        'pupil_mean_norm', 'Pupil dilation (norm.)'
    };
    
    phases_ord = {'Baseline1','Test1','Training_L1','Training_L2','Training_L3','Training_L4','Training_L5','Baseline2','Test2'};
    xlabels = {'BL1','T1','L1','L2','L3','L4','L5','BL2','T2'};
    n_ph = numel(phases_ord);
    
    for oi = 1:size(outcomes_eye,1)
        oc = outcomes_eye{oi,1};
        yl = outcomes_eye{oi,2};
        if ~ismember(oc, T.Properties.VariableNames), continue; end
        
        mu_N = nan(1,n_ph); mu_H = nan(1,n_ph);
        se_N = nan(1,n_ph); se_H = nan(1,n_ph);
        
        for k = 1:n_ph
            ph = phases_ord{k};
            if startsWith(ph,'Training')
                lv = str2double(ph(end));
                Tsub = T(strcmp(T.phase_type,'training') & T.level==lv & isfinite(T.(oc)),:);
            else
                Tsub = T(strcmp(T.phase,ph) & isfinite(T.(oc)),:);
            end
            if isempty(Tsub), continue; end
            
            subj = unique(Tsub.subject);
            xa = nan(numel(subj),1); ih = false(numel(subj),1);
            for si=1:numel(subj)
                s=subj{si};
                xa(si) = mean(Tsub.(oc)(strcmp(Tsub.subject,s)),'omitnan');
                ih(si) = any(Tsub.haptic(strcmp(Tsub.subject,s)));
            end
            xN = xa(~ih & isfinite(xa)); xH = xa(ih & isfinite(xa));
            mu_N(k) = mean(xN,'omitnan'); mu_H(k) = mean(xH,'omitnan');
            se_N(k) = std(xN,'omitnan')/sqrt(numel(xN));
            se_H(k) = std(xH,'omitnan')/sqrt(numel(xH));
        end
        
        x = 1:n_ph;
        fig = figure('Position',[50 50 1100 420]); hold on;
        fill([x fliplr(x)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
        fill([x fliplr(x)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
        plot(x,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
        plot(x,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
        xline(1.5,'k:','LineWidth',1,'HandleVisibility','off');
        xline(6.5,'k:','LineWidth',1,'HandleVisibility','off');
        set(gca,'XTick',1:n_ph,'XTickLabel',xlabels,'FontSize',9);
        ylabel(yl,'FontSize',10); xlabel('Phase','FontSize',10);
        legend('Location','best','FontSize',10);
        title(sprintf('%s: NHF vs HF across all phases (mean \\pm 95%% CI)', strrep(oc,'_',' ')),'FontSize',11);
        grid on; box on;
        exportgraphics(fig, fullfile(fig_dir, sprintf('eye_%s_all_phases.png',oc)),'Resolution',180);
        close(fig);
    end
end

function local_plot_tss_summary(FV, CI, CN, CH, fig_dir)
    metrics = {'tssv','tssf'};
    ylabels = {'log-TSSV [(m/s²)²·s]','log-TSSF [N²]'};
    
    for mi = 1:2
        oc = metrics{mi};
        yl = ylabels{mi};
        
        % Training: rep-by-rep per level (subject means ± SE)
        T_tr = FV(strcmp(FV.phase_type,'training') & isfinite(FV.(oc)) & FV.(oc)>0,:);
        
        fig = figure('Position',[50 50 1600 450]);
        tl = tiledlayout(1,5,'TileSpacing','compact','Padding','compact');
        title(tl, sprintf('%s — mean per repetition per level (mean ± SE + individual subject lines)',upper(oc)),...
            'FontWeight','bold','FontSize',11);
        
        for lv = 1:5
            Tlv = T_tr(T_tr.level==lv,:);
            subj_u = unique(Tlv.subject);
            mat_N = nan(numel(subj_u),10);
            mat_H = nan(numel(subj_u),10);
            is_H = false(numel(subj_u),1);
            
            for si = 1:numel(subj_u)
                s = subj_u{si};
                Ts = Tlv(strcmp(Tlv.subject,s),:);
                is_H(si) = any(Ts.haptic);
                for ri = 1:10
                    v = log(Ts.(oc)(Ts.repetition==ri & Ts.(oc)>0));
                    if ~isempty(v)
                        if is_H(si), mat_H(si,ri) = mean(v,'omitnan');
                        else,        mat_N(si,ri) = mean(v,'omitnan'); end
                    end
                end
            end
            
            mu_lN = mean(mat_N,'omitnan');
            se_lN = std(mat_N,'omitnan')./sqrt(sum(isfinite(mat_N)));
            mu_lH = mean(mat_H,'omitnan');
            se_lH = std(mat_H,'omitnan')./sqrt(sum(isfinite(mat_H)));
            x = 1:10;
            
            nexttile; hold on;
            % Individual lines (thin, transparent)
            for si = 1:numel(subj_u)
                if is_H(si)
                    plot(x,mat_H(si,:),'-','Color',[CH 0.12],'LineWidth',0.5,'HandleVisibility','off');
                else
                    plot(x,mat_N(si,:),'-','Color',[CN 0.12],'LineWidth',0.5,'HandleVisibility','off');
                end
            end
            % Group means
            fill([x fliplr(x)],[mu_lN+se_lN fliplr(mu_lN-se_lN)],CN,'FaceAlpha',0.2,'EdgeColor','none','HandleVisibility','off');
            fill([x fliplr(x)],[mu_lH+se_lH fliplr(mu_lH-se_lH)],CH,'FaceAlpha',0.2,'EdgeColor','none','HandleVisibility','off');
            plot(x,mu_lN,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',5,'DisplayName','NHF');
            plot(x,mu_lH,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',5,'DisplayName','HF');
            
            set(gca,'XTick',1:10,'FontSize',8);
            xlabel('Repetition'); ylabel(yl,'FontSize',8);
            title(sprintf('Level %d',lv),'FontSize',10);
            if lv==1, legend('Location','best','FontSize',8); end
            grid on; box on;
        end
        
        % Sync y-axes across all panels
        all_ax = findobj(fig,'Type','Axes');
        yl_all = cell2mat(arrayfun(@(a)ylim(a),all_ax,'UniformOutput',false)');
        for a = all_ax'
            ylim(a,[min(yl_all(:,1)) max(yl_all(:,2))]);
        end
        
        exportgraphics(fig, fullfile(fig_dir, sprintf('%s_rep_by_rep.png',oc)),'Resolution',180);
        close(fig);
        fprintf('Saved %s_rep_by_rep.png\n',oc);
    end
end

function local_plot_perf_summary(T_perf, CN, CH, fig_dir)
    % Completion time rep-by-rep
    fig = figure('Position',[50 50 1600 450]);
    tl = tiledlayout(1,5,'TileSpacing','compact','Padding','compact');
    title(tl,'Completion time — rep-by-rep within each training level (mean ± SE)','FontWeight','bold','FontSize',11);
    
    for lv = 1:5
        Tlv = T_perf(strcmp(T_perf.phase_type,'training') & T_perf.level==lv & isfinite(T_perf.duration_s),:);
        subj_u = unique(Tlv.subject);
        mat_N = nan(numel(subj_u),10);
        mat_H = nan(numel(subj_u),10);
        is_H = false(numel(subj_u),1);
        
        for si = 1:numel(subj_u)
            s = subj_u{si};
            Ts = Tlv(strcmp(Tlv.subject,s),:);
            is_H(si) = any(Ts.haptic);
            for ri = 1:10
                v = Ts.duration_s(Ts.repetition==ri);
                if ~isempty(v)
                    if is_H(si), mat_H(si,ri) = mean(v,'omitnan');
                    else,        mat_N(si,ri) = mean(v,'omitnan'); end
                end
            end
        end
        
        mu_N = mean(mat_N,'omitnan'); se_N = std(mat_N,'omitnan')./sqrt(sum(isfinite(mat_N)));
        mu_H = mean(mat_H,'omitnan'); se_H = std(mat_H,'omitnan')./sqrt(sum(isfinite(mat_H)));
        x = 1:10;
        
        nexttile; hold on;
        fill([x fliplr(x)],[mu_N+se_N fliplr(mu_N-se_N)],CN,'FaceAlpha',0.2,'EdgeColor','none','HandleVisibility','off');
        fill([x fliplr(x)],[mu_H+se_H fliplr(mu_H-se_H)],CH,'FaceAlpha',0.2,'EdgeColor','none','HandleVisibility','off');
        plot(x,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',5,'DisplayName','NHF');
        plot(x,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',5,'DisplayName','HF');
        set(gca,'XTick',1:10,'FontSize',8);
        xlabel('Repetition'); ylabel('Duration (s)','FontSize',8);
        title(sprintf('Level %d',lv),'FontSize',10);
        if lv==1, legend('Location','best','FontSize',8); end
        grid on; box on;
    end
    exportgraphics(fig, fullfile(fig_dir,'perf_duration_rep_by_rep.png'),'Resolution',180);
    close(fig);
    fprintf('Saved perf_duration_rep_by_rep.png\n');
end