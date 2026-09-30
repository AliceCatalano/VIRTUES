%% tssv_tssf_hypotheses_and_plots.m
clear; clc; close all; cfg = config();
CN = [64 96 179]/255; CH = [139 82 168]/255;
fig_dir = fullfile(cfg.output_root,'figures');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

FV = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); FV = FV.T;
CI = load(fullfile(cfg.output_root,'collision_impact_features.mat'),'T_impact'); CI = CI.T_impact;

all_results = struct();
metrics     = {'tssv','tssf'};
ylabels_raw = {'TSSV ((m s^{-2})^2 s)','TSSF (N^2)'};
ylabels_log = {'log-TSSV (log (m s^{-2})^2 s)','log-TSSF (log N^2)'};
imp_metrics = {'impact_tssv','impact_tssf'};
imp_ylabels = {'log-impact TSSV (log (m s^{-2})^2 s)','log-impact TSSF (log N^2)'};

for mi = 1:2
    oc     = metrics{mi};
    imp_oc = imp_metrics{mi};
    fprintf('\n\n========== %s ==========\n',upper(oc));

    %% === H1: group difference across all phases ===
    fprintf('\n=== H1: %s group difference across training levels ===\n',oc);
    TR = FV(strcmp(FV.phase_type,'training') & isfinite(FV.(oc)) & FV.(oc)>0,:);
    TR.log_m = log(TR.(oc));

    levels=1:5; lnames={'L1','L2','L3','L4','L5'};
    mu_N=nan(1,5); mu_H=nan(1,5); se_N=nan(1,5); se_H=nan(1,5);
    p_raw=nan(1,5); d_vec=nan(1,5); rows_h1={};

    for li=1:5
        Tl=TR(TR.level==li,:);
        subj=unique(Tl.subject); xs=nan(numel(subj),1); ihs=false(numel(subj),1);
        for si=1:numel(subj)
            s=subj{si};
            xs(si)=mean(Tl.log_m(strcmp(Tl.subject,s)),'omitnan');
            ihs(si)=any(Tl.haptic(strcmp(Tl.subject,s)));
        end
        xN=xs(~ihs&isfinite(xs)); xH=xs(ihs&isfinite(xs));
        mu_N(li)=mean(xN); mu_H(li)=mean(xH);
        se_N(li)=std(xN)/sqrt(numel(xN)); se_H(li)=std(xH)/sqrt(numel(xH));
        [~,p_raw(li)]=ttest2(xH,xN,'Vartype','unequal');
        sp=sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
        d_vec(li)=(mean(xH)-mean(xN))/sp*(1-3/(4*(numel(xN)+numel(xH)-2)-1));
        rows_h1(end+1,:)={li,numel(xN),numel(xH),mean(xN),mean(xH),p_raw(li),d_vec(li)};
        fprintf('L%d | n_N=%d n_H=%d | mean_N=%.3f mean_H=%.3f | d=%.3f p=%.4f\n', ...
            li,numel(xN),numel(xH),mean(xN),mean(xH),d_vec(li),p_raw(li));
    end
    p_fdr_h1=mafdr(p_raw(:),'BHFDR',true)';
    fprintf('FDR-corrected p: '); fprintf('%.4f  ',p_fdr_h1); fprintf('\n');
    T_h1=cell2table(rows_h1,'VariableNames',{'level','n_N','n_H','mean_N','mean_H','p_raw','cohens_d'});
    T_h1.p_fdr=p_fdr_h1(:); all_results.(oc).T_H1=T_h1;

    fprintf('\n--- H1: Baseline and Test phases ---\n');
    phases_bl={'Baseline1','Baseline2','Test1','Test2'}; xlbl={'BL1','BL2','T1','T2'};
    mu_Nb=nan(1,4); mu_Hb=nan(1,4); se_Nb=nan(1,4); se_Hb=nan(1,4); p_raw_b=nan(1,4);
    rows_h1b={};
    for pi=1:4
        Tph=FV(strcmp(FV.phase,phases_bl{pi})&isfinite(FV.(oc))&FV.(oc)>0,:);
        if isempty(Tph), continue; end
        Tph.log_m=log(Tph.(oc));
        subj=unique(Tph.subject); xs=nan(numel(subj),1); ihs=false(numel(subj),1);
        for si=1:numel(subj)
            s=subj{si};
            xs(si)=mean(Tph.log_m(strcmp(Tph.subject,s)),'omitnan');
            ihs(si)=any(Tph.haptic(strcmp(Tph.subject,s)));
        end
        xN=xs(~ihs&isfinite(xs)); xH=xs(ihs&isfinite(xs));
        mu_Nb(pi)=mean(xN); mu_Hb(pi)=mean(xH);
        se_Nb(pi)=std(xN)/sqrt(numel(xN)); se_Hb(pi)=std(xH)/sqrt(numel(xH));
        [~,p_raw_b(pi)]=ttest2(xH,xN,'Vartype','unequal');
        sp=sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
        d=(mean(xH)-mean(xN))/sp*(1-3/(4*(numel(xN)+numel(xH)-2)-1));
        fprintf('%s | n_N=%d n_H=%d | mean_N=%.3f mean_H=%.3f | d=%.3f p=%.4f\n', ...
            phases_bl{pi},numel(xN),numel(xH),mean(xN),mean(xH),d,p_raw_b(pi));
        rows_h1b(end+1,:)={phases_bl{pi},numel(xN),numel(xH),mean(xN),mean(xH),p_raw_b(pi),d};
    end
    p_fdr_b=mafdr(p_raw_b(:),'BHFDR',true)';
    T_h1b=cell2table(rows_h1b,'VariableNames',{'phase','n_N','n_H','mean_N','mean_H','p_raw','cohens_d'});
    T_h1b.p_fdr=p_fdr_b(:); all_results.(oc).T_H1_phases=T_h1b;

    %% === H1 Figures — log scale summary ===
    fig_h1sum=figure('Position',[50 50 900 420]);
    tl=tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
    title(tl,sprintf('H1: log-%s by phase — NHF vs HF (subject means ± 95%% CI)',upper(oc)), ...
        'FontWeight','bold','FontSize',11);
    nexttile; hold on;
    fill([levels fliplr(levels)],[mu_N+1.96*se_N fliplr(mu_N-1.96*se_N)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    fill([levels fliplr(levels)],[mu_H+1.96*se_H fliplr(mu_H-1.96*se_H)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    plot(levels,mu_N,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
    plot(levels,mu_H,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
    for li=1:5
        sig=local_stars(p_fdr_h1(li));
        if ~isempty(sig), text(li,max(mu_N(li)+1.96*se_N(li),mu_H(li)+1.96*se_H(li))+0.1,sig,'HorizontalAlignment','center','FontSize',13); end
        text(li,min(mu_N(li)-1.96*se_N(li),mu_H(li)-1.96*se_H(li))-0.15,sprintf('d=%.2f',d_vec(li)),'HorizontalAlignment','center','FontSize',7,'Color',[0.4 0.4 0.4]);
    end
    set(gca,'XTick',1:5,'XTickLabel',lnames,'FontSize',9);
    xlabel('Training level'); ylabel(ylabels_log{mi},'FontSize',9);
    legend('Location','best','FontSize',9); grid on; box on; title('Training levels','FontSize',10);

    nexttile; hold on;
    x4=1:4;
    fill([x4 fliplr(x4)],[mu_Nb+1.96*se_Nb fliplr(mu_Nb-1.96*se_Nb)],CN,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    fill([x4 fliplr(x4)],[mu_Hb+1.96*se_Hb fliplr(mu_Hb-1.96*se_Hb)],CH,'FaceAlpha',0.15,'EdgeColor','none','HandleVisibility','off');
    plot(x4,mu_Nb,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',7,'DisplayName','NHF');
    plot(x4,mu_Hb,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',7,'DisplayName','HF');
    for pi=1:4
        sig=local_stars(p_fdr_b(pi));
        if ~isempty(sig), text(pi,max(mu_Nb(pi)+1.96*se_Nb(pi),mu_Hb(pi)+1.96*se_Hb(pi))+0.1,sig,'HorizontalAlignment','center','FontSize',13); end
    end
    set(gca,'XTick',1:4,'XTickLabel',xlbl,'FontSize',9);
    xlabel('Phase'); ylabel(ylabels_log{mi},'FontSize',9);
    legend('Location','best','FontSize',9); grid on; box on; title('Baseline & Test','FontSize',10);
    exportgraphics(fig_h1sum,fullfile(fig_dir,sprintf('%s_H1_summary.png',oc)),'Resolution',180);

    %% === H1 Unfolded — rep-by-rep within each level (RAW scale) ===
    T_raw = FV(strcmp(FV.phase_type,'training')&isfinite(FV.(oc))&FV.(oc)>0,:);

    fig_rep=figure('Position',[50 50 1600 500]);
    tl_rep=tiledlayout(1,5,'TileSpacing','compact','Padding','compact');
    title(tl_rep,sprintf('%s — Rep-by-rep within each training level (raw, group mean ± SE + individual lines)',upper(oc)), ...
        'FontWeight','bold','FontSize',11);

    for lv=1:5
        Tlv=T_raw(T_raw.level==lv,:);
        subj_list=unique(Tlv.subject);
        mat_N=nan(numel(subj_list),cfg.n_training_reps);
        mat_H=nan(numel(subj_list),cfg.n_training_reps);
        is_H_l=false(numel(subj_list),1);
        for si=1:numel(subj_list)
            s=subj_list{si};
            Ts=Tlv(strcmp(Tlv.subject,s),:);
            is_H_l(si)=any(Ts.haptic);
            for ri=1:cfg.n_training_reps
                v=Ts.(oc)(Ts.repetition==ri);
                if ~isempty(v)
                    if is_H_l(si), mat_H(si,ri)=mean(v,'omitnan');
                    else,          mat_N(si,ri)=mean(v,'omitnan'); end
                end
            end
        end
        mu_lN=mean(mat_N,'omitnan'); se_lN=std(mat_N,'omitnan')./sqrt(sum(isfinite(mat_N)));
        mu_lH=mean(mat_H,'omitnan'); se_lH=std(mat_H,'omitnan')./sqrt(sum(isfinite(mat_H)));
        x=1:cfg.n_training_reps;

        nexttile; hold on;
        % individual subject lines
        for si=1:numel(subj_list)
            if is_H_l(si), col=CH; dat=mat_H(si,:);
            else,          col=CN; dat=mat_N(si,:); end
            plot(x,dat,'-','Color',[col 0.12],'LineWidth',0.6,'HandleVisibility','off');
        end
        fill([x fliplr(x)],[mu_lN+se_lN fliplr(mu_lN-se_lN)],CN,'FaceAlpha',0.2,'EdgeColor','none','HandleVisibility','off');
        fill([x fliplr(x)],[mu_lH+se_lH fliplr(mu_lH-se_lH)],CH,'FaceAlpha',0.2,'EdgeColor','none','HandleVisibility','off');
        plot(x,mu_lN,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',5,'DisplayName','NHF');
        plot(x,mu_lH,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',5,'DisplayName','HF');
        set(gca,'XTick',1:cfg.n_training_reps,'FontSize',8);
        xlabel('Repetition'); ylabel(ylabels_raw{mi},'FontSize',8);
        title(sprintf('Level %d',lv),'FontSize',10);
        if lv==1, legend('Location','best','FontSize',8); end
        grid on; box on;
    end
    exportgraphics(fig_rep,fullfile(fig_dir,sprintf('%s_rep_by_rep.png',oc)),'Resolution',180);

    %% === H1 Unfolded — full training sequence (rep 1-50) ===
    all_subj=unique(T_raw.subject);
    grand_N=nan(numel(all_subj),50); grand_H=nan(numel(all_subj),50);
    is_H_g=false(numel(all_subj),1);
    for si=1:numel(all_subj)
        s=all_subj{si};
        Ts=T_raw(strcmp(T_raw.subject,s),:);
        is_H_g(si)=any(Ts.haptic);
        for lv=1:5
            for ri=1:cfg.n_training_reps
                cidx=(lv-1)*cfg.n_training_reps+ri;
                v=Ts.(oc)(Ts.level==lv&Ts.repetition==ri);
                if ~isempty(v)
                    if is_H_g(si), grand_H(si,cidx)=mean(v,'omitnan');
                    else,          grand_N(si,cidx)=mean(v,'omitnan'); end
                end
            end
        end
    end
    x50=1:50;
    mu_N50=mean(grand_N,'omitnan'); se_N50=std(grand_N,'omitnan')./sqrt(sum(isfinite(grand_N)));
    mu_H50=mean(grand_H,'omitnan'); se_H50=std(grand_H,'omitnan')./sqrt(sum(isfinite(grand_H)));

    fig_seq=figure('Position',[50 50 1400 450]); hold on;
    for si=1:numel(all_subj)
        if is_H_g(si), col=CH; dat=grand_H(si,:);
        else,          col=CN; dat=grand_N(si,:); end
        plot(x50,dat,'-','Color',[col 0.1],'LineWidth',0.5,'HandleVisibility','off');
    end
    fill([x50 fliplr(x50)],[mu_N50+se_N50 fliplr(mu_N50-se_N50)],CN,'FaceAlpha',0.2,'EdgeColor','none','HandleVisibility','off');
    fill([x50 fliplr(x50)],[mu_H50+se_H50 fliplr(mu_H50-se_H50)],CH,'FaceAlpha',0.2,'EdgeColor','none','HandleVisibility','off');
    plot(x50,mu_N50,'o-','Color',CN,'LineWidth',2,'MarkerFaceColor',CN,'MarkerSize',4,'DisplayName','NHF');
    plot(x50,mu_H50,'o-','Color',CH,'LineWidth',2,'MarkerFaceColor',CH,'MarkerSize',4,'DisplayName','HF');
    for lv=1:4, xline(lv*10+0.5,'k:','LineWidth',1.2,'HandleVisibility','off'); end
    for lv=1:5
        text((lv-1)*10+5.5,max([mu_N50+se_N50 mu_H50+se_H50],[],'omitnan')*1.08, ...
            sprintf('L%d',lv),'HorizontalAlignment','center','FontSize',10,'Color',[0.35 0.35 0.35]);
    end
    set(gca,'XTick',(1:5)*10-4,'XTickLabel',{'L1','L2','L3','L4','L5'},'FontSize',9);
    xlabel('Training repetition (all levels unfolded)'); ylabel(ylabels_raw{mi},'FontSize',10);
    title(sprintf('%s — Full training sequence unfolded (raw, group mean ± SE + individual subject lines)',upper(oc)),'FontSize',11);
    legend('Location','best','FontSize',9); grid on; box on;
    exportgraphics(fig_seq,fullfile(fig_dir,sprintf('%s_full_sequence.png',oc)),'Resolution',180);

    %% === H1 Unfolded — Baseline levels (BL1 and BL2) ===
    fig_bl=figure('Position',[50 50 1000 450]);
    tl_bl=tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
    title(tl_bl,sprintf('%s — Baseline: 5 difficulty levels (raw, individual dots + group mean ± SE)',upper(oc)), ...
        'FontWeight','bold','FontSize',11);

    for bi=1:2
        bl_phase=sprintf('Baseline%d',bi);
        Tbl=FV(strcmp(FV.phase,bl_phase)&isfinite(FV.(oc))&FV.(oc)>0,:);
        nexttile; hold on;
        for grp=[false true]
            col=local_ternary(grp,CH,CN); lbl=local_ternary(grp,'HF','NHF');
            mu_bl=nan(1,5); se_bl=nan(1,5);
            Tg=Tbl(Tbl.haptic==grp,:); subj_g=unique(Tg.subject);
            for lv=1:5
                xs=nan(numel(subj_g),1);
                for si=1:numel(subj_g)
                    v=Tg.(oc)(strcmp(Tg.subject,subj_g{si})&Tg.level==lv);
                    if ~isempty(v), xs(si)=mean(v,'omitnan'); end
                end
                xs=xs(isfinite(xs));
                % individual dots
                jx=lv+local_ternary(grp,0.1,-0.1)+(rand(numel(xs),1)-0.5)*0.08;
                scatter(jx,xs,18,col,'filled','MarkerFaceAlpha',0.35,'HandleVisibility','off');
                mu_bl(lv)=mean(xs); se_bl(lv)=std(xs)/sqrt(numel(xs));
            end
            errorbar(1:5,mu_bl,se_bl,'o-','Color',col,'LineWidth',2, ...
                'MarkerFaceColor',col,'MarkerSize',7,'DisplayName',lbl);
        end
        set(gca,'XTick',1:5,'XTickLabel',{'L1','L2','L3','L4','L5'},'FontSize',9);
        xlabel('Baseline level (difficulty)'); ylabel(ylabels_raw{mi},'FontSize',9);
        title(sprintf('%s — note: levels reflect task difficulty, not training order',bl_phase),'FontSize',9);
        if bi==1, legend('Location','best','FontSize',9); end
        grid on; box on;
    end
    exportgraphics(fig_bl,fullfile(fig_dir,sprintf('%s_baseline_levels.png',oc)),'Resolution',180);

    %% === H1 Unfolded — Test phases ===
    fig_test=figure('Position',[50 50 700 420]);
    tl_test=tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
    title(tl_test,sprintf('%s — Test phases: NHF vs HF (raw, individual dots + mean ± SE)',upper(oc)), ...
        'FontWeight','bold','FontSize',11);
    for ti=1:2
        tph=sprintf('Test%d',ti);
        Ttest=FV(strcmp(FV.phase,tph)&isfinite(FV.(oc))&FV.(oc)>0,:);
        subj_t=unique(Ttest.subject);
        xN_t=nan(numel(subj_t),1); xH_t=nan(numel(subj_t),1); ihs_t=false(numel(subj_t),1);
        for si=1:numel(subj_t)
            s=subj_t{si}; v=Ttest.(oc)(strcmp(Ttest.subject,s));
            ihs_t(si)=any(Ttest.haptic(strcmp(Ttest.subject,s)));
            if ihs_t(si), xH_t(si)=mean(v,'omitnan');
            else,         xN_t(si)=mean(v,'omitnan'); end
        end
        xN_t=xN_t(~ihs_t&isfinite(xN_t)); xH_t=xH_t(ihs_t&isfinite(xH_t));
        nexttile; hold on;
        scatter(0.9+(rand(numel(xN_t),1)-0.5)*0.15,xN_t,22,CN,'filled','MarkerFaceAlpha',0.4,'HandleVisibility','off');
        scatter(1.9+(rand(numel(xH_t),1)-0.5)*0.15,xH_t,22,CH,'filled','MarkerFaceAlpha',0.4,'HandleVisibility','off');
        errorbar(1,mean(xN_t,'omitnan'),std(xN_t,'omitnan')/sqrt(numel(xN_t)),'o', ...
            'Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',9,'DisplayName','NHF');
        errorbar(2,mean(xH_t,'omitnan'),std(xH_t,'omitnan')/sqrt(numel(xH_t)),'o', ...
            'Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',9,'DisplayName','HF');
        xticks([1 2]); xticklabels({'NHF','HF'});
        ylabel(ylabels_raw{mi},'FontSize',9); title(tph,'FontSize',10);
        if ti==1, legend('Location','best','FontSize',9); end
        grid on; box on; xlim([0.5 2.5]);
    end
    exportgraphics(fig_test,fullfile(fig_dir,sprintf('%s_test_phases.png',oc)),'Resolution',180);

    %% === H2: variance by intensity bin ===
    fprintf('\n=== H2: %s variance by intensity bin (group-specific quartiles) ===\n',imp_oc);
    CI_tr=CI(strcmp(CI.phase_type,'training')&isfinite(CI.(imp_oc))&CI.(imp_oc)>0,:);
    CI_tr.log_impact=log(CI_tr.(imp_oc));
    qp=[0 0.25 0.50 0.75 1.0];
    edges_N=quantile(CI_tr.log_impact(~CI_tr.haptic),qp);
    edges_H=quantile(CI_tr.log_impact( CI_tr.haptic),qp);
    fprintf('NHF quartile edges: '); fprintf('%.3f  ',edges_N); fprintf('\n');
    fprintf('HF  quartile edges: '); fprintf('%.3f  ',edges_H); fprintf('\n');
    [~,~,binN]=histcounts(CI_tr.log_impact(~CI_tr.haptic),edges_N);
    [~,~,binH]=histcounts(CI_tr.log_impact( CI_tr.haptic),edges_H);
    CI_tr.bin=zeros(height(CI_tr),1);
    CI_tr.bin(~CI_tr.haptic)=binN; CI_tr.bin(CI_tr.haptic)=binH;
    n_bins=4; rows_h2={};
    for b=1:n_bins
        xN=CI_tr.log_impact(~CI_tr.haptic&CI_tr.bin==b); xN=xN(isfinite(xN));
        xH=CI_tr.log_impact( CI_tr.haptic&CI_tr.bin==b); xH=xH(isfinite(xH));
        sdN=std(xN); sdH=std(xH);
        p_lev=local_levene(xN,xH);
        [~,p_mu]=ttest2(xH,xN,'Vartype','unequal');
        sp=sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
        d=(mean(xH)-mean(xN))/sp*(1-3/(4*(numel(xN)+numel(xH)-2)-1));
        fprintf('Bin %d | n_N=%d n_H=%d | SD_N=%.3f SD_H=%.3f ratio=%.3f | Levene_p=%.4f mean_p=%.4f d=%.3f\n', ...
            b,numel(xN),numel(xH),sdN,sdH,sdN/sdH,p_lev,p_mu,d);
        rows_h2(end+1,:)={b,numel(xN),numel(xH),mean(xN),mean(xH),sdN,sdH,sdN/sdH,p_lev,p_mu,d};
    end
    T_h2=cell2table(rows_h2,'VariableNames',{'bin','n_N','n_H','mean_N','mean_H','sd_N','sd_H','ratio_sd','p_levene','p_mean','cohens_d'});
    T_h2.p_levene_fdr=mafdr(T_h2.p_levene,'BHFDR',true);
    T_h2.p_mean_fdr  =mafdr(T_h2.p_mean,'BHFDR',true);
    disp(T_h2(:,{'bin','n_N','n_H','mean_N','mean_H','sd_N','sd_H','ratio_sd','p_levene_fdr','p_mean_fdr','cohens_d'}));
    all_results.(oc).T_H2=T_h2;

    fig_h2=figure('Position',[50 50 1100 480]);
    tl_h2=tiledlayout(1,n_bins+1,'TileSpacing','compact','Padding','compact');
    title(tl_h2,sprintf('H2: log-%s variance by intensity bin (group-specific quartiles)',imp_oc),'FontWeight','bold','FontSize',11);
    for b=1:n_bins
        nexttile; hold on;
        xN=CI_tr.log_impact(~CI_tr.haptic&CI_tr.bin==b); xN=xN(isfinite(xN));
        xH=CI_tr.log_impact( CI_tr.haptic&CI_tr.bin==b); xH=xH(isfinite(xH));
        local_violin(xN,1,CN); local_violin(xH,2,CH);
        errorbar(1,mean(xN),std(xN)/sqrt(numel(xN))*1.96,'o','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');
        errorbar(2,mean(xH),std(xH)/sqrt(numel(xH))*1.96,'o','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',8,'HandleVisibility','off');
        ymax=max([xN;xH]); ymin=min([xN;xH]);
        sig=local_stars(T_h2.p_levene_fdr(b));
        if ~isempty(sig)
            yt=ymax+0.05*(ymax-ymin);
            plot([1 2],[yt yt],'k-','LineWidth',1,'HandleVisibility','off');
            text(1.5,yt+0.03*(ymax-ymin),sig,'HorizontalAlignment','center','FontSize',13);
        end
        xticks([1 2]); xticklabels({'NHF','HF'});
        ylabel(imp_ylabels{mi},'FontSize',8);
        title(sprintf('Bin %d\nSD_N=%.3f SD_H=%.3f\np_{Lev,FDR}=%s',b,std(xN),std(xH),local_pstr(T_h2.p_levene_fdr(b))),'FontSize',8);
        grid on; xlim([0.5 2.5]);
    end
    nexttile; hold on;
    bh=bar(1:n_bins,T_h2.ratio_sd,0.55); bh.FaceColor='flat';
    for b=1:n_bins, bh.CData(b,:)=local_ternary(T_h2.p_levene_fdr(b)<0.05,[0.3 0.6 0.3],[0.7 0.7 0.7]); end
    yline(1,'r--','LineWidth',1.8,'HandleVisibility','off');
    for b=1:n_bins
        sig=local_stars(T_h2.p_levene_fdr(b));
        if ~isempty(sig), text(b,T_h2.ratio_sd(b)+0.02,sig,'HorizontalAlignment','center','FontSize',12); end
    end
    ylabel('SD_{NHF}/SD_{HF}','FontSize',9); xlabel('Intensity quartile','FontSize',9);
    title('SD ratio','FontSize',9); set(gca,'XTick',1:4); grid on;
    exportgraphics(fig_h2,fullfile(fig_dir,sprintf('%s_H2_variance.png',oc)),'Resolution',180);

    %% === H3: pre/post snapshot ===
    fprintf('\n=== H3: %s pre/post snapshot and change ===\n',imp_oc);
    CI_bl=CI(ismember(CI.phase_type,{'baseline','test'})&isfinite(CI.(imp_oc))&CI.(imp_oc)>0,:);
    CI_bl.log_impact=log(CI_bl.(imp_oc));

    fprintf('\n--- 3a: Post-training snapshot ---\n');
    rows_h3a={};
    for ph={'Baseline2','Test2'}
        Tph=CI_bl(strcmp(CI_bl.phase,ph{1}),:);
        subj=unique(Tph.subject); xs=nan(numel(subj),1); ihs=false(numel(subj),1);
        for si=1:numel(subj)
            s=subj{si};
            xs(si)=mean(Tph.log_impact(strcmp(Tph.subject,s)),'omitnan');
            ihs(si)=any(Tph.haptic(strcmp(Tph.subject,s)));
        end
        xN=xs(~ihs&isfinite(xs)); xH=xs(ihs&isfinite(xs));
        [~,p2]=ttest2(xH,xN,'Vartype','unequal');
        [~,pN0]=ttest(xN); [~,pH0]=ttest(xH);
        sp=sqrt(((numel(xN)-1)*var(xN)+(numel(xH)-1)*var(xH))/(numel(xN)+numel(xH)-2));
        d=(mean(xH)-mean(xN))/sp*(1-3/(4*(numel(xN)+numel(xH)-2)-1));
        fprintf('%s | n_N=%d n_H=%d | mean_N=%.3f mean_H=%.3f | d=%.3f p_NvsH=%.4f | p_N_vs0=%.4f p_H_vs0=%.4f\n', ...
            ph{1},numel(xN),numel(xH),mean(xN),mean(xH),d,p2,pN0,pH0);
        rows_h3a(end+1,:)={ph{1},numel(xN),numel(xH),mean(xN),mean(xH),d,p2,pN0,pH0};
    end
    T_h3a=cell2table(rows_h3a,'VariableNames',{'phase','n_N','n_H','mean_N','mean_H','cohens_d','p_NvsH','p_N_vs0','p_H_vs0'});
    T_h3a.p_fdr=mafdr(T_h3a.p_NvsH,'BHFDR',true);

    fprintf('\n--- 3b: Pre to post change ---\n');
    rows_h3b={};
    for pair={{'Baseline1','Baseline2'},{'Test1','Test2'}}
        ppre=pair{1}{1}; ppost=pair{1}{2};
        Tpre=CI_bl(strcmp(CI_bl.phase,ppre),:);
        Tpost=CI_bl(strcmp(CI_bl.phase,ppost),:);
        subj=unique([Tpre.subject;Tpost.subject]);
        pre_v=nan(numel(subj),1); post_v=nan(numel(subj),1); ihs=false(numel(subj),1);
        for si=1:numel(subj)
            s=subj{si};
            pre_v(si) =mean(Tpre.log_impact(strcmp(Tpre.subject,s)),'omitnan');
            post_v(si)=mean(Tpost.log_impact(strcmp(Tpost.subject,s)),'omitnan');
            ihs(si)=any(CI_bl.haptic(strcmp(CI_bl.subject,s)));
        end
        keep=isfinite(pre_v)&isfinite(post_v); delta=post_v-pre_v;
        dN=delta(~ihs&keep); dH=delta(ihs&keep);
        [~,pN]=ttest(dN); [~,pH]=ttest(dH); [~,p_diff]=ttest2(dH,dN,'Vartype','unequal');
        fprintf('%s->%s | NHF: mean_delta=%.3f p=%.4f | HF: mean_delta=%.3f p=%.4f | diff p=%.4f\n', ...
            ppre,ppost,mean(dN,'omitnan'),pN,mean(dH,'omitnan'),pH,p_diff);
        rows_h3b(end+1,:)={ppre,ppost,numel(dN),numel(dH),mean(dN,'omitnan'),mean(dH,'omitnan'),pN,pH,p_diff};
    end
    T_h3b=cell2table(rows_h3b,'VariableNames',{'phase_pre','phase_post','n_N','n_H','delta_N','delta_H','p_N_paired','p_H_paired','p_diff'});
    all_results.(oc).T_H3a=T_h3a; all_results.(oc).T_H3b=T_h3b;

    fig_h3=figure('Position',[50 50 900 420]);
    tl_h3=tiledlayout(1,4,'TileSpacing','compact','Padding','compact');
    title(tl_h3,sprintf('H3: log-%s post-training snapshot + pre to post change',imp_oc),'FontWeight','bold','FontSize',11);
    for pp=1:2
        ph={'Baseline2','Test2'}; ph_lbl={'Baseline 2','Test 2'};
        Tph=CI_bl(strcmp(CI_bl.phase,ph{pp}),:);
        subj=unique(Tph.subject); xs=nan(numel(subj),1); ihs=false(numel(subj),1);
        for si=1:numel(subj)
            s=subj{si};
            xs(si)=mean(Tph.log_impact(strcmp(Tph.subject,s)),'omitnan');
            ihs(si)=any(Tph.haptic(strcmp(Tph.subject,s)));
        end
        xN=xs(~ihs&isfinite(xs)); xH=xs(ihs&isfinite(xs));
        row=T_h3a(strcmp(T_h3a.phase,ph{pp}),:);
        nexttile; hold on;
        scatter(0.9+(rand(numel(xN),1)-0.5)*0.2,xN,22,CN,'filled','MarkerFaceAlpha',0.45,'HandleVisibility','off');
        scatter(1.9+(rand(numel(xH),1)-0.5)*0.2,xH,22,CH,'filled','MarkerFaceAlpha',0.45,'HandleVisibility','off');
        errorbar(1,mean(xN),std(xN)/sqrt(numel(xN))*1.96,'o','Color',CN,'MarkerFaceColor',CN,'LineWidth',2,'MarkerSize',9,'DisplayName','NHF');
        errorbar(2,mean(xH),std(xH)/sqrt(numel(xH))*1.96,'o','Color',CH,'MarkerFaceColor',CH,'LineWidth',2,'MarkerSize',9,'DisplayName','HF');
        ymax=max([xN;xH]); ymin=min([xN;xH]); rng=ymax-ymin;
        if ~isempty(row)
            sig=local_stars(row.p_fdr);
            if ~isempty(sig), yt=ymax+0.1*rng; plot([1 2],[yt yt],'k-','LineWidth',1,'HandleVisibility','off'); text(1.5,yt+0.05*rng,sig,'HorizontalAlignment','center','FontSize',13); end
            text(1.5,ymin-0.2*rng,sprintf('p_{FDR}=%s\nd=%.2f',local_pstr(row.p_fdr),row.cohens_d),'HorizontalAlignment','center','FontSize',7.5,'Color',[0.3 0.3 0.3]);
        end
        xticks([1 2]); xticklabels({'NHF','HF'});
        ylabel(imp_ylabels{mi},'FontSize',8); title(ph_lbl{pp},'FontSize',9);
        if pp==1, legend('Location','best','FontSize',8); end
        grid on; xlim([0.5 2.5]);
    end
    pair_labels={{'Baseline1','Baseline2'},{'Test1','Test2'}};
    for pp=1:2
        ppre=pair_labels{pp}{1}; ppost=pair_labels{pp}{2};
        Tpre=CI_bl(strcmp(CI_bl.phase,ppre),:); Tpost=CI_bl(strcmp(CI_bl.phase,ppost),:);
        subj=unique([Tpre.subject;Tpost.subject]);
        pre_v=nan(numel(subj),1); post_v=nan(numel(subj),1); ihs=false(numel(subj),1);
        for si=1:numel(subj)
            s=subj{si};
            pre_v(si) =mean(Tpre.log_impact(strcmp(Tpre.subject,s)),'omitnan');
            post_v(si)=mean(Tpost.log_impact(strcmp(Tpost.subject,s)),'omitnan');
            ihs(si)=any(CI_bl.haptic(strcmp(CI_bl.subject,s)));
        end
        keep=isfinite(pre_v)&isfinite(post_v);
        row=T_h3b(strcmp(T_h3b.phase_pre,ppre),:);
        nexttile; hold on;
        for grp=[false true]
            idx=find(ihs==grp&keep); col=local_ternary(grp,CH,CN);
            jx=1+(rand(numel(idx),1)-0.5)*0.1;
            for k=1:numel(idx), plot([jx(k) jx(k)+1],[pre_v(idx(k)) post_v(idx(k))],'-','Color',[col 0.2],'LineWidth',0.8,'HandleVisibility','off'); end
            mu=[mean(pre_v(idx),'omitnan') mean(post_v(idx),'omitnan')];
            sem=[std(pre_v(idx),'omitnan') std(post_v(idx),'omitnan')]./sqrt(numel(idx))*1.96;
            errorbar([1 2]+local_ternary(grp,0.1,-0.1),mu,sem,'-o','Color',col,'LineWidth',2,'MarkerFaceColor',col,'MarkerSize',8,'DisplayName',local_ternary(grp,'HF','NHF'));
        end
        allv=[pre_v(keep);post_v(keep)]; ymax=max(allv(isfinite(allv))); ymin=min(allv(isfinite(allv))); rng=ymax-ymin;
        text(1.5,ymax+0.12*rng,sprintf('\\DeltaN vs \\DeltaH\np=%s',local_pstr(row.p_diff)),'HorizontalAlignment','center','FontSize',7.5,'Color',[0.3 0.3 0.3]);
        xlim([0.5 2.5]); xticks([1 2]); xticklabels({ppre,ppost});
        ylabel(imp_ylabels{mi},'FontSize',8);
        title(sprintf('%s to %s',ppre,ppost),'FontSize',8,'Interpreter','none');
        if pp==1, legend('Location','best','FontSize',8); end
        grid on;
    end
    exportgraphics(fig_h3,fullfile(fig_dir,sprintf('%s_H3_pre_post.png',oc)),'Resolution',180);

end

save(fullfile(cfg.output_root,'tssv_tssf_hypotheses_results.mat'),'all_results');
fprintf('\nSaved tssv_tssf_hypotheses_results.mat\n');

function s=local_stars(p)
    if isnan(p)||p>0.05,s=''; elseif p>0.01,s='*'; elseif p>0.001,s='**'; else,s='***'; end
end
function s=local_pstr(p)
    if isnan(p),s='n/a'; elseif p<0.001,s=sprintf('%.2e',p); else,s=sprintf('%.3f',p); end
end
function local_violin(x,xpos,col)
    if numel(x)<3,scatter(xpos+(rand(numel(x),1)-0.5)*0.2,x,18,col,'filled','MarkerFaceAlpha',0.4,'HandleVisibility','off'); return; end
    [f,xi]=ksdensity(x,'NumPoints',100,'BoundaryCorrection','reflection');
    f=f/max(f)*0.35;
    patch([xpos+f fliplr(xpos-f)],[xi fliplr(xi)],col,'FaceAlpha',0.25,'EdgeColor',col,'LineWidth',0.8,'HandleVisibility','off');
    scatter(xpos+(rand(numel(x),1)-0.5)*0.15,x,10,col,'filled','MarkerFaceAlpha',0.3,'HandleVisibility','off');
end
function p=local_levene(x,y)
    mx=median(x); my=median(y);
    [~,p]=ttest2(abs(x-mx),abs(y-my),'Vartype','unequal');
end
function out=local_ternary(c,a,b), if c,out=a; else,out=b; end, end