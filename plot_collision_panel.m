function plot_collision_panel(ax,gsr,gsr_col,gsr_label,t_col,src,resp,...
        col_idx,n_total,has_cvx,baseline_before,scr_window,scl_end,t_trial_start,t_trial_end)
    pre_s=baseline_before+0.5; post_s=scl_end+1.5;
    zm = (gsr.t >= t_col-pre_s) & (gsr.t <= t_col+post_s);
    t_rel = gsr.t(zm)-t_col;
    if ~any(zm), title(ax,sprintf('Col %d -- no data',col_idx)); return; end
    plot(ax,t_rel,gsr.(gsr_col)(zm),'b','LineWidth',1.2); hold(ax,'on');
    if has_cvx && ismember('scr',gsr.Properties.VariableNames)
        yyaxis(ax,'right');
        plot(ax,t_rel,gsr.scr(zm),'r','LineWidth',1,'DisplayName','SCR');
        plot(ax,t_rel,gsr.scl(zm),'Color',[0 0.6 0],'LineWidth',1,'DisplayName','SCL');
        ylabel(ax,'SCR/SCL (z-uS)'); yyaxis(ax,'left');
    end
    xline(ax,0,'r--','LineWidth',1.8,'HandleVisibility','off');
    xline(ax,-baseline_before,':','Color',[0.5 0.5 0.5],'LineWidth',1,'HandleVisibility','off');
    xline(ax,scr_window,'--','Color',[0.9 0.5 0],'LineWidth',1,'HandleVisibility','off');
    xline(ax,scl_end,':','Color',[0 0.6 0.7],'LineWidth',1,'HandleVisibility','off');
    if ~isnan(resp.baseline)
        yline(ax,resp.baseline,'--','Color',[0 0 0.7],'LineWidth',1,'HandleVisibility','off'); end
    for tr_t = {t_trial_start, t_trial_end}
        tr = tr_t{1};
        if ~isnan(tr) && (tr-t_col) >= -pre_s && (tr-t_col) <= post_s
            xline(ax,tr-t_col,'-','Color',[0 0.7 0],'LineWidth',2,'HandleVisibility','off'); end
    end
    if resp.has_scr
        idx = find(gsr.t >= t_col+resp.scr_latency,1);
        if ~isempty(idx) && zm(idx)
            plot(ax,resp.scr_latency,gsr.(gsr_col)(idx),'ro','MarkerSize',8,'LineWidth',2,'HandleVisibility','off'); end
    end
    src_names={'Accel','Force','Both'}; src_colors={[0.2 0.4 0.9],[0.6 0.1 0.6],[0.1 0.6 0.1]};
    src_name=src_names{min(src,3)}; src_col=src_colors{min(src,3)};
    scr_str='-'; scl_str='-';
    if resp.has_scr, scr_str=sprintf('lat=%.2fs amp=%.1f',resp.scr_latency,resp.scr_amplitude); end
    if resp.has_scl, scl_str=sprintf('D=%.1f',resp.scl_change); end
    title(ax,sprintf('#%d/%d  t=%.2fs  [%s]\nSCR:%s  SCL:%s',col_idx,n_total,t_col,src_name,scr_str,scl_str),'FontSize',8);
    text(ax,0.01,0.99,src_name,'Units','normalized','FontSize',8,'FontWeight','bold','Color',src_col,...
        'VerticalAlignment','top','BackgroundColor',[src_col 0.15]);
    xlabel(ax,'Time rel. collision (s)'); ylabel(ax,gsr_label); grid(ax,'on');
end