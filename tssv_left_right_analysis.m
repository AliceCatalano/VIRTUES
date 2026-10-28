%% tssv_left_right_analysis.m
% Computes TSSV separately for left tool (channels 1-3) and right tool
% (channels 4-6) across all phases. Exclusions loaded from
% accel_exclusion_lists.mat (saved by accel_exclusion_list.m).

clear; clc; close all; cfg = config();
CN = [64 96 179]/255; CH = [139 82 168]/255;
fig_dir = fullfile(cfg.output_root,'figures','hand_asymmetry');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

BP_LOW  = 80;
BP_HIGH = 1000;
SENS    = cfg.accel_sensitivity_ms2_per_V;
THR     = cfg.tssv_noise_threshold_ms2;

%% Load exclusion lists
excl_path = fullfile(cfg.output_root,'accel_exclusion_lists.mat');
if ~isfile(excl_path)
    error(['tssv_left_right_analysis: accel_exclusion_lists.mat not found.\n' ...
           'Run accel_exclusion_list.m first to generate it.']);
end
excl = load(excl_path);

% Whole-subject exclusions (sensor completely non-functional)
tssv_subj_excl = excl.tssv_subj_excl;   
tssf_subj_excl = excl.tssf_subj_excl;   

% Per-acquisition exclusions: struct or table with fields subject / phase / acquisition
% accel_exclusion_list.m must save tssv_acq_excl as a cell array Nx3: {subject, phase, acquisition}

if isfield(excl,'tssv_acq_excl')
    tssv_acq_excl = excl.tssv_acq_excl;   % Nx3 cell
else
    tssv_acq_excl = {};
    warning('tssv_left_right_analysis: tssv_acq_excl not found in accel_exclusion_lists.mat — only whole-subject exclusions will be applied.');
end

fprintf('Loaded exclusion lists from %s\n', excl_path);
fprintf('  Whole-subject TSSV exclusions (%d): %s\n', ...
    numel(tssv_subj_excl), strjoin(strrep(tssv_subj_excl,'subject_',''), ', '));
fprintf('  Per-acquisition TSSV exclusions: %d entries\n', size(tssv_acq_excl,1));

%% Extraction loop
all_phases = [cfg.baseline_phases, cfg.training_levels, cfg.test_phases];
rows = {};

for si = 1:numel(cfg.all_subjects)
    subj = cfg.all_subjects{si};

    % Skip whole-subject exclusions
    if ismember(subj, tssv_subj_excl)
        fprintf('  [skip whole-subject] %s\n', strrep(subj,'subject_',''));
        continue;
    end

    group    = subj(end);
    haptic   = strcmp(group,'H');
    subj_dir = fullfile(cfg.data_root, subj);

    for ph_idx = 1:numel(all_phases)
        phase     = all_phases{ph_idx};
        phase_dir = fullfile(subj_dir, phase);
        if ~isfolder(phase_dir), continue; end

        is_training = ismember(phase, cfg.training_levels);
        is_baseline = ismember(phase, cfg.baseline_phases);
        is_test     = ismember(phase, cfg.test_phases);

        if is_training
            phase_type   = 'training';
            level_num    = str2double(regexp(phase,'\d+','match','once'));
            acquisitions = arrayfun(@(k) sprintf('rep_%02d',k),1:cfg.n_training_reps,'UniformOutput',false);
            rep_nums     = 1:cfg.n_training_reps;
        elseif is_baseline
            phase_type   = 'baseline';
            level_num    = NaN;
            acquisitions = arrayfun(@(k) sprintf('Level%d',k),1:numel(cfg.level_names),'UniformOutput',false);
            rep_nums     = nan(1,numel(acquisitions));
        else
            phase_type   = 'test';
            level_num    = NaN;
            acquisitions = {'main'};
            rep_nums     = NaN;
        end

        for ai = 1:numel(acquisitions)
            acq = acquisitions{ai};

            % Skip per-acquisition exclusions
            if local_is_acq_excluded(tssv_acq_excl, subj, phase, acq)
                continue;
            end

            if is_test, acq_dir = phase_dir;
            else
                acq_dir = fullfile(phase_dir, acq);
                % if ~isfolder(acq_dir)
                %     if isfolder([acq_dir '_R']), acq_dir = [acq_dir '_R'];
                %     else, continue; end
                % end
            end

            ev_path    = fullfile(acq_dir,'events.mat');
            accel_path = fullfile(acq_dir,'accel.mat');
            if ~isfile(ev_path) || ~isfile(accel_path), continue; end

            [t_start, t_end] = safe_trial_window(ev_path);
            if isnan(t_start) || isnan(t_end), continue; end

            % Load accel
            LA   = load(accel_path,'ACCEL');
            t_a  = LA.ACCEL.time_rel(:);
            fs   = 1 / median(diff(LA.ACCEL.time_rel));
            dt   = 1/fs;
            rv   = LA.ACCEL.data;

            % Bias removal
            bm = t_a >= (t_start-1.0) & t_a < t_start;
            if sum(bm) < 3, bm = t_a < (t_a(1)+1.0); end
            bias   = mean(rv(bm,:),1,'omitnan');
            rv_ms2 = (rv - bias) * SENS;

            % Trial window
            tm = t_a >= t_start & t_a <= t_end;
            if sum(tm) < 10, continue; end
            seg = rv_ms2(tm,:);

            % Bandpass
            if fs/2 > BP_HIGH
                [b,a_f] = butter(4,[BP_LOW BP_HIGH]/(fs/2),'bandpass');
                for c = 1:6
                    seg(:,c) = filtfilt(b, a_f, double(seg(:,c)));
                end
            else
                continue;  % cannot bandpass — skip
            end

            % Separate left and right signed sums
            A_left  = sqrt(sum(seg(:,1:3).^2, 2));
            A_right = sqrt(sum(seg(:,4:6).^2, 2));

            % Noise threshold per hand
            A_L_thr = A_left;  A_L_thr((A_L_thr) < THR) = 0;
            A_R_thr = A_right; A_R_thr((A_R_thr) < THR) = 0;

            tssv_left  = A_L_thr* dt;
            tssv_right = A_R_thr * dt;

            % Per-channel RMS for quality/heatmap
            rms_per_ch     = sqrt(mean(seg.^2, 1));
            dominant_hand  = local_ternary(tssv_left >= tssv_right,'left','right');

            rep_this   = rep_nums(ai);
            if is_training,     level_this = level_num;
            elseif is_baseline, level_this = ai;
            else,               level_this = NaN; end

            rows(end+1,:) = {subj, group, haptic, phase_type, phase, acq,level_this, rep_this, ...
                tssv_left, tssv_right, tssv_left+tssv_right,dominant_hand, ...
                rms_per_ch(1), rms_per_ch(2), rms_per_ch(3), ...
                rms_per_ch(4), rms_per_ch(5), rms_per_ch(6)}; %#ok<AGROW>
        end
    end
    fprintf('Processed %s\n', subj);
end

%% Build table
varnames = {'subject','group','haptic','phase_type','phase','acquisition',...
    'level','repetition','tssv_left','tssv_right','tssv_total','dominant_hand',...
    'rms_ch1','rms_ch2','rms_ch3','rms_ch4','rms_ch5','rms_ch6'};
T = cell2table(rows,'VariableNames',varnames);
if height(T) > 0, T.haptic = logical(T.haptic); end

% Log-transforms
T.log_left  = log(T.tssv_left);
T.log_left(~isfinite(T.log_left)  | T.tssv_left  <= 0) = NaN;
T.log_right = log(T.tssv_right);
T.log_right(~isfinite(T.log_right) | T.tssv_right <= 0) = NaN;
T.log_ratio = T.log_right - T.log_left;   % positive = right more active

% Asymmetry index: (R-L)/(R+L)
T.asymmetry = (T.tssv_right - T.tssv_left) ./ (T.tssv_right + T.tssv_left);

fprintf('\nFinal table: %d rows | %d subjects\n', height(T), numel(unique(T.subject)));
fprintf('NHF: %d rows | HF: %d rows\n', sum(~T.haptic), sum(T.haptic));

save(fullfile(cfg.output_root,'tssv_left_right.mat'),'T');
writetable(T,fullfile(cfg.output_root,'tssv_left_right.csv'));
fprintf('Saved tssv_left_right.mat\n');

%% FIGURE 1: All phases — left vs right + asymmetry 
phases_ord = {'Baseline1','Test1','level_L1','level_L2','level_L3','level_L4','level_L5','Baseline2','Test2'};
xlabels_p  = {'BL1','T1','L1','L2','L3','L4','L5','BL2','T2'};
n_ph = numel(phases_ord);

fig1 = figure('Position',[50 50 1600 900]);
tl1  = tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
title(tl1,'TSSV Left vs Right Hand across all phases (subject means ± 95% CI)', ...
    'FontWeight','bold','FontSize',12);

metrics_fig1 = {
    'log_left',  'log-TSSV Left tool'
    'log_right', 'log-TSSV Right tool'
    'log_ratio', 'log(Right/Left)  [+ve = right more active]'
    'asymmetry', 'Asymmetry index (R−L)/(R+L)'
};

for mi = 1:4
    oc = metrics_fig1{mi,1};
    yl = metrics_fig1{mi,2};

    mu_N = nan(1,n_ph); mu_H = nan(1,n_ph);
    se_N = nan(1,n_ph); se_H = nan(1,n_ph);

    for k = 1:n_ph
        ph = phases_ord{k};
        if startsWith(ph,'level_')
            lv   = str2double(regexp(ph,'\d+','match','once'));
            Tsub = T(strcmp(T.phase_type,'training') & T.level==lv & isfinite(T.(oc)),:);
        else
            Tsub = T(strcmp(T.phase,ph) & isfinite(T.(oc)),:);
        end
        if isempty(Tsub), continue; end
        subj_u = unique(Tsub.subject);
        xa = nan(numel(subj_u),1); ih = false(numel(subj_u),1);
        for si2 = 1:numel(subj_u)
            s = subj_u{si2};
            xa(si2) = mean(Tsub.(oc)(strcmp(Tsub.subject,s)),'omitnan');
            ih(si2) = any(Tsub.haptic(strcmp(Tsub.subject,s)));
        end
        xN=xa(~ih&isfinite(xa)); xH=xa(ih&isfinite(xa));
        mu_N(k)=mean(xN,'omitnan'); se_N(k)=std(xN,'omitnan')/sqrt(numel(xN));
        mu_H(k)=mean(xH,'omitnan'); se_H(k)=std(xH,'omitnan')/sqrt(numel(xH));
    end

    nexttile; hold on;
    x = 1:n_ph;
    fill([x fliplr(x)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,...
        'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    fill([x fliplr(x)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,...
        'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    plot(x,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,...
        'MarkerSize',7,'DisplayName','NHF');
    plot(x,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,...
        'MarkerSize',7,'DisplayName','HF');
    if mi >= 3, yline(0,'k--','LineWidth',1,'HandleVisibility','off'); end
    xline(1.5,'k:','LineWidth',1,'HandleVisibility','off');
    xline(6.5,'k:','LineWidth',1,'HandleVisibility','off');
    set(gca,'XTick',1:n_ph,'XTickLabel',xlabels_p,'FontSize',9);
    ylabel(yl,'FontSize',9); xlabel('Phase','FontSize',9);
    legend('Location','best','FontSize',9);
    title(yl,'FontSize',9,'Interpreter','none');
    grid on; box on;
end
exportgraphics(fig1,fullfile(fig_dir,'tssv_LR_all_phases.png'),'Resolution',180);
fprintf('Saved tssv_LR_all_phases.png\n');

%% FIGURE 2: Training rep-by-rep — left (solid) vs right (dashed) ───────
T_tr = T(strcmp(T.phase_type,'training'),:);

cols_LR = {[0.15 0.45 0.80], [0.85 0.33 0.10]};   % left=blue, right=orange

fig2 = figure('Position',[50 50 1800 900]);
tl2  = tiledlayout(2,5,'TileSpacing','compact','Padding','compact');
title(tl2,...
    'TSSV Left tool (solid) vs Right tool (dashed) — rep-by-rep per training level',...
    'FontWeight','bold','FontSize',12);

for grp = [false true]
    grp_col = local_ternary(grp,CH,CN);
    grp_lbl = local_ternary(grp,'HF','NHF');
    Tg = T_tr(T_tr.haptic==grp,:);

    for lv = 1:5
        Tlv    = Tg(Tg.level==lv,:);
        subj_u = unique(Tlv.subject);
        mat_L  = nan(numel(subj_u),10);
        mat_R  = nan(numel(subj_u),10);

        for si2 = 1:numel(subj_u)
            s  = subj_u{si2};
            Ts = Tlv(strcmp(Tlv.subject,s),:);
            for ri = 1:10
                vL = Ts.log_left(Ts.repetition==ri);
                vR = Ts.log_right(Ts.repetition==ri);
                if ~isempty(vL), mat_L(si2,ri) = mean(vL,'omitnan'); end
                if ~isempty(vR), mat_R(si2,ri) = mean(vR,'omitnan'); end
            end
        end

        mu_L = mean(mat_L,'omitnan');
        se_L = std(mat_L,'omitnan')./sqrt(sum(isfinite(mat_L)));
        mu_R = mean(mat_R,'omitnan');
        se_R = std(mat_R,'omitnan')./sqrt(sum(isfinite(mat_R)));

        tile_idx = local_ternary(grp, lv+5, lv);
        nexttile(tile_idx); hold on;

        x = 1:10;
        % Left tool — solid
        fill([x fliplr(x)],[mu_L+se_L fliplr(mu_L-se_L)],cols_LR{1},...
            'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
        plot(x,mu_L,'o-','Color',cols_LR{1},'LineWidth',2,...
            'MarkerFaceColor',cols_LR{1},'MarkerSize',5,'DisplayName','Left tool');
        % Right tool — dashed
        fill([x fliplr(x)],[mu_R+se_R fliplr(mu_R-se_R)],cols_LR{2},...
            'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
        plot(x,mu_R,'s--','Color',cols_LR{2},'LineWidth',2,...
            'MarkerFaceColor',cols_LR{2},'MarkerSize',5,'DisplayName','Right tool');

        set(gca,'XTick',1:10,'FontSize',7);
        xlabel('Repetition','FontSize',8);
        ylabel('log-TSSV','FontSize',8);
        title(sprintf('%s | Level %d',grp_lbl,lv),'FontSize',9,'Color',grp_col);
        if lv==1, legend('FontSize',7,'Location','best'); end
        grid on; box on;
    end
end
exportgraphics(fig2,fullfile(fig_dir,'tssv_LR_rep_by_rep.png'),'Resolution',180);
fprintf('Saved tssv_LR_rep_by_rep.png\n');

%% FIGURE 3: Asymmetry across phases ────────────────────────────────────
fig3 = figure('Position',[50 50 1200 500]);
tl3  = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
title(tl3,...
    'Hand asymmetry index (R−L)/(R+L)   [0 = symmetric  |  +1 = right only]',...
    'FontWeight','bold','FontSize',12);

% Panel 1: by training level
nexttile; hold on;
for grp = [false true]
    col = local_ternary(grp,CH,CN);
    lbl = local_ternary(grp,'HF','NHF');
    Tg  = T_tr(T_tr.haptic==grp & isfinite(T_tr.asymmetry),:);
    subj_u = unique(Tg.subject);
    mu_as = nan(1,5); se_as = nan(1,5);
    for lv = 1:5
        xs = nan(numel(subj_u),1);
        for si2 = 1:numel(subj_u)
            s = subj_u{si2};
            v = Tg.asymmetry(strcmp(Tg.subject,s) & Tg.level==lv);
            if ~isempty(v), xs(si2) = mean(v,'omitnan'); end
        end
        xs = xs(isfinite(xs));
        mu_as(lv) = mean(xs,'omitnan');
        se_as(lv) = std(xs,'omitnan')/sqrt(numel(xs));
    end
    fill([1:5 fliplr(1:5)],[mu_as+1.96*se_as fliplr(mu_as-1.96*se_as)],col,...
        'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    plot(1:5,mu_as,'o-','Color',col,'LineWidth',2,'MarkerFaceColor',col,...
        'MarkerSize',7,'DisplayName',lbl);
end
yline(0,'k--','LineWidth',1.2,'HandleVisibility','off');
set(gca,'XTick',1:5,'XTickLabel',{'L1','L2','L3','L4','L5'},'FontSize',9);
xlabel('Training level','FontSize',10);
ylabel('Asymmetry index','FontSize',10);
title('Training: hand asymmetry by difficulty','FontSize',10);
legend('Location','best','FontSize',9); grid on; box on;

% Panel 2: all phases
nexttile; hold on;
mu_aN = nan(1,n_ph); mu_aH = nan(1,n_ph);
se_aN = nan(1,n_ph); se_aH = nan(1,n_ph);
for k = 1:n_ph
    ph = phases_ord{k};
    if startsWith(ph,'level_')
        lv   = str2double(regexp(ph,'\d+','match','once'));
        Tsub = T(strcmp(T.phase_type,'training') & T.level==lv & isfinite(T.asymmetry),:);
    else
        Tsub = T(strcmp(T.phase,ph) & isfinite(T.asymmetry),:);
    end
    if isempty(Tsub), continue; end
    subj_u = unique(Tsub.subject);
    xa = nan(numel(subj_u),1); ih = false(numel(subj_u),1);
    for si2 = 1:numel(subj_u)
        s = subj_u{si2};
        xa(si2) = mean(Tsub.asymmetry(strcmp(Tsub.subject,s)),'omitnan');
        ih(si2) = any(Tsub.haptic(strcmp(Tsub.subject,s)));
    end
    xN=xa(~ih&isfinite(xa)); xH=xa(ih&isfinite(xa));
    mu_aN(k)=mean(xN,'omitnan'); se_aN(k)=std(xN,'omitnan')/sqrt(numel(xN));
    mu_aH(k)=mean(xH,'omitnan'); se_aH(k)=std(xH,'omitnan')/sqrt(numel(xH));
end
x = 1:n_ph;
fill([x fliplr(x)],[mu_aN+1.96*se_aN fliplr(mu_aN-1.96*se_aN)],CN,...
    'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
fill([x fliplr(x)],[mu_aH+1.96*se_aH fliplr(mu_aH-1.96*se_aH)],CH,...
    'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
plot(x,mu_aN,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,...
    'MarkerSize',7,'DisplayName','NHF');
plot(x,mu_aH,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,...
    'MarkerSize',7,'DisplayName','HF');
yline(0,'k--','LineWidth',1,'HandleVisibility','off');
xline(1.5,'k:','LineWidth',1,'HandleVisibility','off');
xline(6.5,'k:','LineWidth',1,'HandleVisibility','off');
set(gca,'XTick',1:n_ph,'XTickLabel',xlabels_p,'FontSize',9);
xlabel('Phase','FontSize',10); ylabel('Asymmetry index','FontSize',10);
title('Asymmetry across all phases','FontSize',10);
legend('Location','best','FontSize',9); grid on; box on;
exportgraphics(fig3,fullfile(fig_dir,'tssv_LR_asymmetry.png'),'Resolution',180);
fprintf('Saved tssv_LR_asymmetry.png\n');

%% FIGURE 4: Scatter left vs right + dominance bar ─────────────────────
fig4 = figure('Position',[50 50 1100 480]);
tl4  = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
title(tl4,'Left vs Right TSSV relationship (training phase)',...
    'FontWeight','bold','FontSize',12);

% Scatter: log_left vs log_right
nexttile; hold on;
T_sc = T_tr(isfinite(T_tr.log_left) & isfinite(T_tr.log_right),:);
scatter(T_sc.log_left(~T_sc.haptic), T_sc.log_right(~T_sc.haptic),...
    8,CN,'filled','MarkerFaceAlpha',0.15,'DisplayName','NHF');
scatter(T_sc.log_left(T_sc.haptic),  T_sc.log_right(T_sc.haptic),...
    8,CH,'filled','MarkerFaceAlpha',0.15,'DisplayName','HF');
xy_lim = [min([T_sc.log_left;T_sc.log_right],[],'omitnan') ...
          max([T_sc.log_left;T_sc.log_right],[],'omitnan')];
plot(xy_lim,xy_lim,'k--','LineWidth',1.5,'HandleVisibility','off');
r_N = corr(T_sc.log_left(~T_sc.haptic), T_sc.log_right(~T_sc.haptic),'Rows','complete');
r_H = corr(T_sc.log_left( T_sc.haptic), T_sc.log_right( T_sc.haptic),'Rows','complete');
xlabel('log-TSSV Left tool','FontSize',10);
ylabel('log-TSSV Right tool','FontSize',10);
title(sprintf('Per-trial left vs right\nr_{NHF}=%.3f  r_{HF}=%.3f',r_N,r_H),'FontSize',10);
legend('Location','best','FontSize',9); grid on; box on;
text(xy_lim(1)+0.2,xy_lim(2)-0.3,'Diagonal = symmetric','FontSize',8,...
    'Color',[0.4 0.4 0.4],'FontAngle','italic');

% Bar: % trials right-dominant by phase and group
nexttile; hold on;
phase_types_bar = {'baseline','training','test'};
phase_lbl_bar   = {'Baseline','Training','Test'};
bar_data = nan(2,3);
for pi2 = 1:3
    Tph = T(strcmp(T.phase_type,phase_types_bar{pi2}),:);
    for grp = [false true]
        gi  = local_ternary(grp,2,1);
        Tg  = Tph(Tph.haptic==grp,:);
        if isempty(Tg), continue; end
        bar_data(gi,pi2) = 100*mean(strcmp(Tg.dominant_hand,'right'),'omitnan');
    end
end
b = bar(bar_data',0.7,'grouped');
b(1).FaceColor = CN; b(2).FaceColor = CH;
yline(50,'k--','LineWidth',1.5,'HandleVisibility','off');
set(gca,'XTick',1:3,'XTickLabel',phase_lbl_bar,'FontSize',10);
ylabel('% trials where right tool TSSV > left','FontSize',10);
legend({'NHF','HF'},'Location','best','FontSize',10);
title({'Which tool is more active?','50% line = perfect symmetry'},'FontSize',10);
ylim([30 70]); grid on; box on;
exportgraphics(fig4,fullfile(fig_dir,'tssv_LR_scatter_dominance.png'),'Resolution',180);
fprintf('Saved tssv_LR_scatter_dominance.png\n');

%% FIGURE 5: Per-channel RMS heatmap ────────────────────────────────────
fig5 = figure('Position',[50 50 1400 600]);
tl5  = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
title(tl5,'Mean per-channel RMS (m/s²) during training — sorted by total TSSV',...
    'FontWeight','bold','FontSize',12);

ch_names = {'L1 (Lx)','L2 (Ly)','L3 (Lz)','R1 (Rx)','R2 (Ry)','R3 (Rz)'};
rms_cols  = {'rms_ch1','rms_ch2','rms_ch3','rms_ch4','rms_ch5','rms_ch6'};

for grp = [false true]
    col_str = local_ternary(grp,'HF','NHF');
    Tg      = T_tr(T_tr.haptic==grp,:);
    subj_u  = unique(Tg.subject);
    ns      = numel(subj_u);
    rms_mat  = nan(ns,6);
    tssv_tot = nan(ns,1);

    for si2 = 1:ns
        s  = subj_u{si2};
        Ts = Tg(strcmp(Tg.subject,s),:);
        for c = 1:6
            rms_mat(si2,c) = mean(Ts.(rms_cols{c}),'omitnan');
        end
        tssv_tot(si2) = mean(Ts.log_left + Ts.log_right,'omitnan');
    end

    [~,ord]   = sort(tssv_tot,'ascend');
    rms_mat   = rms_mat(ord,:);
    subj_lbl  = strrep(subj_u(ord),'subject_','');

    nexttile;
    imagesc(rms_mat);
    colormap(parula); cb = colorbar;
    cb.Label.String = 'RMS (m/s²)';
    set(gca,'XTick',1:6,'XTickLabel',ch_names,...
        'XTickLabelRotation',35,'FontSize',8);
    set(gca,'YTick',1:ns,'YTickLabel',subj_lbl,'FontSize',7);
    xlabel('Channel','FontSize',10);
    ylabel('Subject (↑ = higher total TSSV)','FontSize',9);
    title(sprintf('%s — channel RMS heatmap',col_str),'FontSize',10);
    xline(3.5,'w-','LineWidth',2.5,'HandleVisibility','off');
    text(2,   -0.6,'LEFT TOOL', 'HorizontalAlignment','center',...
        'FontSize',9,'Color',[0 0 0],'FontWeight','bold');
    text(5,   -0.6,'RIGHT TOOL','HorizontalAlignment','center',...
        'FontSize',9,'Color',[0 0 0],'FontWeight','bold');
end
exportgraphics(fig5,fullfile(fig_dir,'tssv_channel_rms_heatmap.png'),'Resolution',180);
fprintf('Saved tssv_channel_rms_heatmap.png\n');

%% Statistical summary─
fprintf('\n\n=== LEFT vs RIGHT TSSV STATISTICAL SUMMARY ===\n');
fprintf('%-12s %-6s %10s %10s %10s %10s %10s\n',...
    'Phase','Group','mean_L','mean_R','paired_p','d_LR','asym_mean');

for pt = {'baseline','training','test'}
    Tph = T(strcmp(T.phase_type,pt{1}) & ...
            isfinite(T.log_left) & isfinite(T.log_right),:);
    for grp = [false true]
        lbl = local_ternary(grp,'HF','NHF');
        Tg  = Tph(Tph.haptic==grp,:);
        if height(Tg) < 5, continue; end
        subj_u = unique(Tg.subject);
        mu_L = nan(numel(subj_u),1); mu_R = nan(numel(subj_u),1);
        for si2 = 1:numel(subj_u)
            s = subj_u{si2};
            mu_L(si2) = mean(Tg.log_left(strcmp(Tg.subject,s)) ,'omitnan');
            mu_R(si2) = mean(Tg.log_right(strcmp(Tg.subject,s)),'omitnan');
        end
        keep = isfinite(mu_L) & isfinite(mu_R);
        [~,p_pair] = ttest(mu_L(keep), mu_R(keep));
        d_LR  = mean(mu_R(keep)-mu_L(keep),'omitnan') / ...
                std( mu_R(keep)-mu_L(keep),'omitnan');
        asym  = mean(Tg.asymmetry,'omitnan');
        fprintf('%-12s %-6s %10.3f %10.3f %10.4f %10.3f %10.4f\n',...
            pt{1},lbl,...
            mean(mu_L(keep),'omitnan'), mean(mu_R(keep),'omitnan'),...
            p_pair, d_LR, asym);
    end
end

fprintf('\n=== Hand dominance (right tool > left tool) ===\n');
for pt = {'baseline','training','test'}
    for grp = [false true]
        lbl = local_ternary(grp,'HF','NHF');
        Tg  = T(strcmp(T.phase_type,pt{1}) & T.haptic==grp,:);
        if isempty(Tg), continue; end
        pct_R = 100*mean(strcmp(Tg.dominant_hand,'right'),'omitnan');
        fprintf('%-10s %-6s: Right dominant %.1f%%  Left dominant %.1f%%\n',...
            pt{1},lbl,pct_R,100-pct_R);
    end
end

fprintf('\nAll figures saved to: %s\n', fig_dir);

%% LOCAL HELPERS───────
function is_excl = local_is_acq_excluded(acq_excl, subj, phase, acq)
% Returns true if this subject/phase/acquisition triplet is in the
% per-acquisition exclusion list.
% acq_excl is expected to be an Nx3 cell array {subject, phase, acq}.
    is_excl = false;
    if isempty(acq_excl), return; end
    is_excl = any(strcmp(acq_excl(:,1),subj) & ...
                  strcmp(acq_excl(:,2),phase) & ...
                  strcmp(acq_excl(:,3),acq));
end

function out = local_ternary(c,a,b)
    if c, out=a; else, out=b; end
end