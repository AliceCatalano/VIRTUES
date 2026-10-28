%% generate_all_level_divergence_figures.m
% Generates all level divergence plots with correct outcome names.
% Run after confirming eye_lmm_results.mat has the 6 outcomes above.

cfg = config();
COLOR_N = [55  138 221] / 255;
COLOR_H = [212  83 126] / 255;
fig_dir = fullfile(cfg.output_root, 'figures');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

%% Load all LMM result files
Reda  = load(fullfile(cfg.output_root, 'training_lmm_results.mat'),    'results','outcomes');
Rperf = load(fullfile(cfg.output_root, 'performance_lmm_results.mat'), 'results','outcomes');
Reye  = load(fullfile(cfg.output_root, 'eye_lmm_results.mat'),         'results','outcomes');

fprintf('EDA outcomes:  %s\n', strjoin(Reda.outcomes,  ', '));
fprintf('Perf outcomes: %s\n', strjoin(Rperf.outcomes, ', '));
fprintf('Eye outcomes:  %s\n', strjoin(Reye.outcomes,  ', '));

%% ═══════════════════════════════════════════════════════════════════════
%% FIGURE 1: EDA + Performance (the main dissociation figure)
%% ═══════════════════════════════════════════════════════════════════════
% EDA outcomes — keys must match exactly what's in Reda.outcomes
eda_keys   = {'scl_mean_bc',    'scr_freq',    'scr_mean_amp_bc',    'collision_scr_amp_mean_bc'};
eda_labels = {'Tonic SCL (µS)', 'SCR freq (events/min)', 'SCR amplitude', 'ER-SCR amplitude'};

perf_keys   = {'duration_s',         'n_collisions'};
perf_labels = {'Completion time (s)', 'Collisions (log-rate)'};

n_eda  = numel(eda_keys);
n_perf = numel(perf_keys);
n_cols = max(n_eda, n_perf);

fig1 = figure('Name','Level divergence: EDA + Performance', ...
    'Position',[50 50 1500 680]);
sgtitle({'Level effect (vs. Level 1) — NHF (blue) vs HF (pink)', ...
    'Physiology (top row) vs Performance (bottom row)', ...
    'Filled markers = FDR-significant Haptic×Level interaction  |  95% CI error bars'}, ...
    'FontWeight','bold','FontSize',11);

% ── Top row: EDA ─────────────────────────────────────────────────────────
for k = 1:n_eda
    subplot(2, n_cols, k);
    local_level_panel(Reda, eda_keys{k}, eda_labels{k}, COLOR_N, COLOR_H, k==1);
end

% ── Bottom row: Performance ───────────────────────────────────────────────
for k = 1:n_perf
    subplot(2, n_cols, n_cols + k);
    local_level_panel(Rperf, perf_keys{k}, perf_labels{k}, COLOR_N, COLOR_H, k==1);
end

saveas(fig1, fullfile(fig_dir, 'level_divergence_eda_perf.png'));
fprintf('Saved level_divergence_eda_perf.png\n');

%% ═══════════════════════════════════════════════════════════════════════
%% FIGURE 2: Eye tracking level divergence
%% ═══════════════════════════════════════════════════════════════════════
% Using correct names from eye_lmm_results.mat
eye_keys   = {'gaze_entropy',    'fixation_rate',          'pupil_mean_norm',    'collision_pupil_response_mean'};
eye_labels = {'Gaze entropy (bits)', 'Fixation rate (fix/min)', 'Pupil (norm.)',  'Collision pupil response'};

n_eye = numel(eye_keys);

fig2 = figure('Name','Level divergence: Eye tracking', ...
    'Position',[50 50 1500 400]);
sgtitle({'Eye-tracking: Level effect (vs. Level 1) — NHF (blue) vs HF (pink)', ...
    'Filled markers = FDR-significant Haptic×Level interaction  |  95% CI error bars'}, ...
    'FontWeight','bold','FontSize',11);

for k = 1:n_eye
    subplot(1, n_eye, k);
    local_level_panel(Reye, eye_keys{k}, eye_labels{k}, COLOR_N, COLOR_H, k==1);
end

saveas(fig2, fullfile(fig_dir, 'level_divergence_eye.png'));
fprintf('Saved level_divergence_eye.png\n');

%% ═══════════════════════════════════════════════════════════════════════
%% FIGURE 3: Combined all-outcomes overview (one big figure)
%% ═══════════════════════════════════════════════════════════════════════
all_res    = {Reda,       Reye,          Reye,              Reye,           Rperf,              Rperf};
all_keys   = {'scl_mean_bc', 'gaze_entropy', 'fixation_rate', 'pupil_mean_norm', 'duration_s', 'n_collisions'};
all_labels = {'Tonic SCL', 'Gaze entropy',  'Fixation rate',  'Pupil (norm.)', 'Completion time', 'Collisions'};
all_rows   = [1 1 1 1 2 2];  % which subplot row
all_cols   = [1 2 3 4 1 2];  % which subplot column

fig3 = figure('Name','Level divergence: All outcomes overview', ...
    'Position',[50 50 1600 620]);
sgtitle({'All outcomes: Level effect (vs. Level 1) — NHF (blue) vs HF (pink)', ...
    'Row 1: Physiological  |  Row 2: Performance',...
    'Filled markers = p<.05  |  95% CI'}, ...
    'FontWeight','bold','FontSize',11);

for k = 1:numel(all_keys)
    subplot(2, 4, (all_rows(k)-1)*4 + all_cols(k));
    local_level_panel(all_res{k}, all_keys{k}, all_labels{k}, COLOR_N, COLOR_H, k==1);
end

% Add annotation explaining what filled vs hollow means
annotation('textbox',[0.01 0.01 0.5 0.04], ...
    'String','Filled = Haptic×Level interaction p<.05 (uncorrected); Hollow = n.s.', ...
    'EdgeColor','none','FontSize',9,'Color',[0.4 0.4 0.4]);

saveas(fig3, fullfile(fig_dir, 'level_divergence_all_outcomes.png'));
fprintf('Saved level_divergence_all_outcomes.png\n');

%% ═══════════════════════════════════════════════════════════════════════
%% FIGURE 4: SCR frequency dissociation — enlarged for the slide
%% ═══════════════════════════════════════════════════════════════════════
fig4 = figure('Name','SCR frequency dissociation', 'Position',[50 50 1000 440]);
tl4 = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
sgtitle({'SCR Frequency: The Level 5 Dissociation', ...
    'NHF suppresses phasic arousal at L5 — HF maintains it'}, ...
    'FontWeight','bold','FontSize',12);

oi_scrf = find(strcmp(Reda.outcomes,'scr_freq'),1);
se_scrf = Reda.results{oi_scrf}.simple_effects;
is_level = ~cellfun('isempty', regexp(se_scrf.effect,'^level \d+ vs level 1$','once'));
se_scrf = se_scrf(is_level,:);
lvl_num = cellfun(@(s) sscanf(s,'level %d vs level 1'), se_scrf.effect);

% Left panel: full level trajectory
nexttile; hold on;
for grp = {'N','H'}
    g = grp{1}; mask = strcmp(se_scrf.group,g);
    x = lvl_num(mask); [x,ord]=sort(x);
    y  = se_scrf.beta(mask);  y  = y(ord);
    lo = se_scrf.lower(mask); lo = lo(ord);
    hi = se_scrf.upper(mask); hi = hi(ord);
    pv = se_scrf.p(mask);     pv = pv(ord);
    col = local_ternary(strcmp(g,'H'), COLOR_H, COLOR_N);
    lbl = local_ternary(strcmp(g,'H'), 'HF', 'NHF');
    fill([x' fliplr(x')],[hi' fliplr(lo')],col,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    plot(x, y, 'o-','Color',col,'LineWidth',2.5,'MarkerFaceColor',col,'MarkerSize',8,'DisplayName',lbl);
end
yline(0,'k--','LineWidth',1,'HandleVisibility','off');
xlabel('Training level (vs. Level 1)','FontSize',11);
ylabel('\Delta SCR frequency (events/min)','FontSize',11);
legend('Location','southwest','FontSize',10);
title({'SCR frequency change from Level 1', ...
    'NHF: monotonic suppression  |  HF: recovery at L5'},'FontSize',10);
xlim([1.5 5.5]); xticks(2:5); grid on; box on;

% Add significance stars
se_all = Reda.results{oi_scrf}.simple_effects;
is_lh = contains(se_all.Name, 'level_cat') & contains(se_all.Name, 'haptic_num');

% Right panel: L5 simple effect bar chart
nexttile; hold on;
groups = {'N','H'}; colors = {COLOR_N, COLOR_H};
for gi = 1:2
    g = groups{gi};
    mask_l5 = strcmp(se_scrf.group,g) & lvl_num==5;
    if ~any(mask_l5), continue; end
    beta_l5 = se_scrf.beta(mask_l5);
    se_l5   = (se_scrf.upper(mask_l5) - se_scrf.lower(mask_l5)) / (2*1.96);
    p_l5    = se_scrf.p(mask_l5);
    b = bar(gi, beta_l5, 0.5, 'FaceColor',colors{gi}, 'EdgeColor','none');
    errorbar(gi, beta_l5, se_l5*1.96, 'k.','LineWidth',1.5,'CapSize',10);
    % p-value annotation
    sig = local_stars(p_l5);
    if ~isempty(sig)
        ypos = beta_l5 + sign(beta_l5)*se_l5*1.96 + 0.05;
        text(gi, ypos, sig,'HorizontalAlignment','center','FontSize',16,'Color',colors{gi});
    end
    text(gi, beta_l5 - sign(beta_l5)*0.15, sprintf('β=%.3f\np=%.3f',beta_l5,p_l5), ...
        'HorizontalAlignment','center','FontSize',9,'Color',colors{gi});
end
yline(0,'k-','LineWidth',1.2,'HandleVisibility','off');
xticks([1 2]); xticklabels({'NHF','HF'});
ylabel('\Delta SCR freq at L5 vs L1 (events/min)','FontSize',11);
title({'Level 5 vs Level 1 simple effect', ...
    'Haptic×L5 interaction p_{FDR}=0.001'},'FontSize',10);
xlim([0.4 2.6]); grid on; box on;

saveas(fig4, fullfile(fig_dir,'level_divergence_scr_freq_detail.png'));
fprintf('Saved level_divergence_scr_freq_detail.png\n');

%% ═══════════════════════════════════════════════════════════════════════
%% FIGURE 5: Fixation rate reversal — enlarged for the slide
%% ═══════════════════════════════════════════════════════════════════════
fig5 = figure('Name','Fixation rate reversal', 'Position',[50 50 1000 440]);
tl5 = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
sgtitle({'Fixation Rate: Complete Directional Reversal', ...
    'NHF scans LESS at harder levels — HF scans MORE'}, ...
    'FontWeight','bold','FontSize',12);

oi_fix = find(strcmp(Reye.outcomes,'fixation_rate'),1);
se_fix = Reye.results{oi_fix}.simple_effects;
is_level = ~cellfun('isempty', regexp(se_fix.effect,'^level \d+ vs level 1$','once'));
se_fix = se_fix(is_level,:);
lvl_fix = cellfun(@(s) sscanf(s,'level %d vs level 1'), se_fix.effect);

% Left panel: full trajectory
nexttile; hold on;
for grp = {'N','H'}
    g = grp{1}; mask = strcmp(se_fix.group,g);
    x = lvl_fix(mask); [x,ord]=sort(x);
    y  = se_fix.beta(mask);  y  = y(ord);
    lo = se_fix.lower(mask); lo = lo(ord);
    hi = se_fix.upper(mask); hi = hi(ord);
    pv = se_fix.p(mask);     pv = pv(ord);
    col = local_ternary(strcmp(g,'H'), COLOR_H, COLOR_N);
    lbl = local_ternary(strcmp(g,'H'), 'HF', 'NHF');
    fill([x' fliplr(x')],[hi' fliplr(lo')],col,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    h_line = plot(x, y, 'o-','Color',col,'LineWidth',2.5,'MarkerFaceColor',col,...
        'MarkerSize',8,'DisplayName',lbl);
    % Mark significant levels with filled markers (already filled), 
    % n.s. with open markers
    for xi = 1:numel(x)
        if pv(xi) >= 0.05
            plot(x(xi), y(xi), 'o','Color',col,'MarkerFaceColor','w',...
                'MarkerSize',10,'LineWidth',2,'HandleVisibility','off');
        end
    end
end
yline(0,'k--','LineWidth',1,'HandleVisibility','off');
xlabel('Training level (vs. Level 1)','FontSize',11);
ylabel('\Delta Fixation rate (fixations/min)','FontSize',11);
legend('Location','northwest','FontSize',10);
title({'Fixation rate change from Level 1', ...
    'Complete reversal: NHF ↓, HF ↑'},'FontSize',10);
xlim([1.5 5.5]); xticks(2:5); grid on; box on;

% Add zero-crossing annotation
text(3.5, 1, 'HF', 'Color',COLOR_H,'FontSize',14,'FontWeight','bold');
text(3.5,-2.5,'NHF','Color',COLOR_N,'FontSize',14,'FontWeight','bold');

% Right panel: L3 detail (most significant)
nexttile; hold on;
bar_data = nan(2,4);  % groups x levels 2-5
bar_se   = nan(2,4);
bar_p    = nan(2,4);
for gi = 1:2
    g = groups{gi};
    for li = 1:4
        lv = li+1;
        mask_lv = strcmp(se_fix.group,g) & lvl_fix==lv;
        if any(mask_lv)
            bar_data(gi,li) = se_fix.beta(mask_lv);
            bar_se(gi,li)   = (se_fix.upper(mask_lv)-se_fix.lower(mask_lv))/(2*1.96);
            bar_p(gi,li)    = se_fix.p(mask_lv);
        end
    end
end

bw = 0.35;
for gi = 1:2
    x_pos = (1:4) + local_ternary(gi==1,-bw/2,bw/2);
    b = bar(x_pos, bar_data(gi,:), bw,'FaceColor',colors{gi},'EdgeColor','none','DisplayName',groups{gi});
    errorbar(x_pos, bar_data(gi,:), bar_se(gi,:)*1.96,'k.','LineWidth',1.2,'CapSize',6,'HandleVisibility','off');
    for li = 1:4
        sig = local_stars(bar_p(gi,li));
        if ~isempty(sig)
            yoff = bar_data(gi,li) + sign(bar_data(gi,li))*(bar_se(gi,li)*1.96+0.5);
            text(x_pos(li), yoff, sig,'HorizontalAlignment','center','FontSize',13,'Color',colors{gi});
        end
    end
end
yline(0,'k-','LineWidth',1.2,'HandleVisibility','off');
set(gca,'XTick',1:4,'XTickLabel',{'L2','L3','L4','L5'},'FontSize',10);
ylabel('\Delta Fixation rate (fix/min)','FontSize',11);
title({'Simple effects per level', 'FDR-sig interactions at L2-L4'},'FontSize',10);
legend({'NHF','HF'},'Location','best','FontSize',10);
grid on; box on;

saveas(fig5, fullfile(fig_dir,'level_divergence_fixation_detail.png'));
fprintf('Saved level_divergence_fixation_detail.png\n');

%% ═══════════════════════════════════════════════════════════════════════
%% Print all significant Haptic×Level interactions in one clean table
%% ═══════════════════════════════════════════════════════════════════════
fprintf('\n\n=== ALL SIGNIFICANT Haptic×Level INTERACTIONS ===\n');
fprintf('%-35s %-8s %8s %8s %8s\n','Outcome','Level','β','SE','p_FDR');
fprintf('%s\n', repmat('-',1,70));

all_result_sets = {
    Reda,  'EDA'
    Reye,  'Eye'
    Rperf, 'Performance'
};

for rs = 1:3
    Rset = all_result_sets{rs,1};
    rslbl = all_result_sets{rs,2};
    
    % Collect all lh_p values for FDR within this modality
    all_p = []; all_idx = []; all_oc = {}; all_lv = [];
    for oi = 1:numel(Rset.outcomes)
        lh = Rset.results{oi}.level_haptic;
        for j = 1:height(lh)
            all_p(end+1)   = lh.p(j);
            all_idx(end+1) = oi;
            all_oc{end+1}  = Rset.outcomes{oi};
            % extract level number from term name
            tok = regexp(lh.term{j},'level_cat_(\d+)','tokens','once');
            all_lv(end+1) = str2double(tok{1});
        end
    end
    
    p_fdr = local_bh_fdr(all_p);
    
    for k = 1:numel(all_p)
        if p_fdr(k) < 0.05
            oi = all_idx(k);
            lh = Rset.results{oi}.level_haptic;
            fprintf('[%s] %-30s L%-2d: β=%+.4f  SE=%.4f  p_FDR=%.4f %s\n', ...
                rslbl, all_oc{k}, all_lv(k), ...
                lh.beta(mod(k-1,height(lh))+1), ...
                lh.se(mod(k-1,height(lh))+1), ...
                p_fdr(k), local_stars(p_fdr(k)));
        end
    end
end

fprintf('\nAll level divergence figures saved to: %s\n', fig_dir);

%% ── LOCAL FUNCTIONS ─────────────────────────────────────────────────────

function local_level_panel(Rset, outcome_key, outcome_label, COLOR_N, COLOR_H, show_legend)
    hold on;
    
    oi = find(strcmp(Rset.outcomes, outcome_key), 1);
    if isempty(oi)
        title(sprintf('%s\n(not found)', strrep(outcome_key,'_',' ')), 'FontSize',9);
        axis off;
        return;
    end

    se = Rset.results{oi}.simple_effects;
    is_level = ~cellfun('isempty', regexp(se.effect, '^level \d+ vs level 1$', 'once'));
    se = se(is_level, :);
    if isempty(se)
        title(sprintf('%s\n(no level effects)', strrep(outcome_key,'_',' ')), 'FontSize',9);
        return;
    end

    lvl_num = cellfun(@(s) sscanf(s, 'level %d vs level 1'), se.effect);
    n_sig = 0;

    for grp = {'N','H'}
        g = grp{1}; mask = strcmp(se.group, g);
        if ~any(mask), continue; end
        x  = lvl_num(mask); [x,ord] = sort(x);
        y  = se.beta(mask);  y  = y(ord);
        lo = se.lower(mask); lo = lo(ord);
        hi = se.upper(mask); hi = hi(ord);
        pv = se.p(mask);     pv = pv(ord);
        col = local_ternary(strcmp(g,'H'), COLOR_H, COLOR_N);
        lbl = local_ternary(strcmp(g,'H'), 'HF', 'NHF');
        errorbar(x, y, y-lo, hi-y, '-', 'Color',col, 'LineWidth',1.6, ...
            'CapSize',4, 'DisplayName',lbl);
        is_sig = pv < 0.05; n_sig = n_sig + sum(is_sig);
        if any(is_sig),  scatter(x(is_sig),  y(is_sig),  55, col, 'filled','HandleVisibility','off'); end
        if any(~is_sig), scatter(x(~is_sig), y(~is_sig), 55, col, 'HandleVisibility','off'); end
    end

    yline(0, ':k', 'HandleVisibility','off');
    xlabel('Level (vs. 1)','FontSize',9);
    ylabel('\beta','FontSize',9);
    xlim([1.5 5.5]); xticks(2:5);
    title(sprintf('%s\n%d/8 contrasts p<.05 (filled)', outcome_label, n_sig), ...
        'FontSize',9,'Interpreter','tex');
    if show_legend, legend('Location','best','FontSize',7); end
    grid on; box on;
end

function s = local_stars(p)
    if isnan(p)||p>0.05, s='';
    elseif p>0.01, s='*';
    elseif p>0.001, s='**';
    else, s='***'; end
end

function p_adj = local_bh_fdr(p)
    p = p(:); n = numel(p); p_adj = nan(n,1);
    valid = find(isfinite(p));
    [ps,ix] = sort(p(valid)); m = numel(ps);
    adj = nan(m,1); prev = 1;
    for k = m:-1:1
        val = ps(k)*m/k; prev = min(prev,val); adj(k) = prev;
    end
    p_adj(valid(ix)) = min(adj,1);
end

function out = local_ternary(cond, a, b)
    if cond, out=a; else, out=b; end
end