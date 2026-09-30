%% generate_all_report_figures.m
clear; clc; close all; cfg = config();
fig_dir = fullfile(cfg.output_root,'figures');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end
CN = [64 96 179]/255; CH = [139 82 168]/255;
fprintf('=== Generating all report figures ===\n\n');

%% ── FIX 1: column name patch ─────────────────────────────────────────────
% force_vibration_features.mat now has 'tssf' not 'tssf_raw'
% patch the table once so all downstream functions work
fv_path = fullfile(cfg.output_root,'force_vibration_features.mat');
if isfile(fv_path)
    FV_raw = load(fv_path,'T'); FV_patch = FV_raw.T;
    if ismember('tssf',FV_patch.Properties.VariableNames) && ~ismember('tssf_raw',FV_patch.Properties.VariableNames)
        FV_patch.tssf_raw = FV_patch.tssf;
        save(fv_path,'FV_patch','-append');
        % reload with correct variable name
        save(fv_path,'-struct','FV_raw');
        FV_patch2.T = FV_patch;
        save(fv_path,'-struct','FV_patch2');
        fprintf('Patched force_vibration_features.mat: added tssf_raw alias\n');
    end
end

%% ── SECTION 1: Signal quality and preprocessing figures ─────────────────
fprintf('\n--- Section 1: Signal quality ---\n');
try; sensor_quality_check; fprintf('Sensor quality done.\n'); catch ME; fprintf('SKIP: %s\n',ME.message); end
try; accel_timestamp_quality; fprintf('Timestamp quality done.\n'); catch ME; fprintf('SKIP: %s\n',ME.message); end

%% ── SECTION 2: EDA hypothesis figures ───────────────────────────────────
fprintf('\n--- Section 2: EDA figures ---\n');
try; run('summary_plots.m'); fprintf('EDA summary done.\n'); catch ME; fprintf('SKIP summary_plots: %s\n',ME.message); end

%% ── SECTION 3: Eye tracking figures ─────────────────────────────────────
fprintf('\n--- Section 3: Eye tracking figures ---\n');
try; eye_hypotheses; fprintf('Eye hypotheses done.\n'); catch ME; fprintf('SKIP eye_hypotheses: %s\n',ME.message); end

%% ── SECTION 4: TSSV/TSSF hypothesis figures ─────────────────────────────
fprintf('\n--- Section 4: TSSV/TSSF hypothesis figures ---\n');
try
    FV = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); FV=FV.T;
    CI = load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact'); CI=CI.T_impact;
    tssv_tssf_hypotheses_and_plots(FV,CI,cfg);
    fprintf('TSSV/TSSF hypotheses done.\n');
catch ME; fprintf('SKIP tssv_tssf_hypotheses: %s\n',ME.message); end

%% ── SECTION 5: LMM figures ───────────────────────────────────────────────
fprintf('\n--- Section 5: LMM figures ---\n');
try
    lmm_tssv_tssf_analysis(cfg);
    fprintf('LMM done.\n');
catch ME; fprintf('SKIP lmm: %s\n',ME.message); end

%% ── SECTION 6: Baseline1 TSSF ANCOVA ────────────────────────────────────
fprintf('\n--- Section 6: Baseline1 TSSF ANCOVA ---\n');
try
    FV_c = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); FV_c=FV_c.T;
    local_tssf_ancova(FV_c,CN,CH,fig_dir);
    fprintf('ANCOVA done.\n');
catch ME; fprintf('SKIP ancova: %s\n',ME.message); end

%% ── SECTION 7: Cross-modality figures ───────────────────────────────────
fprintf('\n--- Section 7: Cross-modality figures ---\n');
try
    results_cm = cross_modality_tssv_tssf_eda_pupil(cfg);
    fprintf('Cross-modality done.\n');
catch ME; fprintf('SKIP cross_modality: %s\n',ME.message); end

%% ── SECTION 8: H2 corrected (audio intensity bins) ──────────────────────
fprintf('\n--- Section 8: H2 corrected ---\n');
try
    CI2 = load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact'); CI2=CI2.T_impact;
    h2_tssv_tssf_corrected_fn(CI2,cfg,CN,CH,fig_dir);
    fprintf('H2 corrected done.\n');
catch ME; fprintf('SKIP h2_corrected: %s\n',ME.message); end

%% ── SECTION 9: Performance figures ──────────────────────────────────────
fprintf('\n--- Section 9: Performance figures ---\n');
try
    T_perf = load(fullfile(cfg.output_root,'perf_features.mat'),'T'); T_perf=T_perf.T;
    local_perf_figures(T_perf,CN,CH,fig_dir);
    fprintf('Performance figures done.\n');
catch ME; fprintf('SKIP perf figures: %s\n',ME.message); end

%% ── SECTION 10: Existing plot functions ─────────────────────────────────
fprintf('\n--- Section 10: Existing plot functions ---\n');
fns = {
    @()plot_learning_curves(cfg),           'learning_curves'
    @()plot_learning_curves_levels(cfg),    'learning_curves_levels'
    @()plot_level_divergence(cfg),          'level_divergence'
    @()plot_transfer_curves(cfg),           'transfer_curves'
    @()plot_transfer_paired_estimation(cfg),'transfer_paired'
    @()plot_sessiontiming_paired_estimation(cfg),'sessiontiming'
    @()plot_layer1_levels(cfg),             'layer1_levels'
};
for fi=1:size(fns,1)
    try; fns{fi,1}(); fprintf('  %s done.\n',fns{fi,2});
    catch ME; fprintf('  SKIP %s: %s\n',fns{fi,2},ME.message); end
end

fprintf('\n=== All figures done. Saved to %s ===\n',fig_dir);

%% ── LOCAL FUNCTIONS ──────────────────────────────────────────────────────

function local_tssf_ancova(FV,CN,CH,fig_dir)
% Baseline1 TSSF ANCOVA: does post-training TSSF group difference survive
% controlling for pre-training (Baseline1) TSSF?

    fprintf('\n=== Baseline1 TSSF ANCOVA ===\n');
    % get subject-level mean log-TSSF at each phase
    phases = {'Baseline1','Baseline2','Test2'};
    subj_list = unique(FV.subject);
    D = table();
    D.subject = subj_list;
    D.haptic  = false(numel(subj_list),1);
    D.group   = repmat({'N'},numel(subj_list),1);

    for ph = phases
        col = nan(numel(subj_list),1);
        for si=1:numel(subj_list)
            s=subj_list{si};
            Ts=FV(strcmp(FV.subject,s)&strcmp(FV.phase,ph{1})&isfinite(FV.tssf)&FV.tssf>0,:);
            if ~isempty(Ts), col(si)=mean(log(Ts.tssf),'omitnan'); end
        end
        D.(sprintf('log_tssf_%s',strrep(ph{1},'1','_pre'))) = col;
        if strcmp(ph{1},'Baseline1')
            for si=1:numel(subj_list)
                s=subj_list{si};
                Ts=FV(strcmp(FV.subject,s),:);
                D.haptic(si)=any(Ts.haptic);
                D.group{si}=FV.group{find(strcmp(FV.subject,s),1)};
            end
        end
    end
    D.haptic_num = double(D.haptic);
    D.haptic_cat = categorical(D.group,{'N','H'});

    bl1 = D.log_tssf_Baseline__pre;
    bl2_col = 'log_tssf_Baseline__pre'; % need to rebuild
    % simpler: extract directly
    bl1_v=nan(numel(subj_list),1); bl2_v=nan(numel(subj_list),1); te2_v=nan(numel(subj_list),1);
    for si=1:numel(subj_list)
        s=subj_list{si};
        Tbl1=FV(strcmp(FV.subject,s)&strcmp(FV.phase,'Baseline1')&isfinite(FV.tssf)&FV.tssf>0,:);
        Tbl2=FV(strcmp(FV.subject,s)&strcmp(FV.phase,'Baseline2')&isfinite(FV.tssf)&FV.tssf>0,:);
        Tte2=FV(strcmp(FV.subject,s)&strcmp(FV.phase,'Test2')&isfinite(FV.tssf)&FV.tssf>0,:);
        if ~isempty(Tbl1), bl1_v(si)=mean(log(Tbl1.tssf),'omitnan'); end
        if ~isempty(Tbl2), bl2_v(si)=mean(log(Tbl2.tssf),'omitnan'); end
        if ~isempty(Tte2), te2_v(si)=mean(log(Tte2.tssf),'omitnan'); end
    end

    % ANCOVA: post ~ haptic + baseline1 (removes pre-existing difference)
    for pair = {{'Baseline2',bl2_v},{'Test2',te2_v}}
        ph_name = pair{1}{1}; post_v = pair{1}{2};
        keep = isfinite(bl1_v) & isfinite(post_v);
        D_anc = table(bl1_v(keep),post_v(keep),D.haptic_num(keep),D.haptic_cat(keep), ...
            'VariableNames',{'bl1','post','haptic_num','haptic_cat'});
        lme_unadj = fitlm(D_anc,'post ~ haptic_num');
        lme_adj   = fitlm(D_anc,'post ~ haptic_num + bl1');
        fprintf('\n%s — unadjusted haptic p=%.4f, d=%.3f\n', ph_name, ...
            lme_unadj.Coefficients.pValue(2), ...
            lme_unadj.Coefficients.Estimate(2)/lme_unadj.RMSE);
        fprintf('%s — ANCOVA (controlling BL1) haptic p=%.4f, beta=%.3f\n', ph_name, ...
            lme_adj.Coefficients.pValue(2), lme_adj.Coefficients.Estimate(2));
    end

    % Figure: BL1 vs BL2 scatter coloured by group, ANCOVA regression lines
    fig=figure('Position',[50 50 900 420]);
    tl=tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
    title(tl,'TSSF ANCOVA: post-training controlling for Baseline1 (log scale)','FontWeight','bold','FontSize',11);
    for pi=1:2
        if pi==1, post_v=bl2_v; ph_name='Baseline2'; else, post_v=te2_v; ph_name='Test2'; end
        keep=isfinite(bl1_v)&isfinite(post_v);
        nexttile; hold on;
        for grp=[false true]
            idx=find(D.haptic==grp&keep); col=local_ternary(grp,CH,CN); lbl=local_ternary(grp,'HF','NHF');
            scatter(bl1_v(idx),post_v(idx),30,col,'filled','MarkerFaceAlpha',0.6,'DisplayName',lbl);
            pf=polyfit(bl1_v(idx),post_v(idx),1);
            xl=[min(bl1_v(keep)) max(bl1_v(keep))];
            plot(xl,polyval(pf,xl),'-','Color',col,'LineWidth',2,'HandleVisibility','off');
        end
        xlabel('log-TSSF Baseline1 (pre-training)','FontSize',9);
        ylabel(sprintf('log-TSSF %s (post-training)',ph_name),'FontSize',9);
        title(ph_name,'FontSize',10); legend('Location','best','FontSize',9); grid on; box on;
        refline(1,0);
    end
    exportgraphics(fig,fullfile(fig_dir,'tssf_ancova_baseline1.png'),'Resolution',180);
    fprintf('ANCOVA figure saved.\n');
end

function local_perf_figures(T_perf,CN,CH,fig_dir)
    % Rep-by-rep duration per level
    fig1=figure('Position',[50 50 1600 500]);
    tl=tiledlayout(1,5,'TileSpacing','compact','Padding','compact');
    title(tl,'Completion time — rep-by-rep within each training level (mean ± SE)','FontWeight','bold','FontSize',11);
    for lv=1:5
        Tlv=T_perf(strcmp(T_perf.phase_type,'training')&T_perf.level==lv&isfinite(T_perf.duration_s),:);
        nexttile; hold on;
        for grp=[false true]
            Tg=Tlv(Tlv.haptic==grp,:); col=local_ternary(grp,CH,CN); lbl=local_ternary(grp,'HF','NHF');
            subj_u=unique(Tg.subject); mat=nan(numel(subj_u),10);
            for si=1:numel(subj_u)
                for ri=1:10
                    v=Tg.duration_s(strcmp(Tg.subject,subj_u{si})&Tg.repetition==ri);
                    if ~isempty(v), mat(si,ri)=mean(v,'omitnan'); end
                end
            end
            mu=mean(mat,'omitnan'); se=std(mat,'omitnan')./sqrt(sum(isfinite(mat)));
            fill([1:10 fliplr(1:10)],[mu+se fliplr(mu-se)],col,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
            plot(1:10,mu,'o-','Color',col,'LineWidth',2,'MarkerFaceColor',col,'MarkerSize',5,'DisplayName',lbl);
        end
        set(gca,'XTick',1:10,'FontSize',8); xlabel('Repetition'); ylabel('Duration (s)','FontSize',8);
        title(sprintf('Level %d',lv),'FontSize',10); grid on; box on;
        if lv==1, legend('Location','best','FontSize',8); end
    end
    all_ax=findobj(fig1,'Type','Axes');
    yl=cell2mat(arrayfun(@(a)ylim(a),all_ax,'UniformOutput',false)');
    for a=all_ax', ylim(a,[min(yl(:,1)) max(yl(:,2))]); end
    exportgraphics(fig1,fullfile(fig_dir,'perf_duration_rep_by_rep.png'),'Resolution',180);

    % Collision count by level
    fig2=figure('Position',[50 50 700 400]); hold on;
    for grp=[false true]
        Tg=T_perf(T_perf.haptic==grp&strcmp(T_perf.phase_type,'training'),:);
        col=local_ternary(grp,CH,CN); lbl=local_ternary(grp,'HF','NHF');
        mu_lv=nan(1,5); se_lv=nan(1,5);
        for lv=1:5
            subj_u=unique(Tg.subject); xs=nan(numel(subj_u),1);
            for si=1:numel(subj_u)
                v=Tg.n_collisions(strcmp(Tg.subject,subj_u{si})&Tg.level==lv);
                if ~isempty(v), xs(si)=mean(v,'omitnan'); end
            end
            xs=xs(isfinite(xs)); mu_lv(lv)=mean(xs); se_lv(lv)=std(xs)/sqrt(numel(xs));
        end
        fill([1:5 fliplr(1:5)],[mu_lv+se_lv fliplr(mu_lv-se_lv)],col,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
        plot(1:5,mu_lv,'o-','Color',col,'LineWidth',2,'MarkerFaceColor',col,'MarkerSize',7,'DisplayName',lbl);
    end
    set(gca,'XTick',1:5,'XTickLabel',{'L1','L2','L3','L4','L5'},'FontSize',9);
    xlabel('Training level'); ylabel('Mean collisions per trial');
    title('Collision count by level — groups equivalent (mean ± SE)','FontSize',11);
    legend('Location','best','FontSize',9); grid on; box on;
    exportgraphics(fig2,fullfile(fig_dir,'perf_collision_count_levels.png'),'Resolution',180);

    % Pre/post paired — duration and collisions
    for oc={'duration_s','n_collisions'}
        oc=oc{1}; yl_str=local_ternary(strcmp(oc,'duration_s'),'Completion time (s)','Collisions per trial');
        fig3=figure('Position',[50 50 900 420]);
        tl=tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
        title(tl,sprintf('%s: pre vs post training',strrep(oc,'_',' ')),'FontWeight','bold','FontSize',11);
        pairs={{'Baseline1','Baseline2','baseline'},{'Test1','Test2','test'}};
        for pp=1:2
            ppre=pairs{pp}{1}; ppost=pairs{pp}{2}; ptype=pairs{pp}{3};
            Tpp=T_perf(strcmp(T_perf.phase_type,ptype)&ismember(T_perf.phase,{ppre,ppost})&isfinite(T_perf.(oc)),:);
            subj_u=unique(Tpp.subject);
            pre_v=nan(numel(subj_u),1); post_v=nan(numel(subj_u),1); ihs=false(numel(subj_u),1);
            for si=1:numel(subj_u)
                s=subj_u{si};
                pre_v(si)=mean(Tpp.(oc)(strcmp(Tpp.subject,s)&strcmp(Tpp.phase,ppre)),'omitnan');
                post_v(si)=mean(Tpp.(oc)(strcmp(Tpp.subject,s)&strcmp(Tpp.phase,ppost)),'omitnan');
                ihs(si)=any(Tpp.haptic(strcmp(Tpp.subject,s)));
            end
            keep=isfinite(pre_v)&isfinite(post_v);
            nexttile; hold on;
            for grp=[false true]
                idx=find(ihs==grp&keep); col=local_ternary(grp,CH,CN);
                jx=1+(rand(numel(idx),1)-0.5)*0.1;
                for k=1:numel(idx), plot([jx(k) jx(k)+1],[pre_v(idx(k)) post_v(idx(k))],'-','Color',[col 0.2],'LineWidth',0.8,'HandleVisibility','off'); end
                mu=[mean(pre_v(idx),'omitnan') mean(post_v(idx),'omitnan')];
                sem=[std(pre_v(idx),'omitnan') std(post_v(idx),'omitnan')]./sqrt(numel(idx))*1.96;
                errorbar([1 2]+local_ternary(grp,0.1,-0.1),mu,sem,'-o','Color',col,'LineWidth',2,'MarkerFaceColor',col,'MarkerSize',8,'DisplayName',local_ternary(grp,'HF','NHF'));
            end
            xlim([0.5 2.5]); xticks([1 2]); xticklabels({ppre,ppost});
            ylabel(yl_str,'FontSize',9); title(sprintf('%s phase',ptype),'FontSize',10);
            if pp==1, legend('Location','best','FontSize',9); end
            grid on;
        end
        exportgraphics(fig3,fullfile(fig_dir,sprintf('perf_%s_pre_post.png',oc)),'Resolution',180);
    end
end

function out=local_ternary(c,a,b), if c,out=a; else,out=b; end, end