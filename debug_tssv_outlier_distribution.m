%% check_tssv_tssf_outlier_distribution.m
clear; clc; cfg = config();
FV_raw = load(fullfile(cfg.output_root,'force_vibration_features.mat'),'T'); T_raw=FV_raw.T;
FV_cln = load(fullfile(cfg.output_root,'force_vibration_features_clean.mat'),'T'); T_cln=FV_cln.T;

metrics={'tssv','tssf'}; units={'(m/s²)²·s','N²'};

for mi=1:2
    oc=metrics{mi}; un=units{mi};
    fprintf('\n=== %s ===\n',upper(oc));

    T_tr = T_raw(strcmp(T_raw.phase_type,'training')&isfinite(T_raw.(oc))&T_raw.(oc)>0,:);
    T_tr.log_m = log(T_tr.(oc));

    p1=quantile(T_tr.log_m,0.01); p99=quantile(T_tr.log_m,0.99);
    fprintf('n=%d  mean=%.3f  median=%.3f  std=%.3f  skew=%.3f\n', height(T_tr),mean(T_tr.log_m),median(T_tr.log_m),std(T_tr.log_m),skewness(T_tr.log_m));
    fprintf('Global p1=%.3f(%.4f %s)  p99=%.3f(%.4f %s)  would_remove=%d(%.1f%%)\n', p1,exp(p1),un,p99,exp(p99),un,sum(T_tr.log_m<p1|T_tr.log_m>p99),...
        100*mean(T_tr.log_m<p1|T_tr.log_m>p99));

    subj_list=unique(T_tr.subject);
    pct_3mad = nan(numel(subj_list),1); 
    pct_p1p99 = nan(numel(subj_list),1);
    fprintf('\n%-20s %5s %7s %7s %8s %8s\n','Subject','n','median','MAD','3MAD%','p1p99%');
    for si=1:numel(subj_list)
        s = subj_list{si}; 
        v = T_tr.log_m(strcmp(T_tr.subject,s)); 
        v = v(isfinite(v));
        if numel(v)<3, continue; end
        med_v = median(v); 
        mad_v = mad(v,1);
        pct_3mad(si) =100*mean(abs(v-med_v)>3*mad_v);
        pct_p1p99(si) =100*mean(v<p1|v>p99);
        if pct_3mad(si)>15||pct_p1p99(si)>5
            fprintf('%-20s %5d %7.2f %7.3f %7.1f%% %7.1f%%\n', strrep(s,'subject_',''),numel(v),med_v,mad_v,pct_3mad(si),pct_p1p99(si));
        end
    end
    f =isfinite(pct_3mad);
    fprintf('3MAD:  mean=%.1f%% max=%.1f%%  |  p1p99: mean=%.1f%% max=%.1f%%\n', mean(pct_3mad(f)),max(pct_3mad(f)),mean(pct_p1p99(f)),max(pct_p1p99(f)));

    Tc_tr = T_cln(strcmp(T_cln.phase_type,'training'),:);
    fprintf('\n%-20s %6s %6s %6s  extreme_log_values\n','Subject','n_raw','n_cln','rmvd');
    for si=1:numel(subj_list)
        s = subj_list{si};
        n_raw = sum(strcmp(T_tr.subject,s));
        n_cln = sum(strcmp(Tc_tr.subject,s)&isfinite(Tc_tr.(oc))&Tc_tr.(oc)>0);
        rmvd = n_raw-n_cln;
        if rmvd<3, continue; end
        v = sort(T_tr.log_m(strcmp(T_tr.subject,s)));
        ns = min(3,numel(v));
        fprintf('%-20s %6d %6d %6d  low[%s]  high[%s]\n', strrep(s,'subject_',''),n_raw,n_cln,rmvd,...
            strtrim(sprintf('%.2f ',v(1:ns))), strtrim(sprintf('%.2f ',v(end-ns+1:end))));
    end

    log_raw = log(T_raw.(oc)(strcmp(T_raw.phase_type,'training')&isfinite(T_raw.(oc))&T_raw.(oc)>0));
    log_cln = log(T_cln.(oc)(strcmp(T_cln.phase_type,'training')&isfinite(T_cln.(oc))&T_cln.(oc)>0));
    
    fprintf('\nRAW:   n=%d  range=%.2f log-units (%.4f to %.4f)\n', numel(log_raw),max(log_raw)-min(log_raw),min(log_raw),max(log_raw));
    fprintf('CLEAN: n=%d  range=%.2f log-units (%.4f to %.4f)  removed=%d(%.1f%%)\n',...
        numel(log_cln),max(log_cln)-min(log_cln),min(log_cln),max(log_cln),...
        numel(log_raw)-numel(log_cln),100*(numel(log_raw)-numel(log_cln))/numel(log_raw));

    fig = figure('Position',[2000 2000 1600 400]);
    tl = tiledlayout(1,5,'TileSpacing','compact','Padding','compact');
    title(tl,sprintf('%s: RAW (grey) vs CLEAN (blue) per training level',upper(oc)), 'FontWeight','bold','FontSize',11);
    for lv=1:5
        vr = log(T_raw.(oc)(strcmp(T_raw.phase_type,'training')&T_raw.level==lv&isfinite(T_raw.(oc))&T_raw.(oc)>0));
        vc = log(T_cln.(oc)(strcmp(T_cln.phase_type,'training')&T_cln.level==lv&isfinite(T_cln.(oc))&T_cln.(oc)>0));
        nexttile; hold on;
        histogram(vr,30,'FaceColor',[0.7 0.7 0.7],'EdgeColor','none','FaceAlpha',0.7, Normalization','probability','DisplayName',sprintf('RAW n=%d',numel(vr)));
        histogram(vc,30,'FaceColor',[0.2 0.5 0.8],'EdgeColor','none','FaceAlpha',0.7, 'Normalization','probability','DisplayName',sprintf('CLEAN n=%d',numel(vc)));
        xlabel(sprintf('log-%s',upper(oc)),'FontSize',8); ylabel('Proportion','FontSize',8);
        title(sprintf('L%d  removed=%d',lv,numel(vr)-numel(vc)),'FontSize',9);
        legend('FontSize',7,'Location','best'); grid on;
    end
    fig_dir=fullfile(cfg.output_root,'figures');
    if ~exist(fig_dir,'dir'), mkdir(fig_dir); end
    exportgraphics(fig,fullfile(fig_dir,sprintf('%s_raw_vs_clean.png',oc)),'Resolution',150);
    fprintf('Saved %s_raw_vs_clean.png\n',oc);
end