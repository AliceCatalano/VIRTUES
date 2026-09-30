function results = lmm_tssv_tssf_analysis(cfg)

    fv = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); FV = fv.T;

    metrics   = {'tssv','tssf'};
    results   = struct();

    for mi = 1:2
        oc = metrics{mi};
        fprintf('\n==============================\n=== LMM: log-%s ===\n==============================\n',upper(oc));

        TR = FV(strcmp(FV.phase_type,'training') & isfinite(FV.(oc)) & FV.(oc)>0, :);
        TR.log_metric = log(TR.(oc));

        n_edge=3; n_reps=cfg.n_training_reps;
        timing_vec=repmat("mid",height(TR),1);
        timing_vec(ismember(TR.repetition,1:n_edge))                 = "start";
        timing_vec(ismember(TR.repetition,(n_reps-n_edge+1):n_reps)) = "end";
        TR.timing=categorical(timing_vec,{'start','end','mid'});
        TR=TR(TR.timing~='mid',:);
        TR.timing=removecats(TR.timing,'mid');

        agg=varfun(@(x) mean(x,'omitnan'),TR, ...
            'GroupingVariables',{'subject','group','haptic','level','timing'}, ...
            'InputVariables',{'log_metric'}, ...
            'OutputFormat','table');
        agg.Properties.VariableNames=strrep(agg.Properties.VariableNames,'Fun_','');
        agg.GroupCount=[];

        agg.haptic_cat = categorical(agg.group,{'N','H'});
        agg.session    = reordercats(categorical(agg.level),{'1','2','3','4','5'});
        agg.timing     = categorical(agg.timing,{'start','end'});
        agg.subject    = categorical(agg.subject);

        lme=fitlme(agg,'log_metric ~ 1 + haptic_cat*session + timing + (1|subject)', ...
            'FitMethod','REML','DummyVarCoding','reference','Verbose',false);

        fprintf('\n--- Fixed Effects ---\n');
        disp(dataset2table(lme.Coefficients));
        fprintf('\n--- ANOVA ---\n');
        disp(anova(lme));

        ph=posthoc_per_session(lme,oc);

        results.(oc).agg_table    = agg;
        results.(oc).lme          = lme;
        results.(oc).posthoc      = ph;
    end

    save(fullfile(cfg.output_root,'lmm_tssv_tssf_results.mat'),'results');
    fprintf('\nSaved lmm_tssv_tssf_results.mat\n');
    plot_results(results,cfg);
end

% -------------------------------------------------------------------------
function ph = posthoc_per_session(lme, label)
    sessions={'1','2','3','4','5'}; n=numel(sessions);
    ph=table('Size',[n 7],'VariableTypes',{'string','double','double','double','double','double','double'}, ...
        'VariableNames',{'session','delta','SE','tStat','df','p_raw','p_bonf'});
    cnames=lme.CoefficientNames; beta=lme.Coefficients.Estimate; V=lme.CoefficientCovariance;
    for si=1:n
        lv=sessions{si}; C=zeros(1,numel(cnames));
        ih=find(strcmp(cnames,'haptic_cat_H'));
        ii=find(strcmp(cnames,sprintf('haptic_cat_H:session_%s',lv)));
        if ~isempty(ih), C(ih)=1; end
        if ~isempty(ii), C(ii)=1; end
        delta=C*beta; se_est=sqrt(C*V*C');
        [p,~,~,df2]=coefTest(lme,C);
        ph.session(si)=lv; ph.delta(si)=delta; ph.SE(si)=se_est;
        ph.tStat(si)=delta/se_est; ph.df(si)=df2; ph.p_raw(si)=p;
    end
    ph.p_bonf=min(ph.p_raw*n,1);
    fprintf('\nPost-hoc H-NHF per session (%s):\n',label);
    fprintf('  %-8s %8s %8s %8s %8s %8s %8s\n','session','delta','SE','t','df','p_raw','p_bonf');
    for si=1:n
        fprintf('  %-8s %8.3f %8.3f %8.3f %8.1f %8.4f %8.4f\n', ...
            ph.session(si),ph.delta(si),ph.SE(si),ph.tStat(si),ph.df(si),ph.p_raw(si),ph.p_bonf(si));
    end
end

% -------------------------------------------------------------------------
function plot_results(results, cfg)
    CN=[64 96 179]/255; CH=[139 82 168]/255;
    fig_dir=fullfile(cfg.output_root,'figures');
    if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

    metrics  = {'tssv','tssf'};
    ylabels  = {'log-TSSV (log (m s^{-2})^2 s)','log-TSSF (log N^2)'};

    for mi = 1:2
        oc  = metrics{mi};
        agg = results.(oc).agg_table;
        ph  = results.(oc).posthoc;
        sessions=1:5;

        % P1: observed means by session x timing
        fig=figure('Position',[50 50 1000 420]);
        tl=tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
        title(tl,sprintf('LMM observed means — log-%s (mean \\pm 95%% CI)',upper(oc)),'FontWeight','bold','FontSize',11);
        for ti=1:2
            t_lbl=local_ternary(ti==1,'start','end');
            nexttile; hold on;
            mu_N=nan(1,5); se_N=nan(1,5); mu_H=nan(1,5); se_H=nan(1,5);
            for lv=sessions
                vN=agg.log_metric(agg.haptic_cat=='N'&agg.session==string(lv)&agg.timing==t_lbl);
                vH=agg.log_metric(agg.haptic_cat=='H'&agg.session==string(lv)&agg.timing==t_lbl);
                vN=vN(isfinite(vN)); vH=vH(isfinite(vH));
                if ~isempty(vN), mu_N(lv)=mean(vN); se_N(lv)=std(vN)/sqrt(numel(vN)); end
                if ~isempty(vH), mu_H(lv)=mean(vH); se_H(lv)=std(vH)/sqrt(numel(vH)); end
            end
            fill([sessions fliplr(sessions)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
            fill([sessions fliplr(sessions)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
            plot(sessions,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
            plot(sessions,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
            set(gca,'XTick',1:5,'XTickLabel',{'L1','L2','L3','L4','L5'},'FontSize',9);
            xlabel('Training level'); ylabel(ylabels{mi},'FontSize',9);
            title(sprintf('Timing: %s',t_lbl)); legend('Location','best','FontSize',9); grid on; box on;
        end
        exportgraphics(fig,fullfile(fig_dir,sprintf('lmm_%s_P1_observed.png',oc)),'Resolution',180);

        % P2: post-hoc forest plot
        n=height(ph);
        fig2=figure('Position',[50 50 520 400]); hold on;
        yline(0,'k--','LineWidth',1.2,'HandleVisibility','off');
        for si=1:n
            col=local_ternary(ph.p_bonf(si)<0.05,[0.8 0.2 0.2],[0.5 0.5 0.5]);
            errorbar(si,ph.delta(si),1.96*ph.SE(si),'o','Color',col,'MarkerFaceColor',col,'LineWidth',1.8,'MarkerSize',8,'HandleVisibility','off');
            sig=local_stars(ph.p_bonf(si));
            if ~isempty(sig), text(si,ph.delta(si)+1.96*ph.SE(si)+0.03,sig,'HorizontalAlignment','center','FontSize',13,'Color',col); end
        end
        set(gca,'XTick',1:n,'XTickLabel',arrayfun(@(s)sprintf('L%s',s),ph.session,'UniformOutput',false),'FontSize',9);
        xlabel('Training level'); ylabel('\Delta (HF − NHF) log-units','FontSize',9);
        title(sprintf('Post-hoc: HF − NHF per session — log-%s (±95%% CI, Bonferroni)',upper(oc)),'FontSize',10);
        h1p=plot(nan,nan,'o','Color',[0.8 0.2 0.2],'MarkerFaceColor',[0.8 0.2 0.2],'DisplayName','p_{Bonf}<0.05');
        h2p=plot(nan,nan,'o','Color',[0.5 0.5 0.5],'MarkerFaceColor',[0.5 0.5 0.5],'DisplayName','n.s.');
        legend([h1p h2p],'Location','best','FontSize',8); grid on; box on;
        exportgraphics(fig2,fullfile(fig_dir,sprintf('lmm_%s_P2_posthoc.png',oc)),'Resolution',180);
    end
    fprintf('LMM figures saved to %s\n',fig_dir);
end

% -------------------------------------------------------------------------
function s = local_stars(p)
    if isnan(p)||p>0.05, s=''; elseif p>0.01, s='*'; elseif p>0.001, s='**'; else, s='***'; end
end
function out = local_ternary(c,a,b), if c, out=a; else, out=b; end, end