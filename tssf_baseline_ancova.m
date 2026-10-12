%% tssf_tssv_baseline_change_and_ancova.m
% 1. Within-group paired test: BL1 vs BL2 for TSSV and TSSF
% 2. Between-group comparison of BL1→BL2 delta
% 3. ANCOVA for post-training phases controlling for BL1

clear; clc; close all; cfg = config();
CN = [64 96 179]/255; CH = [139 82 168]/255;
fig_dir = fullfile(cfg.output_root,'figures');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

FV = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); FV=FV.T;

metrics   = {'tssv','tssf'};
ylabels   = {'log-TSSV (log (m s^{-2})^2 s)','log-TSSF (log N^2)'};
all_results = struct();

for mi = 1:2
    oc = metrics{mi};
    fprintf('\n\n========== %s ==========\n',upper(oc));

    % get subject-level means per phase
    phases_needed = {'Baseline1','Baseline2','Test1','Test2'};
    subj_list = unique(FV.subject);
    n_subj    = numel(subj_list);

    D = table();
    D.subject  = subj_list;
    D.haptic   = false(n_subj,1);
    D.group    = repmat({'N'},n_subj,1);
    for ph = phases_needed
        D.(ph{1}) = nan(n_subj,1);
    end

    for si = 1:n_subj
        s  = subj_list{si};
        Ts = FV(strcmp(FV.subject,s),:);
        D.haptic(si) = any(Ts.haptic);
        D.group{si}  = Ts.group{1};
        for ph = phases_needed
            Tph = Ts(strcmp(Ts.phase,ph{1}) & isfinite(Ts.(oc)) & Ts.(oc)>0,:);
            if ~isempty(Tph)
                D.(ph{1})(si) = mean(log(Tph.(oc)),'omitnan');
            end
        end
    end
    D.haptic_num = double(D.haptic);
    D.haptic_cat = categorical(D.group,{'N','H'});

    %% 1. Within-group paired BL1 vs BL2
    fprintf('\n--- Within-group paired BL1 vs BL2 ---\n');
    for grp = [false true]
        glbl = local_ternary(grp,'HF','NHF');
        mask = D.haptic==grp;
        pre  = D.Baseline1(mask); post = D.Baseline2(mask);
        keep = isfinite(pre)&isfinite(post);
        pre=pre(keep); post=post(keep);
        delta=post-pre;
        [~,p_paired]=ttest(delta);
        [p_wilc]=signrank(delta);
        sp=std(delta,'omitnan')/sqrt(numel(delta));
        d_paired=mean(delta,'omitnan')/std(delta,'omitnan');
        fprintf('%s: n=%d  mean_BL1=%.3f  mean_BL2=%.3f  delta=%.3f  t-test p=%.4f  Wilcoxon p=%.4f  d=%.3f\n',...
            glbl,numel(delta),mean(pre,'omitnan'),mean(post,'omitnan'),mean(delta,'omitnan'),p_paired,p_wilc,d_paired);
        all_results.(oc).within.(glbl) = struct('delta',delta,'p_paired',p_paired,'p_wilc',p_wilc,'d',d_paired,'n',numel(delta));
    end

    %% 2. Between-group comparison of BL1→BL2 delta
    fprintf('\n--- Between-group comparison of BL1→BL2 delta ---\n');
    dN = D.Baseline2(~D.haptic)-D.Baseline1(~D.haptic);
    dH = D.Baseline2( D.haptic)-D.Baseline1( D.haptic);
    dN=dN(isfinite(dN)); dH=dH(isfinite(dH));
    [~,p_delta]=ttest2(dH,dN,'Vartype','unequal');
    p_delta_w=ranksum(dH,dN);
    sp=sqrt(((numel(dN)-1)*var(dN)+(numel(dH)-1)*var(dH))/(numel(dN)+numel(dH)-2));
    d_delta=(mean(dH,'omitnan')-mean(dN,'omitnan'))/sp*(1-3/(4*(numel(dN)+numel(dH)-2)-1));
    fprintf('NHF delta: mean=%.3f  SD=%.3f  n=%d\n',mean(dN,'omitnan'),std(dN,'omitnan'),numel(dN));
    fprintf('HF  delta: mean=%.3f  SD=%.3f  n=%d\n',mean(dH,'omitnan'),std(dH,'omitnan'),numel(dH));
    fprintf('Between-group delta comparison: t-test p=%.4f  Wilcoxon p=%.4f  d=%.3f\n',p_delta,p_delta_w,d_delta);
    all_results.(oc).between_delta = struct('p_ttest',p_delta,'p_wilc',p_delta_w,'d',d_delta);

    %% 3. ANCOVA for Baseline2 and Test2 controlling for Baseline1
    fprintf('\n--- ANCOVA: post-training phases controlling for Baseline1 ---\n');
    for ph = {'Baseline2','Test2'}
        ph_name = ph{1};
        keep = isfinite(D.Baseline1) & isfinite(D.(ph_name));
        Danc = D(keep,:);
        n_tot = height(Danc);

        % unadjusted
        [~,p_unadj]=ttest2(Danc.(ph_name)(~Danc.haptic),Danc.(ph_name)(Danc.haptic),'Vartype','unequal');
        xN=Danc.(ph_name)(~Danc.haptic); xH=Danc.(ph_name)(Danc.haptic);
        sp=sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
        d_unadj=(mean(xH,'omitnan')-mean(xN,'omitnan'))/sp*(1-3/(4*(numel(xN)+numel(xH)-2)-1));

        % ANCOVA
        mdl=fitlm(Danc,sprintf('%s ~ haptic_num + Baseline1',ph_name));
        beta_h = mdl.Coefficients.Estimate(strcmp(mdl.CoefficientNames,'haptic_num'));
        se_h   = mdl.Coefficients.SE(strcmp(mdl.CoefficientNames,'haptic_num'));
        p_adj  = mdl.Coefficients.pValue(strcmp(mdl.CoefficientNames,'haptic_num'));
        t_adj  = mdl.Coefficients.tStat(strcmp(mdl.CoefficientNames,'haptic_num'));
        beta_bl1 = mdl.Coefficients.Estimate(strcmp(mdl.CoefficientNames,'Baseline1'));
        p_bl1    = mdl.Coefficients.pValue(strcmp(mdl.CoefficientNames,'Baseline1'));
        r2       = mdl.Rsquared.Ordinary;

        fprintf('\n%s (n=%d):\n',ph_name,n_tot);
        fprintf('  Unadjusted: d=%.3f  p=%.4f\n',d_unadj,p_unadj);
        fprintf('  ANCOVA:     beta_haptic=%.3f  SE=%.3f  t=%.3f  p=%.4f\n',beta_h,se_h,t_adj,p_adj);
        fprintf('  BL1 covariate: beta=%.3f  p=%.4f  R²=%.3f\n',beta_bl1,p_bl1,r2);

        if p_unadj<0.05 && p_adj>=0.05
            verdict='SIGNIFICANCE LOST — original result explained by BL1 pre-existing difference';
        elseif p_unadj>=0.05 && p_adj<0.05
            verdict='SIGNIFICANCE GAINED after adjustment';
        elseif p_unadj<0.05 && p_adj<0.05
            verdict='SIGNIFICANT both unadjusted and adjusted — robust to pre-existing difference';
        else
            verdict='Non-significant both ways';
        end
        fprintf('  Verdict: %s\n',verdict);
        all_results.(oc).ancova.(ph_name)=struct('p_unadj',p_unadj,'d_unadj',d_unadj,...
            'p_adj',p_adj,'beta_h',beta_h,'se_h',se_h,'beta_bl1',beta_bl1,'p_bl1',p_bl1,'r2',r2,'verdict',verdict);
    end

    %% Figure: BL1 vs BL2 paired lines + delta comparison
    fig=figure('Position',[2000 2000 1100 420]);
    tl=tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
    title(tl,sprintf('%s — Baseline1 vs Baseline2: within-group change and delta comparison',upper(oc)),...
        'FontWeight','bold','FontSize',11);

    % Panel 1: paired lines NHF
    nexttile; hold on;
    title('NHF: BL1→BL2 (individual + mean±95%CI)','FontSize',9);
    mask=~D.haptic; pre=D.Baseline1(mask); post=D.Baseline2(mask);
    keep=isfinite(pre)&isfinite(post);
    pre=pre(keep); post=post(keep);
    jx=1+(rand(numel(pre),1)-0.5)*0.1;
    for k=1:numel(pre), plot([jx(k) jx(k)+1],[pre(k) post(k)],'-','Color',[CN 0.2],'LineWidth',0.8,'HandleVisibility','off'); end
    errorbar([1 2],[mean(pre,'omitnan') mean(post,'omitnan')],...
        [std(pre,'omitnan') std(post,'omitnan')]./sqrt([numel(pre) numel(post)])*1.96,...
        '-o','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',9,'DisplayName','NHF');
    r=all_results.(oc).within.NHF;
    text(1.5,max([pre;post])+0.2,sprintf('paired p=%.4f\nd=%.3f',r.p_paired,r.d),...
        'HorizontalAlignment','center','FontSize',8,'Color',[0.3 0.3 0.3]);
    xticks([1 2]); xticklabels({'BL1','BL2'}); ylabel(ylabels{mi},'FontSize',9);
    xlim([0.5 2.5]); grid on; box on;

    % Panel 2: paired lines HF
    nexttile; hold on;
    title('HF: BL1→BL2 (individual + mean±95%CI)','FontSize',9);
    mask=D.haptic; pre=D.Baseline1(mask); post=D.Baseline2(mask);
    keep=isfinite(pre)&isfinite(post);
    pre=pre(keep); post=post(keep);
    jx=1+(rand(numel(pre),1)-0.5)*0.1;
    for k=1:numel(pre), plot([jx(k) jx(k)+1],[pre(k) post(k)],'-','Color',[CH 0.2],'LineWidth',0.8,'HandleVisibility','off'); end
    errorbar([1 2],[mean(pre,'omitnan') mean(post,'omitnan')],...
        [std(pre,'omitnan') std(post,'omitnan')]./sqrt([numel(pre) numel(post)])*1.96,...
        '-o','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',9,'DisplayName','HF');
    r=all_results.(oc).within.HF;
    text(1.5,max([pre;post])+0.2,sprintf('paired p=%.4f\nd=%.3f',r.p_paired,r.d),...
        'HorizontalAlignment','center','FontSize',8,'Color',[0.3 0.3 0.3]);
    xticks([1 2]); xticklabels({'BL1','BL2'}); ylabel(ylabels{mi},'FontSize',9);
    xlim([0.5 2.5]); grid on; box on;

    % Panel 3: delta comparison
    nexttile; hold on;
    title('BL2-BL1 delta: NHF vs HF','FontSize',9);
    dN=all_results.(oc).within.NHF.delta;
    dH=all_results.(oc).within.HF.delta;
    scatter(ones(numel(dN),1)+(rand(numel(dN),1)-0.5)*0.2,dN,22,CN,'filled','MarkerFaceAlpha',0.5,'HandleVisibility','off');
    scatter(2*ones(numel(dH),1)+(rand(numel(dH),1)-0.5)*0.2,dH,22,CH,'filled','MarkerFaceAlpha',0.5,'HandleVisibility','off');
    errorbar(1,mean(dN,'omitnan'),std(dN,'omitnan')/sqrt(numel(dN))*1.96,'o','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',9,'DisplayName','NHF');
    errorbar(2,mean(dH,'omitnan'),std(dH,'omitnan')/sqrt(numel(dH))*1.96,'o','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',9,'DisplayName','HF');
    yline(0,'k--','LineWidth',1,'HandleVisibility','off');
    r=all_results.(oc).between_delta;
    text(1.5,max([dN;dH])+0.2,sprintf('NvsH p=%.4f\nd=%.3f',r.p_ttest,r.d),...
        'HorizontalAlignment','center','FontSize',8,'Color',[0.3 0.3 0.3]);
    xticks([1 2]); xticklabels({'NHF','HF'}); ylabel(sprintf('\\Delta log-%s (BL2-BL1)',upper(oc)),'FontSize',9);
    xlim([0.5 2.5]); grid on; box on; legend('Location','best','FontSize',9);
    exportgraphics(fig,fullfile(fig_dir,sprintf('%s_baseline_change_ancova.png',oc)),'Resolution',180);
end

save(fullfile(cfg.output_root,'tssf_tssv_baseline_ancova.mat'),'all_results');
fprintf('\nSaved tssf_tssv_baseline_ancova.mat\n');

function out=local_ternary(c,a,b), if c,out=a; else,out=b; end, end